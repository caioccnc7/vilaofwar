-- Tela do ERP do provedor: ordens de serviço (agenda dos técnicos), equipe, receitas e
-- despesas e estoque. Abre com a tecla O, pelo botão "ERP" na tela ou no computador do
-- balcão da recepção. Enquanto está aberta, o servidor manda os dados a cada segundo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local UiFit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiFit"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ErpOpen = Remotes:WaitForChild("ErpOpen") :: RemoteEvent
local ErpAction = Remotes:WaitForChild("ErpAction") :: RemoteEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local BG = Color3.fromRGB(16, 20, 30)
local ROW = Color3.fromRGB(28, 34, 46)
local INK = Color3.fromRGB(235, 240, 248)
local QUIET = Color3.fromRGB(150, 160, 175)
local ACCENT = Color3.fromRGB(80, 190, 255)
local GREEN = Color3.fromRGB(46, 160, 90)
local RED = Color3.fromRGB(190, 60, 55)
local GREY = Color3.fromRGB(60, 66, 80)
local GOOD = Color3.fromRGB(46, 204, 113)
local WARN = Color3.fromRGB(241, 196, 15)
local BAD = Color3.fromRGB(231, 76, 60)

local StatusColor = {
	pendente = WARN,
	agendada = ACCENT,
	execucao = Color3.fromRGB(230, 126, 34),
	concluida = GOOD,
	cancelada = QUIET,
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

local gui = new("ScreenGui", { Name = "ERP", ResetOnSpawn = false, DisplayOrder = 22, Parent = playerGui })

-- ---------------------------------------------------------------------------
-- Janela
-- ---------------------------------------------------------------------------

local W, H = 700, 480
local win = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(W, H), BackgroundColor3 = BG, Visible = false, Parent = gui })
corner(win, 14)
new("UIStroke", { Color = ACCENT, Thickness = 2, Parent = win })
UiFit.scale(win, W, H, 10)

local title = new("TextLabel", { Position = UDim2.fromOffset(18, 10), Size = UDim2.new(0.55, 0, 0, 30), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 22, TextColor3 = ACCENT, TextXAlignment = Enum.TextXAlignment.Left, Text = "ERP", Parent = win })
local cash = new("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -60, 0, 12), Size = UDim2.new(0.42, -40, 0, 26), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = Color3.fromRGB(240, 200, 40), TextXAlignment = Enum.TextXAlignment.Right, Text = "", Parent = win })

local tabsRow = new("Frame", { Position = UDim2.fromOffset(18, 48), Size = UDim2.new(1, -36, 0, 32), BackgroundTransparency = 1, Parent = win })
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), Parent = tabsRow })

local list = new("ScrollingFrame", { Position = UDim2.fromOffset(18, 90), Size = UDim2.new(1, -36, 1, -104), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, CanvasSize = UDim2.new(), Parent = win })
local listLayout = new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	list.CanvasSize = UDim2.fromOffset(0, listLayout.AbsoluteContentSize.Y + 8)
end)

local function closeWindow()
	if win.Visible then
		win.Visible = false
		ErpAction:FireServer("close")
	end
end
UiFit.closeX(win, closeWindow)

local Tabs = {
	{ id = "orders", label = "Ordens de serviço" },
	{ id = "team", label = "Equipe" },
	{ id = "finance", label = "Receitas e despesas" },
	{ id = "stock", label = "Estoque" },
}
local currentTab = "orders"
local data: any = nil
local lastKey = ""
local confirmAtt = false
local tabButtons = {}
local render: () -> ()

for i, t in Tabs do
	local b = new("TextButton", { LayoutOrder = i, Size = UDim2.fromOffset(if i == 1 or i == 3 then 182 else 120, 32), BackgroundColor3 = Color3.fromRGB(40, 46, 60), Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = Color3.new(1, 1, 1), Text = t.label, Parent = tabsRow })
	corner(b, 8)
	tabButtons[t.id] = b
	b.Activated:Connect(function()
		currentTab = t.id
		confirmAtt = false
		list.CanvasPosition = Vector2.zero
		render()
	end)
end

-- ---------------------------------------------------------------------------
-- Peças da lista
-- ---------------------------------------------------------------------------

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function header(text: string)
	new("TextLabel", { LayoutOrder = nextOrder(), Size = UDim2.new(1, -8, 0, 26), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 15, TextColor3 = ACCENT, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Bottom, Text = text, Parent = list })
end

local function line(text: string, color: Color3?, size: number?)
	new("TextLabel", { LayoutOrder = nextOrder(), Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = size or 14, TextWrapped = true, RichText = true, TextColor3 = color or INK, TextXAlignment = Enum.TextXAlignment.Left, Text = text, Parent = list })
end

type Btn = { label: string, enabled: boolean, color: Color3?, onClick: () -> () }

