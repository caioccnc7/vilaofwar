-- Terminal do console dos equipamentos e a tela do terminal de compras.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TextService = game:GetService("TextService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UiFit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiFit"))
local ConsoleOpen = Remotes:WaitForChild("ConsoleOpen") :: RemoteEvent
local ConsoleCommand = Remotes:WaitForChild("ConsoleCommand") :: RemoteFunction
local ConsoleComplete = Remotes:WaitForChild("ConsoleComplete") :: RemoteFunction
local ShopOpen = Remotes:WaitForChild("ShopOpen") :: RemoteEvent
local ShopBuy = Remotes:WaitForChild("ShopBuy") :: RemoteEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GREEN = Color3.fromRGB(120, 230, 140)
local MAX_CHARS = 20000

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

local gui = new("ScreenGui", { Name = "Console", ResetOnSpawn = false, DisplayOrder = 20, Parent = playerGui })

-- ---------------------------------------------------------------------------
-- Terminal
-- ---------------------------------------------------------------------------

local win = new("Frame", { Name = "Terminal", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.72, 0.7), BackgroundColor3 = Color3.fromRGB(8, 10, 12), Visible = false, Parent = gui })
new("UICorner", { CornerRadius = UDim.new(0, 10), Parent = win })
new("UIStroke", { Color = Color3.fromRGB(70, 80, 95), Thickness = 2, Parent = win })
local titleBar = new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Color3.fromRGB(30, 34, 42), Parent = win })
new("UICorner", { CornerRadius = UDim.new(0, 10), Parent = titleBar })
local title = new("TextLabel", { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -212, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = Color3.fromRGB(220, 225, 235), TextXAlignment = Enum.TextXAlignment.Left, Text = "Console", Parent = titleBar })
local closeBtn = new("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(100, 22), BackgroundColor3 = Color3.fromRGB(170, 50, 50), Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = Color3.new(1, 1, 1), Text = "Fechar", Parent = titleBar })
new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = closeBtn })
-- botão que abre a wiki ao lado do console (a tecla J não serve: ela é digitada no console)
local wikiBtn = new("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -114, 0.5, 0), Size = UDim2.fromOffset(84, 22), BackgroundColor3 = Color3.fromRGB(30, 90, 130), Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = Color3.new(1, 1, 1), Text = if UiFit.touch then "Wiki" else "Wiki (F1)", Parent = titleBar })
new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = wikiBtn })

-- Com a wiki aberta junto (atributo WikiAberta, posto pela tela da wiki), o console
-- vai para a esquerda e a wiki fica na direita.
local small = false
local function layout()
	local docked = gui:GetAttribute("WikiAberta") == true
	if docked then
		win.AnchorPoint = Vector2.new(0, 0.5)
		win.Position = UDim2.fromScale(0.01, 0.5)
		win.Size = if small then UDim2.fromScale(0.5, 0.95) else UDim2.fromScale(0.57, 0.86)
	else
		win.AnchorPoint = Vector2.new(0.5, 0.5)
		win.Position = UDim2.fromScale(0.5, 0.5)
		-- no celular o console ocupa quase a tela toda
		win.Size = if small then UDim2.fromScale(0.97, 0.95) else UDim2.fromScale(0.72, 0.7)
	end
	wikiBtn.BackgroundColor3 = if docked then Color3.fromRGB(80, 190, 255) else Color3.fromRGB(30, 90, 130)
end
UiFit.onResize(gui, function(s)
	small = s
	layout()
end)
gui:GetAttributeChangedSignal("WikiAberta"):Connect(layout)

