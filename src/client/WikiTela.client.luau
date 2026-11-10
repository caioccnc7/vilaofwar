-- Tela da wiki do provedor: índice por categoria, busca e páginas com o guia prático.
-- Abre com a tecla J, pelo botão "Wiki" ou pelo quiosque da recepção.
-- Com o console aberto, a wiki fica num painel à direita dele (botão Wiki ou F1 no
-- console) e um clique num bloco de comando manda o comando para a linha do console.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Wiki = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Wiki"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UiFit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiFit"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local BG = Color3.fromRGB(12, 16, 24)
local PANEL = Color3.fromRGB(20, 26, 38)
local PANEL2 = Color3.fromRGB(28, 36, 52)
local INK = Color3.fromRGB(232, 238, 246)
local QUIET = Color3.fromRGB(140, 155, 175)
local ACCENT = Color3.fromRGB(80, 190, 255)
local CODE = Color3.fromRGB(120, 230, 140)
local WARN = Color3.fromRGB(240, 160, 60)

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

local function pad(parent: Instance, l: number, t: number, r: number, b: number)
	new("UIPadding", { PaddingLeft = UDim.new(0, l), PaddingTop = UDim.new(0, t), PaddingRight = UDim.new(0, r), PaddingBottom = UDim.new(0, b), Parent = parent })
end

local gui = new("ScreenGui", { Name = "Wiki", ResetOnSpawn = false, DisplayOrder = 25, Parent = playerGui })

-- botão fixo na tela
local openBtn = new("TextButton", {
	-- no celular fica no alto à esquerda (embaixo é o controle de andar)
	AnchorPoint = if UiFit.touch then Vector2.new(0, 0) else Vector2.new(0, 1),
	Position = if UiFit.touch then UDim2.fromOffset(12, 84) else UDim2.new(0, 12, 1, -134),
	Size = UDim2.fromOffset(if UiFit.touch then 110 else 120, 36),
	BackgroundColor3 = BG,
	BackgroundTransparency = 0.1,
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	TextColor3 = ACCENT,
	Text = if UiFit.touch then "Wiki" else "Wiki  (J)",
	Parent = gui,
})
corner(openBtn, 8)
new("UIStroke", { Color = ACCENT, Thickness = 1.5, Parent = openBtn })

-- janela
local win = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.82, 0.82),
	BackgroundColor3 = BG,
	Visible = false,
	Parent = gui,
})
corner(win, 12)
new("UIStroke", { Color = ACCENT, Thickness = 2, Parent = win })
new("UISizeConstraint", { MaxSize = Vector2.new(1180, 820), Parent = win })

local header = new("Frame", { Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = PANEL, Parent = win })
corner(header, 12)
local headTitle = new("TextLabel", {
	Position = UDim2.fromOffset(18, 0),
	Size = UDim2.new(1, -150, 1, 0),
	TextTruncate = Enum.TextTruncate.AtEnd,
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextSize = 20,
	TextColor3 = ACCENT,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = Wiki.Title,
	Parent = header,
})
local closeBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -10, 0.5, 0),
	Size = UDim2.fromOffset(110, 30),
	BackgroundColor3 = Color3.fromRGB(170, 50, 50),
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextColor3 = Color3.new(1, 1, 1),
	Text = if UiFit.touch then "Fechar" else "Fechar (J)",
	Parent = header,
})
corner(closeBtn, 6)
-- painel ao lado do console: o índice vira um botão para caber a página
local indexBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -96, 0.5, 0),
	Size = UDim2.fromOffset(78, 30),
	BackgroundColor3 = PANEL2,
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextColor3 = INK,
	Text = "Índice",
	Visible = false,
	Parent = header,
})
corner(indexBtn, 6)