-- linha com título, texto e até 2 botões à direita
local function row(titleText: string, info: string, buttons: { Btn }?, stripe: Color3?)
	local r = new("Frame", { LayoutOrder = nextOrder(), Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = ROW, Parent = list })
	corner(r, 8)
	new("UISizeConstraint", { MinSize = Vector2.new(0, 52), Parent = r })
	if stripe then
		new("Frame", { Size = UDim2.new(0, 5, 1, 0), BackgroundColor3 = stripe, BorderSizePixel = 0, Parent = r })
	end
	local nb = if buttons then #buttons else 0
	local textCol = new("Frame", { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -(nb * 128 + 22), 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = r })
	new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = textCol })
	new("UIPadding", { PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 8), Parent = textCol })
	new("TextLabel", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 15, TextWrapped = true, RichText = true, TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Left, Text = titleText, Parent = textCol })
	if info ~= "" then
		new("TextLabel", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 13, TextWrapped = true, RichText = true, TextColor3 = QUIET, TextXAlignment = Enum.TextXAlignment.Left, Text = info, Parent = textCol })
	end
	if buttons then
		for i, b in buttons do
			local btn = new("TextButton", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10 - (nb - i) * 128, 0.5, 0),
				Size = UDim2.fromOffset(120, 36),
				BackgroundColor3 = if b.enabled then (b.color or GREEN) else GREY,
				AutoButtonColor = b.enabled,
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextWrapped = true,
				TextColor3 = Color3.new(1, 1, 1),
				Text = b.label,
				Parent = r,
			})
			corner(btn, 8)
			if b.enabled then
				btn.Activated:Connect(b.onClick)
			end
		end
	end
end

local function money(v: number): string
	return string.format("R$ %d", math.floor(v + 0.5))
end

local function send(action: string, arg: any?)
	ErpAction:FireServer(action, arg)
end

-- ---------------------------------------------------------------------------
-- Abas
-- ---------------------------------------------------------------------------

local function orderInfo(o: any): string
	local parts = { string.format("Aberta %s %s", o.opened, o.origin) }
	if o.scheduled then
		table.insert(parts, string.format("agendada %s por %s", o.scheduled, o.by or "?"))
	end
	if o.closed then
		table.insert(parts, "encerrada " .. o.closed)
	end
	local text = table.concat(parts, " · ")
	if o.note and o.note ~= "" then
		text ..= "\n" .. o.note
	end
	return text
end

local function orderTitle(o: any): string
	local color = StatusColor[o.status] or INK
	return string.format('#%d · %s · Casa %d (%s) · <font color="#%s">%s</font>', o.id, o.kindText, o.index, o.client, color:ToHex(), o.statusText)
end