local scroll = new("ScrollingFrame", {
	Position = UDim2.fromOffset(10, 36),
	Size = UDim2.new(1, -20, 1, -80),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 8,
	CanvasSize = UDim2.new(),
	Parent = win,
})
local output = new("TextLabel", {
	Size = UDim2.new(1, -12, 0, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.Code,
	TextSize = 16,
	TextColor3 = GREEN,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
	Text = "",
	Parent = scroll,
})
local inputRow = new("Frame", { Position = UDim2.new(0, 10, 1, -38), Size = UDim2.new(1, -20, 0, 28), BackgroundColor3 = Color3.fromRGB(18, 22, 26), Parent = win })
new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = inputRow })
local promptLabel = new("TextLabel", { Position = UDim2.fromOffset(8, 0), Size = UDim2.new(0, 10, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 16, TextColor3 = Color3.fromRGB(240, 220, 120), TextXAlignment = Enum.TextXAlignment.Left, Text = "", Parent = inputRow })
local box = new("TextBox", {
	Position = UDim2.new(0, 8, 0, 0),
	Size = UDim2.new(1, -16, 1, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.Code,
	TextSize = 16,
	TextColor3 = Color3.new(1, 1, 1),
	PlaceholderText = "digite um comando · TAB completa · Enter executa",
	PlaceholderColor3 = Color3.fromRGB(90, 100, 110),
	TextXAlignment = Enum.TextXAlignment.Left,
	ClearTextOnFocus = false,
	Text = "",
	Parent = inputRow,
})

local currentId = nil
local currentPrompt = ""
local history: { string } = {}
local histIndex = 0
local busy = false
-- Fila de comandos: o jogador pode digitar o próximo enquanto o servidor
-- responde o anterior, como num terminal de verdade.
local queue: { string } = {}

-- Altura calculada na mão: AutomaticSize dentro de ScrollingFrame não cresce
-- o canvas de forma confiável, e a saída ficava cortada embaixo.
local function relayout()
	local w = math.max(50, scroll.AbsoluteSize.X - 12)
	local ok, sz = pcall(function()
		return TextService:GetTextSize(output.Text, output.TextSize, output.Font, Vector2.new(w, 1e6))
	end)
	local h = (if ok then sz.Y else 0) + 10
	output.Size = UDim2.new(1, -12, 0, h)
	scroll.CanvasSize = UDim2.fromOffset(0, h)
	scroll.CanvasPosition = Vector2.new(0, math.max(0, h - scroll.AbsoluteSize.Y))
end
scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)

local function append(text: string)
	local t = output.Text .. text
	if #t > MAX_CHARS then
		t = string.sub(t, #t - MAX_CHARS)
	end
	output.Text = t
	relayout()
end

local function clearOutput()
	output.Text = ""
	relayout()
end

-- página da wiki que combina com o que está aberto no console (a wiki abre nela)
local function wikiContext(p: string)
	local t = title.Text
	local page
	if string.find(p, "^%[admin@") then
		page = "roteador"
	elseif p ~= "" and string.find(p, "[#>]$") then
		page = "olt"
	elseif string.find(t, "RouterOS") then
		page = "roteador"
	elseif string.find(t, "MA5800") then
		page = "olt"
	elseif string.find(t, "Notebook") then
		page = "notebook"
	elseif string.find(t, "PC do NOC") then
		page = "pcs-noc"
	else
		page = "sala-de-rack"
	end
	gui:SetAttribute("WikiPagina", page)
end

local function setPrompt(p: string)
	currentPrompt = p
	promptLabel.Text = p
	wikiContext(p)
	task.defer(function()
		local w = promptLabel.AbsoluteSize.X
		box.Position = UDim2.new(0, 8 + w + 4, 0, 0)
		box.Size = UDim2.new(1, -(16 + w + 4 + (if UiFit.touch then 58 else 0)), 1, 0)
	end)
end

local function close()
	win.Visible = false
	currentId = nil
	table.clear(queue)
	box:ReleaseFocus()
end

closeBtn.MouseButton1Click:Connect(close)

ConsoleOpen.OnClientEvent:Connect(function(data)
	title.Text = data.title
	clearOutput()
	append(data.banner .. "\n")
	currentId = data.id
	win.Visible = true
	inputRow.Visible = data.id ~= 0
	wikiContext(if data.id ~= 0 then data.prompt or "" else "")
	if data.id == 0 then
		-- manual e ficha: começa a leitura do topo
		scroll.CanvasPosition = Vector2.zero
	end
	if data.id ~= 0 then
		setPrompt(data.prompt)
		task.defer(function()
			box:CaptureFocus()
		end)
	end
end)


local function runQueue()
	if busy then
		return
	end
	busy = true
	while #queue > 0 and currentId and currentId ~= 0 do
		local line = table.remove(queue, 1) :: string
		append(currentPrompt .. line .. "\n")
		local id = currentId
		local ok, res = pcall(function()
			return ConsoleCommand:InvokeServer(id, line)
		end)
		if currentId ~= id then
			break
		end
		if not ok or type(res) ~= "table" then
			append("% Sem resposta\n")
		else
			if res.output and res.output ~= "" then
				append(res.output .. "\n")
			end
			if res.closed then
				currentId = nil
				inputRow.Visible = false
				table.clear(queue)
				break
			end
			if res.prompt and res.prompt ~= "" then
				currentPrompt = res.prompt
				setPrompt(res.prompt)
			end
		end
	end
	busy = false
end

box.FocusLost:Connect(function(enterPressed)
	if not enterPressed or not currentId or currentId == 0 then
		return
	end
	local line = box.Text
	box.Text = ""
	task.defer(function()
		if win.Visible and inputRow.Visible then
			box:CaptureFocus()
		end
	end)
	if line ~= "" then
		table.insert(history, line)
		if #history > 50 then
			table.remove(history, 1)
		end
	end
	histIndex = #history + 1
	if line == "clear" or line == "cls" then
		clearOutput()
		return
	end
	if #queue < 20 then
		table.insert(queue, line)
	end
	task.spawn(runQueue)
end)

-- ---------------------------------------------------------------------------
-- TAB: completa o comando ou lista as opções parecidas (quem decide é o servidor,
-- que sabe em que equipamento e em que menu/modo o jogador está)
-- ---------------------------------------------------------------------------

local completing = false
local lastTab = 0
local settingText = false

local function setBoxText(t: string)
	settingText = true
	box.Text = t
	box.CursorPosition = #t + 1
	settingText = false
end

local function doComplete()
	if completing or not currentId or currentId == 0 or busy or #queue > 0 then
		return
	end
	if os.clock() - lastTab < 0.08 then
		return
	end
	lastTab = os.clock()
	completing = true
	local line = string.gsub(box.Text, "[\r\n\t]", "")
	local id = currentId
	local ok, res = pcall(function()
		return ConsoleComplete:InvokeServer(id, line)
	end)
	completing = false
	if currentId ~= id then
		return
	end
	if not ok or type(res) ~= "table" then
		setBoxText(line)
		return
	end
	if type(res.show) == "string" and res.show ~= "" then
		-- como no terminal: repete a linha, mostra as opções e devolve o que já foi digitado
		append(currentPrompt .. line .. "\n" .. res.show .. "\n")
	end
	if type(res.line) == "string" then
		setBoxText(res.line)
	else
		setBoxText(line)
	end
	if win.Visible and inputRow.Visible and not box:IsFocused() then
		box:CaptureFocus()
	end
end

-- o TextBox do Roblox pode inserir o caractere de tabulação: tira e trata como TAB
box:GetPropertyChangedSignal("Text"):Connect(function()
	if settingText then
		return
	end
	local t = box.Text
	local hasTab = string.find(t, "\t", 1, true) ~= nil
	if hasTab or string.find(t, "[\r\n]") then
		-- tira o TAB e também o \r que o Enter deixa no começo da caixa
		setBoxText((string.gsub(t, "[\r\n\t]", "")))
		if hasTab then
			task.spawn(doComplete)
		end
	end
end)

-- celular não tem tecla TAB: botão ao lado da linha de comando
if UiFit.touch then
	local tabBtn = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		Size = UDim2.fromOffset(52, 22),
		BackgroundColor3 = Color3.fromRGB(50, 60, 75),
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "TAB",
		ZIndex = 3,
		Parent = inputRow,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 5), Parent = tabBtn })
	tabBtn.Activated:Connect(function()
		task.spawn(doComplete)
	end)
