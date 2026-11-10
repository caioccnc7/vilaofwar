-- HUD do jogador: relógio, caixa, reputação, termômetro, avisos, diálogo com moradores,
-- tablet do técnico (tecla M) e fechamento do dia.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local UiFit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiFit"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local State = ReplicatedStorage:WaitForChild("GameState")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- O relógio fica em GameState; o caixa, o estoque e a fase de cada provedor ficam
-- em GameState.P1 / P2. O atributo "Slot" do jogador diz de qual provedor ele é.
local SLOT_COUNT = 2
local function myFolder(): Instance?
	local slot = player:GetAttribute("Slot")
	return if slot then State:FindFirstChild("P" .. slot) else nil
end
local function PA(name: string): any
	local f = myFolder()
	return if f then f:GetAttribute(name) else nil
end
local providerListeners = {}
local function onProviderChange(fn: () -> ())
	table.insert(providerListeners, fn)
end
local function fireProvider()
	for _, fn in providerListeners do
		task.spawn(fn)
	end
end
for slot = 1, SLOT_COUNT do
	State:WaitForChild("P" .. slot).AttributeChanged:Connect(function()
		fireProvider()
	end)
end
player:GetAttributeChangedSignal("Slot"):Connect(fireProvider)
player:GetAttributeChangedSignal("Wallet"):Connect(fireProvider)

local DARK = Color3.fromRGB(16, 20, 30)
local INK = Color3.fromRGB(235, 240, 248)
local QUIET = Color3.fromRGB(140, 152, 170)
local ACCENT = Color3.fromRGB(80, 190, 255)

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

local function round(parent: Instance, r: number)
	new("UICorner", { CornerRadius = UDim.new(0, r), Parent = parent })
end

local function label(parent: Instance, text: string, props: { [string]: any }?): TextLabel
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = INK,
		Font = Enum.Font.Gotham,
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	})
	if props then
		for k, v in props do
			(l :: any)[k] = v
		end
	end
	return l
end

local gui = new("ScreenGui", { Name = "FibraHud", ResetOnSpawn = false, IgnoreGuiInset = false, Parent = playerGui })

-- ---------------------------------------------------------------------------
-- Barra superior
-- ---------------------------------------------------------------------------

local bar = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(560, 44), BackgroundColor3 = DARK, BackgroundTransparency = 0.1, Parent = gui })
round(bar, 10)
new("UIStroke", { Color = ACCENT, Thickness = 1.5, Transparency = 0.4, Parent = bar })
local layout = new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), Parent = bar })
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

local function cell(width: number): TextLabel
	local f = new("Frame", { Size = UDim2.new(0, width, 1, -12), BackgroundTransparency = 1, Parent = bar })
	return label(f, "", { TextXAlignment = Enum.TextXAlignment.Center })
end
local dayLabel = cell(110)
local moneyLabel = cell(120)
local repLabel = cell(110)
local moodFrame = new("Frame", { Size = UDim2.new(0, 170, 1, -16), BackgroundColor3 = Color3.fromRGB(40, 46, 60), Parent = bar })
round(moodFrame, 6)
local moodFill = new("Frame", { Size = UDim2.fromScale(0.75, 1), BackgroundColor3 = Config.StatusColors.online, Parent = moodFrame })
round(moodFill, 6)
local moodText = label(moodFrame, "Moradores", { Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(15, 15, 20), ZIndex = 2 })
new("UIPadding", { PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3), Parent = moodText })

local function refreshTop()
	local hour = State:GetAttribute("Hour") or 8
	local h = math.floor(hour)
	local m = math.floor((hour - h) * 60)
	dayLabel.Text = string.format("Dia %d · %02d:%02d", State:GetAttribute("Day") or 1, h, m)
	if not myFolder() then
		-- sem provedor: mostra o dinheiro próprio do jogador
		moneyLabel.Text = string.format("Você: R$ %d", player:GetAttribute("Wallet") or 0)
		moneyLabel.TextColor3 = INK
		repLabel.Text = "sem provedor"
		repLabel.TextColor3 = QUIET
		return
	end
	local money = PA("Money") or 0
	moneyLabel.Text = string.format("R$ %d", money)
	moneyLabel.TextColor3 = if money < 0 then Config.StatusColors.offline else INK
	local rep = PA("Reputation") or 0
	local full = math.floor(rep + 0.5)
	repLabel.Text = string.rep("★", full) .. string.rep("☆", 5 - full)
	repLabel.TextColor3 = Config.StatusColors.slow