local function renderOrders()
	local c = data.counts
	line(string.format("Aguardando agendamento: <b>%d</b> · Agendadas: <b>%d</b> · Em execução: <b>%d</b> · Concluídas hoje: <b>%d</b>", c.pendente, c.agendada, c.execucao, c.concluidas))
	local at = data.attendant
	if at.hired then
		line(string.format("%s agenda as OS e ativa na OLT os clientes instalados, das %dh às %dh. Agora: %s.", at.name, at.workStart, at.workEnd, at.state), QUIET, 13)
	else
		line("Sem atendente: aperte <b>Agendar</b> em cada OS ou contrate uma atendente na aba Equipe.", WARN, 13)
	end

	-- clientes instalados que ainda não navegam: falta ativar na OLT
	local olt = data.olt
	if olt and (#olt.pending > 0 or not olt.ready) then
		header("Ativação na OLT")
		line(olt.text, if olt.ready then QUIET else WARN, 13)
		if #olt.pending == 0 then
			line("Nenhum cliente esperando ativação.", QUIET, 13)
		end
		for _, a in olt.pending do
			local info = string.format("SN %s · porta PON %d · %s", a.sn, a.port, a.state)
			if olt.ready and at.hired then
				info ..= "\n" .. at.name .. " ativa sozinha no horário de trabalho."
			end
			row(string.format("Casa %d (%s)", a.index, a.client), info, {
				{ label = "Ativar", enabled = olt.ready, color = ACCENT, onClick = function()
					send("activate", a.index)
				end },
			}, WARN)
		end
	end

	local pend, agenda = {}, {}
	for _, o in data.orders do
		if o.status == "pendente" then
			table.insert(pend, o)
		else
			table.insert(agenda, o)
		end
	end
	header("Aguardando agendamento")
	if #pend == 0 then
		line("Nenhuma OS esperando.", QUIET, 13)
	end
	for _, o in pend do
		row(orderTitle(o), orderInfo(o), {
			{ label = "Cancelar", enabled = true, color = RED, onClick = function()
				send("cancel", o.id)
			end },
			{ label = "Agendar", enabled = true, onClick = function()
				send("schedule", o.id)
			end },
		}, StatusColor.pendente)
	end

	header("Na agenda dos técnicos")
	if #agenda == 0 then
		line("Ninguém na rua com OS agora.", QUIET, 13)
	end
	for _, o in agenda do
		local who = o.techName or "equipe (você faz na caixa da casa)"
		local btns = if o.status == "agendada" then { { label = "Cancelar", enabled = true, color = RED, onClick = function()
			send("cancel", o.id)
		end } } else nil
		row(orderTitle(o), "Responsável: " .. who .. "\n" .. orderInfo(o), btns, StatusColor[o.status])
	end

	if #data.problems > 0 then
		header("Clientes com problema e sem OS")
		for _, p in data.problems do
			row(string.format("Casa %d (%s) · %s", p.index, p.client, p.status), "No NOC: " .. p.reason .. ". Abra uma OS de reparo para mandar um técnico.", {
				{ label = "Abrir OS", enabled = true, color = ACCENT, onClick = function()
					send("repair", p.index)
				end },
			}, BAD)
		end
	end

	if #data.closed > 0 then
		header("Encerradas")
		for _, o in data.closed do
			row(orderTitle(o), orderInfo(o), nil, StatusColor[o.status])
		end
	end
end

local function renderTeam()
	local at = data.attendant
	header("Atendente do escritório")
	if at.hired then
		row(at.name .. " · " .. at.state, string.format("Registra os pedidos do balcão e os chamados por telefone e agenda no ERP, das %dh às %dh. Agendou %d hoje. Trabalhou %d dia(s). Salário %s por dia.", at.workStart, at.workEnd, at.done, at.daysWorked, money(at.salary)), {
			{ label = if confirmAtt then "Confirmar demissão" else "Demitir " .. money(at.severance), enabled = data.money >= at.severance, color = RED, onClick = function()
				if not confirmAtt then
					confirmAtt = true
					render()
					return
				end
				confirmAtt = false
				send("att_fire")
			end },
		}, GOOD)
	else
		row("Contratar " .. at.name, string.format("Fica no balcão da recepção, registra os pedidos de instalação e os chamados de reparo e agenda tudo para os técnicos, das %dh às %dh. Salário %s por dia.", at.workStart, at.workEnd, money(at.salary)), {
			{ label = "Contratar " .. money(at.hireFee), enabled = data.money >= at.hireFee, onClick = function()
				send("att_hire")
			end },
		}, QUIET)
	end

	header("Técnicos de rua")
	if data.canHireTech then
		row("Contratar " .. tostring(data.nextTech), string.format("Faz as OS da fila dele no celular: instalações e reparos. Salário %s por dia. Demitir só no terminal de compras.", money(data.techSalary)), {
			{ label = "Contratar " .. money(data.techHireFee), enabled = data.money >= data.techHireFee, onClick = function()
				send("tech_hire")
			end },
		}, QUIET)
	end
	if #data.techs == 0 then
		line("Nenhum técnico contratado. As OS agendadas ficam com a equipe: vá até a casa com a ferramenta certa.", QUIET, 13)
	end
	for _, m in data.techs do
		local fila = if #m.queue > 0 then table.concat(m.queue, ", ") else "vazia"
		row(m.name, string.format("%s\nFila no celular: %s\nOS feitas hoje: %d", m.state, fila, m.jobsToday), nil, ACCENT)
	end
	if data.unassigned > 0 then
		line(string.format("%d OS agendada(s) sem técnico: ficam com a equipe (você).", data.unassigned), WARN, 13)
	end
end

local function renderFinance()
	local f = data.finance
	local result = f.totalReceitas - f.totalDespesas
	header(string.format("Hoje (dia %d)", f.day))
	row(string.format('Receitas <font color="#%s">%s</font> · Despesas <font color="#%s">%s</font>', GOOD:ToHex(), money(f.totalReceitas), BAD:ToHex(), money(f.totalDespesas)), string.format("Resultado do dia até agora: %s%s. Mensalidades, link, salários e parcelas entram no fechamento do dia.", if result < 0 then "-" else "", money(math.abs(result))), nil, if result < 0 then BAD else GOOD)
	if f.temOntem then
		local y = f.ontemReceitas - f.ontemDespesas
		line(string.format("Ontem: receitas %s · despesas %s · resultado %s%s", money(f.ontemReceitas), money(f.ontemDespesas), if y < 0 then "-" else "", money(math.abs(y))), QUIET, 13)
	end
	if f.debt > 0 then
		line(string.format("Dívida com o crédito do governo: %s", money(f.debt)), WARN, 13)
	end
	header("Receitas por categoria")
	if #f.receitas == 0 then
		line("Nenhuma receita hoje.", QUIET, 13)
	end
	for _, c in f.receitas do
		line(string.format("%s: <b>%s</b>", c.name, money(c.amount)), GOOD, 14)
	end
	header("Despesas por categoria")
	if #f.despesas == 0 then
		line("Nenhuma despesa hoje.", QUIET, 13)
	end
	for _, c in f.despesas do
		line(string.format("%s: <b>%s</b>", c.name, money(c.amount)), BAD, 14)
	end
	header("Extrato (mais recente primeiro)")
	if #f.ledger == 0 then
		line("Sem lançamentos.", QUIET, 13)
	end
	for _, e in f.ledger do
		local sign = if e.kind == "receita" then "+" else "-"
		local color = if e.kind == "receita" then GOOD else BAD
		local desc = if e.desc ~= "" then " · " .. e.desc else ""
		line(string.format('Dia %d %s  <font color="#%s"><b>%s%s</b></font>  %s%s', e.day, e.time, color:ToHex(), sign, money(e.amount), e.category, desc), INK, 13)
	end
end

local function renderStock()
	local s = data.stock
	header("Insumos")
	for _, it in s.items do
		local low = it.qty < it.min
		local titleText = string.format('%s: <font color="#%s">%d em estoque</font>', it.name, (if low then BAD elseif it.qty == it.min then WARN else GOOD):ToHex(), it.qty)
		row(titleText, string.format("Mínimo %d%s · usadas hoje: %d · pacote com %d por %s", it.min, if low then " (abaixo do mínimo!)" else "", it.used, it.pack, money(it.price)), {
			{ label = "Comprar " .. money(it.price), enabled = data.money >= it.price, onClick = function()
				send("buy", it.key)
			end },
		}, if low then BAD else GOOD)
	end
	header("Ferramentas")
	local tools = {}
	for _, t in s.tools do
		table.insert(tools, t.name .. (if t.owned then " ✓" else string.format(" (falta: %s no terminal)", money(t.price))))
	end
	line(table.concat(tools, " · "), INK, 13)
	header("Movimentação (mais recente primeiro)")
	if #s.moves == 0 then
		line("Sem movimentação.", QUIET, 13)
	end
	for _, mv in s.moves do
		local color = if mv.delta > 0 then GOOD else BAD
		line(string.format('%s  <font color="#%s"><b>%s%d %s</b></font>  %s · ficou %d', mv.time, color:ToHex(), if mv.delta > 0 then "+" else "", mv.delta, mv.name, mv.reason, mv.after), INK, 13)
	end
end

render = function()
	for id, b in tabButtons do
		b.BackgroundColor3 = if id == currentTab then ACCENT else Color3.fromRGB(40, 46, 60)
		b.TextColor3 = if id == currentTab then Color3.fromRGB(10, 14, 22) else Color3.new(1, 1, 1)
	end
	if not data then
		return
	end
	local keep = list.CanvasPosition
	for _, c in list:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	order = 0
	title.Text = "ERP · " .. data.provider
	cash.Text = string.format("%s · Caixa %s", data.clock, money(data.money))
	if currentTab == "orders" then
		renderOrders()
	elseif currentTab == "team" then
		renderTeam()
	elseif currentTab == "finance" then
		renderFinance()
	else
		renderStock()
	end
	-- mantém a rolagem quando os dados chegam de novo
	task.defer(function()
		list.CanvasPosition = keep
	end)
end

ErpOpen.OnClientEvent:Connect(function(payload)
	if payload == nil then
		win.Visible = false
		return
	end
	data = payload
	-- só redesenha quando algo mudou (o servidor manda a cada segundo)
	local ok, key = pcall(HttpService.JSONEncode, HttpService, payload)
	key = if ok then key else tostring(os.clock())
	local firstOpen = not win.Visible
	win.Visible = true
	if firstOpen or key ~= lastKey or confirmAtt then
		lastKey = key
		if firstOpen then
			list.CanvasPosition = Vector2.zero
		end
		render()
	end
end)

local function toggle()
	if win.Visible then
		closeWindow()
	else
		ErpAction:FireServer("open")
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.O then
		toggle()
	end
end)

-- botão na tela: no celular embaixo do botão Provedor; no PC ao lado do botão da wiki
local openBtn = new("TextButton", {
	Name = "BotaoERP",
	AnchorPoint = if UiFit.touch then Vector2.new(0, 0) else Vector2.new(0, 1),
	Position = if UiFit.touch then UDim2.fromOffset(12, 214) else UDim2.new(0, 140, 1, -134),
	Size = UDim2.fromOffset(110, 36),
	BackgroundColor3 = BG,
	BackgroundTransparency = 0.1,
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	TextColor3 = ACCENT,
	Text = if UiFit.touch then "ERP" else "ERP  (O)",
	Parent = gui,
})
corner(openBtn, 8)
new("UIStroke", { Color = ACCENT, Thickness = 1.5, Parent = openBtn })
openBtn.Activated:Connect(toggle)
