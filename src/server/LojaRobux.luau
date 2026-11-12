-- Loja com Robux (aprovada pelo Caio em 12/11/2026).
--   - Pacotes de dinheiro do jogo (Developer Products, compráveis várias vezes):
--     o valor cai no caixa do provedor de quem comprou, ou na carteira dele se ainda
--     não tem provedor. Vale para a partida (o jogo não guarda progresso).
--   - Passe VIP (Game Pass): só visual. Fachada dourada no prédio do provedor e
--     uniforme VIP. Não dá vantagem no jogo.
-- Os IDs ficam em Config.Robux. Com ID 0 o item aparece como "em breve" e não vende.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local Providers = require(script.Parent.Providers)

local R = Config.Robux
local Loja = {}

local granted = {} :: { [string]: boolean } -- recibos já entregues neste servidor
local vipOf = {} :: { [number]: boolean } -- [UserId] = tem o Passe VIP

-- registro dos recibos (evita entregar duas vezes se o Roblox repetir o aviso).
-- Sem acesso ao DataStore (Studio com API desligada), segue só com a memória.
local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore("RecibosRobux")
end)

local function packByKey(key: string): any
	for _, p in R.Packs do
		if p.key == key then
			return p
		end
	end
	return nil
end

local function packByProduct(id: number): any
	for _, p in R.Packs do
		if p.productId ~= 0 and p.productId == id then
			return p
		end
	end
	return nil
end

-- entrega o dinheiro de um pacote
function Loja.grant(player: Player, pack: any)
	local P = Providers.of(player)
	if P then
		P.game.earn(pack.money, pack.name .. " (loja)", player, "Aporte")
		Providers.notify(P, nil, string.format("%s trouxe R$ %d para o caixa do %s (%s).", player.DisplayName, pack.money, P.name, pack.name), "success")
	else
		player:SetAttribute("Wallet", (player:GetAttribute("Wallet") or 0) + pack.money)
		Remotes.notify(player, string.format("R$ %d na sua carteira (%s). Use para abrir o seu provedor ou aportar como sócio (tecla P).", pack.money, pack.name), "success")
	end
end

local function processReceipt(info: any): Enum.ProductPurchaseDecision
	local key = tostring(info.PurchaseId)
	if granted[key] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local pack = packByProduct(info.ProductId)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not pack or not player then
		-- o Roblox tenta de novo quando o jogador voltar
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if store then
		local ok, seen = pcall(function()
			return (store :: DataStore):GetAsync(key)
		end)
		if ok and seen then
			granted[key] = true
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end
	Loja.grant(player, pack)
	granted[key] = true
	if store then
		pcall(function()
			(store :: DataStore):SetAsync(key, true)
		end)
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- ---------------------------------------------------------------------------
-- Passe VIP: uniforme e fachada
-- ---------------------------------------------------------------------------

local GOLD = Color3.fromRGB(240, 190, 40)

local function dressVip(char: Model)
	if char:FindFirstChild("ColeteVIP") then
		return
	end
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	local head = char:FindFirstChild("Head")
	if not torso or not torso:IsA("BasePart") then
		return
	end
	local vest = Instance.new("Part")
	vest.Name = "ColeteVIP"
	vest.Size = torso.Size * Vector3.new(1.08, 0.85, 1.15)
	vest.Color = GOLD
	vest.Material = Enum.Material.SmoothPlastic
	vest.CanCollide = false
	vest.CanQuery = false
	vest.Massless = true
	vest.CFrame = torso.CFrame
	local stripe = Instance.new("Part")
	stripe.Name = "FaixaVIP"
	stripe.Size = Vector3.new(vest.Size.X + 0.04, 0.25, vest.Size.Z + 0.04)
	stripe.Color = Color3.fromRGB(30, 30, 35)
	stripe.Material = Enum.Material.Neon
	stripe.CanCollide = false
	stripe.CanQuery = false
	stripe.Massless = true
	stripe.CFrame = torso.CFrame * CFrame.new(0, -0.15, 0)
	for _, p in { vest, stripe } do
		local w = Instance.new("WeldConstraint")
		w.Part0 = torso
		w.Part1 = p
		w.Parent = p
		p.Parent = char
	end
	if head then
		local tag = Instance.new("BillboardGui")
		tag.Name = "EtiquetaVIP"
		tag.Size = UDim2.fromOffset(70, 22)
		tag.StudsOffset = Vector3.new(0, 2.6, 0)
		tag.MaxDistance = 60
		tag.AlwaysOnTop = false
		local l = Instance.new("TextLabel")
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBlack
		l.TextScaled = true
		l.TextColor3 = GOLD
		l.TextStrokeTransparency = 0.4
		l.Text = "★ VIP"
		l.Parent = tag
		tag.Parent = head
	end
end

