-- Telas da sala de monitoramento (NOC). Tudo vem do estado real da rede,
-- que o servidor envia uma vez por segundo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local NocUpdate = Remotes:WaitForChild("NocUpdate") :: RemoteEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PPS = 50 -- pixels por stud nas telas
local PPS_BY_KIND = { Topology = 38, Rack = 36 } -- menos pixels por stud = desenho maior
local BG = Color3.fromRGB(8, 12, 20)
local PANEL = Color3.fromRGB(18, 24, 36)
local INK = Color3.fromRGB(230, 236, 245)
local QUIET = Color3.fromRGB(130, 145, 165)
local ACCENT = Color3.fromRGB(80, 190, 255)
local SevColor = {
	critical = Config.StatusColors.offline,
	warning = Config.StatusColors.unstable,
	ok = Config.StatusColors.online,
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

local function text(parent: Instance, t: string, pos: UDim2, size: UDim2, props: { [string]: any }?): TextLabel
	local label = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = pos,
		Size = size,
		Text = t,
		TextColor3 = INK,
		Font = Enum.Font.Gotham,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	})
	if props then
		for k, v in props do
			(label :: any)[k] = v
		end
	end
	return label
end

local function corner(parent: Instance, r: number)
	new("UICorner", { CornerRadius = UDim.new(0, r), Parent = parent })
end

-- ---------------------------------------------------------------------------
-- Tela base
-- ---------------------------------------------------------------------------

type Screen = { kind: string, part: BasePart, gui: SurfaceGui, root: Frame, body: Frame, w: number, h: number, state: { [string]: any } }
local screens: { Screen } = {}

local Titles = {
	Map = "MAPA DA REDE · VILA AURORA",
	Topology = "TOPOLOGIA DA REDE",
	Traffic = "TRÁFEGO DO LINK",
	Alarms = "ALARMES",
	Onus = "SINAL DAS ONUs",
	Tickets = "CHAMADOS E A VOZ DA RUA",
	Summary = "RESUMO DO DIA",
	Mood = "TERMÔMETRO DOS MORADORES",
	Rack = "DATACENTER · EQUIPAMENTOS E CABOS",
}

local function attach(part: BasePart)
	local kind = part:GetAttribute("ScreenKind")
	if not kind then
		return
	end
	for _, s in screens do
		if s.part == part then
			return
		end
	end
	local gui = new("SurfaceGui", {
		Name = "Noc_" .. kind,
		Adornee = part,
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = PPS_BY_KIND[kind] or PPS,
		LightInfluence = 0,
		Brightness = 1.4,
		ResetOnSpawn = false,
		Parent = playerGui,
	})
	local pps = PPS_BY_KIND[kind] or PPS
	local w, h = part.Size.X * pps, part.Size.Y * pps
	local root = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = BG, BorderSizePixel = 0, Parent = gui })
	local header = new("Frame", { Size = UDim2.new(1, 0, 0, math.floor(h * 0.12)), BackgroundColor3 = PANEL, BorderSizePixel = 0, Parent = root })
	new("Frame", { Size = UDim2.new(1, 0, 0, 2), Position = UDim2.new(0, 0, 1, -2), BackgroundColor3 = ACCENT, BorderSizePixel = 0, Parent = header })
	text(header, Titles[kind] or kind, UDim2.new(0, 12, 0.15, 0), UDim2.new(0.7, 0, 0.7, 0), { Font = Enum.Font.GothamBold, TextColor3 = ACCENT })
	local clock = text(header, "--:--", UDim2.new(0.7, 0, 0.15, 0), UDim2.new(0.3, -12, 0.7, 0), { TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = QUIET })
	local body = new("Frame", {
		Position = UDim2.new(0, 0, 0, math.floor(h * 0.12)),
		Size = UDim2.new(1, 0, 1, -math.floor(h * 0.12)),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = root,
	})
	table.insert(screens, { kind = kind, part = part, gui = gui, root = root, body = body, w = w, h = h - math.floor(h * 0.12), state = { clock = clock } })
end

for _, p in CollectionService:GetTagged("NocScreen") do
	attach(p)
end
CollectionService:GetInstanceAddedSignal("NocScreen"):Connect(attach)

local function clear(frame: Instance)
	for _, c in frame:GetChildren() do
		c:Destroy()
	end
end

-- ---------------------------------------------------------------------------
-- Mapa
-- ---------------------------------------------------------------------------

local MIN_X, MAX_X, MIN_Z, MAX_Z = -160, 350, -262, 50
local blink = false