end

local function toggleWiki()
	-- no celular o teclado virtual cobre a wiki: solta a linha de comando
	if UiFit.touch then
		box:ReleaseFocus()
	end
	local w = playerGui:FindFirstChild("Wiki")
	local ev = w and w:FindFirstChild("Alternar")
	if ev then
		(ev :: BindableEvent):Fire(gui:GetAttribute("WikiPagina"))
	end
end
wikiBtn.Activated:Connect(toggleWiki)

-- a wiki manda um comando (clique num bloco de código): vai para a linha do console,
-- sem executar. O jogador confere, troca o que precisar e aperta Enter.
local insertEv = new("BindableEvent", { Name = "Inserir", Parent = gui })
insertEv.Event:Connect(function(cmd)
	if typeof(cmd) ~= "string" or not win.Visible or not inputRow.Visible then
		return
	end
	setBoxText((string.gsub(cmd, "[\r\n\t]", "")))
	task.defer(function()
		box:CaptureFocus()
		box.CursorPosition = #box.Text + 1
	end)
end)

UserInputService.InputBegan:Connect(function(input)
	if not win.Visible then
		return
	end
	if input.KeyCode == Enum.KeyCode.F1 then
		toggleWiki()
	elseif box:IsFocused() and input.KeyCode == Enum.KeyCode.Tab then
		task.spawn(doComplete)
	elseif box:IsFocused() and input.KeyCode == Enum.KeyCode.Up and #history > 0 then
		histIndex = math.max(1, histIndex - 1)
		box.Text = history[histIndex] or ""
		box.CursorPosition = #box.Text + 1
	elseif box:IsFocused() and input.KeyCode == Enum.KeyCode.Down and #history > 0 then
		histIndex = math.min(#history + 1, histIndex + 1)
		box.Text = history[histIndex] or ""
		box.CursorPosition = #box.Text + 1
	end
end)

-- ---------------------------------------------------------------------------
-- Loja: terminal de compras com abas (equipamentos, ferramentas, insumos e financeiro)
-- ---------------------------------------------------------------------------

local shop = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(660, 470), BackgroundColor3 = Color3.fromRGB(16, 20, 30), Visible = false, Parent = gui })
-- encolhe para caber no celular (a janela é desenhada em 660 × 470)
UiFit.scale(shop, 660, 470, 10)
new("UICorner", { CornerRadius = UDim.new(0, 14), Parent = shop })
new("UIStroke", { Color = Color3.fromRGB(80, 190, 255), Thickness = 2, Parent = shop })
new("TextLabel", { Position = UDim2.fromOffset(18, 10), Size = UDim2.new(0.6, 0, 0, 30), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 22, TextColor3 = Color3.fromRGB(80, 190, 255), TextXAlignment = Enum.TextXAlignment.Left, Text = "Terminal de compras", Parent = shop })
local cashLabel = new("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -62, 0, 12), Size = UDim2.new(0.4, -44, 0, 26), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = Color3.fromRGB(240, 200, 40), TextXAlignment = Enum.TextXAlignment.Right, Text = "", Parent = shop })

local tabsRow = new("Frame", { Position = UDim2.fromOffset(18, 48), Size = UDim2.new(1, -36, 0, 32), BackgroundTransparency = 1, Parent = shop })
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), Parent = tabsRow })
local list = new("ScrollingFrame", { Position = UDim2.fromOffset(18, 90), Size = UDim2.new(1, -36, 1, -150), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, CanvasSize = UDim2.new(), Parent = shop })
local listLayout = new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	list.CanvasSize = UDim2.fromOffset(0, listLayout.AbsoluteContentSize.Y + 8)
end)
local shopClose = new("TextButton", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(160, 36), BackgroundColor3 = Color3.fromRGB(60, 66, 80), Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = Color3.new(1, 1, 1), Text = "Fechar", Parent = shop })
new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = shopClose })
shopClose.MouseButton1Click:Connect(function()
	shop.Visible = false
end)
UiFit.closeX(shop, function()
	shop.Visible = false
end)