-- índice (esquerda)
local side = new("Frame", { Position = UDim2.fromOffset(12, 56), Size = UDim2.new(0, 250, 1, -68), BackgroundColor3 = PANEL, Parent = win })
corner(side, 8)
-- a busca fica embaixo: em cima o chat do Roblox cobre o canto e rouba o clique
local search = new("TextBox", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 8, 1, -8),
	Size = UDim2.new(1, -16, 0, 32),
	BackgroundColor3 = PANEL2,
	Font = Enum.Font.Gotham,
	TextSize = 15,
	TextColor3 = INK,
	PlaceholderText = "Buscar na wiki...",
	PlaceholderColor3 = QUIET,
	ClearTextOnFocus = false,
	Text = "",
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = side,
})
corner(search, 6)
pad(search, 10, 0, 10, 0)
local list = new("ScrollingFrame", {
	Position = UDim2.fromOffset(0, 6),
	Size = UDim2.new(1, 0, 1, -54),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	CanvasSize = UDim2.new(),
	Parent = side,
})
local listLayout = new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
pad(list, 8, 0, 8, 8)
listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	list.CanvasSize = UDim2.fromOffset(0, listLayout.AbsoluteContentSize.Y + 12)
end)

-- página (direita)
local pageTitle = new("TextLabel", {
	Position = UDim2.fromOffset(278, 58),
	Size = UDim2.new(1, -296, 0, 38),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextSize = 26,
	TextColor3 = INK,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Text = "",
	Parent = win,
})
local pageCat = new("TextLabel", {
	Position = UDim2.fromOffset(278, 94),
	Size = UDim2.new(1, -296, 0, 18),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 13,
	TextColor3 = ACCENT,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
	Parent = win,
})
local content = new("ScrollingFrame", {
	Position = UDim2.fromOffset(272, 120),
	Size = UDim2.new(1, -284, 1, -132),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 8,
	CanvasSize = UDim2.new(),
	Parent = win,
})
local contentLayout = new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
pad(content, 6, 4, 18, 16)
contentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	content.CanvasSize = UDim2.fromOffset(0, contentLayout.AbsoluteContentSize.Y + 24)
end)

-- docked: a wiki está aberta junto com o console, num painel à direita
local small = false
local docked = false
local showIndex = false -- no painel: mostrando o índice no lugar da página

local function layout()
	if docked then
		win.AnchorPoint = Vector2.new(1, 0.5)
		win.Position = UDim2.fromScale(0.99, 0.5)
		win.Size = if small then UDim2.fromScale(0.47, 0.95) else UDim2.fromScale(0.41, 0.86)
		-- botões à esquerda: no canto de cima à direita fica a lista de jogadores do Roblox
		headTitle.Text = "Wiki"
		headTitle.Size = UDim2.new(0, 60, 1, 0)
		closeBtn.AnchorPoint = Vector2.new(0, 0.5)
		closeBtn.Position = UDim2.new(0, 166, 0.5, 0)
		closeBtn.Size = UDim2.fromOffset(78, 30)
		closeBtn.Text = "Fechar"
		indexBtn.AnchorPoint = Vector2.new(0, 0.5)
		indexBtn.Position = UDim2.new(0, 80, 0.5, 0)
		indexBtn.Visible = true
		indexBtn.BackgroundColor3 = if showIndex then ACCENT else PANEL2
		indexBtn.TextColor3 = if showIndex then BG else INK
		side.Visible = showIndex
		side.Size = UDim2.new(1, -24, 1, -68)
		pageTitle.Visible = not showIndex
		pageCat.Visible = not showIndex
		content.Visible = not showIndex
		pageTitle.Position = UDim2.fromOffset(16, 54)
		pageTitle.Size = UDim2.new(1, -32, 0, 32)
		pageTitle.TextSize = 20
		pageCat.Position = UDim2.fromOffset(16, 84)
		pageCat.Size = UDim2.new(1, -32, 0, 18)
		content.Position = UDim2.fromOffset(10, 106)
		content.Size = UDim2.new(1, -20, 1, -116)
		return
	end
	-- no celular a janela ocupa a tela quase toda e o índice fica mais estreito
	local sw = if small then 190 else 250
	win.AnchorPoint = Vector2.new(0.5, 0.5)
	win.Position = UDim2.fromScale(0.5, 0.5)
	win.Size = if small then UDim2.fromScale(0.98, 0.96) else UDim2.fromScale(0.82, 0.82)
	headTitle.Text = Wiki.Title
	headTitle.Size = UDim2.new(1, -150, 1, 0)
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -10, 0.5, 0)
	closeBtn.Size = UDim2.fromOffset(110, 30)
	closeBtn.Text = if UiFit.touch then "Fechar" else "Fechar (J)"
	indexBtn.Visible = false
	side.Visible = true
	pageTitle.Visible = true
	pageCat.Visible = true
	content.Visible = true
	side.Size = UDim2.new(0, sw, 1, -68)
	pageTitle.Position = UDim2.fromOffset(sw + 28, 58)
	pageTitle.Size = UDim2.new(1, -(sw + 46), 0, 38)
	pageTitle.TextSize = 26
	pageCat.Position = UDim2.fromOffset(sw + 28, 94)
	pageCat.Size = UDim2.new(1, -(sw + 46), 0, 18)
	content.Position = UDim2.fromOffset(sw + 22, 120)
	content.Size = UDim2.new(1, -(sw + 34), 1, -132)