local function renderMap(s: Screen, snap: any)
	local body = s.body
	clear(body)
	local pad = 10
	local mw, mh = s.w - pad * 2, s.h - pad * 2 - 26
	local function px(x: number, z: number): (number, number)
		return pad + (x - MIN_X) / (MAX_X - MIN_X) * mw, pad + (z - MIN_Z) / (MAX_Z - MIN_Z) * mh
	end
	local function rect(x0: number, z0: number, x1: number, z1: number, color: Color3, transparency: number?)
		local ax, az = px(x0, z0)
		local bx, bz = px(x1, z1)
		return new("Frame", { Position = UDim2.fromOffset(ax, az), Size = UDim2.fromOffset(bx - ax, bz - az), BackgroundColor3 = color, BackgroundTransparency = transparency or 0, BorderSizePixel = 0, Parent = body })
	end
	local function line(x1: number, z1: number, x2: number, z2: number, color: Color3, thick: number)
		local ax, az = px(x1, z1)
		local bx, bz = px(x2, z2)
		local dx, dz = bx - ax, bz - az
		local len = math.sqrt(dx * dx + dz * dz)
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset((ax + bx) / 2, (az + bz) / 2),
			Size = UDim2.fromOffset(len, thick),
			Rotation = math.deg(math.atan2(dz, dx)),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = body,
		})
	end

	-- rua e prédio
	rect(MIN_X, -12, 330, 12, Color3.fromRGB(34, 40, 52))
	rect(288, -262, 312, -12, Color3.fromRGB(34, 40, 52))
	text(body, "Rua Principal", UDim2.fromOffset(px(160, -10)), UDim2.fromOffset(120, 14), { TextColor3 = QUIET, ZIndex = 2 })
	text(body, "R. das Palmeiras", UDim2.fromOffset(px(214, -255)), UDim2.fromOffset(110, 14), { TextColor3 = QUIET, ZIndex = 2 })
	local garage = rect(-87, -52, -63, -22, Color3.fromRGB(90, 60, 20))
	corner(garage, 3)
	if snap.tech and snap.tech.car and snap.tech.car.owned and snap.tech.car.x then
		local cx, cz = px(snap.tech.car.x, snap.tech.car.z)
		local car = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, cz), Size = UDim2.fromOffset(16, 16), BackgroundColor3 = Color3.fromRGB(255, 150, 40), BorderSizePixel = 0, ZIndex = 6, Parent = body })
		corner(car, 8)
		text(car, "C", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), { TextXAlignment = Enum.TextXAlignment.Center, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(20, 20, 20), ZIndex = 7 })
	end
	if snap.tech and snap.tech.team then
		for _, m in snap.tech.team do
			if m.x then
				local tx, tz = px(m.x, m.z)
				local dot = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(tx, tz), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = Color3.fromRGB(255, 120, 20), BorderSizePixel = 0, ZIndex = 6, Parent = body })
				corner(dot, 5)
			end
		end
	end
	local isp = rect(-148, -58, -92, -22, Color3.fromRGB(20, 60, 100))
	corner(isp, 4)
	text(isp, "PROVEDOR", UDim2.fromScale(0.05, 0.3), UDim2.fromScale(0.9, 0.4), { TextXAlignment = Enum.TextXAlignment.Center, Font = Enum.Font.GothamBold })

	-- cabos
	for _, e in snap.edges do
		local color = ACCENT
		if e.state == "broken" then
			color = if blink then Config.StatusColors.offline else Color3.fromRGB(90, 20, 20)
		elseif e.state == "dirty" then
			color = Config.StatusColors.unstable
		end
		local thick = if e.kind == "trunk" then 5 elseif e.kind == "distribution" then 4 else 2
		line(e.x1, e.z1, e.x2, e.z2, color, thick)
	end
	-- caixas
	for _, n in snap.nodes do
		local x, z = px(n.x, n.z)
		local d = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, z), Size = UDim2.fromOffset(14, 14), Rotation = 45, BackgroundColor3 = INK, BorderSizePixel = 0, Parent = body })
		d.ZIndex = 3
		if n.kind == "splitter" then
			text(body, n.label, UDim2.fromOffset(x - 50, z + (if n.z > 0 then 10 else -26)), UDim2.fromOffset(100, 16), { TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = QUIET, ZIndex = 3 })
		end
	end
	-- casas
	for _, h in snap.houses do
		local x, z = px(h.x, h.z)
		-- casa que é cliente do outro provedor: roxa
		local rival = h.contract == "rival"
		local color = if rival then Color3.fromRGB(150, 90, 200) else Config.StatusColors[h.status] or QUIET
		local box = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, z), Size = UDim2.fromOffset(30, 22), BackgroundColor3 = color, BackgroundTransparency = if h.status == "nocontract" and not rival then 0.7 else 0, BorderSizePixel = 0, Parent = body })
		box.ZIndex = 4
		corner(box, 5)
		text(box, tostring(h.index), UDim2.fromScale(0, 0.1), UDim2.fromScale(1, 0.8), { TextXAlignment = Enum.TextXAlignment.Center, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(10, 10, 15), ZIndex = 5 })
		if h.ticket then
			local badge = new("Frame", { Position = UDim2.new(1, -6, 0, -8), Size = UDim2.fromOffset(16, 16), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 6, Parent = box })
			corner(badge, 8)
			text(badge, "!", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), { TextXAlignment = Enum.TextXAlignment.Center, Font = Enum.Font.GothamBlack, TextColor3 = Config.StatusColors.offline, ZIndex = 7 })
		end
	end
	-- legenda
	local legend = { "online", "slow", "unstable", "nodns", "offline", "nocontract" }
	local lw = (s.w - 20) / #legend
	for i, key in legend do
		local x = 10 + (i - 1) * lw
		new("Frame", { Position = UDim2.fromOffset(x, s.h - 22), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = Config.StatusColors[key], BorderSizePixel = 0, Parent = body })
		text(body, Config.StatusLabels[key], UDim2.fromOffset(x + 16, s.h - 25), UDim2.fromOffset(lw - 20, 18), { TextColor3 = QUIET })
	end