end
-- linha de estoque e dívida, logo abaixo da barra
local stockLine = label(gui, "", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 56),
	Size = UDim2.fromOffset(560, 20),
	TextScaled = false,
	TextSize = 14,
	TextColor3 = INK,
	BackgroundTransparency = 0.25,
	BackgroundColor3 = DARK,
})
round(stockLine, 6)
UiFit.scale(bar, 580)
UiFit.scale(stockLine, 580)
local function refreshStock()
	local f = myFolder()
	if not f then
		stockLine.Text = "Você ainda não tem provedor: aperte P para abrir um ou entrar como sócio."
		return
	end
	local parts = {}
	for _, k in Config.SupplyOrder do
		local n = PA("Stock_" .. k) or 0
		table.insert(parts, string.format("%s %d", Config.Supplies[k].name, n))
	end
	local text = (f:GetAttribute("Name") or "") .. " · Estoque: " .. table.concat(parts, " · ")
	local debt = PA("Debt") or 0
	if debt > 0 then
		text ..= string.format("   |   Dívida com o governo: R$ %d", debt)
	end
	stockLine.Text = text
end
onProviderChange(refreshStock)
refreshStock()

-- prazo de implantação e manifestação, logo abaixo da linha de estoque
local phaseLine = label(gui, "", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 80),
	Size = UDim2.fromOffset(560, 22),
	TextScaled = false,
	TextSize = 14,
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.fromRGB(15, 15, 20),
	BackgroundTransparency = 0.1,
	BackgroundColor3 = Config.StatusColors.slow,
	Visible = false,
})
round(phaseLine, 6)
UiFit.scale(phaseLine, 580)
local function refreshPhase()
	if not myFolder() then
		phaseLine.Visible = false
		return
	end
	local phase = PA("Phase") or "operacao"
	-- o prazo conta do dia em que o provedor abriu
	local grace = (PA("OpenedDay") or 1) + (State:GetAttribute("GraceDays") or 3) - 1
	local day = State:GetAttribute("Day") or 1
	local hour = State:GetAttribute("Hour") or Config.DayStartHour
	if phase == "implantacao" then
		-- horas de jogo até o fechamento do último dia do prazo
		local perDay = Config.DayEndHour - Config.DayStartHour
		local left = (grace - day) * perDay + (Config.DayEndHour - hour)
		local d = math.floor(left / perDay)
		local hh = math.floor(left - d * perDay)
		local todo = if PA("LinkOn") then "" else " · contrate o link"
		phaseLine.Text = string.format("Implantação: internet até o fim do dia %d (faltam %s%dh)%s", grace, if d > 0 then d .. "d " else "", hh, todo)
		phaseLine.BackgroundColor3 = Config.StatusColors.slow
		phaseLine.TextColor3 = Color3.fromRGB(15, 15, 20)
		phaseLine.Visible = true
	elseif phase == "protesto" then
		phaseLine.Text = "MANIFESTAÇÃO na frente do provedor! Em 0% o provedor vai à falência."
		phaseLine.BackgroundColor3 = Config.StatusColors.offline
		phaseLine.TextColor3 = Color3.new(1, 1, 1)
		phaseLine.Visible = true
	else
		phaseLine.Visible = false
	end
end
for _, a in { "Day", "Hour", "GraceDays" } do
	State:GetAttributeChangedSignal(a):Connect(refreshPhase)
end
onProviderChange(refreshPhase)
refreshPhase()

State:GetAttributeChangedSignal("Hour"):Connect(refreshTop)
onProviderChange(refreshTop)
refreshTop()

-- ---------------------------------------------------------------------------
-- Avisos (toasts)
-- ---------------------------------------------------------------------------