local Tabs = {
	{ id = "equip", label = "Equipamentos", kinds = { router = true, olt = true, link = true } },
	{ id = "tool", label = "Ferramentas", kinds = { tool = true } },
	{ id = "supply", label = "Insumos", kinds = { supply = true } },
	{ id = "team", label = "Equipe" },
	{ id = "finance", label = "Financeiro" },
}
local confirmFire: any = false
local currentTab = "tool"
local lastData: any = nil
local tabButtons = {}
local renderShop: () -> ()

for i, t in Tabs do
	local b = new("TextButton", { LayoutOrder = i, Size = UDim2.fromOffset(117, 32), BackgroundColor3 = Color3.fromRGB(40, 46, 60), Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = Color3.new(1, 1, 1), Text = t.label, Parent = tabsRow })
	new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = b })
	tabButtons[t.id] = b
	b.MouseButton1Click:Connect(function()
		currentTab = t.id
		confirmFire = false
		renderShop()
	end)
end

local function rowFrame(order: number, height: number): Frame
	local row = new("Frame", { LayoutOrder = order, Size = UDim2.new(1, -8, 0, height), BackgroundColor3 = Color3.fromRGB(28, 34, 46), Parent = list })
	new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = row })
	return row
end

local function rowText(row: Frame, title: string, info: string)
	new("TextLabel", { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -170, 0, 24), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left, Text = title, Parent = row })
	new("TextLabel", { Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -170, 1, -34), BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 13, TextWrapped = true, TextColor3 = Color3.fromRGB(150, 160, 175), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = info, Parent = row })