end

UiFit.onResize(gui, function(s)
	small = s
	layout()
end)

indexBtn.MouseButton1Click:Connect(function()
	showIndex = not showIndex
	layout()
end)

-- linha de comando do console aberta? (aí os blocos de comando viram botões)
local function consoleInput(): BindableEvent?
	local console = playerGui:FindFirstChild("Console")
	local term = console and console:FindFirstChild("Terminal")
	if not term or not (term :: GuiObject).Visible then
		return nil
	end
	for _, d in term:GetDescendants() do
		if d:IsA("TextBox") and (d.Parent :: GuiObject).Visible then
			return console:FindFirstChild("Inserir") :: BindableEvent?
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Desenho de uma página
-- ---------------------------------------------------------------------------

-- string.upper não conhece acentos (UTF-8)
local function upper(s: string): string
	s = string.upper(s)
	for a, b in { ["ç"] = "Ç", ["ã"] = "Ã", ["á"] = "Á", ["â"] = "Â", ["é"] = "É", ["ê"] = "Ê", ["í"] = "Í", ["ó"] = "Ó", ["õ"] = "Õ", ["ô"] = "Ô", ["ú"] = "Ú" } do
		s = string.gsub(s, a, b)
	end
	return s
end

local function textLabel(parent: Instance, text: string, props: { [string]: any }): TextLabel
	local l = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 16,
		TextColor3 = INK,
		TextWrapped = true,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = text,
		Parent = parent,
	})
	for k, v in props do
		(l :: any)[k] = v
	end
	return l
end

local function box(order: number, color: Color3, transparency: number): Frame
	local b = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = color,
		BackgroundTransparency = transparency,
		LayoutOrder = order,
		Parent = content,
	})
	corner(b, 6)
	return b
end

local function escapeCode(s: string): string
	s = string.gsub(s, "&", "&amp;")
	s = string.gsub(s, "<", "&lt;")
	s = string.gsub(s, ">", "&gt;")
	return s
end

