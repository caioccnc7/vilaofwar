-- Tela Guerra dos provedores (tecla K ou botão "Guerra"): ataque DDoS, defesa e loja.
--   Ataque: o dono escolhe o alvo, o tipo e a duração. A força vem dos clientes online.
--   Defesa: ataques em andamento, o que o firewall do roteador já faz, anti-DDoS e
--           blackhole (RTBH) da operadora, equipamentos e histórico para denunciar.
--   Loja:   pacotes de dinheiro do jogo e Passe VIP, comprados com Robux.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local UiFit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiFit"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GuerraState = Remotes:WaitForChild("GuerraState") :: RemoteFunction
local GuerraAction = Remotes:WaitForChild("GuerraAction") :: RemoteEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local BG = Color3.fromRGB(16, 20, 30)
local ROW = Color3.fromRGB(28, 34, 46)
local INK = Color3.fromRGB(235, 240, 248)
local QUIET = Color3.fromRGB(150, 160, 175)
local ACCENT = Color3.fromRGB(255, 80, 90)
local GOLD = Color3.fromRGB(240, 200, 40)
local GREEN = Color3.fromRGB(46, 160, 90)
local RED = Color3.fromRGB(190, 60, 55)
local BLUE = Color3.fromRGB(60, 120, 220)
local OFF = Color3.fromRGB(60, 66, 80)
local GOOD = Color3.fromRGB(46, 204, 113)
local WARN = Color3.fromRGB(241, 196, 15)

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
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		RichText = true,
		Text = text,
		Parent = parent,
	})
	for k, v in props do
		(l :: any)[k] = v
	end
	return l
end

local function button(parent: Instance, text: string, color: Color3, enabled: boolean, props: { [string]: any }, onClick: () -> ()): TextButton
	local b = new("TextButton", {
		BackgroundColor3 = if enabled then color else OFF,
		AutoButtonColor = enabled,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = Color3.new(1, 1, 1),
		TextWrapped = true,
		Text = text,
		Parent = parent,
	})
	for k, v in props do
		(b :: any)[k] = v
	end
	corner(b, 6)
	if enabled then
		b.Activated:Connect(onClick)
	end
	return b
end

local gui = new("ScreenGui", { Name = "Guerra", ResetOnSpawn = false, DisplayOrder = 23, Parent = playerGui })

local W, H = 660, 500
local win = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(W, H), BackgroundColor3 = BG, Visible = false, Parent = gui })
corner(win, 14)
new("UIStroke", { Color = ACCENT, Thickness = 2, Parent = win })
UiFit.scale(win, W, H, 10)

label(win, "GUERRA DOS PROVEDORES", { Position = UDim2.fromOffset(18, 10), Size = UDim2.new(1, -220, 0, 30), Font = Enum.Font.GothamBlack, TextSize = 22, TextColor3 = ACCENT })
local cash = label(win, "", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -56, 0, 14), Size = UDim2.fromOffset(200, 24), Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Right })

local tabsRow = new("Frame", { Position = UDim2.fromOffset(18, 46), Size = UDim2.new(1, -36, 0, 32), BackgroundTransparency = 1, Parent = win })
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), Parent = tabsRow })

local list = new("ScrollingFrame", { Position = UDim2.fromOffset(18, 86), Size = UDim2.new(1, -36, 1, -98), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, ScrollBarImageColor3 = ACCENT, CanvasSize = UDim2.new(), Parent = win })
local layout = new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	list.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 8)
end)

local Tabs = {
	{ id = "ataque", label = "Ataque" },
	{ id = "defesa", label = "Defesa" },
	{ id = "loja", label = "Loja (Robux)" },
}
local currentTab = "defesa"
local tabButtons = {}
local data: any = nil
local lastKey = ""
local hours = 2
local render: () -> ()

for i, t in Tabs do
	local b = new("TextButton", { LayoutOrder = i, Size = UDim2.fromOffset(140, 32), BackgroundColor3 = ROW, Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = INK, Text = t.label, Parent = tabsRow })
	corner(b, 8)
	tabButtons[t.id] = b
	b.Activated:Connect(function()
		currentTab = t.id
		list.CanvasPosition = Vector2.zero
		render()
	end)
end

local order = 0
local function card(height: number): Frame
	order += 1
	local f = new("Frame", { LayoutOrder = order, Size = UDim2.new(1, -10, 0, height), BackgroundColor3 = ROW, Parent = list })
	corner(f, 10)
	return f
end

local function note(text: string, color: Color3?, height: number?)
	order += 1
	label(list, text, { LayoutOrder = order, Size = UDim2.new(1, -10, 0, height or 36), TextColor3 = color or QUIET, TextSize = 13 })
end