end

local function rowButton(row: Frame, label: string, enabled: boolean, onClick: () -> ())
	local buy = new("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(140, 38), BackgroundColor3 = if enabled then Color3.fromRGB(46, 160, 90) else Color3.fromRGB(60, 66, 80), AutoButtonColor = enabled, Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = Color3.new(1, 1, 1), Text = label, Parent = row })
	new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = buy })
	if enabled then
		buy.MouseButton1Click:Connect(onClick)
	end
end

renderShop = function()
	for _, c in list:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for id, b in tabButtons do
		b.BackgroundColor3 = if id == currentTab then Color3.fromRGB(80, 190, 255) else Color3.fromRGB(40, 46, 60)
		b.TextColor3 = if id == currentTab then Color3.fromRGB(10, 14, 22) else Color3.new(1, 1, 1)
	end
	local data = lastData
	if not data then
		return
	end
	cashLabel.Text = string.format("Caixa: R$ %d", data.money)
	list.CanvasPosition = Vector2.zero

	if currentTab == "team" then
		local tk = data.tech
		if not tk then
			return
		end
		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end
		-- carro da equipe
		local car = tk.car
		local carRow = rowFrame(nextOrder(), 96)
		if car.owned then
			rowText(carRow, car.name .. " · " .. car.stateText, string.format("Custa R$ %d por dia (combustível e seguro). Para dirigir: E na porta do motorista. Os técnicos só usam o carro quando ele está na garagem.", car.dailyCost))
			rowButton(carRow, "Recolher", car.state == "away", function()
				ShopBuy:FireServer("car_recall")
			end)
		else
			rowText(carRow, car.name, string.format("Deixa o técnico (e você) muito mais rápido na Rua das Palmeiras. Fica na garagem ao lado do prédio. Custo diário de R$ %d. O técnico vai a pé quando o carro não está na garagem.", car.dailyCost))
			rowButton(carRow, "Comprar R$ " .. car.price, data.money >= car.price, function()
				ShopBuy:FireServer("car_buy")
			end)
		end
		-- contratar
		local hireRow = rowFrame(nextOrder(), 96)
		if tk.canHire then
			rowText(hireRow, "Contratar " .. tk.nextName, string.format("Técnico de rua: emenda fibra, refaz conector e troca ONU, gastando o estoque. Trabalha das %dh às %dh. Salário R$ %d por dia. Equipe atual: %d de %d.", tk.workStart, tk.workEnd, tk.salary, #tk.team, tk.max))
			rowButton(hireRow, "Contratar R$ " .. tk.hireFee, data.money >= tk.hireFee, function()
				ShopBuy:FireServer("tech_hire")
			end)
		else
			rowText(hireRow, "Equipe completa", string.format("Você já tem %d técnicos, o máximo do jogo.", #tk.team))
			rowButton(hireRow, "Contratar", false, function() end)
		end
		-- equipe atual
		for _, m in tk.team do
			local row = rowFrame(nextOrder(), 72)
			rowText(row, m.name .. (if m.car then " · com o carro" else ""), string.format("%s\nTrabalhou %d dia(s) · consertos hoje: %d", m.state, m.daysWorked, m.jobsToday))
			local confirming = confirmFire == m.id
			rowButton(row, if confirming then "Confirmar demissão" else "Demitir R$ " .. m.severance, data.money >= m.severance, function()
				if confirmFire ~= m.id then
					confirmFire = m.id
					renderShop()
					return
				end
				confirmFire = false
				ShopBuy:FireServer("tech_fire:" .. m.id)
			end)
		end
		local info = rowFrame(nextOrder(), 96)
		rowText(info, string.format("Gasto diário da equipe: R$ %d", tk.dailyTotal), string.format("O salário sai todo dia, com ou sem problema na rua. Demitir custa uma rescisão de R$ %d por dia trabalhado (mínimo R$ %d). Técnico não mexe na OLT: ONU trocada por ele ainda precisa ser autorizada.", tk.severancePerDay, tk.severanceMin))
		return
	end

	if currentTab == "finance" then
		local L = data.loan
		local row = rowFrame(1, 110)
		rowText(row, "Crédito do governo · " .. L.name, string.format("Recebe R$ %d agora e devolve R$ %d (juros de %d%%), em parcelas de R$ %d descontadas no fechamento de cada dia. Um pedido por dia.", L.amount, L.repay, math.floor((L.repay / L.amount - 1) * 100 + 0.5), L.daily))
		rowButton(row, if L.canRequest then "Pedir R$ " .. L.amount else "Indisponível", L.canRequest, function()
			ShopBuy:FireServer("loan")
		end)
		local row2 = rowFrame(2, 70)
		rowText(row2, string.format("Dívida atual: R$ %d", L.debt), if L.canRequest then string.format("Limite de dívida: R$ %d.", L.maxDebt) else L.reason)
		return
	end

	local tab = nil
	for _, t in Tabs do
		if t.id == currentTab then
			tab = t
		end
	end
	local order = 0
	for _, it in data.items do
		if tab and tab.kinds and tab.kinds[it.kind] then
			order += 1
			local row = rowFrame(order, 64)
			local info = it.info
			if it.stock ~= nil then
				info = string.format("Em estoque: %d · %s", it.stock, info)
			end
			rowText(row, it.name, info)
			if it.owned then
				rowButton(row, "Já é do provedor", false, function() end)
			else
				rowButton(row, "R$ " .. it.price, data.money >= it.price, function()
					ShopBuy:FireServer(it.id)
				end)
			end
		end
	end
end

ShopOpen.OnClientEvent:Connect(function(data)
	local firstOpen = not shop.Visible
	lastData = data
	if firstOpen then
		-- primeira vez: abre na aba do que ainda falta comprar
		local missingTool = false
		for _, it in data.items do
			if it.kind == "tool" and not it.owned then
				missingTool = true
			end
		end
		currentTab = if missingTool then "tool" else "supply"
	end
	renderShop()
	shop.Visible = true
end)

-- ---------------------------------------------------------------------------
-- Menu de ações do equipamento do rack
-- Um prompt só ("Opções", E) por equipamento abre este painel. Cada ação tem
-- a sua tecla, como no prompt antigo, mas agora organizadas numa lista.
-- ---------------------------------------------------------------------------

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RackMenu = Remotes:WaitForChild("RackMenu") :: RemoteEvent
local RackAction = Remotes:WaitForChild("RackAction") :: RemoteEvent

local MENU_BG = Color3.fromRGB(16, 20, 30)
local MENU_ROW = Color3.fromRGB(28, 34, 46)
local MENU_ACCENT = Color3.fromRGB(80, 190, 255)
local MENU_QUIET = Color3.fromRGB(150, 160, 175)
local MENU_DANGER = Color3.fromRGB(200, 70, 60)
local StateColor = {
	ok = Color3.fromRGB(46, 204, 113),
	boot = Color3.fromRGB(241, 196, 15),
	config = Color3.fromRGB(230, 126, 34),
	nocable = Color3.fromRGB(230, 126, 34),
	off = Color3.fromRGB(127, 140, 141),
	fail = Color3.fromRGB(231, 76, 60),
}

local menu = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -24, 0.5, 0), Size = UDim2.fromOffset(330, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = MENU_BG, Visible = false, Parent = gui })
new("UICorner", { CornerRadius = UDim.new(0, 12), Parent = menu })
new("UIStroke", { Color = MENU_ACCENT, Thickness = 2, Parent = menu })
new("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), Parent = menu })
new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = menu })
UiFit.scale(menu, 360, 450, 10)

local menuTitle = new("TextLabel", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 22, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left, Text = "", Parent = menu })
local menuSub = new("TextLabel", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 14, TextColor3 = MENU_QUIET, TextXAlignment = Enum.TextXAlignment.Left, Text = "", Parent = menu })
local stateRow = new("Frame", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = MENU_ROW, Parent = menu })
new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = stateRow })
local stateDot = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = StateColor.ok, Parent = stateRow })
new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = stateDot })
local stateText = new("TextLabel", { Position = UDim2.fromOffset(32, 0), Size = UDim2.new(1, -40, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left, Text = "", Parent = stateRow })

type MenuButton = { frame: TextButton, chip: TextLabel, text: TextLabel, hint: TextLabel, enabled: boolean }
local function menuButton(order: number, key: string): MenuButton
	local b = new("TextButton", { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = MENU_ROW, AutoButtonColor = true, Text = "", Parent = menu })
	new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = b })
	local chip = new("TextLabel", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), Size = UDim2.fromOffset(32, 32), BackgroundColor3 = Color3.fromRGB(235, 240, 248), Font = Enum.Font.GothamBlack, TextSize = 16, TextColor3 = Color3.fromRGB(16, 20, 30), Text = key, Parent = b })
	new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = chip })
	local text = new("TextLabel", { Position = UDim2.new(0, 50, 0, 4), Size = UDim2.new(1, -58, 0, 22), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left, Text = "", Parent = b })
	local hint = new("TextLabel", { Position = UDim2.new(0, 50, 0, 25), Size = UDim2.new(1, -58, 0, 16), BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = MENU_QUIET, TextXAlignment = Enum.TextXAlignment.Left, Text = "", Parent = b })
	return { frame = b, chip = chip, text = text, hint = hint, enabled = true }
