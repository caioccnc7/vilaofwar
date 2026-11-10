-- Licitações dos prédios públicos (Prefeitura, Escola, Delegacia e Hospital).
--
-- Cada órgão contrata a internet por licitação. Regras (escolhidas para o pedido do
-- Caio de 10/11/2026, valores no Config.Bids):
--   1. O edital abre (a primeira vez a partir do dia Config.Bids.FirstDay) e fica
--      aberto por Config.Bids.OpenHours horas de jogo.
--   2. Só o DONO de um provedor manda proposta: um preço por dia entre o piso e o valor
--      de referência do edital. A proposta é fechada (ninguém vê o valor dos outros) e
--      pode ser trocada até o edital fechar.
--   3. Para participar, o provedor precisa do atestado de capacidade técnica: pelo menos
--      Config.Bids.MinClients clientes online na hora em que o edital fecha.
--   4. Ganha o menor preço. Empate: mais estrelas de reputação; depois, quem mandou antes.
--   5. O vencedor recebe a OS de instalação no ERP e tem até Config.Bids.InstallDays dia(s)
--      para ligar e ativar o prédio. O contrato dura Config.Bids.ContractDays dias e paga
--      o preço da proposta por dia, no fechamento do dia.
--   6. SLA: o prédio público não pode ficar mais que slaHours (de cada órgão) sem internet.
--      Estourou, ou não instalou no prazo: multa de Config.Bids.Fine, contrato rescindido
--      e a licitação abre de novo. A multa por hora sem internet também é maior.
--   7. No fim do contrato abre outra licitação. Se outro provedor ganhar, a internet do
--      antigo é desligada e o novo instala.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local Providers = require(script.Parent.Providers)

local Bids = {}
Bids.list = {} -- uma licitação por órgão

local net: any
local gameService: any
local folder: Folder

local B = Config.Bids
local DAY_HOURS = Config.DayEndHour - Config.DayStartHour

-- Horas de expediente desde o começo do dia 1 (o relógio do jogo só anda no expediente)
local function now(): number
	return (gameService.day - 1) * DAY_HOURS + (gameService.hour - Config.DayStartHour)
end

local function whenText(t: number): string
	local day = math.floor(t / DAY_HOURS) + 1
	local hour = Config.DayStartHour + (t - (day - 1) * DAY_HOURS)
	local h = math.floor(hour)
	local m = math.floor((hour - h) * 60)
	return string.format("dia %d, %02d:%02d", day, h, m)
end
Bids.whenText = whenText

local function onlineClients(slot: number): number
	local n = 0
	for _, h in net.houses do
		if h.contract == "active" and h.slot == slot and not h.house.public and (h.status == "online" or h.status == "slow") then
			n += 1
		end
	end
	return n
end
Bids.onlineClients = onlineClients

local function publish(b: any)
	local f = b.folder
	f:SetAttribute("Status", b.status)
	f:SetAttribute("Opens", whenText(b.opensAt))
	f:SetAttribute("Closes", if b.status == "aberta" then whenText(b.closesAt) else "")
	f:SetAttribute("Bids", b.bidCount or 0)
	local W = b.winner and Providers.slots[b.winner]
	f:SetAttribute("Winner", if W then W.name else "")
	f:SetAttribute("WinnerSlot", b.winner or 0)
	f:SetAttribute("Price", b.price or 0)
	f:SetAttribute("Until", if b.untilT then whenText(b.untilT) else "")
	f:SetAttribute("InstallBy", if b.installBy then whenText(b.installBy) else "")
	local h = net.houses[b.index]
	f:SetAttribute("Installed", h ~= nil and h.contract == "active")
	f:SetAttribute("Last", b.last or "")
	f:SetAttribute("Round", b.round)
end

local function announce(text: string, kind: string?)
	Remotes.notify(nil, text, kind or "info")
end