end

-- ---------------------------------------------------------------------------
-- Topologia (lógica): internet -> roteador -> OLT -> splitter -> CTOs -> casas
-- ---------------------------------------------------------------------------

local DevColor = {
	ok = Config.StatusColors.online,
	boot = Config.StatusColors.unstable,
	config = Config.StatusColors.slow,
	off = Config.StatusColors.offline,
	fail = Config.StatusColors.offline,
	nocable = Config.StatusColors.offline,
}
local DevText = {
	ok = "OPERANDO",
	boot = "INICIALIZANDO",
	config = "CONFIG INCOMPLETA",
	off = "DESLIGADO",
	fail = "SEM RESPOSTA",
	nocable = "SEM CABO",
}
local GREY = Color3.fromRGB(70, 78, 92)

local function renderTopology(s: Screen, snap: any)
	local body = s.body
	clear(body)
	local t = snap.topo
	if not t then
		return
	end
	local W, H = s.w, s.h - 24

	local function link(x1: number, y1: number, x2: number, y2: number, color: Color3, thick: number)
		local dx, dy = x2 - x1, y2 - y1
		local len = math.sqrt(dx * dx + dy * dy)
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2),
			Size = UDim2.fromOffset(len, thick),
			Rotation = math.deg(math.atan2(dy, dx)),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = body,
		})
	end
	local function edgeColor(state: string, up: boolean): Color3
		if state == "broken" then
			return if blink then Config.StatusColors.offline else Color3.fromRGB(90, 20, 20)
		elseif state == "dirty" then
			return Config.StatusColors.unstable
		end
		return if up then ACCENT else GREY
	end
	local function card(cx: number, cy: number, w: number, h: number, color: Color3, title: string, lines: { string }): Frame
		local f = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, cy), Size = UDim2.fromOffset(w, h), BackgroundColor3 = PANEL, BorderSizePixel = 0, ZIndex = 3, Parent = body })
		corner(f, 6)
		new("UIStroke", { Color = color, Thickness = 2, Parent = f })
		new("Frame", { Size = UDim2.new(0, 5, 1, 0), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 4, Parent = f })
		text(f, title, UDim2.fromOffset(9, 3), UDim2.new(1, -12, 0, 15), { Font = Enum.Font.GothamBold, ZIndex = 4 })
		for i, l in lines do
			text(f, l, UDim2.fromOffset(9, 4 + i * 13), UDim2.new(1, -12, 0, 12), { TextColor3 = if i == #lines then color else QUIET, ZIndex = 4 })
		end
		return f
	end

	local cy = H / 2
	local colX = { W * 0.075, W * 0.235, W * 0.405, W * 0.545, W * 0.68, W * 0.875 }
	local cardW = W * 0.15

	-- internet
	local netColor = if t.internet then Config.StatusColors.online else Config.StatusColors.offline
	card(colX[1], cy, W * 0.12, 70, netColor, "INTERNET", { "Upstream", tostring(t.uplink) .. " Mbps", if t.internet then "OK" else "SEM ROTA" })
	local dnsColor = if t.dns then Config.StatusColors.online else Config.StatusColors.nodns
	card(colX[1], cy + 70, W * 0.12, 44, dnsColor, "DNS", { if t.dns then "RESOLVENDO" else "FALHANDO" })

	-- roteador
	local r = t.router
	local rUp = r ~= nil and (r.state == "ok" or r.state == "config")
	link(colX[1], cy, colX[2], cy, if t.internet then ACCENT else GREY, 4)
	if r then
		local c = DevColor[r.state] or GREY
		local lines = { r.model, "IP " .. r.ip, DevText[r.state] or r.state }
		card(colX[2], cy, cardW, 70, c, r.label, lines)
		if r.state == "config" and r.problem ~= "" then
			text(body, r.problem, UDim2.fromOffset(colX[2] - cardW / 2, cy + 40), UDim2.fromOffset(cardW, 26), { TextColor3 = Config.StatusColors.slow, TextWrapped = true, TextScaled = true, ZIndex = 4 })
		end
	else
		card(colX[2], cy, cardW, 70, GREY, "ROTEADOR", { "nenhum no rack", "", "AUSENTE" })
	end

	-- OLT
	local o = t.olt
	local oUp = o ~= nil and o.state == "ok"
	link(colX[2], cy, colX[3], cy, if rUp and oUp then ACCENT else GREY, 4)
	if o then
		card(colX[3], cy, cardW, 70, DevColor[o.state] or GREY, o.label, { o.model, "IP " .. o.ip .. " · " .. o.onts .. " ONTs", DevText[o.state] or o.state })
	else
		card(colX[3], cy, cardW, 70, GREY, "OLT", { "nenhuma no rack", "", "AUSENTE" })
	end

	-- troncos, splitters, CTOs e casas (uma linha por CTO)
	local spls = t.splitters or { { label = t.splitter, state = t.trunk, ctos = t.ctos } }
	local ctoCount = 0
	for _, sp in spls do
		ctoCount += #sp.ctos
	end
	local slot = 0
	for si, sp in spls do
		local sy = H * ((si - 0.5) / #spls)
		link(colX[3], cy, colX[4], sy, edgeColor(sp.state, oUp), 5)
		new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(colX[4], sy), Size = UDim2.fromOffset(20, 20), Rotation = 45, BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 3, Parent = body })
		text(body, sp.label, UDim2.fromOffset(colX[4] - 60, sy + 14), UDim2.fromOffset(120, 14), { TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = QUIET, ZIndex = 3 })
		local trunkOk = oUp and sp.state ~= "broken"
		for _, cto in sp.ctos do
			slot += 1
			local y = H * ((slot - 0.5) / math.max(1, ctoCount))
			local ctoUp = trunkOk and cto.edge ~= "broken"
			link(colX[4], sy, colX[5], y, edgeColor(cto.edge, trunkOk), 4)
			local online, total = 0, 0
			for _, h in cto.houses do
				if h.contract == "active" then
					total += 1
					if h.status == "online" or h.status == "slow" then
						online += 1
					end
				end
			end
			local cc = if not ctoUp then Config.StatusColors.offline elseif online == total then Config.StatusColors.online else Config.StatusColors.unstable
			card(colX[5], y, W * 0.12, 44, cc, cto.label, { "PON 0/1/" .. cto.port, online .. "/" .. total .. " online" })

			local n = #cto.houses
			local band = H / math.max(1, ctoCount)
			local rowH = math.min(26, (band - 4) / math.max(1, n))
			for j, h in cto.houses do
				local hy = y + (j - (n + 1) / 2) * rowH
				local active = h.contract == "active"
				local color = Config.StatusColors[h.status] or QUIET
				if active then
					link(colX[5] + W * 0.06, y, colX[6] - W * 0.11, hy, if ctoUp then Color3.fromRGB(60, 120, 170) else GREY, 2)
				end
				local row = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(colX[6], hy), Size = UDim2.fromOffset(W * 0.22, rowH - 2), BackgroundColor3 = if active then color else PANEL, BackgroundTransparency = if active then 0 else 0.3, BorderSizePixel = 0, ZIndex = 3, Parent = body })
				corner(row, 3)
				local label = "Casa " .. h.index
				if not active then
					label ..= " · sem contrato"
				elseif h.signal then
					label ..= string.format(" · %.1f dBm · %s", h.signal, Config.StatusLabels[h.status] or h.status)
				else
					label ..= " · " .. (Config.StatusLabels[h.status] or h.status)
				end
				text(row, label, UDim2.fromOffset(6, 1), UDim2.new(1, -10, 1, -2), { Font = Enum.Font.GothamBold, TextColor3 = if active then Color3.fromRGB(10, 12, 18) else QUIET, ZIndex = 4 })
			end
		end
	end

	-- legenda
	text(body, "Azul: enlace ativo · Cinza: sem tráfego · Vermelho piscando: fibra rompida · Amarelo: sinal atenuado", UDim2.fromOffset(10, s.h - 20), UDim2.new(1, -20, 0, 14), { TextColor3 = QUIET })
