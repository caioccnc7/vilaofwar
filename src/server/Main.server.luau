-- Ponto de entrada do servidor: monta a Vila Aurora, liga a rede, as licitações e roda o relógio do jogo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local World = require(script.Parent.WorldBuilder)
local Game = require(script.Parent.GameService)
local Net = require(script.Parent.NetworkService)
local Residents = require(script.Parent.ResidentService)
local Director = require(script.Parent.IncidentDirector)
local Providers = require(script.Parent.Providers)
local RackModule = require(script.Parent.RackService)
local TechModule = require(script.Parent.TechService)
local ErpModule = require(script.Parent.ErpService)
local OltCli = require(script.Parent.Cli.OltCli)
local Bids = require(script.Parent.LicitacaoService)

local world = World.build()

Providers.init()
Game.init(Net, Residents)
Net.init(world, Game)
Residents.init(world, Net, Game)
Director.init(Net)
RackModule.start()
ErpModule.start()
Bids.init(Net, Game)

-- Fases de cada provedor: prazo de implantação, manifestação e falência
local function phaseHandler(P: any)
	return function(phase: string, old: string)
		if phase == "protesto" then
			Residents.setProtest(P.slot, true)
			Net.addAlarm(P.slot, "Moradores", "Manifestação na frente do provedor! Moradores abaixo de " .. Config.Opening.ProtestBelow .. "%", "critical")
			P.game.notify(nil, "MANIFESTAÇÃO! Os moradores estão na frente do " .. P.name .. ". Leve internet para as casas antes que chegue a 0% e o provedor vá à falência.", "alarm")
		elseif old == "protesto" then
			Residents.setProtest(P.slot, false)
			if phase == "operacao" then
				Net.addAlarm(P.slot, "Moradores", "Manifestação encerrada, moradores voltando para casa", "ok")
				P.game.notify(nil, "A manifestação acabou. Os moradores voltaram para casa.", "success")
			end
		end
		if phase == "falencia" then
			Residents.setProtest(P.slot, false)
			Providers.close(P, "falência")
		end
	end
end

-- Provedor novo: caixa, rack, loja, equipe e carro no prédio dele
Providers.onOpen = function(P: any)
	Net.resetSlot(P.slot)
	Net.attachProvider(P.slot) -- troncos do prédio novo até os splitters da rua
	Net.setupIsp(P.slot)
	P.game = Game.newProvider(P)
	P.rack = RackModule.new(P, world, Net)
	P.erp = ErpModule.new(P, world, Net) -- antes da equipe: os técnicos trabalham pela fila do ERP
	P.tech = TechModule.new(P, world, Net)
	P.rack.setTech(P.tech)
	P.erp.setTech(P.tech)
	P.game.onPhase = phaseHandler(P)
	Net.addAlarm(P.slot, "Provedor", P.name .. " aberto. Prazo de implantação até o fim do dia " .. P.game.deadlineDay(), "ok")
end

-- Provedor fechou: as casas dele ficam livres e o prédio volta a ficar disponível
Providers.onClose = function(P: any, _reason: string)
	local members = Providers.members(P)
	Residents.setProtest(P.slot, false)
	Net.dropProvider(P.slot)
	if P.rack then
		P.rack.destroy()
	end
	if P.tech then
		P.tech.destroy()
	end
	if P.erp then
		P.erp.destroy()
	end
	Net.detachProvider(P.slot)
	Net.resetSlot(P.slot)
	-- depois que a equipe sai do provedor, as ferramentas dele somem da mochila
	task.defer(function()
		for _, pl in members do
			if pl.Parent then
				Net.giveTools(pl)
			end
		end
	end)
end

Providers.start(world)