-- Tira o prédio do provedor que tinha o contrato (fim do contrato, rescisão ou fechou)
local function endContract(b: any)
	local h = net.houses[b.index]
	if h then
		if h.contract == "active" then
			net.cancel(b.index)
		end
		-- OS de instalação que ficou aberta no ERP do antigo vencedor
		local P = b.winner and Providers.slots[b.winner]
		local o = P and P.erp and P.erp.openInstallFor(b.index)
		if o then
			P.erp.cancel(o, "Contrato da licitação encerrado")
		end
		h.choice = nil
		h.bidPrice = nil
	end
	b.winner = nil
	b.price = nil
	b.untilT = nil
	b.installBy = nil
end

local function reopenLater(b: any, hours: number)
	b.status = "aguardando"
	b.opensAt = now() + hours
	b.bids = {}
	b.bidCount = 0
	publish(b)
end

local function openRound(b: any)
	b.status = "aberta"
	b.round += 1
	b.closesAt = now() + B.OpenHours
	b.bids = {}
	b.bidCount = 0
	publish(b)
	announce(string.format("Licitação aberta: %s (até R$ %d por dia). Donos de provedor mandam proposta até %s (botão Licitações, tecla L).", b.label, b.ref, whenText(b.closesAt)), "info")
end

local function fine(P: any, b: any, why: string)
	if not P then
		return
	end
	P.game.money -= B.Fine
	P.game.record("despesa", "Multas de SLA", string.format("Multa da licitação (%s): %s", b.label, why), B.Fine)
	P.game.publish()
	net.addAlarm(P.slot, "Licitação", string.format("Multa de R$ %d: %s (%s)", B.Fine, why, b.label), "critical")
end

-- Fecha o edital e escolhe o vencedor
local function award(b: any)
	local best, bestPrice, bestRep, bestT = nil, math.huge, -1, math.huge
	local disq = 0
	for slot, bid in b.bids do
		local P = Providers.slots[slot]
		if not P or P.game.bankrupt then
			continue
		end
		if onlineClients(slot) < B.MinClients then
			disq += 1
			Providers.notify(P, nil, string.format("Licitação %s: proposta desclassificada. O atestado pede %d clientes online e o %s tem %d.", b.label, B.MinClients, P.name, onlineClients(slot)), "error")
			continue
		end
		local rep = P.game.reputation or 0
		if bid.price < bestPrice or (bid.price == bestPrice and (rep > bestRep or (rep == bestRep and bid.t < bestT))) then
			best, bestPrice, bestRep, bestT = slot, bid.price, rep, bid.t
		end
	end
	if not best then
		b.last = if disq > 0 then "Rodada " .. b.round .. ": todas as propostas desclassificadas" else "Rodada " .. b.round .. ": deserta (ninguém mandou proposta)"
		announce(string.format("Licitação %s fechou sem vencedor (%s). Abre de novo em %d horas.", b.label, if disq > 0 then "propostas desclassificadas" else "deserta", B.RetryHours), "info")
		-- se ninguém ganhou, quem já estava contratado continua até reabrir
		if b.winner and Providers.slots[b.winner] then
			b.status = "contratada"
			b.untilT = now() + B.RetryHours
			publish(b)
		else
			endContract(b)
			reopenLater(b, B.RetryHours)
		end
		return
	end
	local W = Providers.slots[best]
	local same = b.winner == best and net.houses[b.index].contract == "active" and net.houses[b.index].slot == best
	if not same then
		endContract(b)
	end
	b.winner = best
	b.price = bestPrice
	b.status = "contratada"
	b.untilT = now() + B.ContractDays * DAY_HOURS
	b.installBy = if same then nil else now() + B.InstallDays * DAY_HOURS
	b.last = string.format("Rodada %d: %s venceu com R$ %d por dia", b.round, W.name, bestPrice)
	local h = net.houses[b.index]
	h.choice = best
	h.bidPrice = bestPrice
	if same then
		h.price = bestPrice -- renovação: vale o preço novo
	elseif W.erp then
		W.erp.request(b.index)
	end
	publish(b)
	announce(string.format("%s venceu a licitação %s com R$ %d por dia.", W.name, b.label, bestPrice), "success")
	if not same then
		Providers.notify(W, nil, string.format("Vocês ganharam a licitação %s! Tem OS de instalação no ERP. Prazo para ligar e ativar: %s.", b.label, whenText(b.installBy)), "money")
	end