local toastHolder = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 64), Size = UDim2.fromOffset(340, 400), BackgroundTransparency = 1, Parent = gui })
new("UIListLayout", { Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Top, Parent = toastHolder })
UiFit.onResize(gui, function(small)
	-- no celular os avisos ficam mais estreitos para não cobrir o jogo
	toastHolder.Size = if small then UDim2.fromOffset(270, 240) else UDim2.fromOffset(340, 400)
end)
local ToastColor = {
	info = ACCENT,
	alarm = Config.StatusColors.offline,
	error = Config.StatusColors.unstable,
	success = Config.StatusColors.online,
	money = Config.StatusColors.slow,
	measure = Color3.fromRGB(240, 200, 40),
}

local function toast(text: string, kind: string)
	local f = new("Frame", { Size = UDim2.new(1, 0, 0, if kind == "measure" then 52 else 40), BackgroundColor3 = DARK, BackgroundTransparency = 0.05, Parent = toastHolder })
	round(f, 8)
	new("Frame", { Size = UDim2.new(0, 5, 1, 0), BackgroundColor3 = ToastColor[kind] or ACCENT, BorderSizePixel = 0, Parent = f })
	local l = label(f, text, { Position = UDim2.fromOffset(14, 4), Size = UDim2.new(1, -22, 1, -8), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true })
	new("UITextSizeConstraint", { MaxTextSize = 18, Parent = l })
	local children = toastHolder:GetChildren()
	local frames = {}
	for _, c in children do
		if c:IsA("Frame") then
			table.insert(frames, c)
		end
	end
	if #frames > 5 then
		frames[1]:Destroy()
	end
	task.delay(if kind == "measure" then 8 else 5, function()
		if f.Parent then
			local tw = TweenService:Create(f, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
			tw:Play()
			tw.Completed:Wait()
			f:Destroy()
		end
	end)
end

Remotes:WaitForChild("Notify").OnClientEvent:Connect(toast)

-- ---------------------------------------------------------------------------
-- Diálogo com morador
-- ---------------------------------------------------------------------------

local dialog = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -110), Size = UDim2.fromOffset(560, 130), BackgroundColor3 = Color3.fromRGB(250, 248, 242), Visible = false, Parent = gui })
round(dialog, 14)
local dialogStroke = new("UIStroke", { Thickness = 3, Color = Config.StatusColors.online, Parent = dialog })
local dialogName = label(dialog, "", { Position = UDim2.fromOffset(18, 10), Size = UDim2.new(1, -36, 0, 26), Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(30, 30, 35), TextXAlignment = Enum.TextXAlignment.Left })
local dialogText = label(dialog, "", { Position = UDim2.fromOffset(18, 42), Size = UDim2.new(1, -36, 1, -52), TextColor3 = Color3.fromRGB(40, 40, 45), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true })
new("UITextSizeConstraint", { MaxTextSize = 20, Parent = dialogText })
UiFit.scale(dialog, 580)
UiFit.closeX(dialog, function()
	dialog.Visible = false
end, 28)
dialogName.Size = UDim2.new(1, -70, 0, 26)
UiFit.onResize(gui, function(small)
	-- no celular o diálogo sobe para não ficar em cima do controle de andar
	if small then
		dialog.AnchorPoint = Vector2.new(0.5, 0)
		dialog.Position = UDim2.new(0.5, 0, 0, 84)
	else
		dialog.AnchorPoint = Vector2.new(0.5, 1)
		dialog.Position = UDim2.new(0.5, 0, 1, -110)
	end
end)
local dialogToken = 0

local function moodColor(m: number): Color3
	if m >= 70 then
		return Config.StatusColors.online
	elseif m >= 40 then
		return Config.StatusColors.slow
	elseif m >= 15 then
		return Config.StatusColors.unstable
	end
	return Config.StatusColors.offline
end

Remotes:WaitForChild("Dialog").OnClientEvent:Connect(function(d)
	dialogName.Text = string.format("%s · Casa %d · humor %s (%d)", d.name, d.house, d.moodWord, d.mood)
	dialogText.Text = d.text
	dialogStroke.Color = moodColor(d.mood)
	dialog.Visible = true
	dialogToken += 1
	local token = dialogToken
	task.delay(9, function()
		if dialogToken == token then
			dialog.Visible = false
		end
	end)
end)