-- fachada dourada no prédio do provedor que tem um VIP na equipe
local function setFacade(P: any, on: boolean)
	local model = P.isp and P.isp.model
	if not model or not model.Parent then
		return
	end
	local old = model:FindFirstChild("FachadaVIP")
	if not on then
		if old then
			old:Destroy()
		end
		return
	end
	if old then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "FachadaVIP"
	local cf, size = model:GetBoundingBox()
	local top = cf * CFrame.new(0, size.Y / 2 + 0.3, 0)
	local function bar(name: string, sz: Vector3, offset: CFrame)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CastShadow = false
		p.Size = sz
		p.Color = GOLD
		p.Material = Enum.Material.Neon
		p.CFrame = top * offset
		p.Parent = folder
		return p
	end
	bar("FaixaNorte", Vector3.new(size.X, 0.6, 0.6), CFrame.new(0, 0, -size.Z / 2))
	bar("FaixaSul", Vector3.new(size.X, 0.6, 0.6), CFrame.new(0, 0, size.Z / 2))
	bar("FaixaLeste", Vector3.new(0.6, 0.6, size.Z), CFrame.new(size.X / 2, 0, 0))
	local west = bar("FaixaOeste", Vector3.new(0.6, 0.6, size.Z), CFrame.new(-size.X / 2, 0, 0))
	local sign = Instance.new("BillboardGui")
	sign.Name = "LetreiroVIP"
	sign.Size = UDim2.fromOffset(260, 46)
	sign.StudsOffsetWorldSpace = Vector3.new(size.X / 2, 6, 0)
	sign.MaxDistance = 400
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	l.TextColor3 = GOLD
	l.TextStrokeTransparency = 0.3
	l.Text = "★ " .. P.name .. " ★"
	l.Parent = sign
	sign.Parent = west
	folder.Parent = model
end

function Loja.isVip(player: Player): boolean
	if player:GetAttribute("Vip") == true then
		return true
	end
	local id = R.Vip.gamePassId
	if id == 0 then
		return false
	end
	local cached = vipOf[player.UserId]
	if cached ~= nil then
		return cached
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
	end)
	local v = ok and owns == true
	vipOf[player.UserId] = v
	if v then
		player:SetAttribute("Vip", true)
	end
	return v
end

-- liga o VIP de um jogador (compra feita agora ou atalho de teste)
function Loja.applyVip(player: Player)
	vipOf[player.UserId] = true
	player:SetAttribute("Vip", true)
	if player.Character then
		dressVip(player.Character)
	end
	local P = Providers.of(player)
	if P then
		setFacade(P, true)
	end
end

-- ---------------------------------------------------------------------------
-- Tela (aba Loja da janela Guerra)
-- ---------------------------------------------------------------------------

function Loja.info(player: Player): any
	local P = Providers.of(player)
	local packs = {}
	for _, p in R.Packs do
		table.insert(packs, { key = p.key, name = p.name, robux = p.robux, money = p.money, ready = p.productId ~= 0 })
	end
	return {
		packs = packs,
		vip = { name = R.Vip.name, robux = R.Vip.robux, info = R.Vip.info, ready = R.Vip.gamePassId ~= 0, owned = Loja.isVip(player) },
		dest = if P then "o caixa do " .. P.name else "a sua carteira (você ainda não tem provedor)",
	}
end

function Loja.prompt(player: Player, key: string)
	if key == "vip" then
		if Loja.isVip(player) then
			Remotes.notify(player, "Você já tem o Passe VIP.", "info")
			return
		end
		if R.Vip.gamePassId == 0 then
			Remotes.notify(player, "O Passe VIP ainda não foi criado no Roblox.", "error")
			return
		end
		MarketplaceService:PromptGamePassPurchase(player, R.Vip.gamePassId)
		return
	end
	local pack = packByKey(key)
	if not pack then
		return
	end
	if pack.productId == 0 then
		Remotes.notify(player, "Esse pacote ainda não foi criado no Roblox.", "error")
		return
	end
	MarketplaceService:PromptProductPurchase(player, pack.productId)
end

function Loja.start()
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased and passId == R.Vip.gamePassId then
			Loja.applyVip(player)
			Remotes.notify(player, "Passe VIP ativo! Fachada dourada no seu provedor e uniforme VIP.", "success")
		end
	end)
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(char)
			if Loja.isVip(player) then
				char:WaitForChild("HumanoidRootPart", 5)
				task.wait(0.5)
				dressVip(char)
			end
		end)
		task.spawn(Loja.isVip, player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, pl in Players:GetPlayers() do
		onPlayer(pl)
	end
	Players.PlayerRemoving:Connect(function(player)
		vipOf[player.UserId] = nil
	end)
	-- a fachada acompanha a equipe: provedor com algum VIP fica dourado
	task.spawn(function()
		while true do
			task.wait(5)
			for _, P in Providers.list() do
				local any = false
				for _, pl in Providers.members(P) do
					if pl:GetAttribute("Vip") == true then
						any = true
					end
				end
				setFacade(P, any)
			end
		end
	end)
end

return Loja
