-- Provedores da cidade (mundo aberto). Cada prédio pode ter um provedor aberto.
--
-- Um provedor (P) tem dono, sócios, nome, preço e os seus serviços próprios:
-- caixa e estoque (GameService), rack/NOC/loja (RackService), equipe e carro
-- (TechService). A rua (postes, CTOs e casas) é compartilhada: rede neutra.
--
-- Regras do Caio (10/11/2026):
--   - cada jogador chega com R$ 12.000 próprios (atributo "Wallet");
--   - quem abre um provedor coloca esse dinheiro como capital e vira dono;
--   - quem vira sócio pode aportar o próprio dinheiro no caixa;
--   - se o dono sai do jogo, o sócio que entrou por último vira dono e fica com o caixa;
--   - sem ninguém, o provedor fecha e as casas dele ficam livres.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)

local Providers = {}

Providers.slots = {} :: { [number]: any } -- [prédio] = provedor aberto
Providers.SlotCount = 2
Providers.onOpen = nil :: ((any) -> ())? -- o Main cria os serviços do provedor
Providers.onClose = nil :: ((any, string) -> ())? -- o Main desmonta os serviços
local nextId = 0

local stateRoot: Folder

local function slotFolder(slot: number): Folder
	local f = stateRoot:FindFirstChild("P" .. slot) :: Folder?
	if not f then
		f = Instance.new("Folder")
		f.Name = "P" .. slot
		f.Parent = stateRoot
	end
	return f :: Folder
end

function Providers.init()
	stateRoot = ReplicatedStorage:FindFirstChild("GameState") :: Folder
	if not stateRoot then
		stateRoot = Instance.new("Folder")
		stateRoot.Name = "GameState"
		stateRoot.Parent = ReplicatedStorage
	end
	for slot = 1, Providers.SlotCount do
		local f = slotFolder(slot)
		f:SetAttribute("Open", false)
		f:SetAttribute("Name", "")
	end
end

function Providers.folder(slot: number): Folder
	return slotFolder(slot)
end

-- Provedor do jogador (ou nil se ele ainda não escolheu)
function Providers.of(player: Player?): any
	if not player then
		return nil
	end
	local slot = player:GetAttribute("Slot")
	return if slot then Providers.slots[slot] else nil
end

function Providers.list(): { any }
	local out = {}
	for slot = 1, Providers.SlotCount do
		if Providers.slots[slot] then
			table.insert(out, Providers.slots[slot])
		end
	end
	return out
end

function Providers.members(P: any): { Player }
	local out = {}
	if P.owner and P.owner.Parent then
		table.insert(out, P.owner)
	end
	for _, pl in P.partners do
		if pl.Parent then
			table.insert(out, pl)
		end
	end
	return out
end

-- Aviso para toda a equipe do provedor (ou só para um jogador)
function Providers.notify(P: any, player: Player?, text: string, kind: string?)
	if player then
		Remotes.Notify:FireClient(player, text, kind or "info")
		return
	end
	if not P then
		Remotes.Notify:FireAllClients(text, kind or "info")
		return
	end
	for _, pl in Providers.members(P) do
		Remotes.Notify:FireClient(pl, text, kind or "info")
	end
end

local function publishTeam(P: any)
	local f = slotFolder(P.slot)
	f:SetAttribute("Open", true)
	f:SetAttribute("Name", P.name)
	f:SetAttribute("Price", P.price)
	f:SetAttribute("Owner", if P.owner then P.owner.Name else "")
	local names = {}
	for _, pl in P.partners do
		table.insert(names, pl.Name)
	end
	f:SetAttribute("Partners", table.concat(names, ", "))
	for _, label in P.isp.nameLabels do
		label.Text = string.upper(P.name)
	end
end
Providers.publishTeam = publishTeam

local function setPlayerSlot(player: Player, slot: number?)
	player:SetAttribute("Slot", slot)
	local P = slot and Providers.slots[slot]
	if P then
		player.RespawnLocation = P.isp.spawn
	else
		player.RespawnLocation = nil
	end
end

function Providers.cleanName(name: any): string?
	if typeof(name) ~= "string" then
		return nil
	end
	name = string.gsub(name, "[%c<>]", "")
	name = string.gsub(name, "^%s+", "")
	name = string.gsub(name, "%s+$", "")
	if #name < 3 or #name > 24 then
		return nil
	end
	return name
end

-- Abre um provedor novo no prédio livre. O dinheiro do jogador vira o capital.
function Providers.open(player: Player, slot: number?, name: any): any
	if Providers.of(player) then
		Providers.notify(nil, player, "Você já faz parte de um provedor.", "error")
		return nil
	end
	if not slot then
		for s = 1, Providers.SlotCount do
			if not Providers.slots[s] then
				slot = s
				break
			end
		end
	end
	if not slot or Providers.slots[slot] then
		Providers.notify(nil, player, "Não tem prédio livre na cidade. Entre como sócio de um provedor.", "error")
		return nil
	end
	nextId += 1
	local clean = Providers.cleanName(name) or ("Provedor de " .. player.DisplayName)
	local P = {
		id = nextId,
		slot = slot,
		name = clean,
		price = Config.DailyFeePerCustomer,
		owner = player,
		partners = {} :: { Player },
		isp = Providers.world.isps[slot],
		folder = slotFolder(slot),
		closed = false,
	}
	Providers.slots[slot] = P
	local capital = player:GetAttribute("Wallet") or 0
	player:SetAttribute("Wallet", 0)
	if Providers.onOpen then
		Providers.onOpen(P)
	end
	P.game.money = capital
	P.game.record("receita", "Capital", "Capital inicial de " .. player.DisplayName, capital)
	P.game.publish()
	setPlayerSlot(player, slot)
	publishTeam(P)
	Providers.notify(nil, nil, string.format("%s abriu o provedor %s na cidade.", player.DisplayName, P.name), "info")
	-- leva o dono para o prédio dele
	if player.Character then
		player.Character:PivotTo(P.isp.spawn.CFrame + Vector3.new(0, 3, 0))
	end
	return P