local function renderPage(page: any)
	for _, c in content:GetChildren() do
		if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
	pageTitle.Text = page.title
	pageCat.Text = upper(page.category)
	for i, line in page.body do
		local head = string.sub(line, 1, 2)
		if line == "" then
			new("Frame", { Size = UDim2.new(1, 0, 0, 6), BackgroundTransparency = 1, LayoutOrder = i, Parent = content })
		elseif head == "# " then
			textLabel(content, string.sub(line, 3), { Font = Enum.Font.GothamBold, TextSize = 19, TextColor3 = ACCENT, LayoutOrder = i })
		elseif head == "- " then
			textLabel(content, "•  " .. string.sub(line, 3), { LayoutOrder = i })
		elseif head == "$ " then
			local cmd = string.sub(line, 3)
			local canSend = docked and consoleInput() ~= nil
			local b = box(i, Color3.fromRGB(6, 9, 12), 0)
			pad(b, 10, 6, if canSend then 64 else 10, 6)
			textLabel(b, escapeCode(cmd), { Font = Enum.Font.Code, TextSize = 15, TextColor3 = CODE })
			if canSend then
				-- com o console aberto: clicar manda o comando para a linha do console
				local use = new("TextLabel", {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, 58, 0.5, 0),
					Size = UDim2.fromOffset(50, 22),
					BackgroundColor3 = PANEL2,
					Font = Enum.Font.GothamBold,
					TextSize = 12,
					TextColor3 = CODE,
					Text = "usar",
					ZIndex = 2,
					Parent = b,
				})
				corner(use, 5)
				local hit = new("TextButton", {
					-- cobre o bloco inteiro, inclusive as margens (o "usar" é mais alto que a linha)
					Position = UDim2.new(0, -10, 0, -6),
					Size = UDim2.new(1, 74, 1, 12),
					BackgroundTransparency = 1,
					Text = "",
					ZIndex = 4,
					Parent = b,
				})
				local function send()
					local ev = consoleInput()
					if ev then
						ev:Fire(cmd)
						use.Text = "ok"
						task.delay(0.8, function()
							use.Text = "usar"
						end)
					end
				end
				hit.MouseButton1Click:Connect(send)
			end
		elseif head == "> " then
			local b = box(i, ACCENT, 0.85)
			pad(b, 14, 8, 10, 8)
			new("Frame", { Position = UDim2.new(0, -14, 0, -8), Size = UDim2.new(0, 4, 1, 16), BackgroundColor3 = ACCENT, BorderSizePixel = 0, Parent = b })
			textLabel(b, "Dica: " .. string.sub(line, 3), { TextColor3 = INK })
		elseif string.sub(line, 1, 1) == "!" then
			local b = box(i, WARN, 0.82)
			pad(b, 14, 8, 10, 8)
			new("Frame", { Position = UDim2.new(0, -14, 0, -8), Size = UDim2.new(0, 4, 1, 16), BackgroundColor3 = WARN, BorderSizePixel = 0, Parent = b })
			textLabel(b, "<b>Atenção:</b> " .. string.sub(line, 2), { TextColor3 = INK })
		else
			textLabel(content, line, { LayoutOrder = i })
		end
	end
	content.CanvasPosition = Vector2.zero
end

-- ---------------------------------------------------------------------------
-- Índice e busca
-- ---------------------------------------------------------------------------

local current: any = nil
local buttons: { [string]: TextButton } = {}

local function plain(s: string): string
	return string.lower((string.gsub(s, "<[^>]+>", "")))
end

local function matches(page: any, q: string): boolean
	if q == "" then
		return true
	end
	if string.find(plain(page.title), q, 1, true) then
		return true
	end
	for _, line in page.body do
		if string.find(plain(line), q, 1, true) then
			return true
		end
	end
	return false
end

local function highlight()
	for id, b in buttons do
		local on = current ~= nil and current.id == id
		b.BackgroundTransparency = if on then 0 else 1
		b.TextColor3 = if on then BG else INK
	end
end

local function openPage(page: any)
	current = page
	renderPage(page)
	highlight()
	if showIndex then
		showIndex = false
		layout()
	end
end

