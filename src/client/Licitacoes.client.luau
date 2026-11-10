-- Tela das licitações dos prédios públicos (Prefeitura, Escola, Delegacia e Hospital).
-- Abre com a tecla L, pelo botão "Licitações" ou no mural da Prefeitura. O dono do
-- provedor manda a proposta (preço por dia); sócios e outros jogadores só acompanham.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local UiFit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiFit"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local BidState = Remotes:WaitForChild("BidState") :: RemoteFunction
local BidAction = Remotes:WaitForChild("BidAction") :: RemoteEvent
local BidOpen = Remotes:WaitForChild("BidOpen") :: RemoteEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local BG = Color3.fromRGB(16, 20, 30)
local ROW = Color3.fromRGB(28, 34, 46)
local INK = Color3.fromRGB(235, 240, 248)
local QUIET = Color3.fromRGB(150, 160, 175)
local ACCENT = Color3.fromRGB(80, 190, 255)
local GOLD = Color3.fromRGB(240, 200, 40)
local GREEN = Color3.fromRGB(46, 160, 90)
local RED = Color3.fromRGB(190, 60, 55)
local GOOD = Color3.fromRGB(46, 204, 113)
local WARN = Color3.fromRGB(241, 196, 15)

local StatusText = {
	aguardando = { "Edital fechado", QUIET },
	aberta = { "ABERTA para propostas", GOOD },
	contratada = { "Contrato em andamento", ACCENT },
}

local function new(class: string, props: { [string]: any }): any
	local inst = Instance.new(class)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	inst.Parent = props.Parent
	return inst
end

local function corner(parent: Instance, r: number)
	new("UICorner", { CornerRadius = UDim.new(0, r), Parent = parent })
end

local function label(parent: Instance, text: string, props: { [string]: any }): TextLabel
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 14,
		TextColor3 = INK,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Text = text,
		Parent = parent,
	})
	for k, v in props do
		(l :: any)[k] = v
	end
	return l
end

local gui = new("ScreenGui", { Name = "Licitacoes", ResetOnSpawn = false, DisplayOrder = 22, Parent = playerGui })

local W, H = 660, 500
local win = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(W, H), BackgroundColor3 = BG, Visible = false, Parent = gui })
corner(win, 14)
new("UIStroke", { Color = GOLD, Thickness = 2, Parent = win })
UiFit.scale(win, W, H, 10)

label(win, "LICITAÇÕES DA PREFEITURA", { Position = UDim2.fromOffset(18, 10), Size = UDim2.new(1, -80, 0, 30), Font = Enum.Font.GothamBlack, TextSize = 22, TextColor3 = GOLD })
local info = label(win, "", { Position = UDim2.fromOffset(18, 42), Size = UDim2.new(1, -36, 0, 40), TextColor3 = QUIET, TextSize = 13 })

local list = new("ScrollingFrame", { Position = UDim2.fromOffset(18, 88), Size = UDim2.new(1, -36, 1, -100), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, ScrollBarImageColor3 = GOLD, CanvasSize = UDim2.new(), Parent = win })
local layout = new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	list.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 8)
end)

local typed: { [string]: string } = {}
local lastKey = ""
local data: any = nil