-- ---------------------------------------------------------------------------
-- Ajuda das ferramentas
-- ---------------------------------------------------------------------------

local help = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12), Size = UDim2.fromOffset(330, 112), BackgroundColor3 = DARK, BackgroundTransparency = 0.15, Parent = gui })
round(help, 10)
local helpText = label(help, table.concat({
	"Power Meter: medir sinal na casa ou na caixa",
	"Fusão: emendar, refazer conector, instalar cliente",
	"Notebook TI: clique; perto do rack digite console",
	"T: conversar · M: tablet · J: wiki · P: provedor",
}, "\n"), { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 1, -16), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = QUIET })
new("UITextSizeConstraint", { MaxTextSize = 15, Parent = helpText })
-- as dicas falam de teclas; no celular ficam escondidas (o canto é do controle de andar)
UiFit.onResize(gui, function(small)
	help.Visible = not small and not UiFit.touch
end)

-- ---------------------------------------------------------------------------
-- Tablet do técnico (versão resumida do NOC)
-- ---------------------------------------------------------------------------

local tablet = new("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -12), Size = UDim2.fromOffset(470, 330), BackgroundColor3 = Color3.fromRGB(10, 14, 22), Visible = false, Parent = gui })
round(tablet, 14)
new("UIStroke", { Color = Color3.fromRGB(60, 66, 80), Thickness = 4, Parent = tablet })
label(tablet, "TABLET · REDE AO VIVO", { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 20), Font = Enum.Font.GothamBold, TextColor3 = ACCENT, TextXAlignment = Enum.TextXAlignment.Left })
local tabletBody = new("Frame", { Position = UDim2.fromOffset(14, 38), Size = UDim2.new(1, -28, 1, -50), BackgroundTransparency = 1, Parent = tablet })
UiFit.scale(tablet, 470, 330, 10)
UiFit.closeX(tablet, function()
	tablet.Visible = false
end, 28)
UiFit.onResize(gui, function(small)
	-- no celular o tablet abre no meio da tela, longe do botão de pular
	if small then
		tablet.AnchorPoint = Vector2.new(0.5, 0.5)
		tablet.Position = UDim2.fromScale(0.5, 0.5)
	else
		tablet.AnchorPoint = Vector2.new(1, 1)
		tablet.Position = UDim2.new(1, -12, 1, -12)
	end
end)