-- Atalhos para testar pelo Command Bar do Studio (lado do servidor). O Command Bar
-- não enxerga o _G dos scripts, então os atalhos ficam num BindableFunction:
--   game.ServerStorage.FibraTeste:Invoke("incidente", "cut")   rompimento de fibra
--   ... "onu" (ONU queimada), "dirty" (sinal atenuado), "dns" (DNS do upstream), "hw" (equipamento queima)
--   game.ServerStorage.FibraTeste:Invoke("hora", 18)           pula o relógio para as 18h
--   game.ServerStorage.FibraTeste:Invoke("dinheiro", 5000)
--   game.ServerStorage.FibraTeste:Invoke("kit")                ferramentas + insumos de graça
--   game.ServerStorage.FibraTeste:Invoke("semnet", 3)          casa 3 a 10 s de cancelar (se estiver sem internet)
--   game.ServerStorage.FibraTeste:Invoke("abrir", "Nome")     o 1º jogador abre um provedor
--   game.ServerStorage.FibraTeste:Invoke("alvo", 2)           os próximos comandos valem para o prédio 2
--   game.ServerStorage.FibraTeste:Invoke("atendente")          contrata a atendente de graça
--   game.ServerStorage.FibraTeste:Invoke("pedido", 3)          o morador da casa 3 pede instalação (OS)
--   game.ServerStorage.FibraTeste:Invoke("os")                 resumo das OS do ERP
--   game.ServerStorage.FibraTeste:Invoke("envelhecer", 5)      ONUs ficam 5 dias mais velhas (podem queimar)
--   game.ServerStorage.FibraTeste:Invoke("rack")               roteador configurado + OLT de fábrica no rack, link contratado
--   game.ServerStorage.FibraTeste:Invoke("instalar", 3)        instala a casa 3 na hora (gasta ONU e drop)
--   game.ServerStorage.FibraTeste:Invoke("olt", "display service-port all")   roda uma linha no console da OLT
--   game.ServerStorage.FibraTeste:Invoke("ativar", 3)          ativa a casa 3 na OLT pelo ERP
--   game.ServerStorage.FibraTeste:Invoke("lote", 4)            o 1º jogador constrói o provedor no lote 4
--   game.ServerStorage.FibraTeste:Invoke("licitacao")          abre todas as licitações agora
--   game.ServerStorage.FibraTeste:Invoke("proposta", 180)      o provedor alvo propõe R$ 180 em todas as abertas
--   game.ServerStorage.FibraTeste:Invoke("resultado")          fecha as licitações abertas e escolhe o vencedor
--   game.ServerStorage.FibraTeste:Invoke("licitacoes")         resumo das licitações
--   game.ServerStorage.FibraTeste:Invoke("atestado", 0)        muda quantos clientes online o atestado pede
--   game.ServerStorage.FibraTeste:Invoke("sinal", 3)           caminho óptico da casa 3 até a OLT do provedor alvo
--   game.ServerStorage.FibraTeste:Invoke("ir", 25)             leva o 1º jogador até a casa (ou prédio público) N
local target = 1
local function cur(): any
	return Providers.slots[target] or Providers.list()[1]
