-- Moradores da Vila Aurora: o termômetro do provedor.
-- Cada morador está ligado à internet da própria casa. O humor sobe ou desce com o
-- estado da conexão e muda as falas, o lugar para onde ele anda e se ele cancela.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Dialogs = require(ReplicatedStorage.Shared.Dialogs)
local Remotes = require(script.Parent.Remotes)
local World = require(script.Parent.WorldBuilder)
local Looks = require(script.Parent.Looks)
local Providers = require(script.Parent.Providers)

local Residents = {}
Residents.list = {}

local net: any
local world: any
local game_: any
local protesting = {} :: { [number]: boolean } -- [prédio] = manifestação na frente dele

-- Cada morador "pertence" a um provedor: o do contrato, ou o que ele escolheu
-- (o mais barato que cabe no bolso dele). Sem nenhum que sirva: nil.
local function slotOf(r: any): number?
	local h = net.houses[r.index]
	if h.contract == "active" then
		return h.slot
	end
	return h.choice
end

local function providerOf(r: any): any
	local slot = slotOf(r)
	return if slot then Providers.slots[slot] else nil
end

-- O prazo de implantação do provedor dele já passou?
local function pastDeadline(r: any): boolean
	local P = providerOf(r)
	return P ~= nil and P.game.pastDeadline()
end

local function isProtesting(r: any): boolean
	local slot = slotOf(r)
	return slot ~= nil and protesting[slot] == true
end

local Names = { "Dona Cida", "Seu Jorge", "Marina", "Tiago", "Lúcia", "Rafael", "Bia", "Seu Antônio", "Dona Rosa", "Pedro", "Camila", "Seu Valdir", "Helena", "Júlio", "Dona Zezé", "Igor" }
local Skin = {
	Color3.fromRGB(255, 213, 170),
	Color3.fromRGB(198, 134, 66),
	Color3.fromRGB(141, 85, 36),
	Color3.fromRGB(234, 192, 134),
	Color3.fromRGB(105, 64, 40),
	Color3.fromRGB(224, 172, 105),
	Color3.fromRGB(255, 205, 148),
	Color3.fromRGB(160, 102, 60),
}
local Shirts = {
	Color3.fromRGB(220, 60, 80),
	Color3.fromRGB(40, 110, 200),
	Color3.fromRGB(250, 190, 40),
	Color3.fromRGB(40, 160, 110),
	Color3.fromRGB(150, 80, 190),
	Color3.fromRGB(240, 120, 40),
	Color3.fromRGB(240, 240, 240),
	Color3.fromRGB(60, 60, 70),
}
local Pants = {
	Color3.fromRGB(40, 50, 80),
	Color3.fromRGB(70, 60, 50),
	Color3.fromRGB(30, 30, 35),
	Color3.fromRGB(90, 110, 140),
}

local function moodColor(mood: number): Color3
	if mood >= 70 then
		return Config.StatusColors.online
	elseif mood >= 40 then
		return Config.StatusColors.slow
	elseif mood >= 15 then
		return Config.StatusColors.unstable
	end
	return Config.StatusColors.offline
end

local function moodWord(mood: number): string
	if mood >= 70 then
		return "feliz"
	elseif mood >= 40 then
		return "ok"
	elseif mood >= 15 then
		return "irritado"
	end
	return "furioso"
end

-- ---------------------------------------------------------------------------
-- Modelo do morador
-- ---------------------------------------------------------------------------