local function itemRow(it: any)
	local c = card(70)
	label(c, it.name, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -190, 0, 20), Font = Enum.Font.GothamBold, TextSize = 15 })
	label(c, it.info, { Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -190, 0, 38), TextColor3 = QUIET, TextSize = 12 })
	if it.owned then
		button(c, "Já é do provedor", GREEN, false, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(160, 36) }, function() end)
	else
		local can = data.money ~= nil and data.money >= it.price
		button(c, string.format("Comprar R$ %d", it.price), GREEN, can, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(160, 36) }, function()
			GuerraAction:FireServer("buy", it.key)
		end)
	end
end

local function check(ok: boolean, text: string, hint: string)
	local c = card(54)
	label(c, if ok then "✓" else "×", { Position = UDim2.fromOffset(12, 8), Size = UDim2.fromOffset(20, 24), Font = Enum.Font.GothamBlack, TextSize = 18, TextColor3 = if ok then GOOD else ACCENT })
	label(c, text, { Position = UDim2.fromOffset(38, 4), Size = UDim2.new(1, -48, 0, 18), Font = Enum.Font.GothamBold, TextSize = 14 })
	label(c, hint, { Position = UDim2.fromOffset(38, 23), Size = UDim2.new(1, -48, 0, 28), TextColor3 = QUIET, TextSize = 11, Font = Enum.Font.Code })
end

local function renderAtaque()
	if not data.provider then
		note("Você ainda não faz parte de um provedor. Abra o seu ou entre como sócio (tecla P).", WARN)
		return
	end
	note(string.format("<b>Botnet:</b> %d clientes online viram bots (mínimo %d). <b>SYN flood:</b> %d mil pacotes/s, %d%% do que um roteador sem proteção aguenta. <b>Volumétrico DNS:</b> %d Mbps%s.", data.bots, data.minBots, data.synKpps, data.synLoad, data.dnsMbps, if data.hasAmp then " (com Amplificador: passa do link da vítima)" else " (sem Amplificador: no máximo 95% do link da vítima, deixa lenta)"), INK, 54)
	note("Custo: durante o ataque, a internet dos seus clientes fica lenta (o upload deles vira bot). A vítima pode rastrear a origem e denunciar na Delegacia: multa de R$ " .. data.fine .. " e perda de reputação. Só no jogo: na vida real, DDoS é crime (art. 266 do Código Penal).", QUIET, 48)
	if data.outgoing then
		local o = data.outgoing
		local c = card(80)
		label(c, string.format("Ataque em andamento contra o %s", o.victim), { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -180, 0, 20), Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = ACCENT })
		label(c, string.format("%s · %d bots · falta %s\nEfeito na vítima agora: %s · prejudicada %d%% do tempo", o.kind, o.bots, o.left, o.effect, o.hit), { Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -180, 0, 44), TextColor3 = QUIET, TextSize = 13 })
		button(c, "Parar ataque", RED, data.owner, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(150, 36) }, function()
			GuerraAction:FireServer("stop")
		end)
	end
	if not data.owner then
		note("Só o dono do provedor decide um ataque. Você pode cuidar da defesa na aba Defesa.", WARN)
	elseif not data.pastDeadline then
		note("Seu provedor está no prazo de implantação: não pode atacar nem ser atacado.", WARN)
	elseif data.cooldown then
		note("Botnet em recarga. Próximo ataque em " .. data.cooldown .. " de jogo.", WARN)
	end
	-- duração
	local d = card(46)
	label(d, string.format("Duração do ataque: <b>%dh</b> de jogo (de %d a %d)", hours, data.minHours, data.maxHours), { Position = UDim2.fromOffset(12, 13), Size = UDim2.new(1, -140, 0, 22), TextSize = 15 })
	button(d, "-", BLUE, hours > data.minHours, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -62, 0.5, 0), Size = UDim2.fromOffset(44, 32), TextSize = 20 }, function()
		hours -= 1
		render()
	end)
	button(d, "+", BLUE, hours < data.maxHours, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(44, 32), TextSize = 20 }, function()
		hours += 1
		render()
	end)
	if #data.targets == 0 then
		note("Nenhum outro provedor aberto na cidade.", QUIET)
	end
	for _, t in data.targets do
		local c = card(84)
		label(c, t.name, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 20), Font = Enum.Font.GothamBold, TextSize = 16 })
		label(c, string.format("%d clientes · link de %d Mbps · %s", t.clients, t.link, t.status), { Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -24, 0, 18), TextColor3 = QUIET, TextSize = 13 })
		local can = t.can and data.owner
		if not t.can and t.why ~= "" then
			label(c, t.why, { Position = UDim2.fromOffset(12, 50), Size = UDim2.new(1, -330, 0, 30), TextColor3 = WARN, TextSize = 12 })
		end
		button(c, "SYN flood", RED, can, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -170, 0, 46), Size = UDim2.fromOffset(150, 30) }, function()
			GuerraAction:FireServer("attack", t.slot, "syn", hours)
		end)
		button(c, "Volumétrico DNS", RED, can, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 46), Size = UDim2.fromOffset(150, 30) }, function()
			GuerraAction:FireServer("attack", t.slot, "dns", hours)
		end)
	end
	note("<b>Equipamentos de ataque</b> (caros: o atalho é a aba Loja)", INK, 22)
	for _, it in data.items do
		if it.side == "ataque" then
			itemRow(it)
		end
	end