local function renderTablet(snap: any)
	for _, c in tabletBody:GetChildren() do
		c:Destroy()
	end
	table.sort(snap.houses, function(a, b)
		return a.index < b.index
	end)
	-- duas colunas: Rua Principal (1 a 8) e Rua das Palmeiras (9 a 16)
	local perCol = math.ceil(#snap.houses / 2)
	for i, h in snap.houses do
		local col = if i > perCol then 1 else 0
		local y = ((i - 1) % perCol) * 20
		local color = Config.StatusColors[h.status] or QUIET
		new("Frame", { Position = UDim2.new(col * 0.5, 0, 0, y + 4), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = color, BorderSizePixel = 0, Parent = tabletBody })
		local sig = if h.contract ~= "active" then "" elseif h.signal then string.format(" · %.1f", h.signal) else " · LOS"
		label(tabletBody, string.format("Casa %d · %s%s%s", h.index, Config.StatusLabels[h.status] or h.status, sig, if h.ticket then " !" else ""), { Position = UDim2.new(col * 0.5, 16, 0, y), Size = UDim2.new(0.5, -18, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true })
	end
	local y = perCol * 20 + 8
	label(tabletBody, "Últimos alarmes", { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 18), Font = Enum.Font.GothamBold, TextColor3 = QUIET, TextXAlignment = Enum.TextXAlignment.Left })
	y += 20
	for i = 1, math.min(4, #snap.alarms) do
		local a = snap.alarms[i]
		label(tabletBody, a.time .. " " .. a.kind .. ": " .. a.text, { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = if a.severity == "ok" then Config.StatusColors.online elseif a.severity == "warning" then Config.StatusColors.unstable else Config.StatusColors.offline })
		y += 18
	end
end

local lastSnap = nil

local function toggleTablet()
	tablet.Visible = not tablet.Visible
	if tablet.Visible and lastSnap then
		renderTablet(lastSnap)
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.M then
		toggleTablet()
	end
end)

-- no celular não há tecla M: botão na tela, logo abaixo do botão da wiki
if UiFit.touch then
	local tabletBtn = new("TextButton", {
		Name = "BotaoTablet",
		Position = UDim2.fromOffset(12, 126),
		Size = UDim2.fromOffset(110, 36),
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.1,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = ACCENT,
		Text = "Tablet",
		Parent = gui,
	})
	round(tabletBtn, 8)
	new("UIStroke", { Color = ACCENT, Thickness = 1.5, Parent = tabletBtn })
	tabletBtn.Activated:Connect(toggleTablet)
end

Remotes:WaitForChild("NocUpdate").OnClientEvent:Connect(function(snap)
	lastSnap = snap
	local avg = snap.mood.average
	if avg < 0 then
		-- ninguém escolheu este provedor ainda
		moodFill.Size = UDim2.fromScale(0.02, 1)
		moodText.Text = "Moradores: ninguém"
		if tablet.Visible then
			renderTablet(snap)
		end
		return
	end
	moodFill.Size = UDim2.fromScale(math.clamp(avg / 100, 0.02, 1), 1)
	moodFill.BackgroundColor3 = moodColor(avg)
	moodText.Text = string.format("Moradores %d%%", math.floor(avg))
	if tablet.Visible then
		renderTablet(snap)
	end
end)

-- ---------------------------------------------------------------------------
-- Fechamento do dia
-- ---------------------------------------------------------------------------

local summary = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(440, 420), BackgroundColor3 = DARK, Visible = false, ZIndex = 10, Parent = gui })
round(summary, 16)
new("UIStroke", { Color = ACCENT, Thickness = 2, Parent = summary })
local summaryTitle = label(summary, "", { Position = UDim2.fromOffset(20, 16), Size = UDim2.new(1, -40, 0, 34), Font = Enum.Font.GothamBlack, TextColor3 = ACCENT, ZIndex = 11 })
local summaryBody = label(summary, "", { Position = UDim2.fromOffset(24, 64), Size = UDim2.new(1, -48, 1, -140), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 11 })
new("UITextSizeConstraint", { MaxTextSize = 19, Parent = summaryBody })
UiFit.scale(summary, 440, 420, 10)
local closeBtn = new("TextButton", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(240, 44), BackgroundColor3 = ACCENT, Text = "Começar o próximo dia", Font = Enum.Font.GothamBold, TextScaled = true, TextColor3 = Color3.fromRGB(10, 15, 25), ZIndex = 11, Parent = summary })
round(closeBtn, 10)
new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), Parent = closeBtn })
closeBtn.MouseButton1Click:Connect(function()
	summary.Visible = false
end)

Remotes:WaitForChild("DaySummary").OnClientEvent:Connect(function(s)
	summaryTitle.Text = "Fim do dia " .. s.day .. " · " .. (s.provider or "")
	local full = math.floor(s.reputation + 0.5)
	summaryBody.Text = table.concat({
		string.format("Clientes ativos: %d", s.customers),
		string.format("Mensalidades: R$ %d", s.fees),
		string.format("Receita total: R$ %d", s.revenue),
		string.format("Custos (compras, link, multas): R$ %d", s.costs),
		string.format("Parcela do crédito do governo: R$ %d · dívida restante R$ %d", s.loanPayment or 0, s.debt or 0),
		string.format("Equipe de rua e carro: R$ %d", s.staffCost or 0),
		string.format("Multas de SLA: R$ %d", s.penalties),
		string.format("SLA do dia: %.1f%%", s.sla),
		string.format("Humor médio dos moradores: %d", math.floor(s.mood)),
		string.format("Instalações: %d · Reparos: %d · Cancelamentos: %d", s.installs, s.repairs, s.cancellations),
		string.format("Caixa: R$ %d", s.money),
		"Reputação: " .. string.rep("★", full) .. string.rep("☆", 5 - full),
	}, "\n")
	summary.Visible = true
end)