end
local Debug
Debug = {
	incidente = Director.force,
	hora = function(h: number)
		Game.hour = h
	end,
	abrir = function(name: string?)
		local pl = Players:GetPlayers()[1]
		if not pl then
			return "nenhum jogador"
		end
		local P = Providers.open(pl, nil, name)
		return if P then "aberto no prédio " .. P.slot else "não abriu"
	end,
	lote = function(slot: number)
		local pl = Players:GetPlayers()[1]
		if not pl then
			return "nenhum jogador"
		end
		local P = Providers.open(pl, slot, "Teste Lote " .. tostring(slot))
		target = slot
		return if P then "provedor no lote " .. P.slot else "não abriu"
	end,
	licitacao = function()
		Bids.forceOpen()
		return "licitações abertas"
	end,
	resultado = function()
		Bids.forceClose()
		return "licitações fechadas"
	end,
	-- muda o atestado (clientes online exigidos) só nesta sessão de teste
	atestado = function(n: number)
		Config.Bids.MinClients = n
		return "atestado: " .. n .. " clientes"
	end,
	proposta = function(price: number)
		local P = cur()
		if not P or not P.owner then
			return "sem provedor"
		end
		for _, b in Bids.list do
			Bids.bid(P.owner, b.key, price)
		end
		return "propostas enviadas"
	end,
	licitacoes = function()
		local out = {}
		for _, b in Bids.list do
			local W = b.winner and Providers.slots[b.winner]
			table.insert(out, string.format("%s: %s %s %s (%s)", b.key, b.status, if W then W.name else "-", tostring(b.price or ""), tostring(b.last or "")))
		end
		return table.concat(out, " | ")
	end,
	-- diagnóstico: caminho óptico da casa N até a OLT do provedor alvo
	sinal = function(index: number)
		local P = cur()
		local h = Net.houses[index]
		if not (P and h and h.onuId) then
			return "sem ONU"
		end
		local ok, loss, why = Net.graph:traceToOlt(h.onuId, P.slot)
		local chain = {}
		local node = Net.graph.nodes[h.onuId]
		local guard = 0
		while node and node.kind ~= "olt" and guard < 20 do
			guard += 1
			local pe = if node.parentBy then node.parentBy[P.slot] else node.parentEdge
			table.insert(chain, node.id .. (if node.powered then "" else "(sem energia)") .. ">" .. tostring(pe))
			node = pe and Net.graph.edges[pe] and Net.graph.nodes[Net.graph.edges[pe].from]
		end
		return string.format("sn=%s pon=%s ok=%s perda=%.1f motivo=%s contrato=%s status=%s | %s", tostring(h.sn), tostring(Net.ponPortOf(h)), tostring(ok), loss, tostring(why), tostring(h.contract), tostring(h.status), table.concat(chain, " "))
	end,
	ir = function(index: number)
		local pl = Players:GetPlayers()[1]
		local h = Net.houses[index]
		if pl and pl.Character and h then
			pl.Character:PivotTo(CFrame.new(h.house.doorPoint + Vector3.new(0, 4, 0)))
		end
	end,
	alvo = function(slot: number)
		target = slot
		return "alvo: prédio " .. tostring(slot)
	end,
	dinheiro = function(v: number)
		cur().game.money = v
		cur().game.publish()
	end,
	-- compra o kit inicial de graça (ferramentas + 1 pacote de cada insumo)
	kit = function()
		local P = cur()
		for _, key in Config.ToolOrder do
			Net.grantTool(P, key)
		end
		for key, sp in Config.Supplies do
			P.game.addStock(key, sp.pack, "Kit de teste")
		end
	end,
	-- contrata o técnico de graça (para testar)
	tecnico = function()
		cur().game.money += Config.Tech.HireFee
		cur().tech.hire(nil)
	end,
	-- compra o carro da equipe de graça (para testar)
	carro = function()
		cur().game.money += Config.Car.Price
		cur().tech.Car.buy(nil)
	end,
	-- rompe um cabo específico (ex.: "TRONCO1_SPL2", "DIST_E", "DROP9")
	romper = function(edgeId: string)
		Net.breakEdge(edgeId)
	end,
	-- resumo da equipe e do carro (volta como texto)
	equipe = function()
		local st = cur().tech.status()
		local out = { "carro: " .. st.car.stateText }
		for _, m in st.team do
			table.insert(out, m.name .. ": " .. m.state)
		end
		return table.concat(out, " | ")
	end,
	-- pula para o primeiro dia depois do prazo de implantação do provedor alvo
	prazo = function()
		Game.day = cur().game.deadlineDay() + 1
		Game.hour = Config.DayStartHour
		Game.publishClock()
	end,
	-- muda o humor de todos os moradores (ex.: 6 para testar a manifestação, 0.4 a falência)
	humor = function(v: number)
		for _, r in Residents.list do
			r.mood = v
		end
	end,
	-- contrata o link de graça
	link = function()
		local P = cur()
		P.game.linkContracted = true
		Net.slot(P.slot).upstreamMbps = Config.StartUpstreamMbps
		P.game.publish()
	end,
	-- rack pronto para testar: roteador configurado e OLT de fábrica, ligados e cabeados
	rack = function()
		local P = cur()
		P.game.linkContracted = true
		Net.slot(P.slot).upstreamMbps = Config.StartUpstreamMbps
		if not P.rack.activeOf("router") then
			P.rack.addDevice("router", 1, true)
		end
		if not P.rack.activeOf("olt") then
			P.rack.addDevice("olt", 2, true)
		end
		P.game.publish()
		return "rack pronto"
	end,
	-- instala a casa na hora, como se o técnico tivesse ido
	instalar = function(index: number)
		local P = cur()
		local h = Net.houses[index]
		if h then
			h.choice = P.slot
		end
		return Net.install(index, P, nil, "Teste")
	end,
	-- uma linha no console da OLT ativa (sessão de teste guardada entre chamadas)
	olt = function(line: string)
		local P = cur()
		local dev = P.rack.activeOf("olt")
		if not dev then
			return "sem OLT ativa"
		end
		dev.testSession = dev.testSession or { mode = "user" }
		local before = OltCli.prompt(dev.cfg, dev.testSession)
		local out = OltCli.run(dev.cfg, dev.testSession, line, {
			autofind = function()
				return {}
			end,
			ontState = function()
				return { run = "offline" }
			end,
			uptime = "0h",
		})
		return before .. line .. "\n" .. out
	end,
	ativar = function(index: number)
		local ok, msg = cur().erp.activate(index, "Teste")
		return tostring(ok) .. " " .. msg
	end,
	-- contrata a atendente de graça
	atendente = function()
		cur().game.money += Config.Attendant.HireFee
		cur().erp.hireAttendant(nil)
	end,
	-- o morador da casa N vai ao balcão pedir instalação (só se ele escolheu este provedor)
	pedido = function(index: number)
		local P = cur()
		local h = Net.houses[index]
		if not h or h.choice ~= P.slot then
			return "a casa " .. tostring(index) .. " não escolheu este provedor"
		end
		local o = P.erp.request(index)
		return if o then "OS #" .. o.id .. " (" .. o.status .. ")" else "não abriu"
	end,
	-- resumo das OS: #id tipo casa status técnico
	os = function()
		local out = {}
		for _, o in cur().erp.orders do
			table.insert(out, string.format("#%d %s c%d %s %s", o.id, o.kind, o.index, o.status, o.techName or "-"))
		end
		return if #out > 0 then table.concat(out, " | ") else "nenhuma OS"
	end,
	-- envelhece as ONUs instaladas (dias) para testar a ONU queimada
	envelhecer = function(days: number)
		for _, h in Net.houses do
			if h.onuId then
				h.onuDay = (h.onuDay or Game.day) - (days or Config.Onu.MinAgeDays)
			end
		end
	end,
	-- pula o tempo sem internet da casa N para perto do cancelamento
	semnet = function(index: number)
		local h = Net.houses[index]
		if h then
			h.downSeconds = Config.CancelAfterSeconds - 10
		end
	end,
	-- quem cada casa escolheria agora (preço e reputação)
	escolhas = function()
		local out = {}
		for i, h in Net.houses do
			table.insert(out, i .. "=" .. (if h.contract == "active" then "P" .. tostring(h.slot) .. "*" else tostring(h.choice)) .. "/" .. tostring(h.willing))
		end
		return table.concat(out, " ")
	end,
}
_G.Fibra = Debug
local debugFn = Instance.new("BindableFunction")
debugFn.Name = "FibraTeste"
debugFn.OnInvoke = function(cmd: string, arg: any)
	local f = Debug[cmd]
	if not f then
		return "comandos: abrir, lote, alvo, licitacao, proposta, resultado, licitacoes, ir, incidente, hora, dinheiro, kit, semnet, tecnico, carro, romper, equipe, prazo, humor, link, escolhas, atendente, pedido, os, envelhecer"
	end
	return f(arg) or "ok"