end

-- Entra como sócio de um provedor que já existe.
function Providers.join(player: Player, slot: number): any
	local P = Providers.slots[slot]
	if not P then
		return nil
	end
	if Providers.of(player) then
		Providers.notify(nil, player, "Você já faz parte de um provedor.", "error")
		return nil
	end
	table.insert(P.partners, player)
	setPlayerSlot(player, slot)
	publishTeam(P)
	Providers.notify(P, nil, string.format("%s entrou como sócio do %s.", player.DisplayName, P.name), "success")
	if player.Character then
		player.Character:PivotTo(P.isp.spawn.CFrame + Vector3.new(0, 3, 0))
	end
	return P
end

-- Sócio coloca o próprio dinheiro no caixa do provedor.
function Providers.invest(player: Player, amount: any)
	local P = Providers.of(player)
	if not P or typeof(amount) ~= "number" then
		return
	end
	local wallet = player:GetAttribute("Wallet") or 0
	amount = math.floor(math.clamp(amount, 0, wallet))
	if amount <= 0 then
		Providers.notify(nil, player, "Você não tem dinheiro próprio para aportar.", "error")
		return
	end
	player:SetAttribute("Wallet", wallet - amount)
	P.game.money += amount
	P.game.record("receita", "Capital", "Aporte de " .. player.DisplayName, amount)
	P.game.publish()
	Providers.notify(P, nil, string.format("%s aportou R$ %d no caixa do %s.", player.DisplayName, amount, P.name), "money")
end

function Providers.rename(player: Player, name: any)
	local P = Providers.of(player)
	local clean = Providers.cleanName(name)
	if not P then
		return
	end
	if not clean then
		Providers.notify(nil, player, "Nome inválido: use de 3 a 24 letras.", "error")
		return
	end
	P.name = clean
	publishTeam(P)
	Providers.notify(P, nil, "O provedor agora se chama " .. clean .. ".", "success")
end

-- Preço da mensalidade (por dia de jogo) para contratos NOVOS. Quem já é cliente
-- continua pagando o preço do contrato até cancelar.
function Providers.setPrice(player: Player, price: any)
	local P = Providers.of(player)
	if not P or typeof(price) ~= "number" then
		return
	end
	local L = Config.Price
	price = math.floor(math.clamp(price, L.Min, L.Max))
	P.price = price
	publishTeam(P)
	Providers.notify(P, nil, string.format("Preço novo do %s: R$ %d por dia, para quem contratar daqui em diante.", P.name, price), "money")
end

-- Fecha o provedor (falência ou ninguém mais na equipe).
function Providers.close(P: any, reason: string)
	if P.closed then
		return
	end
	P.closed = true
	if Providers.onClose then
		Providers.onClose(P, reason)
	end
	Providers.slots[P.slot] = nil
	for _, pl in Providers.members(P) do
		setPlayerSlot(pl, nil)
		pl:SetAttribute("Wallet", Config.StartMoney) -- recomeça com o capital de um jogador novo
	end
	local f = slotFolder(P.slot)
	f:SetAttribute("Open", false)
	f:SetAttribute("Name", "")
	for _, label in P.isp.nameLabels do
		label.Text = "PRÉDIO DISPONÍVEL"
	end
	Providers.notify(nil, nil, string.format("O provedor %s fechou (%s). O prédio está disponível.", P.name, reason), "alarm")
end

-- Jogador saiu do jogo: passa o provedor para o último sócio, ou fecha.
local function onLeave(player: Player)
	local P = Providers.of(player)
	if not P then
		return
	end
	for i, pl in P.partners do
		if pl == player then
			table.remove(P.partners, i)
			publishTeam(P)
			return
		end
	end
	if P.owner == player then
		-- o sócio que entrou por último vira o dono e fica com o caixa
		local heir = table.remove(P.partners)
		while heir and not heir.Parent do
			heir = table.remove(P.partners)
		end
		if heir then
			P.owner = heir
			publishTeam(P)
			Providers.notify(P, nil, string.format("%s saiu. %s agora é o dono do %s.", player.DisplayName, heir.DisplayName, P.name), "info")
		else
			P.owner = nil
			Providers.close(P, "o dono saiu e não tinha sócios")
		end
	end
end

function Providers.start(world: any)
	Providers.world = world
	local function onPlayer(player: Player)
		player:SetAttribute("Wallet", Config.StartMoney)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, pl in Players:GetPlayers() do
		onPlayer(pl)
	end
	Players.PlayerRemoving:Connect(onLeave)

	-- menu "Provedor": abrir, entrar como sócio, aportar, renomear e mudar o preço
	Remotes.ProviderAction.OnServerEvent:Connect(function(player, action, a, b)
		if action == "open" then
			Providers.open(player, tonumber(a), b)
		elseif action == "join" then
			Providers.join(player, tonumber(a) or 0)
		elseif action == "invest" then
			Providers.invest(player, tonumber(a))
		elseif action == "rename" then
			Providers.rename(player, a)
		elseif action == "price" then
			Providers.setPrice(player, tonumber(a))
		end
	end)
end

return Providers