-- primeira dica
task.delay(4, function()
	toast("Dica: compre as ferramentas e os insumos no terminal de compras do almoxarifado. Dúvidas: aperte J (wiki).", "info")
end)

-- ---------------------------------------------------------------------------
-- Falência: fim de jogo
-- ---------------------------------------------------------------------------

local over = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(8, 8, 12), BackgroundTransparency = 0.15, Visible = false, ZIndex = 50, Parent = gui })
local overBox = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(460, 340), BackgroundColor3 = DARK, ZIndex = 51, Parent = over })
round(overBox, 16)
new("UIStroke", { Color = Config.StatusColors.offline, Thickness = 2, Parent = overBox })
UiFit.scale(overBox, 460, 340, 10)
local overTitle = label(overBox, "O PROVEDOR FALIU", { Position = UDim2.fromOffset(20, 18), Size = UDim2.new(1, -40, 0, 40), Font = Enum.Font.GothamBlack, TextColor3 = Config.StatusColors.offline, ZIndex = 52 })
local overBody = label(overBox, "", { Position = UDim2.fromOffset(28, 72), Size = UDim2.new(1, -56, 1, -150), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, ZIndex = 52 })
new("UITextSizeConstraint", { MaxTextSize = 18, Parent = overBody })
local againBtn = new("TextButton", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(240, 46), BackgroundColor3 = ACCENT, Text = "Escolher provedor", Font = Enum.Font.GothamBold, TextScaled = true, TextColor3 = Color3.fromRGB(10, 15, 25), ZIndex = 52, Parent = overBox })
round(againBtn, 10)
new("UIPadding", { PaddingTop = UDim.new(0, 9), PaddingBottom = UDim.new(0, 9), Parent = againBtn })
local openProviderMenu: () -> () -- definido no menu Provedor, mais abaixo
againBtn.Activated:Connect(function()
	over.Visible = false
	openProviderMenu()
end)

local function showBankrupt(d: any?)
	d = d or {}
	overBody.Text = table.concat({
		string.format("Os moradores perderam a paciência com o %s: a satisfação chegou a 0%% e o provedor fechou.", d.name or "provedor"),
		"Você recebeu de novo R$ " .. Config.StartMoney .. " para recomeçar: abra outro provedor ou entre como sócio.",
		"",
		string.format("Dia: %s", tostring(d.day or State:GetAttribute("Day") or "?")),
		string.format("Casas com internet: %s de %s", tostring(d.customers or "?"), tostring(d.houses or 16)),
		string.format("Caixa: R$ %s   Dívida: R$ %s", tostring(d.money or 0), tostring(d.debt or 0)),
		"",
		"Dica: contrate o link e monte o rack logo no começo, e leve internet às casas antes do fim do prazo.",
	}, "\n")
	over.Visible = true
end
Remotes:WaitForChild("Bankrupt").OnClientEvent:Connect(showBankrupt)

-- ---------------------------------------------------------------------------
-- Menu Provedor (tecla P): abrir um provedor, entrar como sócio, aportar,
-- renomear e mudar o preço da internet
-- ---------------------------------------------------------------------------

local ProviderAction = Remotes:WaitForChild("ProviderAction") :: RemoteEvent
local GREEN = Config.StatusColors.online

local menu = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(500, 480), BackgroundColor3 = DARK, Visible = false, ZIndex = 20, Parent = gui })
round(menu, 16)
new("UIStroke", { Color = ACCENT, Thickness = 2, Parent = menu })
UiFit.scale(menu, 500, 480, 10)
UiFit.closeX(menu, function()
	menu.Visible = false
end, 30)
local menuBody = new("Frame", { Position = UDim2.fromOffset(18, 14), Size = UDim2.new(1, -36, 1, -28), BackgroundTransparency = 1, ZIndex = 21, Parent = menu })