end

local btn = {
	console = menuButton(10, "E"),
	power = menuButton(11, "R"),
	cables = menuButton(12, "F"),
	manual = menuButton(13, "H"),
	remove = menuButton(14, "G"),
}
local Keys = { [Enum.KeyCode.E] = "console", [Enum.KeyCode.R] = "power", [Enum.KeyCode.F] = "cables", [Enum.KeyCode.H] = "manual", [Enum.KeyCode.G] = "remove" }
new("TextLabel", { LayoutOrder = 20, Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = MENU_QUIET, Text = if UiFit.touch then "Toque no X ou afaste-se para fechar" else "Esc ou Q fecha · afaste-se para fechar", Parent = menu })
local menuX = UiFit.closeX(menuTitle, function() end, 30)
menuX.Position = UDim2.new(1, 0, 0, -2)

local menuData: any = nil
local confirmRemove = false

local function setButton(b: MenuButton, label: string, hint: string, enabled: boolean, danger: boolean?)
	b.enabled = enabled
	b.text.Text = label
	b.hint.Text = hint
	b.frame.AutoButtonColor = enabled
	b.frame.BackgroundColor3 = if danger and enabled then Color3.fromRGB(70, 32, 32) else MENU_ROW
	b.text.TextColor3 = if enabled then (if danger then Color3.fromRGB(255, 150, 140) else Color3.new(1, 1, 1)) else Color3.fromRGB(100, 108, 122)
	b.chip.BackgroundTransparency = if enabled then 0 else 0.6