local function buildList()
	for _, c in list:GetChildren() do
		if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
	table.clear(buttons)
	local q = string.lower(search.Text)
	local order = 0
	for _, cat in Wiki.Categories do
		local pages = {}
		for _, p in Wiki.Pages do
			if p.category == cat and matches(p, q) then
				table.insert(pages, p)
			end
		end
		if #pages > 0 then
			order += 1
			new("TextLabel", {
				Size = UDim2.new(1, 0, 0, 26),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				TextSize = 12,
				TextColor3 = ACCENT,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Bottom,
				Text = upper(cat),
				LayoutOrder = order,
				Parent = list,
			})
			for _, p in pages do
				order += 1
				local b = new("TextButton", {
					Size = UDim2.new(1, 0, 0, 28),
					BackgroundColor3 = ACCENT,
					BackgroundTransparency = 1,
					AutoButtonColor = false,
					Font = Enum.Font.Gotham,
					TextSize = 14,
					TextColor3 = INK,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Text = "   " .. p.title,
					LayoutOrder = order,
					Parent = list,
				})
				corner(b, 5)
				b.MouseButton1Click:Connect(function()
					openPage(p)
				end)
				buttons[p.id] = b
			end
		end
	end
	if order == 0 then
		new("TextLabel", {
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextSize = 14,
			TextColor3 = QUIET,
			TextWrapped = true,
			Text = "Nada encontrado.",
			Parent = list,
		})
	end
	highlight()
end

search:GetPropertyChangedSignal("Text"):Connect(buildList)

-- ---------------------------------------------------------------------------
-- Abrir e fechar
-- ---------------------------------------------------------------------------

local function open(pageId: string?)
	win.Visible = true
	local page = (pageId and Wiki.byId(pageId)) or current or Wiki.Pages[1]
	showIndex = false
	buildList()
	openPage(page)
	layout()
end

local function close()
	win.Visible = false
	search:ReleaseFocus()
end

local function toggle()
	if win.Visible then
		close()
	else
		open()
	end
end

openBtn.MouseButton1Click:Connect(toggle)

-- o console pede (botão Wiki ou F1): abre já na página do equipamento em uso
local toggleEv = new("BindableEvent", { Name = "Alternar", Parent = gui })
toggleEv.Event:Connect(function(pageId)
	if win.Visible then
		close()
	else
		open(if typeof(pageId) == "string" then pageId else nil)
	end
end)

-- Acompanha o console: com ele aberto, a wiki vira painel à direita e o console
-- vai para a esquerda. O botão Wiki da tela some (o console tem o dele), e também
-- some com o terminal de compras aberto, que ficaria por baixo.
local lastCanSend = false
task.spawn(function()
	while true do
		task.wait(0.2)
		local console = playerGui:FindFirstChild("Console")
		local term = console and console:FindFirstChild("Terminal") :: GuiObject?
		local termOpen = term ~= nil and term.Visible
		local covered = termOpen
		if console then
			for _, f in console:GetChildren() do
				if f:IsA("Frame") and f.Visible and f.Size.X.Offset == 660 then
					covered = true
				end
			end
		end
		openBtn.Visible = not covered
		local d = termOpen and win.Visible
		if console then
			console:SetAttribute("WikiAberta", d)
		end
		local canSend = consoleInput() ~= nil
		if d ~= docked or (d and canSend ~= lastCanSend) then
			docked = d
			if not d then
				showIndex = false
			end
			layout()
			if win.Visible and current then
				local y = content.CanvasPosition.Y
				renderPage(current)
				task.defer(function()
					content.CanvasPosition = Vector2.new(0, y)
				end)
			end
		end
		lastCanSend = canSend
	end
end)
closeBtn.MouseButton1Click:Connect(close)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or UserInputService:GetFocusedTextBox() then
		return
	end
	if input.KeyCode == Enum.KeyCode.J then
		toggle()
	end
end)

-- o quiosque da recepção (servidor) pede para abrir
task.spawn(function()
	local ev = Remotes:WaitForChild("WikiOpen", 60)
	if ev then
		(ev :: RemoteEvent).OnClientEvent:Connect(function(pageId)
			open(if typeof(pageId) == "string" then pageId else nil)
		end)
	end
end)