end

function Bids.tick(_dt: number)
	local t = now()
	for _, b in Bids.list do
		if b.status == "aguardando" then
			if t >= b.opensAt and #Providers.list() > 0 then
				openRound(b)
			end
		elseif b.status == "aberta" then
			if t >= b.closesAt then
				award(b)
			end
		elseif b.status == "contratada" then
			local P = b.winner and Providers.slots[b.winner]
			local h = net.houses[b.index]
			if not P then
				-- o provedor contratado fechou
				b.last = "Contrato encerrado: o provedor fechou"
				endContract(b)
				reopenLater(b, 1)
			elseif h.contract ~= "active" and b.installBy and t > b.installBy then
				fine(P, b, "não ligou o prédio no prazo")
				b.last = string.format("%s perdeu o contrato: não instalou no prazo", P.name)
				announce(string.format("%s perdeu o contrato da %s (não instalou no prazo). Nova licitação em breve.", P.name, b.label), "alarm")
				endContract(b)
				reopenLater(b, 1)
			elseif h.contract == "active" and (h.downSeconds or 0) >= b.slaHours * Config.HourSeconds then
				fine(P, b, string.format("mais de %dh sem internet", b.slaHours))
				b.last = string.format("%s perdeu o contrato: estourou o SLA de %dh", P.name, b.slaHours)
				announce(string.format("%s perdeu o contrato da %s (estourou o SLA). Nova licitação em breve.", P.name, b.label), "alarm")
				endContract(b)
				reopenLater(b, 1)
			elseif t >= b.untilT then
				openRound(b) -- renovação: o atual continua atendendo até sair o resultado
			else
				if h.contract == "active" and b.installBy then
					b.installBy = nil -- instalou dentro do prazo
					net.addAlarm(P.slot, "Licitação", b.label .. " ligada. Contrato valendo até " .. whenText(b.untilT), "ok")
				end
				-- aviso de SLA na metade do tempo
				if h.contract == "active" and (h.downSeconds or 0) >= b.slaHours * Config.HourSeconds * 0.5 and not b.slaWarned then
					b.slaWarned = true
					net.addAlarm(P.slot, "Licitação", string.format("%s sem internet há %s. Com %dh o contrato é rescindido", b.label, net.gameDuration(h.downSeconds), b.slaHours), "critical")
				elseif (h.downSeconds or 0) == 0 then
					b.slaWarned = false
				end
			end
		end
		publish(b)
	end
end

-- Proposta do dono (ou retirada, com price = nil)
function Bids.bid(player: Player, key: any, price: any)
	local b
	for _, x in Bids.list do
		if x.key == key then
			b = x
		end
	end
	local P = Providers.of(player)
	if not b or not P then
		return
	end
	if P.owner ~= player then
		Providers.notify(nil, player, "Só o dono do provedor manda proposta. Combine com ele o preço.", "error")
		return
	end
	if b.status ~= "aberta" then
		Providers.notify(nil, player, "Esta licitação não está aberta agora.", "error")
		return
	end
	if price == nil then
		if b.bids[P.slot] then
			b.bids[P.slot] = nil
			b.bidCount -= 1
			Providers.notify(P, nil, string.format("%s retirou a proposta da licitação %s.", player.DisplayName, b.label), "info")
		end
		publish(b)
		return
	end
	if typeof(price) ~= "number" or price ~= price then
		return
	end
	price = math.floor(price)
	if price < b.floor or price > b.ref then
		Providers.notify(nil, player, string.format("A proposta precisa ficar entre R$ %d e R$ %d por dia.", b.floor, b.ref), "error")
		return
	end
	if not b.bids[P.slot] then
		b.bidCount += 1
	end
	b.bids[P.slot] = { price = price, t = os.clock() }
	publish(b)
	local ok = onlineClients(P.slot) >= B.MinClients
	Providers.notify(P, nil, string.format("Proposta de R$ %d por dia enviada para %s.%s", price, b.label, if ok then "" else string.format(" Atenção: o atestado pede %d clientes online até o edital fechar.", B.MinClients)), if ok then "success" else "error")
end