local function mLabel(text: string, x: number, y: number, w: number, h: number, props: { [string]: any }?): TextLabel
	local l = label(menuBody, text, { Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22 })
	if props then
		for k, v in props do
			(l :: any)[k] = v
		end
	end
	return l
end

-- o que já foi digitado sobrevive quando o menu é redesenhado
local typed: { [string]: string } = {}
local function mBox(id: string, placeholder: string, x: number, y: number, w: number): TextBox
	local b = new("TextBox", {
		Name = id,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, 30),
		BackgroundColor3 = Color3.fromRGB(32, 38, 52),
		TextColor3 = INK,
		PlaceholderText = placeholder,
		PlaceholderColor3 = QUIET,
		Text = typed[id] or "",
		Font = Enum.Font.Gotham,
		TextSize = 15,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 22,
		Parent = menuBody,
	})
	round(b, 6)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), Parent = b })
	b:GetPropertyChangedSignal("Text"):Connect(function()
		typed[id] = b.Text
	end)
	return b
end

local function mButton(text: string, x: number, y: number, w: number, color: Color3, onClick: () -> ())
	local b = new("TextButton", {
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, 30),
		BackgroundColor3 = color,
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = Color3.fromRGB(10, 15, 25),
		ZIndex = 22,
		Parent = menuBody,
	})
	round(b, 6)
	b.Activated:Connect(onClick)
end

local function renderMenu()
	for _, c in menuBody:GetChildren() do
		c:Destroy()
	end
	local mySlot = player:GetAttribute("Slot")
	local wallet = player:GetAttribute("Wallet") or 0
	local P = Config.Price
	mLabel("PROVEDORES DA VILA", 0, 0, 420, 28, { Font = Enum.Font.GothamBlack, TextColor3 = ACCENT })
	local status
	if mySlot then
		local f = State:FindFirstChild("P" .. mySlot)
		local role = if f and f:GetAttribute("Owner") == player.Name then "dono" else "sócio"
		status = string.format("Você é %s do %s · seu dinheiro: R$ %d", role, if f then f:GetAttribute("Name") or "?" else "?", wallet)
	else
		status = string.format("Seu dinheiro: R$ %d. Abra um provedor (vira o capital) ou entre como sócio.", wallet)
	end
	mLabel(status, 0, 32, 464, 20, { TextColor3 = QUIET, TextScaled = false, TextSize = 14, TextWrapped = true })

	-- um cartão por prédio
	local y = 62
	for slot = 1, SLOT_COUNT do
		local f = State:FindFirstChild("P" .. slot)
		local open = f and f:GetAttribute("Open")
		local card = new("Frame", { Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(464, 92), BackgroundColor3 = Color3.fromRGB(26, 31, 44), ZIndex = 21, Parent = menuBody })
		round(card, 10)
		if open then
			local partners = f:GetAttribute("Partners") or ""
			mLabel(string.format("Prédio %d · %s · R$ %d por dia", slot, f:GetAttribute("Name") or "?", f:GetAttribute("Price") or 0), 12, y + 8, 440, 22, { Font = Enum.Font.GothamBold })
			mLabel(string.format("Dono: %s%s", f:GetAttribute("Owner") or "?", if partners ~= "" then " · Sócios: " .. partners else ""), 12, y + 32, 440, 18, { TextColor3 = QUIET, TextScaled = false, TextSize = 14 })
			if not mySlot then
				mButton("Entrar como sócio", 12, y + 56, 200, GREEN, function()
					ProviderAction:FireServer("join", slot)
					menu.Visible = false
				end)
			elseif mySlot == slot then
				mLabel("(o seu provedor)", 12, y + 60, 200, 18, { TextColor3 = GREEN, TextScaled = false, TextSize = 14 })
			end
		else
			mLabel(string.format("Prédio %d · disponível", slot), 12, y + 8, 440, 22, { Font = Enum.Font.GothamBold, TextColor3 = QUIET })
			if not mySlot then
				mLabel(string.format("Seus R$ %d viram o capital do provedor.", wallet), 12, y + 32, 440, 18, { TextColor3 = QUIET, TextScaled = false, TextSize = 14 })
				local nameBox = mBox("open" .. slot, "Nome do provedor (3 a 24 letras)", 12, y + 56, 250)
				mButton("Abrir provedor", 272, y + 56, 180, ACCENT, function()
					ProviderAction:FireServer("open", slot, nameBox.Text)
					table.clear(typed)
					menu.Visible = false
				end)
			end
		end
		y += 100
	end

	-- configurações do próprio provedor
	if mySlot then
		local f = State:FindFirstChild("P" .. mySlot)
		mLabel("MEU PROVEDOR", 0, y, 300, 20, { Font = Enum.Font.GothamBold, TextColor3 = ACCENT })
		y += 26
		local nameBox = mBox("rename", "Novo nome (agora: " .. (if f then f:GetAttribute("Name") or "" else "") .. ")", 0, y, 290)
		mButton("Renomear", 300, y, 164, ACCENT, function()
			ProviderAction:FireServer("rename", nameBox.Text)
			typed.rename = nil
		end)
		y += 38
		local priceBox = mBox("price", string.format("Preço novo, de R$ %d a %d (agora: R$ %s)", P.Min, P.Max, if f then tostring(f:GetAttribute("Price") or "?") else "?"), 0, y, 290)
		mButton("Mudar preço", 300, y, 164, ACCENT, function()
			ProviderAction:FireServer("price", tonumber(priceBox.Text))
			typed.price = nil
		end)
		y += 34
		mLabel("O preço novo vale para quem contratar daqui em diante. Quem já é cliente continua pagando o preço do contrato.", 0, y, 464, 30, { TextColor3 = QUIET, TextScaled = false, TextSize = 13, TextWrapped = true })
		y += 34
		local investBox = mBox("invest", string.format("Aportar do seu dinheiro (até R$ %d)", wallet), 0, y, 290)
		mButton("Aportar no caixa", 300, y, 164, GREEN, function()
			ProviderAction:FireServer("invest", tonumber(investBox.Text))
			typed.invest = nil
		end)
	end