end

local function closeMenu(tellServer: boolean)
	if menu.Visible and tellServer and menuData then
		RackAction:FireServer(menuData.id, "close")
	end
	menu.Visible = false
	menuData = nil
	confirmRemove = false
	ProximityPromptService.Enabled = true
end

local function renderMenu()
	local d = menuData
	if not d then
		return
	end
	menuTitle.Text = d.label
	menuSub.Text = string.format("%s · slot %d · %s", d.model, d.slot, d.ip)
	stateDot.BackgroundColor3 = StateColor[d.state] or MENU_QUIET
	stateText.Text = d.stateText
	local canConsole = d.powered and not d.failed
	setButton(btn.console, "Abrir console", if canConsole then "Cabo de console direto no equipamento" else "Ligue a energia primeiro", canConsole)
	setButton(btn.power, if d.powered then "Desligar energia" else "Ligar energia", if d.powered then "Derruba a rede que passa por ele" else "Leva uns segundos para inicializar", true)
	setButton(btn.cables, if d.cabled then "Desconectar cabos" else "Conectar cabos", if d.cabled then "Tira os cabos de rede e as fibras" else "Liga os cabos de rede e as fibras", true)
	setButton(btn.manual, "Ler manual", "Comandos do equipamento", true)
	if d.powered then
		setButton(btn.remove, "Remover do rack", "Desligue antes de remover", false, true)
	else
		setButton(btn.remove, if confirmRemove then "Confirmar remoção (G de novo)" else "Remover do rack", "Tira o equipamento e libera o slot", true, true)
	end