end

local function renderDefesa()
	if not data.provider then
		note("Você ainda não faz parte de um provedor. Abra o seu ou entre como sócio (tecla P).", WARN)
		return
	end
	if #data.incoming == 0 then
		note("Nenhum ataque contra o seu provedor agora." .. (if data.rtbh then " Blackhole em andamento: seu IP volta em " .. data.rtbh .. "." else ""), GOOD, 22)
	end
	for _, a in data.incoming do
		local c = card(78)
		label(c, "ATAQUE DDoS EM ANDAMENTO", { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 20), Font = Enum.Font.GothamBlack, TextSize = 15, TextColor3 = ACCENT })
		label(c, string.format("Sintoma: %s\nEfeito nos clientes: %s · começou há %s · origem: %s", a.symptom, a.effect, a.running, a.origin), { Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -24, 0, 44), TextColor3 = INK, TextSize = 13 })
	end
	note("<b>Firewall do roteador</b> (comandos completos na wiki, página Defesa contra DDoS)", INK, 22)
	if not data.router then
		note("Sem roteador ativo no rack.", WARN, 22)
	else
		local s = data.shield
		check(s.syncookies, "SYN cookies ligado", "/ip settings set tcp-syncookies=yes")
		check(s.synLimit, "Limite de conexões novas (contra SYN flood)", "/ip firewall filter add chain=input protocol=tcp tcp-flags=syn connection-limit=100,32 action=drop")
		check(s.blacklist, "Lista negra automática com drop na raw", "detect-ddos + add-src-to-address-list + /ip firewall raw drop")
		check(s.ampDrop, "Filtro contra DNS amplificado", "/ip firewall raw add ... protocol=udp src-port=53 src-address-list=!dns-confiaveis action=drop")
		check(s.closedDns, "Porta 53 fechada na WAN (não serve de refletor)", "/ip firewall filter add chain=input in-interface=ether1 protocol=udp dst-port=53 action=drop")
	end
	note("<b>Operadora</b>", INK, 22)
	local op = card(70)
	label(op, "Anti-DDoS da operadora" .. (if data.antiDdos then " · ATIVO" else ""), { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -190, 0, 20), Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = if data.antiDdos then GOOD else INK })
	label(op, string.format("Limpa o tráfego de ataque antes do seu link (corta 95%%) e manda o relatório com a origem. Ativação R$ %d + R$ %d por dia.", data.antiDdosFee, data.antiDdosDaily), { Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -190, 0, 38), TextColor3 = QUIET, TextSize = 12 })
	if data.antiDdos then
		button(op, "Cancelar", RED, true, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(160, 36) }, function()
			GuerraAction:FireServer("antiddos", false)
		end)
	else
		button(op, "Contratar R$ " .. data.antiDdosFee, GREEN, (data.money or 0) >= data.antiDdosFee, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(160, 36) }, function()
			GuerraAction:FireServer("antiddos", true)
		end)
	end
	local bh = card(70)
	label(bh, "Blackhole (RTBH) na operadora", { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -190, 0, 20), Font = Enum.Font.GothamBold, TextSize = 15 })
	label(bh, string.format("Grátis. A operadora descarta tudo que vai para o seu IP: o ataque para na hora, mas seus clientes ficam %dh sem internet. Vem com o relatório da origem.", data.rtbhHours), { Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -190, 0, 38), TextColor3 = QUIET, TextSize = 12 })
	button(bh, "Pedir blackhole", RED, #data.incoming > 0, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(160, 36) }, function()
		GuerraAction:FireServer("rtbh")
	end)
	note("<b>Equipamentos de defesa</b>", INK, 22)
	for _, it in data.items do
		if it.side == "defesa" then
			itemRow(it)
		end
	end
	if #data.history > 0 then
		note("<b>Histórico</b> (denúncia: balcão de ocorrências na frente da Delegacia, casa 27)", INK, 22)
		for _, line in data.history do
			note(line, if string.find(line, "DENUNCIE", 1, true) then WARN else QUIET, 20)
		end
	end
end

-- 300000 -> "300.000"
local function thousands(n: number): string
	local s = tostring(math.floor(n))
	local out = ""
	while #s > 3 do
		out = "." .. string.sub(s, -3) .. out
		s = string.sub(s, 1, -4)
	end
	return s .. out
end