local function render()
	for _, c in list:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	if not data then
		return
	end
	local who = if data.provider then string.format("%s · %d clientes online (o atestado pede %d)", data.provider, data.online, data.minClients) else "Você ainda não faz parte de um provedor"
	info.Text = string.format("Agora: %s · %s\nMenor preço vence. Só o dono manda proposta. Contrato de %d dias; multa de R$ %d se não instalar no prazo ou estourar o SLA.", data.now, who, data.contractDays, data.fine)
	for i, b in data.list do
		local card = new("Frame", { LayoutOrder = i, Size = UDim2.new(1, -10, 0, 128), BackgroundColor3 = ROW, Parent = list })
		corner(card, 10)
		local st = StatusText[b.status] or { b.status, QUIET }
		label(card, string.format("%s  ·  Casa %d", b.label, b.index), { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(0.6, 0, 0, 22), Font = Enum.Font.GothamBold, TextSize = 17 })
		label(card, st[1], { Position = UDim2.new(0.6, 0, 0, 6), Size = UDim2.new(0.4, -12, 0, 22), Font = Enum.Font.GothamBold, TextColor3 = st[2], TextXAlignment = Enum.TextXAlignment.Right })
		label(card, string.format("Valor de referência: até R$ %d por dia · mínimo R$ %d · SLA: no máximo %dh sem internet", b.ref, b.floor, b.slaHours), { Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -24, 0, 18), TextColor3 = QUIET, TextSize = 13 })
		local line
		if b.status == "aberta" then
			line = string.format("Propostas até %s · %d proposta(s) recebida(s)", b.closes, b.bids)
			if b.myBid then
				line ..= string.format(" · a sua: R$ %d", b.myBid)
			end
		elseif b.status == "contratada" then
			line = string.format("Contratado: %s por R$ %d por dia, até %s", b.winner, b.price or 0, b.untilText)
			if not b.installed and b.installBy ~= "" then
				line ..= " · instalar até " .. b.installBy
			end
		else
			line = "Próximo edital: " .. b.opens
		end
		label(card, line, { Position = UDim2.fromOffset(12, 50), Size = UDim2.new(1, -24, 0, 18), TextColor3 = if b.mineWinner then GOOD else INK, TextSize = 14 })
		if b.last ~= "" then
			label(card, b.last, { Position = UDim2.fromOffset(12, 70), Size = UDim2.new(1, -24, 0, 16), TextColor3 = QUIET, TextSize = 12 })
		end
		if b.status == "aberta" and data.owner then
			local box = new("TextBox", {
				Position = UDim2.fromOffset(12, 92),
				Size = UDim2.fromOffset(250, 28),
				BackgroundColor3 = Color3.fromRGB(40, 48, 64),
				TextColor3 = INK,
				PlaceholderText = string.format("Preço por dia (R$ %d a %d)", b.floor, b.ref),
				PlaceholderColor3 = QUIET,
				Text = typed[b.key] or "",
				Font = Enum.Font.Gotham,
				TextSize = 14,
				ClearTextOnFocus = false,
				Parent = card,
			})
			corner(box, 6)
			box:GetPropertyChangedSignal("Text"):Connect(function()
				typed[b.key] = box.Text
			end)
			local send = new("TextButton", { Position = UDim2.fromOffset(272, 92), Size = UDim2.fromOffset(160, 28), BackgroundColor3 = GREEN, Text = if b.myBid then "Trocar proposta" else "Enviar proposta", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = Color3.new(1, 1, 1), Parent = card })
			corner(send, 6)
			send.Activated:Connect(function()
				local v = tonumber((string.gsub(box.Text, "[^%d]", "")))
				if v then
					BidAction:FireServer(b.key, v)
					typed[b.key] = nil
				end
			end)
			if b.myBid then
				local back = new("TextButton", { Position = UDim2.fromOffset(442, 92), Size = UDim2.fromOffset(150, 28), BackgroundColor3 = RED, Text = "Retirar proposta", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = Color3.new(1, 1, 1), Parent = card })
				corner(back, 6)
				back.Activated:Connect(function()
					BidAction:FireServer(b.key, nil)
				end)
			end
		elseif b.status == "aberta" then
			label(card, if data.provider then "Só o dono do provedor manda proposta." else "Abra um provedor (tecla P) para disputar.", { Position = UDim2.fromOffset(12, 96), Size = UDim2.new(1, -24, 0, 20), TextColor3 = WARN, TextSize = 13 })
		end
	end
end

local polling = false
local function refresh()
	local ok, res = pcall(function()
		return BidState:InvokeServer()
	end)
	if not ok or not res then
		return
	end
	data = res
	local okKey, key = pcall(HttpService.JSONEncode, HttpService, res)
	key = if okKey then key else tostring(os.clock())
	if key ~= lastKey then
		lastKey = key
		-- não redesenha enquanto o jogador digita (o texto sobrevive em typed)
		local focused = UserInputService:GetFocusedTextBox()
		if not focused or not focused:IsDescendantOf(win) then
			render()
		end
	end
end

local function open()
	win.Visible = true
	lastKey = ""
	refresh()
	if polling then
		return
	end
	polling = true
	task.spawn(function()
		while win.Visible do
			task.wait(1.5)
			if win.Visible then
				refresh()
			end
		end
		polling = false
	end)
end

local function close()
	win.Visible = false
end

local function toggle()
	if win.Visible then
		close()
	else
		open()
	end
end

UiFit.closeX(win, close, 32)
BidOpen.OnClientEvent:Connect(open)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.L then
		toggle()
	end
end)

-- botão na tela: no celular embaixo do botão ERP; no PC ao lado do botão ERP
local btn = new("TextButton", {
	Name = "BotaoLicitacoes",
	AnchorPoint = if UiFit.touch then Vector2.new(0, 0) else Vector2.new(0, 1),
	Position = if UiFit.touch then UDim2.fromOffset(12, 258) else UDim2.new(0, 260, 1, -134),
	Size = UDim2.fromOffset(130, 36),
	BackgroundColor3 = BG,
	BackgroundTransparency = 0.1,
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	TextColor3 = GOLD,
	Text = if UiFit.touch then "Licitações" else "Licitações (L)",
	Parent = gui,
})
corner(btn, 8)
new("UIStroke", { Color = GOLD, Thickness = 1.5, Parent = btn })
btn.Activated:Connect(toggle)

-- aviso quando um edital abre (o servidor manda no Notify; aqui só pisca o botão)
local folder = ReplicatedStorage:WaitForChild("GameState"):WaitForChild("Licitacoes", 30)
if folder then
	local function watch(f: Instance)
		f:GetAttributeChangedSignal("Status"):Connect(function()
			if f:GetAttribute("Status") == "aberta" then
				btn.BackgroundColor3 = Color3.fromRGB(70, 60, 10)
				task.delay(8, function()
					btn.BackgroundColor3 = BG
				end)
			end
			if win.Visible then
				refresh()
			end
		end)
	end
	for _, f in folder:GetChildren() do
		watch(f)
	end
	folder.ChildAdded:Connect(watch)
end