end

local function act(action: string)
	local d = menuData
	if not d then
		return
	end
	local b = btn[action]
	if b and not b.enabled then
		return
	end
	if action == "remove" and not confirmRemove then
		confirmRemove = true
		renderMenu()
		return
	end
	confirmRemove = false
	if action == "console" or action == "manual" then
		closeMenu(false)
	end
	RackAction:FireServer(d.id, action)
end

for action, b in btn do
	b.frame.MouseButton1Click:Connect(function()
		act(action)
	end)
end

RackMenu.OnClientEvent:Connect(function(data)
	if not data then
		closeMenu(false)
		return
	end
	if not menuData or menuData.id ~= data.id then
		confirmRemove = false
	end
	menuData = data
	renderMenu()
	menu.Visible = true
	-- com o menu aberto, a tecla E é do menu (abrir console), não do prompt
	ProximityPromptService.Enabled = false
end)

menuX.Activated:Connect(function()
	closeMenu(true)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not menu.Visible or processed or UserInputService:GetFocusedTextBox() then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.Backspace then
		closeMenu(true)
		return
	end
	local action = Keys[input.KeyCode]
	if action then
		act(action)
	end
end)

-- fecha sozinho quando o jogador se afasta do equipamento
RunService.Heartbeat:Connect(function()
	if not menu.Visible or not menuData then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or (root.Position - menuData.pos).Magnitude > 12 then
		closeMenu(true)
	end
end)

-- Slot vazio do rack: o prompt "Instalar equipamento" só aparece para quem está
-- segurando a caixa de um equipamento, e só se o slot estiver livre.
task.spawn(function()
	while true do
		local char = player.Character
		local tool = char and char:FindFirstChildOfClass("Tool")
		local holdingBox = tool ~= nil and tool:GetAttribute("EquipmentKind") ~= nil
		for _, part in CollectionService:GetTagged("RackSlot") do
			local p = part:FindFirstChildOfClass("ProximityPrompt")
			if p then
				p.Enabled = holdingBox and part:GetAttribute("Free") == true
			end
		end
		task.wait(0.3)
	end
end)