end

-- ---------------------------------------------------------------------------
-- Tráfego
-- ---------------------------------------------------------------------------

local history: { number } = {}
local HISTORY = 90

local function renderTraffic(s: Screen, snap: any)
	local body = s.body
	clear(body)
	local cap = snap.capacityMbps
	local util = snap.utilization or 0
	local utilColor = if util > 0.9 then Config.StatusColors.offline elseif util > 0.7 then Config.StatusColors.slow else Config.StatusColors.online
	text(body, string.format("%.0f Mbps", snap.trafficMbps), UDim2.fromOffset(14, 6), UDim2.new(0.5, 0, 0, 50), { Font = Enum.Font.GothamBlack, TextColor3 = utilColor })
	text(body, string.format("de %d Mbps · uso %d%% · demanda %.0f Mbps", cap, math.floor(util * 100), snap.demandMbps), UDim2.fromOffset(14, 58), UDim2.new(1, -28, 0, 22), { TextColor3 = QUIET })

	local top, bottom = 92, s.h - 14
	local left, right = 14, s.w - 14
	local maxV = math.max(cap * 1.15, 1)
	local bw = (right - left) / HISTORY
	for i, v in history do
		local bh = (math.min(v, maxV) / maxV) * (bottom - top)
		local frac = v / cap
		local c = if frac > 0.9 then Config.StatusColors.offline elseif frac > 0.7 then Config.StatusColors.slow else ACCENT
		new("Frame", { Position = UDim2.fromOffset(left + (i - 1) * bw, bottom - bh), Size = UDim2.fromOffset(math.max(bw - 1, 1), bh), BackgroundColor3 = c, BorderSizePixel = 0, Parent = body })
	end
	local capY = bottom - (cap / maxV) * (bottom - top)
	new("Frame", { Position = UDim2.fromOffset(left, capY), Size = UDim2.fromOffset(right - left, 2), BackgroundColor3 = Config.StatusColors.offline, BorderSizePixel = 0, Parent = body })
	text(body, "capacidade", UDim2.fromOffset(right - 120, capY - 20), UDim2.fromOffset(120, 18), { TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Config.StatusColors.offline })