-- Lista para a tela: dados públicos + a proposta do próprio provedor
function Bids.view(player: Player): any
	local P = Providers.of(player)
	local out = {}
	for _, b in Bids.list do
		local mine = P and b.bids[P.slot]
		table.insert(out, {
			key = b.key,
			label = b.label,
			index = b.index,
			ref = b.ref,
			floor = b.floor,
			slaHours = b.slaHours,
			status = b.status,
			opens = whenText(b.opensAt),
			closes = if b.status == "aberta" then whenText(b.closesAt) else "",
			bids = b.bidCount,
			winner = (function()
				local W = b.winner and Providers.slots[b.winner]
				return if W then W.name else ""
			end)(),
			mineWinner = P ~= nil and b.winner == P.slot,
			price = b.price,
			untilText = if b.untilT then whenText(b.untilT) else "",
			installBy = if b.installBy then whenText(b.installBy) else "",
			installed = net.houses[b.index].contract == "active",
			myBid = if mine then mine.price else nil,
			last = b.last or "",
		})
	end
	return {
		list = out,
		owner = P ~= nil and P.owner == player,
		provider = if P then P.name else nil,
		online = if P then onlineClients(P.slot) else 0,
		minClients = B.MinClients,
		now = whenText(now()),
		fine = B.Fine,
		contractDays = B.ContractDays,
	}
end

-- Teste: abre todas as licitações agora
function Bids.forceOpen()
	for _, b in Bids.list do
		if b.status ~= "aberta" then
			openRound(b)
		end
	end
end

-- Teste: fecha todas as abertas agora
function Bids.forceClose()
	for _, b in Bids.list do
		if b.status == "aberta" then
			award(b)
		end
	end
end

function Bids.init(netService: any, game_: any)
	net = netService
	gameService = game_
	local state = ReplicatedStorage:WaitForChild("GameState")
	folder = state:FindFirstChild("Licitacoes") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Licitacoes"
		folder.Parent = state
	end
	for i, org in B.Orgs do
		-- casa (índice da rede) do prédio público deste órgão
		local index
		for idx, h in net.houses do
			if h.house.public and h.house.org == org.key then
				index = idx
			end
		end
		if not index then
			continue
		end
		local h = net.houses[index]
		h.house.demand = org.demand
		h.house.slaMult = B.SlaMult
		local f = Instance.new("Folder")
		f.Name = org.key
		f.Parent = folder
		f:SetAttribute("Org", org.name)
		f:SetAttribute("Index", index)
		f:SetAttribute("Ref", org.ref)
		f:SetAttribute("Floor", math.floor(org.ref * B.FloorFraction))
		f:SetAttribute("Sla", org.slaHours)
		local b = {
			key = org.key,
			label = org.name,
			index = index,
			ref = org.ref,
			floor = math.floor(org.ref * B.FloorFraction),
			slaHours = org.slaHours,
			status = "aguardando",
			opensAt = (B.FirstDay - 1) * DAY_HOURS + (org.openHour or (i - 1) * 3 + 1),
			closesAt = 0,
			bids = {},
			bidCount = 0,
			winner = nil,
			price = nil,
			round = 0,
			folder = f,
		}
		table.insert(Bids.list, b)
		publish(b)
	end

	local action = Remotes.BidAction
	action.OnServerEvent:Connect(function(player, key, price)
		Bids.bid(player, key, price)
	end)
	Remotes.BidState.OnServerInvoke = function(player)
		return Bids.view(player)
	end
	-- o mural da Prefeitura abre a tela das licitações
	for _, b in Bids.list do
		local mural = net.houses[b.index].house.model:FindFirstChild("Mural")
		if mural then
			local pp = Instance.new("ProximityPrompt")
			pp.ActionText = "Ver licitações"
			pp.ObjectText = "Mural de licitações"
			pp.KeyboardKeyCode = Enum.KeyCode.E
			pp.MaxActivationDistance = 12
			pp.RequiresLineOfSight = false
			pp.Parent = mural
			pp.Triggered:Connect(function(player)
				Remotes.BidOpen:FireClient(player)
			end)
		end
	end
end

return Bids