end

-- só redesenha quando algo do menu muda de verdade (para não apagar o que está sendo digitado)
local lastKey = ""
local function menuKey(): string
	local parts = { tostring(player:GetAttribute("Slot")), tostring(player:GetAttribute("Wallet")) }
	for slot = 1, SLOT_COUNT do
		local f = State:FindFirstChild("P" .. slot)
		if f then
			for _, a in { "Open", "Name", "Price", "Owner", "Partners" } do
				table.insert(parts, tostring(f:GetAttribute(a)))
			end
		end
	end
	return table.concat(parts, "|")
end
onProviderChange(function()
	local key = menuKey()
	if menu.Visible and key ~= lastKey then
		lastKey = key
		renderMenu()
	end
	-- saiu do provedor: a barra de moradores não vale mais
	if not player:GetAttribute("Slot") then
		moodFill.Size = UDim2.fromScale(0.02, 1)
		moodText.Text = "Moradores"
	end
end)

openProviderMenu = function()
	lastKey = menuKey()
	renderMenu()
	menu.Visible = true
end

local function toggleMenu()
	if menu.Visible then
		menu.Visible = false
	else
		openProviderMenu()
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.P then
		toggleMenu()
	end
end)
Remotes:WaitForChild("ProviderMenu").OnClientEvent:Connect(openProviderMenu)

-- botão na tela (no celular não tem tecla P)
local menuBtn = new("TextButton", {
	Name = "BotaoProvedor",
	Position = if UiFit.touch then UDim2.fromOffset(12, 170) else UDim2.new(0, 12, 1, -176),
	Size = UDim2.fromOffset(110, 36),
	BackgroundColor3 = DARK,
	BackgroundTransparency = 0.1,
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	TextColor3 = ACCENT,
	Text = "Provedor (P)",
	Parent = gui,
})
round(menuBtn, 8)
new("UIStroke", { Color = ACCENT, Thickness = 1.5, Parent = menuBtn })
menuBtn.Activated:Connect(toggleMenu)