end

-- ---------------------------------------------------------------------------
-- Listas
-- ---------------------------------------------------------------------------

local function rows(s: Screen, count: number): (number, number)
	local rh = math.floor((s.h - 12) / count)
	return rh, 6
end

local function renderAlarms(s: Screen, snap: any)
	local body = s.body
	clear(body)
	local rh, y0 = rows(s, 10)
	if #snap.alarms == 0 then
		text(body, "Nenhum alarme. Rede estável.", UDim2.fromOffset(16, 20), UDim2.new(1, -32, 0, 32), { TextColor3 = Config.StatusColors.online })
		return
	end
	for i = 1, math.min(10, #snap.alarms) do
		local a = snap.alarms[i]
		local y = y0 + (i - 1) * rh
		local row = new("Frame", { Position = UDim2.fromOffset(10, y), Size = UDim2.new(1, -20, 0, rh - 4), BackgroundColor3 = PANEL, BorderSizePixel = 0, Parent = body })
		corner(row, 4)
		new("Frame", { Size = UDim2.new(0, 6, 1, 0), BackgroundColor3 = SevColor[a.severity] or QUIET, BorderSizePixel = 0, Parent = row })
		text(row, a.time, UDim2.new(0, 14, 0.15, 0), UDim2.new(0.13, 0, 0.7, 0), { TextColor3 = QUIET })
		text(row, a.kind, UDim2.new(0.16, 0, 0.15, 0), UDim2.new(0.2, 0, 0.7, 0), { Font = Enum.Font.GothamBold })
		text(row, a.text, UDim2.new(0.38, 0, 0.15, 0), UDim2.new(0.6, 0, 0.7, 0))
	end
end

local function renderOnus(s: Screen, snap: any)
	local body = s.body
	clear(body)
	-- duas colunas: Rua Principal (1 a 8) e Rua das Palmeiras (9 a 16)
	local perCol = math.ceil(#snap.houses / 2)
	local rh, y0 = rows(s, perCol + 1)
	local function cx(col: number, frac: number): UDim
		return UDim.new((col - 1) * 0.5 + frac * 0.5, if frac == 0 then 12 else 0)
	end
	for col = 1, 2 do
		text(body, "Casa", UDim2.new(cx(col, 0), UDim.new(0, y0)), UDim2.new(0.1, 0, 0, rh - 6), { TextColor3 = QUIET })
		text(body, "Status", UDim2.new(cx(col, 0.22), UDim.new(0, y0)), UDim2.new(0.17, 0, 0, rh - 6), { TextColor3 = QUIET })
		text(body, "Sinal", UDim2.new(cx(col, 0.6), UDim.new(0, y0)), UDim2.new(0.19, 0, 0, rh - 6), { TextColor3 = QUIET })
	end
	table.sort(snap.houses, function(a, b)
		return a.index < b.index
	end)
	for i, h in snap.houses do
		local col = if i > perCol then 2 else 1
		local y = y0 + (if col == 2 then i - perCol else i) * rh
		local color = Config.StatusColors[h.status] or QUIET
		text(body, tostring(h.index), UDim2.new(cx(col, 0), UDim.new(0, y)), UDim2.new(0.1, 0, 0, rh - 6), { Font = Enum.Font.GothamBold })
		text(body, Config.StatusLabels[h.status] or h.status, UDim2.new(cx(col, 0.22), UDim.new(0, y)), UDim2.new(0.17, 0, 0, rh - 6), { TextColor3 = color })
		local sig = if h.contract ~= "active" then "-" elseif h.signal then string.format("%.1f dBm", h.signal) else "LOS"
		local sigColor = INK
		if h.signal and h.signal < Config.SignalUnstableDbm then
			sigColor = Config.StatusColors.unstable
		elseif h.contract == "active" and not h.signal then
			sigColor = Config.StatusColors.offline
		end
		text(body, sig, UDim2.new(cx(col, 0.6), UDim.new(0, y)), UDim2.new(0.19, 0, 0, rh - 6), { TextColor3 = sigColor })
	end
end

local function renderTickets(s: Screen, snap: any)
	local body = s.body
	clear(body)
	local y = 6
	local rh = math.floor((s.h - 12) / 8)
	local open = 0
	for _, h in snap.houses do
		if h.ticket then
			open += 1
			if open <= 3 then
				local label = "Chamado aberto · Casa " .. h.index
				if h.down and h.down > 0 then
					-- tempo sem internet em horas de jogo; com 1 dia o cliente cancela
					local hours = h.down / Config.HourSeconds
					local limit = Config.CancelAfterSeconds / Config.HourSeconds
					label ..= string.format(" · %dh%02d sem internet (cancela com %dh)", math.floor(hours), math.floor((hours % 1) * 60), limit)
				end
				text(body, label, UDim2.fromOffset(12, y), UDim2.new(1, -24, 0, rh - 6), { Font = Enum.Font.GothamBold, TextColor3 = Config.StatusColors.offline })
				y += rh
			end
		end
	end
	if open == 0 then
		text(body, "Nenhum chamado aberto", UDim2.fromOffset(12, y), UDim2.new(1, -24, 0, rh - 6), { TextColor3 = Config.StatusColors.online })
		y += rh
	end
	-- o que os moradores andam falando
	for _, p in snap.mood.people do
		if y > s.h - rh then
			break
		end
		if p.last ~= "" and p.mood < 60 then
			text(body, p.name .. ": \"" .. p.last .. "\"", UDim2.fromOffset(12, y), UDim2.new(1, -24, 0, rh - 6), { TextColor3 = QUIET })
			y += rh
		end
	end
end

local function renderSummary(s: Screen, snap: any)
	local body = s.body
	clear(body)
	local g = snap.game
	local online, active = 0, 0
	for _, h in snap.houses do
		if h.contract == "active" then
			active += 1
			if h.status == "online" or h.status == "slow" then
				online += 1
			end
		end
	end
	local stars = string.rep("★", math.floor(g.reputation + 0.5)) .. string.rep("☆", 5 - math.floor(g.reputation + 0.5))
	local lines = {
		{ "Dia " .. g.day .. " · " .. g.clock, INK },
		{ string.format("Clientes online: %d de %d", online, active), if online == active then Config.StatusColors.online else Config.StatusColors.unstable },
		{ string.format("SLA do dia: %.1f%%", g.sla), if g.sla >= 98 then Config.StatusColors.online elseif g.sla >= 90 then Config.StatusColors.slow else Config.StatusColors.offline },
		{ string.format("Caixa: R$ %d", g.money), INK },
		{ "Reputação: " .. stars, Config.StatusColors.slow },
		{ string.format("Multas de SLA hoje: R$ %d", g.penalties), QUIET },
		{ if snap.tech and #snap.tech.team > 0 then string.format("Equipe de rua: %d técnico(s) · R$ %d/dia", #snap.tech.team, snap.tech.dailyTotal) else "Equipe de rua: ninguém contratado", if snap.tech and #snap.tech.team > 0 then Config.StatusColors.slow else QUIET },
		{ if snap.tech and snap.tech.car and snap.tech.car.owned then "Carro: " .. snap.tech.car.stateText else "Carro: o provedor não tem", QUIET },
	}
	local rh = math.floor((s.h - 12) / #lines)
	for i, l in lines do
		text(body, l[1], UDim2.fromOffset(12, 6 + (i - 1) * rh), UDim2.new(1, -24, 0, rh - 6), { TextColor3 = l[2], Font = if i == 1 then Enum.Font.GothamBold else Enum.Font.Gotham })
	end
end

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

local function renderMood(s: Screen, snap: any)
	local body = s.body
	clear(body)
	local m = snap.mood
	local avg = m.average
	local bar = new("Frame", { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 22), BackgroundColor3 = PANEL, BorderSizePixel = 0, Parent = body })
	corner(bar, 6)
	local fill = new("Frame", { Size = UDim2.fromScale(math.clamp(avg / 100, 0, 1), 1), BackgroundColor3 = moodColor(avg), BorderSizePixel = 0, Parent = bar })
	corner(fill, 6)
	text(bar, string.format("Humor médio: %d / 100", math.floor(avg)), UDim2.fromScale(0.03, 0.1), UDim2.fromScale(0.94, 0.8), { Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(10, 10, 15) })
	local c = m.counts
	text(body, string.format("Felizes %d · Ok %d · Irritados %d · Furiosos %d", c.feliz, c.ok, c.irritado, c.furioso), UDim2.fromOffset(12, 32), UDim2.new(1, -24, 0, 18), { TextColor3 = QUIET })
	local top = 56
	local perCol = math.ceil(#m.people / 2)
	local rh = math.floor((s.h - top - 4) / math.max(1, perCol))
	for i, p in m.people do
		local col = if i > perCol then 1 else 0
		local y = top + ((i - 1) % perCol) * rh
		text(body, p.name, UDim2.new(col * 0.5, 12, 0, y), UDim2.new(0.22, 0, 0, rh - 4), { TextColor3 = if p.contract == "active" then INK else QUIET })
		local track = new("Frame", { Position = UDim2.new(col * 0.5 + 0.24, 0, 0, y + 3), Size = UDim2.new(0.23, 0, 0, rh - 8), BackgroundColor3 = PANEL, BorderSizePixel = 0, Parent = body })
		if p.contract == "active" then
			new("Frame", { Size = UDim2.fromScale(math.clamp(p.mood / 100, 0, 1), 1), BackgroundColor3 = moodColor(p.mood), BorderSizePixel = 0, Parent = track })
		end
	end
end

-- ---------------------------------------------------------------------------
-- Painel do datacenter: equipamentos do rack e os cabos principais
-- ---------------------------------------------------------------------------

local DevState = {
	ok = { "OK", Config.StatusColors.online },
	boot = { "Iniciando", Config.StatusColors.slow },
	config = { "Sem configuração", Config.StatusColors.unstable },
	nocable = { "Sem cabo", Config.StatusColors.unstable },
	off = { "Desligado", QUIET },
	fail = { "Queimado", Config.StatusColors.offline },
}
local LinkState = {
	ok = { "OK", Config.StatusColors.online },
	down = { "Sem sinal", Config.StatusColors.offline },
	broken = { "Fibra rompida", Config.StatusColors.offline },
	dirty = { "Atenuada", Config.StatusColors.unstable },
}
local CableColor = {
	red = Color3.fromRGB(210, 50, 50),
	blue = Color3.fromRGB(40, 120, 230),
	yellow = Color3.fromRGB(240, 200, 40),
}

local function renderRack(s: Screen, snap: any)
	local body = s.body
	clear(body)
	local rk = snap.rack
	if not rk then
		return
	end
	local split = 0.56
	local rh = math.floor((s.h - 16) / 7)
	text(body, "RACK 02 · EQUIPAMENTOS", UDim2.fromOffset(12, 6), UDim2.new(split, -24, 0, rh - 10), { Font = Enum.Font.GothamBold, TextColor3 = ACCENT })
	if #rk.devices == 0 then
		text(body, "Rack vazio. Compre roteador e OLT no terminal de compras.", UDim2.fromOffset(12, 6 + rh), UDim2.new(split, -24, 0, rh - 8), { TextColor3 = Config.StatusColors.offline })
	end
	for i, d in rk.devices do
		if i > 4 then
			break
		end
		local y = 6 + i * rh
		local row = new("Frame", { Position = UDim2.fromOffset(10, y), Size = UDim2.new(split, -20, 0, rh - 6), BackgroundColor3 = PANEL, BorderSizePixel = 0, Parent = body })
		corner(row, 6)
		local st = DevState[d.state] or { d.state, QUIET }
		new("Frame", { Size = UDim2.new(0, 8, 1, 0), BackgroundColor3 = st[2], BorderSizePixel = 0, Parent = row })
		text(row, string.format("Slot %d · %s", d.slot, d.label), UDim2.new(0, 16, 0.06, 0), UDim2.new(0.62, -16, 0.46, 0), { Font = Enum.Font.GothamBold })
		text(row, st[1], UDim2.new(0.64, 0, 0.06, 0), UDim2.new(0.34, 0, 0.46, 0), { Font = Enum.Font.GothamBold, TextColor3 = st[2], TextXAlignment = Enum.TextXAlignment.Right })
		text(row, string.format("%s · %s · ligado há %s", d.model, d.ip, d.uptime), UDim2.new(0, 16, 0.56, 0), UDim2.new(1, -24, 0.36, 0), { TextColor3 = QUIET })
	end
	text(body, string.format("Slots livres: %d de %d", rk.free, rk.slots), UDim2.fromOffset(12, 6 + 5 * rh + 4), UDim2.new(split, -24, 0, rh - 14), { TextColor3 = QUIET })

	local x0 = math.floor(s.w * split)
	text(body, "CABOS PRINCIPAIS", UDim2.fromOffset(x0 + 6, 6), UDim2.new(1 - split, -18, 0, rh - 10), { Font = Enum.Font.GothamBold, TextColor3 = ACCENT })
	for i, l in rk.links do
		local y = 6 + i * rh
		local row = new("Frame", { Position = UDim2.fromOffset(x0, y), Size = UDim2.new(1 - split, -10, 0, rh - 6), BackgroundColor3 = PANEL, BorderSizePixel = 0, Parent = body })
		corner(row, 6)
		new("Frame", { Position = UDim2.new(0, 8, 0.5, -5), Size = UDim2.new(0, 26, 0, 10), BackgroundColor3 = CableColor[l.color] or INK, BorderSizePixel = 0, Parent = row })
		local st = LinkState[l.state] or { l.state, QUIET }
		text(row, l.name, UDim2.new(0, 42, 0.06, 0), UDim2.new(1, -50, 0.5, 0), { Font = Enum.Font.GothamBold })
		local lbl = st[1]
		if l.state == "down" and blink then
			lbl = "● " .. lbl
		end
		text(row, lbl, UDim2.new(0, 42, 0.56, 0), UDim2.new(1, -50, 0.38, 0), { TextColor3 = st[2] })
	end
	local g = snap.game
	local stock = g.stock or {}
	text(body, string.format("Estoque: %d ONU · %d drop · %d emendas · %d conectores", stock.onu or 0, stock.drop or 0, stock.emenda or 0, stock.conector or 0), UDim2.fromOffset(x0 + 6, 6 + 5 * rh + 4), UDim2.new(1 - split, -18, 0, rh - 14), { TextColor3 = QUIET })
end

local Renderers = {
	Rack = renderRack,
	Map = renderMap,
	Topology = renderTopology,
	Traffic = renderTraffic,
	Alarms = renderAlarms,
	Onus = renderOnus,
	Tickets = renderTickets,
	Summary = renderSummary,
	Mood = renderMood,
}

NocUpdate.OnClientEvent:Connect(function(snap)
	blink = not blink
	table.insert(history, snap.trafficMbps)
	while #history > HISTORY do
		table.remove(history, 1)
	end
	-- cada prédio tem as suas telas: só desenha as do provedor do jogador
	local mySlot = Players.LocalPlayer:GetAttribute("Slot")
	for _, s in screens do
		if (s.part:GetAttribute("Slot") or 1) ~= mySlot then
			continue
		end
		s.state.clock.Text = snap.game.clock
		local r = Renderers[s.kind]
		if r then
			local ok, err = pcall(r, s, snap)
			if not ok then
				warn("[NOC] erro ao desenhar " .. s.kind .. ": " .. tostring(err))
			end
		end
	end
end)