local function makeBody(i: number): Model
	-- aparência própria de cada morador (cabelo, chapéu, óculos, roupa)
	local styled = Looks.resident(i)
	if styled then
		return styled
	end
	local desc = Instance.new("HumanoidDescription")
	local skin = Skin[(i - 1) % #Skin + 1]
	desc.HeadColor = skin
	desc.LeftArmColor = skin
	desc.RightArmColor = skin
	desc.TorsoColor = Shirts[(i - 1) % #Shirts + 1]
	local pants = Pants[(i - 1) % #Pants + 1]
	desc.LeftLegColor = pants
	desc.RightLegColor = pants
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if ok and model then
		return model
	end
	-- plano B: boneco simples parado (caso o Studio não gere o modelo)
	local m = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 4, 1)
	root.Color = Shirts[(i - 1) % #Shirts + 1]
	root.Anchored = true
	root.Parent = m
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.6, 1.6, 1.6)
	head.Color = skin
	head.Anchored = true
	head.CFrame = root.CFrame * CFrame.new(0, 2.8, 0)
	head.Parent = m
	Instance.new("Humanoid").Parent = m
	m.PrimaryPart = root
	return m
end

local function makeBillboards(r: any)
	local head = r.model:FindFirstChild("Head") :: BasePart
	-- nome + humor
	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.fromOffset(170, 22)
	tag.StudsOffset = Vector3.new(0, 2.3, 0)
	tag.MaxDistance = 60
	tag.Parent = head
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.fromScale(1, 1)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.Text = r.name .. " · Casa " .. r.index
	nameLabel.Parent = tag
	r.nameLabel = nameLabel

	-- balão de fala
	local bubble = Instance.new("BillboardGui")
	bubble.Name = "Bubble"
	bubble.Size = UDim2.fromOffset(240, 64)
	bubble.StudsOffset = Vector3.new(0, 4.6, 0)
	bubble.MaxDistance = 90
	bubble.Enabled = false
	bubble.Parent = head
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	frame.Parent = bubble
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Config.StatusColors.online
	stroke.Parent = frame
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = frame
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.Gotham
	text.TextScaled = true
	text.TextWrapped = true
	text.TextColor3 = Color3.fromRGB(30, 30, 35)
	text.Parent = frame
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 22
	limit.Parent = text
	r.bubble = bubble
	r.bubbleText = text
	r.bubbleStroke = stroke

	-- cartaz da manifestação (só aparece quando os moradores protestam)
	local sign = Instance.new("BillboardGui")
	sign.Name = "Cartaz"
	sign.Size = UDim2.fromOffset(150, 56)
	sign.StudsOffset = Vector3.new(0, 7.6, 0)
	sign.MaxDistance = 120
	sign.Enabled = false
	sign.Parent = head
	local board = Instance.new("TextLabel")
	board.Size = UDim2.fromScale(1, 1)
	board.BackgroundColor3 = Color3.fromRGB(250, 245, 225)
	board.BorderSizePixel = 0
	board.Font = Enum.Font.GothamBlack
	board.TextScaled = true
	board.TextColor3 = Color3.fromRGB(190, 30, 30)
	board.Text = Dialogs.Signs[(r.index - 1) % #Dialogs.Signs + 1]
	board.Parent = sign
	local bs = Instance.new("UIStroke")
	bs.Thickness = 3
	bs.Color = Color3.fromRGB(90, 60, 30)
	bs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bs.Parent = board
	r.sign = sign
end

local function say(r: any, text: string, seconds: number?)
	r.bubbleText.Text = text
	r.bubbleStroke.Color = moodColor(r.mood)
	r.bubble.Enabled = true
	r.sayToken += 1
	local token = r.sayToken
	task.delay(seconds or 6, function()
		if r.sayToken == token then
			r.bubble.Enabled = false
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Falas
-- ---------------------------------------------------------------------------

local function situation(r: any): string
	local h = net.houses[r.index]
	if isProtesting(r) and not (h.contract == "active" and h.status == "online") then
		return "protest"
	end
	if h.contract ~= "active" then
		local late = pastDeadline(r)
		if h.contract == "cancelled" then
			return if late then "waiting_late" else "cancelled"
		end
		return if late then "waiting_late" else "waiting"
	end
	local s = h.status
	if s == "online" then
		if r.mood >= 70 then
			return "online_happy"
		elseif r.mood >= 40 then
			return "online_neutral"
		end
		return "online_grumpy"
	elseif s == "offline" then
		if h.reason == "onu" then
			return "offline_onu"
		elseif h.offlineSeconds > 90 then
			return "offline_long"
		end
		return "offline"
	end
	return s
end

local function bubbleLine(r: any): string
	local key = situation(r)
	local list = Dialogs.Bubble[key] or Dialogs.Bubble.online_neutral
	return Dialogs.pick(list)
end

local function talkLine(r: any): string
	local h = net.houses[r.index]
	local key = situation(r)
	if key == "online_happy" or key == "online_neutral" or key == "online_grumpy" then
		key = "online"
	elseif key == "offline_long" then
		key = if h.reason == "onu" then "offline_onu" else "offline"
	end
	local text = Dialogs.Talk[key] or Dialogs.Talk.online
	-- quem ainda não tem internet conta qual provedor vai contratar (ou que está caro)
	if h.contract ~= "active" and key ~= "protest" then
		local P = providerOf(r)
		local order = P and P.erp and P.erp.openInstallFor(r.index)
		if P and order then
			text ..= string.format(" Já pedi a instalação no %s: OS #%d, %s.", P.name, order.id, P.erp.statusText(order))
		elseif P then
			text ..= string.format(" Vou contratar o %s, que cobra R$ %d por dia. Ainda vou passar na recepção pedir.", P.name, P.price)
		elseif #Providers.list() > 0 then
			text ..= string.format(" Mas eu pago no máximo R$ %d por dia, e os provedores daqui cobram mais que isso.", h.willing or 0)
		end
	end
	-- pista sobre os vizinhos: ajuda a separar problema de rua (tronco/CTO) de problema da casa
	if h.contract == "active" and (h.status == "offline" or h.status == "unstable") then
		local sameSide, down = 0, 0
		for i, other in net.houses do
			if i ~= r.index and other.contract == "active" and other.house.side == h.house.side then
				sameSide += 1
				if other.status == "offline" then
					down += 1
				end
			end
		end
		if sameSide > 0 then
			text ..= " " .. (if down > 0 then Dialogs.NeighborHint else Dialogs.AloneHint)
		end
	end
	return text
end

-- ---------------------------------------------------------------------------
-- Movimento
-- ---------------------------------------------------------------------------

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function walk(r: any, target: Vector3)
	local hum = r.humanoid
	local root = r.root
	if not hum or not root or root.Anchored then
		return
	end
	-- MoveTo desiste depois de 8 s; em trechos longos tenta de novo
	local tries = 3 + math.ceil((flat(root.Position) - flat(target)).Magnitude / (math.max(hum.WalkSpeed, 1) * 7))
	for _ = 1, tries do
		hum:MoveTo(target)
		hum.MoveToFinished:Wait()
		if (flat(root.Position) - flat(target)).Magnitude < 4 then
			return
		end
	end
end

local function route(r: any, target: Vector3, via: { Vector3 }?)
	local root = r.root
	if not root then
		return
	end
	local pts = World.path(root.Position, target)
	local last = table.remove(pts)
	for _, p in pts do
		walk(r, p)
	end
	if via then
		for _, p in via do
			walk(r, p)
		end
	end
	walk(r, last or target)
end

local function brain(r: any)
	while r.model.Parent do
		-- se a física arremessar o morador, ele volta para a calçada de casa
		if r.root and not r.root.Anchored and (r.root.Position.Y > 25 or r.root.Position.Y < -10) then
			r.model:PivotTo(CFrame.new(r.house.doorPoint + Vector3.new(0, 3, 0)))
			r.root.AssemblyLinearVelocity = Vector3.zero
		end
		local h = net.houses[r.index]
		local P = providerOf(r)
		local isp = P and P.isp
		local prot = isProtesting(r)
		local online = h.contract == "active" and h.status == "online"
		if r.inCrowd and (not prot or online or r.crowdSlot ~= slotOf(r)) then
			r.inCrowd = false
			r.sign.Enabled = false
		end
		if prot and isp and not online then
			-- manifestação: todo mundo que está sem internet (ou com problema) fica na frente do provedor
			if not r.inCrowd then
				r.inCrowd = true
				r.crowdSlot = P.slot
				route(r, isp.entrance + r.crowdOffset)
				r.sign.Enabled = isProtesting(r)
			end
			if isProtesting(r) then
				if r.humanoid and math.random() < 0.25 then
					r.humanoid.Jump = true
				end
				say(r, Dialogs.pick(Dialogs.Bubble.protest), 4)
				task.wait(5 + math.random() * 4)
			end
		elseif isp and P.erp and h.contract ~= "active" and not P.erp.openInstallFor(r.index) and os.clock() >= r.nextRequest then
			-- escolheu um provedor e ainda não pediu: vai até o balcão da recepção pedir a internet
			r.nextRequest = os.clock() + 60
			route(r, isp.entrance)
			walk(r, isp.reception + Vector3.new(((r.index - 1) % 5) * 1.6 - 3.2, 0, 0))
			local now = net.houses[r.index]
			local still = providerOf(r)
			if still == P and now.contract ~= "active" then
				say(r, Dialogs.pick(Dialogs.Bubble.request), 6)
				task.wait(2)
				local o = P.erp.request(r.index)
				if o then
					r.nextIspVisit = math.max(r.nextIspVisit, os.clock() + 90)
					task.wait(3)
					say(r, string.format("Anotei aqui: OS #%d. Agora é esperar o técnico!", o.id), 6)
				end
			end
			task.wait(5)
		elseif isp and h.contract ~= "active" and os.clock() >= r.nextIspVisit then
			-- quem não tem internet vai até a frente do provedor perguntar quando ela chega
			local O = Config.Opening
			r.nextIspVisit = os.clock() + O.VisitEvery[1] + math.random() * (O.VisitEvery[2] - O.VisitEvery[1])
			route(r, isp.entrance + r.crowdOffset)
			local key = if pastDeadline(r) then "visit_late" else "visit"
			say(r, Dialogs.pick(Dialogs.Bubble[key]), 7)
			task.wait(9 + math.random() * 5)
		elseif isp and h.contract == "active" and h.status == "offline" and h.offlineSeconds > 90 and os.clock() - r.lastIspVisit > 120 then
			-- vai reclamar pessoalmente na recepção do provedor
			r.lastIspVisit = os.clock()
			route(r, isp.entrance)
			walk(r, isp.reception)
			say(r, Dialogs.pick(Dialogs.Bubble.offline_long), 7)
			task.wait(8)
		elseif h.contract == "active" and (h.status == "offline" or h.status == "unstable" or h.status == "nodns") then
			-- fica na frente de casa olhando o celular
			route(r, r.house.yardPoint)
			task.wait(6 + math.random() * 6)
		else
			local roll = math.random()
			if roll < 0.35 then
				route(r, r.house.yardPoint)
			elseif r.house.side >= 2 then
				-- quem mora na Rua das Palmeiras passeia pela própria rua (a praça fica longe)
				local p = world.palmPoints[math.random(1, #world.palmPoints)]
				route(r, p)
			elseif roll < 0.7 then
				local p = world.plazaPoints[math.random(1, #world.plazaPoints)]
				route(r, p)
			else
				local p = world.sidewalkPoints[math.random(1, #world.sidewalkPoints)]
				route(r, p)
			end
			task.wait(6 + math.random() * 10)
		end
	end
end

-- ---------------------------------------------------------------------------

-- Humor médio dos moradores de um provedor (clientes e quem escolheu ele).
-- nil quando ninguém está com esse provedor. Sem slot: a vila inteira.
function Residents.averageMood(slot: number?): number?
	local sum, n = 0, 0
	for _, r in Residents.list do
		if slot == nil or slotOf(r) == slot then
			sum += r.mood
			n += 1
		end
	end
	if n == 0 then
		return nil
	end
	return sum / n
end

-- Moradores de um provedor, para o painel do NOC dele.
function Residents.summary(slot: number?)
	local people = {}
	local counts = { feliz = 0, ok = 0, irritado = 0, furioso = 0 }
	for _, r in Residents.list do
		if slot == nil or slotOf(r) == slot then
			local h = net.houses[r.index]
			table.insert(people, { name = r.name, index = r.index, mood = r.mood, status = h.status, contract = h.contract, last = r.lastLine })
			local w = moodWord(r.mood)
			counts[w] += 1
		end
	end
	return { average = Residents.averageMood(slot) or -1, counts = counts, people = people }
end

function Residents.tick(dt: number)
	for _, r in Residents.list do
		local h = net.houses[r.index]
		if h.contract == "active" then
			local delta = Config.Mood[h.status] or 0
			r.mood = math.clamp(r.mood + delta * dt, 0, 100)
			-- regra: o humor afeta a reputação, mas o cliente só cancela depois de
			-- 1 dia inteiro de expediente seguido sem internet
			if (h.downSeconds or 0) >= Config.CancelAfterSeconds then
				net.cancel(r.index)
				r.mood = 30
				say(r, Dialogs.pick(Dialogs.Bubble.cancelled), 8)
			end
		elseif pastDeadline(r) then
			-- passou o prazo e a casa continua sem internet: a paciência acaba
			local M = Config.Mood
			r.mood = math.clamp(r.mood - (M.WaitBase + M.WaitScale * r.mood / 75) * dt, 0, 100)
		end
		r.nameLabel.TextColor3 = moodColor(r.mood)

		-- fala na hora em que a internet muda, e de tempos em tempos
		local sit = situation(r)
		r.nextLine -= dt
		if sit ~= r.lastSituation then
			r.lastSituation = sit
			r.nextLine = math.min(r.nextLine, 1 + math.random() * 3)
		end
		if r.nextLine <= 0 then
			local line = bubbleLine(r)
			r.lastLine = line
			say(r, line, 6)
			r.nextLine = 14 + math.random() * 16
		end
	end
end

-- Liga e desliga a manifestação na frente do prédio de um provedor.
function Residents.setProtest(slot: number, on: boolean)
	if (protesting[slot] == true) == on then
		return
	end
	protesting[slot] = if on then true else nil
	for _, r in Residents.list do
		if not on and r.inCrowd and r.crowdSlot == slot then
			r.inCrowd = false
			r.sign.Enabled = false
		end
		if slotOf(r) == slot then
			r.nextLine = math.min(r.nextLine, 1 + math.random() * 2)
		end
	end
end

function Residents.init(worldData: any, netService: any, gameService: any)
	world = worldData
	net = netService
	game_ = gameService
	for i, house in world.houses do
		local model = makeBody(i)
		model.Name = Names[i]
		model.Parent = world.npcFolder
		model:PivotTo(CFrame.new(house.doorPoint + Vector3.new(0, 3, 0)))
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
		if humanoid then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			humanoid.WalkSpeed = 7 + math.random() * 3
		end
		if root and not root.Anchored then
			pcall(function()
				root:SetNetworkOwner(nil)
			end)
		end
		local r = {
			index = i,
			name = Names[i],
			model = model,
			humanoid = humanoid,
			root = root,
			house = house,
			mood = Config.Mood.Start,
			sayToken = 0,
			nextLine = 3 + math.random() * 10,
			lastSituation = "",
			lastLine = "",
			lastIspVisit = -1000,
			-- primeira visita ao provedor espalhada no tempo, para não irem todos juntos
			nextIspVisit = os.clock() + 20 + math.random() * 120,
			-- pedido de instalação no balcão: logo depois de escolher um provedor
			nextRequest = os.clock() + Config.Erp.RequestEvery[1] + math.random() * (Config.Erp.RequestEvery[2] - Config.Erp.RequestEvery[1]),
			-- lugar de cada um na frente do provedor (calçada, longe da porta)
			crowdOffset = Vector3.new(((i - 1) % 8) * 3 - 10.5 + (math.random() - 0.5), 0, 2 + math.floor((i - 1) / 8) * 3 + math.random()),
			inCrowd = false,
		}
		makeBillboards(r)

		local talk = Instance.new("ProximityPrompt")
		talk.ActionText = "Conversar"
		talk.ObjectText = r.name
		talk.KeyboardKeyCode = Enum.KeyCode.T
		talk.MaxActivationDistance = 10
		talk.RequiresLineOfSight = false
		talk.Parent = root
		talk.Triggered:Connect(function(player)
			local line = talkLine(r)
			say(r, line, 7)
			Remotes.Dialog:FireClient(player, {
				name = r.name,
				house = r.index,
				text = line,
				mood = math.floor(r.mood),
				moodWord = moodWord(r.mood),
			})
		end)

		table.insert(Residents.list, r)
		task.spawn(brain, r)
	end

	net.onInstalled = function(index: number)
		local r = Residents.list[index]
		if r then
			r.mood = math.max(r.mood, 70)
			r.inCrowd = false
			r.sign.Enabled = false
			say(r, "Uhul, internet nova! Valeu!", 6)
		end
	end
end

return Residents