end
debugFn.Parent = game:GetService("ServerStorage")

-- Quem chega escolhe: abrir um provedor ou entrar como sócio de outro
local welcomed = setmetatable({}, { __mode = "k" })
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		task.wait(2)
		if Providers.of(player) or welcomed[player] then
			return
		end
		welcomed[player] = true
		Remotes.notify(player, string.format("Bem-vindo à %s! Você chegou com R$ %d. Construa o seu provedor num lote livre (R$ %d de obra) ou entre como sócio de outro (tecla P). Guia na Wiki (J).", Config.CityName, Config.StartMoney, Config.Lots.BuildCost), "info")
		Remotes.ProviderMenu:FireClient(player)
	end)
end)

-- Laço principal: 1 vez por segundo
local TICK = 1
while true do
	local dt = task.wait(TICK)
	for _, P in Providers.list() do
		P.rack.apply()
	end
	Net.tick(dt)
	Residents.tick(dt)
	Director.tick(dt)
	Bids.tick(dt)
	for _, P in Providers.list() do
		P.game.tick(dt)
		P.erp.tick(dt)
	end
	Game.tick(dt)

	-- cada equipe vê no NOC só o próprio provedor (a rua aparece para todos)
	local snaps = {}
	for _, pl in Players:GetPlayers() do
		local P = Providers.of(pl)
		if not P then
			continue
		end
		local snap = snaps[P.slot]
		if not snap then
			snap = Net.snapshot(P.slot)
			snap.game = P.game.summary()
			snap.mood = Residents.summary(P.slot)
			snap.utilization = Net.slot(P.slot).utilization
			snap.topo = P.rack.topology()
			snap.rack = P.rack.status()
			snap.tech = P.tech.status()
			snaps[P.slot] = snap
		end
		Remotes.NocUpdate:FireClient(pl, snap)
	end
end