local function renderLoja()
	local r = data.robux
	if not r then
		return
	end
	note(string.format("O dinheiro vai para %s e vale para esta partida. Tudo também pode ser comprado só com o dinheiro ganho no jogo; os Robux são um atalho.", r.dest), QUIET, 40)
	for _, p in r.packs do
		local c = card(60)
		label(c, p.name, { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -190, 0, 20), Font = Enum.Font.GothamBold, TextSize = 16 })
		label(c, "R$ " .. thousands(p.money) .. " de dinheiro do jogo", { Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -190, 0, 20), TextColor3 = GOLD, TextSize = 14 })
		button(c, if p.ready then p.robux .. " Robux" else "Em breve", GREEN, p.ready, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(160, 36) }, function()
			GuerraAction:FireServer("robux", p.key)
		end)
	end
	local v = r.vip
	local c = card(70)
	label(c, v.name .. (if v.owned then " · ATIVO" else ""), { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -190, 0, 20), Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = GOLD })
	label(c, v.info, { Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -190, 0, 38), TextColor3 = QUIET, TextSize = 12 })
	button(c, if v.owned then "Já é seu" elseif v.ready then v.robux .. " Robux" else "Em breve", GOLD, v.ready and not v.owned, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(160, 36), TextColor3 = Color3.fromRGB(20, 20, 20) }, function()
		GuerraAction:FireServer("robux", "vip")
	end)
end

render = function()
	for _, c in list:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	for id, b in tabButtons do
		b.BackgroundColor3 = if id == currentTab then ACCENT else ROW
		b.TextColor3 = if id == currentTab then Color3.fromRGB(20, 10, 12) else INK
	end
	order = 0
	if not data then
		return
	end
	cash.Text = if data.money then string.format("Caixa: R$ %d", data.money) else ""
	hours = math.clamp(hours, data.minHours, data.maxHours)
	if currentTab == "ataque" then
		renderAtaque()
	elseif currentTab == "defesa" then
		renderDefesa()
	else
		renderLoja()
	end
end

local polling = false
local function refresh()
	local ok, res = pcall(function()
		return GuerraState:InvokeServer()
	end)
	if not ok or not res then
		return
	end
	data = res
	local okKey, key = pcall(HttpService.JSONEncode, HttpService, res)
	key = if okKey then key else tostring(os.clock())
	if key ~= lastKey then
		lastKey = key
		render()
	end
end

local function open(tab: string?)
	if tab then
		currentTab = tab
	elseif data and #data.incoming > 0 then
		currentTab = "defesa"
	end
	win.Visible = true
	lastKey = ""
	refresh()
	render()
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

UiFit.closeX(win, close, 32)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.K then
		if win.Visible then
			close()
		else
			open()
		end
	end
end)

-- botões na tela: no celular na coluna da esquerda; no PC ao lado do botão Licitações
-- (ScreenGui separado, abaixo de todas as janelas, inclusive as do FibraHud, que tem DisplayOrder 0)
local hud = new("ScreenGui", { Name = "GuerraHud", ResetOnSpawn = false, DisplayOrder = -1, Parent = playerGui })
local function hudButton(name: string, text: string, color: Color3, touchPos: UDim2, pcPos: UDim2, tab: string?)
	local b = new("TextButton", {
		Name = name,
		AnchorPoint = if UiFit.touch then Vector2.new(0, 0) else Vector2.new(0, 1),
		Position = if UiFit.touch then touchPos else pcPos,
		Size = UDim2.fromOffset(if UiFit.touch then 110 else 130, 36),
		BackgroundColor3 = BG,
		BackgroundTransparency = 0.1,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = color,
		Text = text,
		Parent = hud,
	})
	corner(b, 8)
	new("UIStroke", { Color = color, Thickness = 1.5, Parent = b })
	b.Activated:Connect(function()
		if win.Visible and (tab == nil or currentTab == tab) then
			close()
		else
			open(tab)
		end
	end)
	return b
end
local guerraBtn = hudButton("BotaoGuerra", if UiFit.touch then "Guerra" else "Guerra (K)", ACCENT, UDim2.fromOffset(12, 302), UDim2.new(0, 400, 1, -134), nil)
hudButton("BotaoLoja", "Loja", GOLD, UDim2.fromOffset(150, 84), UDim2.new(0, 540, 1, -134), "loja")

-- pisca o botão Guerra quando chega um aviso de ataque
local Notify = Remotes:WaitForChild("Notify") :: RemoteEvent
Notify.OnClientEvent:Connect(function(text)
	if typeof(text) == "string" and string.find(text, "DDoS", 1, true) then
		guerraBtn.BackgroundColor3 = Color3.fromRGB(90, 20, 25)
		task.delay(10, function()
			guerraBtn.BackgroundColor3 = BG
		end)
		if win.Visible then
			refresh()
		end
	end
end)
