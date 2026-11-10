-- Liga o grafo da rede ao mundo 3D: cabos, LEDs, incidentes, ferramentas e reparos.
-- O grafo é a fonte da verdade. O mundo só mostra o estado dele.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)
local NetworkGraph = require(ReplicatedStorage.Shared.NetworkGraph)
local World = require(script.Parent.WorldBuilder)
local Remotes = require(script.Parent.Remotes)
local Providers = require(script.Parent.Providers)

local Net = {}

Net.graph = NetworkGraph.new()
Net.houses = {} -- por índice: { house, onuId, edgeId, contract, slot, price, choice, willing, status, signal, reason, ... }

-- Dados de rede de cada provedor (por prédio): link, tráfego e alarmes
Net.bySlot = {}
for slot = 1, 2 do
	Net.bySlot[slot] = { upstreamMbps = 0, trafficMbps = 0, demandMbps = 0, utilization = 0, alarms = {} }
end
function Net.slot(slot: number): any
	return Net.bySlot[slot]
end
-- Zera os dados de um prédio quando o provedor fecha
function Net.resetSlot(slot: number)
	Net.bySlot[slot] = { upstreamMbps = 0, trafficMbps = 0, demandMbps = 0, utilization = 0, alarms = {} }
end

-- Ids dos nós do núcleo de cada provedor no grafo (o prédio 1 mantém os nomes antigos)
function Net.coreId(slot: number, kind: string): string
	local base = string.upper(kind)
	return if slot == 1 then base else base .. "_" .. slot
end

local world: any
local game_: any
local visuals: { [string]: { points: { Vector3 }, segments: { BasePart }, extra: { Instance }, color: Color3 } } = {}
local breaks: { [string]: BasePart } = {} -- aresta rompida -> marcador no chão
local ToolNames = Config.ToolNames

-- ---------------------------------------------------------------------------
-- Alarmes e chamados
-- ---------------------------------------------------------------------------

-- Alarme no NOC de um provedor. slot nil: alarme da rua, vai para todos os provedores abertos.
function Net.addAlarm(slot: number?, kind: string, text: string, severity: string)
	if slot == nil then
		for _, P in Providers.list() do
			Net.addAlarm(P.slot, kind, text, severity)
		end
		return
	end
	local list = Net.bySlot[slot].alarms
	table.insert(list, 1, { time = game_.clockText(), kind = kind, text = text, severity = severity })
	while #list > 30 do
		table.remove(list)
	end
	local P = Providers.slots[slot]
	if severity ~= "ok" and P then
		Providers.notify(P, nil, "Novo alarme no NOC: " .. text, "alarm")
	end
end

-- ---------------------------------------------------------------------------
-- Ferramentas
-- ---------------------------------------------------------------------------

local function makeTool(name: string, color: Color3, tip: string): Tool
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.ToolTip = tip
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.8, 1.2, 0.5)
	handle.Color = color
	handle.Material = Enum.Material.SmoothPlastic
	handle.CanCollide = false
	handle.Parent = tool
	local screen = Instance.new("Part")
	screen.Name = "Detail"
	screen.Size = Vector3.new(0.6, 0.5, 0.1)
	screen.Color = Color3.fromRGB(30, 200, 120)
	screen.Material = Enum.Material.Neon
	screen.CanCollide = false
	screen.Massless = true
	screen.CFrame = handle.CFrame * CFrame.new(0, 0.2, -0.3)
	screen.Parent = tool
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = screen
	weld.Parent = handle
	return tool
end

-- Notebook do TI: tela aberta e teclado. O RackService liga o clique ao terminal
-- pela tag "NotebookTI".
local function makeNotebook(): Tool
	local tool = Instance.new("Tool")
	tool.Name = ToolNames.Notebook
	tool.ToolTip = "Clique para abrir o terminal. Perto do rack: comando console"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.GripPos = Vector3.new(0, -0.3, 0.4)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1.6, 0.12, 1.1)
	handle.Color = Color3.fromRGB(40, 42, 48)
	handle.Material = Enum.Material.Metal
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool
	local lid = Instance.new("Part")
	lid.Name = "Tela"
	lid.Size = Vector3.new(1.6, 1, 0.08)
	lid.Color = Color3.fromRGB(20, 60, 90)
	lid.Material = Enum.Material.Neon
	lid.CanCollide = false
	lid.Massless = true
	lid.CFrame = handle.CFrame * CFrame.new(0, 0.5, 0.55) * CFrame.Angles(math.rad(-15), 0, 0)
	lid.Parent = tool
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = lid
	weld.Parent = handle
	CollectionService:AddTag(tool, "NotebookTI")
	return tool
end

-- Ferramentas são do provedor: depois de compradas, todo mundo da equipe recebe.
local toolTemplates: { [string]: Tool } = {}

-- Deixa no inventário só as ferramentas que o provedor do jogador comprou
local function giveTools(player: Player): number
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return 0
	end
	local P = Providers.of(player)
	local owned = if P then P.game.owned else {}
	local n = 0
	for _, key in Config.ToolOrder do
		local t = toolTemplates[key]
		if t and not owned[key] then
			for _, where in { backpack, player.Character } do
				local old = where and where:FindFirstChild(t.Name)
				if old and old:IsA("Tool") then
					old:Destroy()
				end
			end
		end
		if t and owned[key] then
			n += 1
			local has = backpack:FindFirstChild(t.Name) or (player.Character and player.Character:FindFirstChild(t.Name))
			if not has then
				t:Clone().Parent = backpack
			end
		end
	end
	return n
end

Net.giveTools = giveTools

-- Chamado pela loja depois da compra de uma ferramenta.
function Net.grantTool(P: any, key: string)
	P.game.owned[key] = true
	P.game.publish()
	for _, player in Providers.members(P) do
		giveTools(player)
	end
end

-- Provedor do jogador; avisa se ele ainda não tem um
local function providerOf(player: Player): any
	local P = Providers.of(player)
	if not P then
		Remotes.notify(player, "Você ainda não faz parte de nenhum provedor. Abra o menu Provedor (tecla P).", "error")
	end
	return P
end

local function holding(player: Player, toolName: string): boolean
	local char = player.Character
	local t = char and char:FindFirstChild(toolName)
	if t and t:IsA("Tool") then
		return true
	end
	Remotes.notify(player, "Equipe a ferramenta: " .. toolName, "error")
	return false
end

local function prompt(parent: Instance, action: string, object: string, hold: number?, distance: number?): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold or 0
	p.MaxActivationDistance = distance or 12
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

-- ---------------------------------------------------------------------------
-- Cabos
-- ---------------------------------------------------------------------------

local CableColor = {
	trunk = Color3.fromRGB(20, 20, 22),
	distribution = Color3.fromRGB(30, 30, 34),
	drop = Color3.fromRGB(60, 60, 64),
}

local function drawEdge(edgeId: string, points: { Vector3 }, kind: string)
	local color = CableColor[kind] or CableColor.drop
	visuals[edgeId] = {
		points = points,
		segments = World.cable(points, color, world.cablesFolder, edgeId),
		extra = {},
		color = color,
	}
end

local function clearExtras(v)
	for _, inst in v.extra do
		inst:Destroy()
	end
	v.extra = {}
end

local function refreshEdgeVisual(edgeId: string)
	local v = visuals[edgeId]
	local edge = Net.graph.edges[edgeId]
	if not v then
		return
	end
	clearExtras(v)
	for _, s in v.segments do
		s.Transparency = 0
		s.Color = v.color
	end
	if not edge then
		return
	end
	if edge.state == "dirty" then
		-- trecho final do drop fica alaranjado (conector ruim na casa)
		v.segments[#v.segments].Color = Color3.fromRGB(150, 90, 40)
	elseif edge.state == "broken" then
		-- some um segmento e as duas pontas ficam penduradas
		local idx = math.clamp(math.floor(#v.segments / 2) + 1, 1, #v.segments)
		local seg = v.segments[idx]
		seg.Transparency = 1
		local a, b = v.points[idx], v.points[idx + 1]
		local cut = a:Lerp(b, 0.5)
		for _, endPoint in { a:Lerp(b, 0.42), b:Lerp(a, 0.42) } do
			local hangTo = endPoint + Vector3.new(0, -5, 0) + (cut - endPoint).Unit * 1.5
			local hang = World.part({ Name = "CaboPendurado", Size = Vector3.new(0.22, 0.22, (hangTo - endPoint).Magnitude), CFrame = CFrame.lookAt((endPoint + hangTo) / 2, hangTo), Color = v.color, CanCollide = false, Parent = world.effectsFolder })
			table.insert(v.extra, hang)
		end
		-- linhas finas do pedaço do meio caído no chão
		local ground = Vector3.new(cut.X, 0.7, cut.Z)
		local cone = World.part({ Name = "Cone", Size = Vector3.new(1.2, 2, 1.2), CFrame = CFrame.new(ground + Vector3.new(2, 0.5, 0)), Color = Color3.fromRGB(255, 120, 20), Parent = world.effectsFolder })
		table.insert(v.extra, cone)
	end
end

-- ---------------------------------------------------------------------------
-- Montagem da rede
-- ---------------------------------------------------------------------------

local function dropPoints(h: any, ctoBox: BasePart): { Vector3 }
	local house = h.house
	local boxPos = house.box.Position
	local start = ctoBox.Position + Vector3.new(0, 3.5, 0)
	return { start, house.dropMid, boxPos + Vector3.new(0, 0.6, 0) }
end

-- CTOs da rede: cada uma numa porta PON da OLT, atrás de um splitter primário
Net.CtoOrder = { "CTO_A", "CTO_B", "CTO_C", "CTO_D" }
Net.CtoSplitter = { CTO_A = "SPL", CTO_B = "SPL", CTO_C = "SPL2", CTO_D = "SPL2" }
local CtoBoxKey = { CTO_A = "ctoA", CTO_B = "ctoB", CTO_C = "ctoC", CTO_D = "ctoD" }

local function ctoFor(index: number): (string, BasePart)
	local id = Net.houses[index].house.cto
	return id, world.boxes[CtoBoxKey[id]]
end

local HEX = "0123456789ABCDEF"
function Net.newSn(): string
	local out = "HWTC"
	for _ = 1, 8 do
		local i = math.random(1, 16)
		out ..= string.sub(HEX, i, i)
	end
	return out
end

-- Porta PON da OLT que atende cada CTO
Net.PonPort = { CTO_A = 0, CTO_B = 1, CTO_C = 2, CTO_D = 3 }
function Net.ponPortOf(h: any): number
	return Net.PonPort[h.house.cto] or 0
end

local function connectHouse(h: any, P: any)
	local index = h.house.index
	local onuId = "ONU" .. index
	local ctoId, ctoBox = ctoFor(index)
	local pts = dropPoints(h, ctoBox)
	local length = 0
	for i = 1, #pts - 1 do
		length += (pts[i + 1] - pts[i]).Magnitude
	end
	Net.graph:addNode(onuId, "onu", { label = "ONU " .. index, x = h.house.position.X, z = h.house.position.Z, provider = P.slot })
	local edgeId = "DROP" .. index
	Net.graph:addEdge(edgeId, ctoId, onuId, { kind = "drop", label = "Drop casa " .. index, lossDb = 0.8 + length * 0.012 })
	drawEdge(edgeId, pts, "drop")
	h.onuId = onuId
	h.edgeId = edgeId
	h.contract = "active"
	h.slot = P.slot
	h.price = P.price
	h.sn = Net.newSn()
end

local function disconnectHouse(h: any)
	if h.edgeId then
		local v = visuals[h.edgeId]
		if v then
			clearExtras(v)
			for _, s in v.segments do
				s:Destroy()
			end
			visuals[h.edgeId] = nil
		end
		if breaks[h.edgeId] then
			breaks[h.edgeId]:Destroy()
			breaks[h.edgeId] = nil
		end
		Net.graph:removeEdge(h.edgeId)
	end
	if h.onuId then
		Net.graph.nodes[h.onuId] = nil
	end
	h.onuId = nil
	h.edgeId = nil
end

local function buildNetwork()
	local g = Net.graph
	local isp = world.isp
	local P = world.poles
	-- núcleo de cada provedor (um por prédio)
	for slot = 1, 2 do
		local dx = world.isps[slot].offset.X
		local function id(kind: string): string
			return Net.coreId(slot, kind)
		end
		local suffix = if slot == 1 then "" else "_" .. slot
		g:addNode(id("upstream"), "upstream", { label = "Upstream", x = -150 + dx, z = -62, provider = slot })
		g:addNode(id("router"), "router", { label = "Roteador", x = -128 + dx, z = -52, provider = slot })
		g:addNode(id("dns"), "dns", { label = "DNS", x = -112 + dx, z = -52, provider = slot })
		g:addNode(id("olt"), "olt", { label = "OLT", x = -120 + dx, z = -40, provider = slot })
		g:addEdge("CORE1" .. suffix, id("upstream"), id("router"), { kind = "core" })
		g:addEdge("CORE2" .. suffix, id("router"), id("olt"), { kind = "core" })
		g:addEdge("CORE3" .. suffix, id("router"), id("dns"), { kind = "core" })
	end
	local isp2 = world.isps[2]

	g:addNode("SPL", "splitter", { label = "Splitter 1:2", lossDb = 3.7, x = -60, z = -16.5 })
	g:addNode("CTO_A", "splitter", { label = "CTO A", lossDb = 10.5, x = 35, z = -16.5 })
	g:addNode("CTO_B", "splitter", { label = "CTO B", lossDb = 10.5, x = 35, z = 16.5 })

	g:addEdge("TRONCO", "OLT", "SPL", { kind = "trunk", label = "Fibra tronco", lossDb = 2.0, provider = 1 })
	drawEdge("TRONCO", { isp.trunkExit, P["N-85"].top, P["N-60"].top }, "trunk")
	-- tronco do prédio 2 até o mesmo splitter (rede neutra), um pouco mais baixo nos postes
	local low3 = Vector3.new(0, -3, 0)
	g:addEdge("TRONCO_P2", "OLT_2", "SPL", { kind = "trunk", label = "Fibra tronco (prédio 2)", lossDb = 3.0, provider = 2 })
	drawEdge("TRONCO_P2", { isp2.trunkExit, P["N185"].top + low3, P["N135"].top + low3, P["N85"].top + low3, P["N35"].top + low3, P["N-15"].top + low3, P["N-60"].top + low3 }, "trunk")
	g:addEdge("DIST_A", "SPL", "CTO_A", { kind = "distribution", label = "Distribuição A", lossDb = 1.5 })
	drawEdge("DIST_A", { P["N-60"].top, P["N-15"].top, P["N35"].top }, "distribution")
	local down = Vector3.new(0, -1, 0)
	g:addEdge("DIST_B", "SPL", "CTO_B", { kind = "distribution", label = "Distribuição B", lossDb = 1.8 })
	drawEdge("DIST_B", { P["N-60"].top + down, P["N-15"].top + down, P["S-15"].top + down, P["S35"].top + down }, "distribution")
	-- trecho sem uso até o fim da rua (só visual)
	World.cable({ P["S35"].top + down, P["S85"].top + down, P["S135"].top + down }, CableColor.distribution, world.cablesFolder, "Reserva_S")

	-- Rua das Palmeiras: segundo tronco, saindo do mesmo DIO e correndo pelos postes do lado norte
	local down2 = down * 2
	g:addNode("SPL2", "splitter", { label = "Splitter 1:2 Palmeiras", lossDb = 3.7, x = 283.5, z = -35 })
	g:addNode("CTO_C", "splitter", { label = "CTO C", lossDb = 10.5, x = 283.5, z = -135 })
	g:addNode("CTO_D", "splitter", { label = "CTO D", lossDb = 10.5, x = 316.5, z = -135 })
	g:addEdge("TRONCO2", "OLT", "SPL2", { kind = "trunk", label = "Fibra tronco Palmeiras", lossDb = 3.2, provider = 1 })
	g:addEdge("TRONCO2_P2", "OLT_2", "SPL2", { kind = "trunk", label = "Fibra tronco Palmeiras (prédio 2)", lossDb = 2.0, provider = 2 })
	drawEdge("TRONCO2_P2", { isp2.trunkExit + low3, P["N235"].top + low3, P["W-35"].top + low3 }, "trunk")
	drawEdge("TRONCO2", { isp.trunkExit + down, P["N-85"].top + down2, P["N-60"].top + down2, P["N-15"].top + down2, P["N35"].top + down2, P["N85"].top + down2, P["N135"].top + down2, P["N185"].top + down2, P["N235"].top + down2, P["W-35"].top }, "trunk")
	g:addEdge("DIST_C", "SPL2", "CTO_C", { kind = "distribution", label = "Distribuição C", lossDb = 1.4 })
	drawEdge("DIST_C", { P["W-35"].top, P["W-85"].top, P["W-135"].top }, "distribution")
	g:addEdge("DIST_D", "SPL2", "CTO_D", { kind = "distribution", label = "Distribuição D", lossDb = 1.7 })
	drawEdge("DIST_D", { P["W-35"].top + down, P["E-35"].top + down, P["E-85"].top + down, P["E-135"].top + down }, "distribution")
	World.cable({ P["W-135"].top, P["W-185"].top, P["W-235"].top }, CableColor.distribution, world.cablesFolder, "Reserva_W")
	World.cable({ P["E-135"].top + down, P["E-185"].top + down, P["E-235"].top + down }, CableColor.distribution, world.cablesFolder, "Reserva_E")

	for _, house in world.houses do
		local h = {
			house = house,
			onuId = nil,
			edgeId = nil,
			contract = "none",
			status = "nocontract",
			signal = nil,
			reason = "",
			offlineSeconds = 0,
			downSeconds = 0, -- tempo seguido sem internet (cancela com 1 dia)
			cancelWarned = false,
			ticketOpen = false,
			slot = nil, -- prédio do provedor do contrato
			price = nil, -- preço do contrato (fica igual até o cliente cancelar)
			choice = nil, -- provedor que o morador escolheria agora (o mais barato que ele aceita)
			willing = math.random(Config.Price.WillingMin, Config.Price.WillingMax), -- preço máximo que aceita pagar
		}
		-- a vila começa sem internet: nenhuma casa ligada
		Net.houses[house.index] = h
	end
end

-- ---------------------------------------------------------------------------
-- Incidentes
-- ---------------------------------------------------------------------------

function Net.activeIncidents(): number
	local n = 0
	for _, e in Net.graph.edges do
		if e.state ~= "ok" then
			n += 1
		end
	end
	for _, node in Net.graph.nodes do
		if node.state ~= "ok" then
			n += 1
		end
	end
	return n
end

local function spliceAt(edgeId: string, player: Player)
	if not holding(player, ToolNames.Fusion) then
		return
	end
	local edge = Net.graph.edges[edgeId]
	if not edge or edge.state ~= "broken" then
		return
	end
	local P = providerOf(player)
	if not P then
		return
	end
	-- tronco é de um provedor só; distribuição e drops da rua são de quem atende
	local owner = edge.provider or (if edge.kind == "drop" then Net.houses[tonumber(string.match(edgeId, "%d+")) or 0] and Net.houses[tonumber(string.match(edgeId, "%d+")) or 0].slot else nil)
	if owner and owner ~= P.slot then
		local other = Providers.slots[owner]
		Remotes.notify(player, "Esse cabo é do provedor " .. (if other then other.name else "concorrente") .. ".", "error")
		return
	end
	if not P.game.useStock({ emenda = 1 }, player) then
		return
	end
	Net.graph:setEdgeState(edgeId, "ok")
	refreshEdgeVisual(edgeId)
	if breaks[edgeId] then
		breaks[edgeId]:Destroy()
		breaks[edgeId] = nil
	end
	P.game.count("repairs")
	Net.addAlarm(owner, "Reparo", edge.label .. " emendada por " .. P.name, "ok")
	Remotes.notify(player, "Fibra emendada! Confira no NOC se as casas voltaram.", "success")
end

-- ---------------------------------------------------------------------------
-- Reparos feitos pelo técnico NPC (o material sai do estoque, sem ferramenta na mão)
-- ---------------------------------------------------------------------------

-- Problemas físicos na rua que o técnico sabe resolver.
function Net.streetJobs(slot: number)
	local jobs = {}
	for id, e in Net.graph.edges do
		local dropOf = if e.kind == "drop" then Net.houses[tonumber(string.match(id, "%d+")) or 0] else nil
		local owner = e.provider or (dropOf and dropOf.slot)
		if owner and owner ~= slot then
			continue
		end
		if e.state == "broken" and breaks[id] then
			-- tronco e distribuição derrubam várias casas: vêm primeiro
			table.insert(jobs, { kind = "break", key = "break:" .. id, edgeId = id, pos = breaks[id].Position, label = e.label, priority = if e.kind == "drop" then 2 else 1, needs = { emenda = 1 } })
		end
	end
	for index, h in Net.houses do
		if h.contract == "active" and h.slot == slot and h.onuId and h.edgeId then
			local node = Net.graph.nodes[h.onuId]
			local e = Net.graph.edges[h.edgeId]
			local door = h.house.doorPoint
			if node and node.state == "failed" then
				table.insert(jobs, { kind = "onu", key = "onu:" .. index, index = index, pos = door, label = "ONU da casa " .. index, priority = 2, needs = { onu = 1 } })
			elseif e and e.state == "dirty" then
				table.insert(jobs, { kind = "dirty", key = "dirty:" .. index, index = index, pos = door, label = "conector da casa " .. index, priority = 3, needs = { conector = 1 } })
			end
		end
	end
	return jobs
end

-- O trabalho ainda existe? (o jogador pode ter resolvido antes)
function Net.jobOpen(job: any): boolean
	if job.kind == "break" then
		local e = Net.graph.edges[job.edgeId]
		return e ~= nil and e.state == "broken"
	end
	local h = Net.houses[job.index]
	if not h or h.contract ~= "active" or not h.onuId then
		return false
	end
	if job.kind == "onu" then
		local node = Net.graph.nodes[h.onuId]
		return node ~= nil and node.state == "failed"
	end
	local e = Net.graph.edges[h.edgeId]
	return e ~= nil and e.state == "dirty"
end

function Net.techFix(job: any, who: string, P: any): boolean
	if not Net.jobOpen(job) or not P.game.useStock(job.needs, nil) then
		return false
	end
	local slot = P.slot
	if job.kind == "break" then
		local edge = Net.graph.edges[job.edgeId]
		Net.graph:setEdgeState(job.edgeId, "ok")
		refreshEdgeVisual(job.edgeId)
		if breaks[job.edgeId] then
			breaks[job.edgeId]:Destroy()
			breaks[job.edgeId] = nil
		end
		Net.addAlarm(slot, "Reparo", edge.label .. " emendada por " .. who, "ok")
	elseif job.kind == "dirty" then
		local h = Net.houses[job.index]
		Net.graph:setEdgeState(h.edgeId, "ok")
		refreshEdgeVisual(h.edgeId)
		Net.addAlarm(slot, "Reparo", "Conector da casa " .. job.index .. " refeito por " .. who, "ok")
	elseif job.kind == "onu" then
		local h = Net.houses[job.index]
		Net.graph:setNodeState(h.onuId, "ok")
		h.sn = Net.newSn()
		-- a parte da rua está feita; autorizar o SN novo na OLT continua com a equipe
		Net.addAlarm(slot, "Reparo", string.format("%s trocou a ONU da casa %d. SN novo %s: autorize na OLT (ont modify %d <id> sn %s)", who, job.index, h.sn, Net.ponPortOf(h), h.sn), "warning")
	end
	P.game.count("repairs")
	return true
end

function Net.breakEdge(edgeId: string)
	local edge = Net.graph.edges[edgeId]
	local v = visuals[edgeId]
	if not edge or not v then
		return
	end
	Net.graph:setEdgeState(edgeId, "broken")
	refreshEdgeVisual(edgeId)
	local idx = math.clamp(math.floor(#v.segments / 2) + 1, 1, #v.segments)
	local cut = v.points[idx]:Lerp(v.points[idx + 1], 0.5)
	local marker = World.part({
		Name = "Rompimento",
		Size = Vector3.new(2.4, 0.3, 2.4),
		CFrame = CFrame.new(cut.X, 0.75, cut.Z),
		Color = Color3.fromRGB(255, 80, 40),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Transparency = 0.3,
		Parent = world.effectsFolder,
	})
	local p = prompt(marker, "Emendar fibra", edge.label, 4, 14)
	p.Triggered:Connect(function(player)
		spliceAt(edgeId, player)
	end)
	breaks[edgeId] = marker
	-- faísca rápida no momento do rompimento
	local spark = Instance.new("Sparkles")
	spark.SparkleColor = Color3.fromRGB(255, 200, 80)
	spark.Parent = marker
	Debris:AddItem(spark, 4)
end

function Net.dirtyEdge(edgeId: string)
	Net.graph:setEdgeState(edgeId, "dirty", 10.5 + math.random() * 3.5)
	refreshEdgeVisual(edgeId)
end

function Net.burnOnu(onuId: string)
	Net.graph:setNodeState(onuId, "failed")
end

-- ---------------------------------------------------------------------------
-- Interações nas casas, caixas, rack e almoxarifado
-- ---------------------------------------------------------------------------

local function describeSignal(dbm: number?): string
	if dbm == nil then
		return "sem luz (LOS)"
	end
	local quality = "bom"
	if dbm < Config.SignalDownDbm then
		quality = "muito baixo, a ONU não sincroniza"
	elseif dbm < Config.SignalUnstableDbm then
		quality = "baixo, conexão instável"
	elseif dbm < -25 then
		quality = "no limite"
	end
	return string.format("%.1f dBm (%s)", dbm, quality)
end

local function setupHousePrompts(h: any)
	local box = h.house.box
	local index = h.house.index
	local label = "Casa " .. index

	-- casa de cliente do concorrente: só olha
	local function mine(player: Player): any
		local P = providerOf(player)
		if not P then
			return nil
		end
		if h.contract == "active" and h.slot ~= P.slot then
			local other = Providers.slots[h.slot]
			Remotes.notify(player, label .. " é cliente do " .. (if other then other.name else "concorrente") .. ".", "error")
			return nil
		end
		return P
	end

	local measure = prompt(box, "Medir sinal", label, 0.5, 14)
	measure.KeyboardKeyCode = Enum.KeyCode.E
	measure.Triggered:Connect(function(player)
		if not holding(player, ToolNames.PowerMeter) then
			return
		end
		if h.contract ~= "active" or not h.onuId then
			Remotes.notify(player, label .. ": não tem drop instalado.", "info")
			return
		end
		if not mine(player) then
			return
		end
		local dbm = Net.graph:signalAt(h.onuId)
		local text = label .. ": " .. describeSignal(dbm) .. " · SN da ONU " .. (h.sn or "?")
		local node = Net.graph.nodes[h.onuId]
		if node and node.state == "failed" and dbm then
			text ..= " · a luz chega, mas a ONU não responde"
		end
		Remotes.notify(player, text, "measure")
	end)

	local swap = prompt(box, "Trocar ONU", label, 2, 14)
	swap.KeyboardKeyCode = Enum.KeyCode.R
	swap.Triggered:Connect(function(player)
		if h.contract ~= "active" then
			return
		end
		local P = mine(player)
		if not P or not P.game.useStock({ onu = 1 }, player) then
			return
		end
		local node = Net.graph.nodes[h.onuId]
		local wasBroken = node.state == "failed"
		Net.graph:setNodeState(h.onuId, "ok")
		h.sn = Net.newSn()
		if wasBroken then
			P.game.count("repairs")
			Net.addAlarm(P.slot, "Reparo", "ONU " .. index .. " trocada (SN " .. h.sn .. ")", "ok")
		end
		Remotes.notify(player, string.format("ONU nova instalada, SN %s. Autorize na OLT: interface gpon 0/1, ont modify %d <id> sn %s (ou ont add).", h.sn, Net.ponPortOf(h), h.sn), "measure")
		if not wasBroken then
			Remotes.notify(player, "A ONU antiga estava boa. O problema era outro.", "error")
		end
	end)

	local reconnect = prompt(box, "Refazer conector", label, 3, 14)
	reconnect.KeyboardKeyCode = Enum.KeyCode.F
	reconnect.Triggered:Connect(function(player)
		if h.contract ~= "active" or not holding(player, ToolNames.Fusion) then
			return
		end
		local P = mine(player)
		if not P or not P.game.useStock({ conector = 1 }, player) then
			return
		end
		local edge = Net.graph.edges[h.edgeId]
		if edge and edge.state == "dirty" then
			Net.graph:setEdgeState(h.edgeId, "ok")
			refreshEdgeVisual(h.edgeId)
			P.game.count("repairs")
			Net.addAlarm(P.slot, "Reparo", "Conector da casa " .. index .. " refeito", "ok")
			Remotes.notify(player, "Conector limpo e refeito. Meça o sinal de novo.", "success")
		else
			Remotes.notify(player, "Conector refeito, mas o sinal não mudou.", "error")
		end
	end)

	local install = prompt(box, "Instalar internet", label, 4, 14)
	install.KeyboardKeyCode = Enum.KeyCode.E
	install.Triggered:Connect(function(player)
		if h.contract == "active" or not holding(player, ToolNames.Fusion) then
			return
		end
		local P = providerOf(player)
		if not P then
			return
		end
		-- o morador só assina com o provedor que ele escolheu (o mais barato que ele aceita)
		if h.choice ~= P.slot then
			local other = h.choice and Providers.slots[h.choice]
			if other then
				Remotes.notify(player, string.format("%s: o morador prefere o %s (R$ %d por dia). Baixe o seu preço para disputar.", label, other.name, other.price), "error")
			else
				Remotes.notify(player, string.format("%s: o morador acha caro. Ele paga no máximo uns R$ %d por dia.", label, h.willing), "error")
			end
			return
		end
		if not P.game.useStock({ onu = 1, drop = 1 }, player) then
			return
		end
		connectHouse(h, P)
		P.game.earn(Config.InstallFee, "taxa de instalação", player)
		Remotes.notify(player, string.format("Drop e ONU instalados (SN %s), contrato de R$ %d por dia. Agora autorize na OLT: display ont autofind all, depois ont add %d sn-auth %s ... e o service-port.", h.sn, h.price, Net.ponPortOf(h), h.sn), "measure")
		P.game.count("installs")
		Net.addAlarm(P.slot, "Instalação", "Casa " .. index .. " ativada", "ok")
		if Net.onInstalled then
			Net.onInstalled(index)
		end
	end)

	h.prompts = { measure = measure, swap = swap, reconnect = reconnect, install = install }
end

local function refreshHousePrompts(h: any)
	local active = h.contract == "active"
	h.prompts.measure.Enabled = active
	h.prompts.swap.Enabled = active
	h.prompts.reconnect.Enabled = active
	h.prompts.install.Enabled = not active
	h.house.wantSign.Transparency = if active then 1 else 0
	local gui = h.house.wantSign:FindFirstChildOfClass("SurfaceGui")
	if gui then
		gui.Enabled = not active
		-- a placa diz quem o morador escolheu
		local label = gui:FindFirstChildOfClass("TextLabel")
		local P = h.choice and Providers.slots[h.choice]
		local text = if P then "Quero internet!\n" .. P.name else "Quero internet!"
		if label and label.Text ~= text then
			label.Text = text
		end
	end
	local post = h.house.model:FindFirstChild("WantSignPost")
	if post then
		post.Transparency = if active then 1 else 0
	end
end

local function setupBoxPrompts()
	local boxes = {
		{ part = world.boxes.splitter, id = "SPL", label = "Splitter primário" },
		{ part = world.boxes.ctoA, id = "CTO_A", label = "CTO A" },
		{ part = world.boxes.ctoB, id = "CTO_B", label = "CTO B" },
		{ part = world.boxes.splitter2, id = "SPL2", label = "Splitter Palmeiras" },
		{ part = world.boxes.ctoC, id = "CTO_C", label = "CTO C" },
		{ part = world.boxes.ctoD, id = "CTO_D", label = "CTO D" },
	}
	for _, b in boxes do
		local p = prompt(b.part, "Medir sinal na caixa", b.label, 0.5, 18)
		p.Triggered:Connect(function(player)
			if not holding(player, ToolNames.PowerMeter) then
				return
			end
			local P = providerOf(player)
			if not P then
				return
			end
			-- rede neutra: cada provedor mede a luz que vem da OLT dele
			local dbm = Net.graph:signalAt(b.id, P.slot)
			local text = if dbm then string.format("%s: %.1f dBm na saída (luz da OLT do %s)", b.label, dbm, P.name) else b.label .. ": sem luz da OLT do " .. P.name .. " (LOS)"
			Remotes.notify(player, text, "measure")
		end)
	end

	for slot, isp in world.isps do
		local shelf = prompt(isp.shelf, "Pegar ferramentas", "Almoxarifado", 0.5, 12)
		shelf.Triggered:Connect(function(player)
			local P = providerOf(player)
			if not P then
				return
			end
			if P.slot ~= slot then
				Remotes.notify(player, "Esse almoxarifado não é do seu provedor.", "error")
				return
			end
			if giveTools(player) == 0 then
				Remotes.notify(player, "O provedor ainda não tem ferramentas. Compre no terminal de compras, aqui no almoxarifado.", "error")
				return
			end
			local st = P.game.stock
			Remotes.notify(player, string.format("Ferramentas no inventário. Estoque: %d ONU, %d drop, %d emendas, %d conectores.", st.onu, st.drop, st.emenda, st.conector), "info")
		end)
	end
end

-- ---------------------------------------------------------------------------
-- Estado a cada segundo
-- ---------------------------------------------------------------------------

local function hourFactor(hour: number): number
	if hour < 11 then
		return 0.5
	elseif hour < 14 then
		return 0.9
	elseif hour < 17 then
		return 0.7
	elseif hour < 18 then
		return 1.2
	end
	return 1.8
end

local AlarmText = {
	los = "LOS (sem luz)",
	onu = "Dying gasp, ONU sem resposta",
	lowsignal = "Sinal muito baixo",
	power = "Sem energia",
	noroute = "Sem rota para a internet",
	dns = "Falha de resolução DNS",
	unauth = "ONT não autorizada na OLT",
	noservice = "ONT sem service-port",
	olt = "OLT fora do ar",
}

-- Provedor que o morador escolheria agora: o mais barato que ele aceita pagar.
-- Empate: melhor reputação; depois, o prédio mais antigo.
local function choiceOf(h: any): number?
	local best, bestPrice, bestRep = nil, math.huge, -1
	for _, P in Providers.list() do
		if P.game.bankrupt or P.price > h.willing then
			continue
		end
		local rep = P.game.reputation or 0
		if P.price < bestPrice or (P.price == bestPrice and rep > bestRep) then
			best, bestPrice, bestRep = P.slot, P.price, rep
		end
	end
	return best
end
Net.choiceOf = choiceOf

-- Desliga as casas de um provedor que fechou: viram casas sem contrato
function Net.dropProvider(slot: number)
	for _, h in Net.houses do
		if h.contract == "active" and h.slot == slot then
			disconnectHouse(h)
			h.contract = "cancelled"
			h.status = "nocontract"
			h.slot = nil
			h.price = nil
			h.downSeconds = 0
			h.cancelWarned = false
		end
	end
end

function Net.tick(dt: number)
	local results = Net.graph:computeOnus()
	local factor = hourFactor(game_.hour)
	local demand = { 0, 0 }
	for _, h in Net.houses do
		if h.contract == "active" and h.onuId and h.slot then
			local r = results[h.onuId]
			if r and (r.status == "online" or r.status == "unstable") then
				demand[h.slot] += 9 * factor * (0.85 + math.random() * 0.3)
			end
		else
			h.choice = choiceOf(h)
		end
	end
	local saturatedBy = {}
	for slot, d in Net.bySlot do
		d.demandMbps = demand[slot] or 0
		d.trafficMbps = math.min(d.demandMbps, d.upstreamMbps)
		d.utilization = if d.upstreamMbps > 0 then d.demandMbps / d.upstreamMbps else 0
		saturatedBy[slot] = d.utilization > 0.9
	end

	-- alarmes iguais no mesmo segundo viram um alarme só (ex.: DNS caiu para todo mundo)
	local pending: { { slot: number, text: string, severity: string, houses: { number } } } = {}
	local function queueAlarm(index: number, text: string, severity: string)
		local slot = Net.houses[index].slot or 1
		for _, p in pending do
			if p.slot == slot and p.text == text and p.severity == severity then
				table.insert(p.houses, index)
				return
			end
		end
		table.insert(pending, { slot = slot, text = text, severity = severity, houses = { index } })
	end

	for index, h in Net.houses do
		local old = h.status
		if h.contract ~= "active" or not h.onuId then
			h.status = "nocontract"
			h.signal = nil
			h.reason = ""
		else
			local r = results[h.onuId]
			h.status = r.status
			h.signal = r.signalDbm
			h.reason = r.reason
			if h.status == "online" and saturatedBy[h.slot] then
				h.status = "slow"
			end
		end

		-- LED da ONU na casa
		local led = h.house.led
		if h.status == "nocontract" then
			led.Color = Color3.fromRGB(70, 70, 70)
		elseif h.reason == "onu" then
			led.Color = Color3.fromRGB(20, 20, 20)
		else
			led.Color = Config.StatusColors[h.status] or Color3.new(1, 1, 1)
		end

		-- alarmes nas transições
		if old ~= h.status and old ~= "nocontract" and h.status ~= "nocontract" then
			if h.status == "offline" or h.status == "nodns" then
				queueAlarm(index, AlarmText[h.reason] or "Offline", "critical")
			elseif h.status == "unstable" then
				Net.addAlarm(h.slot, "ONU " .. index, string.format("Sinal baixo (%.1f dBm)", h.signal or 0), "warning")
			elseif h.status == "online" and (old == "offline" or old == "unstable" or old == "nodns") then
				queueAlarm(index, "Normalizada", "ok")
			end
		end

		-- chamados de clientes
		if h.contract == "active" and (h.status == "offline" or h.status == "nodns" or h.status == "unstable") then
			h.offlineSeconds += dt
			if not h.ticketOpen and h.offlineSeconds >= Config.TicketAfterSeconds then
				h.ticketOpen = true
				Net.addAlarm(h.slot, "Chamado", "Casa " .. index .. ": cliente reclamou", "warning")
			end
		else
			h.offlineSeconds = 0
			h.ticketOpen = false
		end
		-- sem internet de verdade (offline ou sem DNS): conta para o cancelamento
		if h.contract == "active" and (h.status == "offline" or h.status == "nodns") then
			h.downSeconds += dt
			local warnAt = Config.CancelAfterSeconds * Config.CancelWarnFraction
			if not h.cancelWarned and h.downSeconds >= warnAt then
				h.cancelWarned = true
				Net.addAlarm(h.slot, "Chamado", string.format("Casa %d está há %s sem internet. Com 1 dia o cliente cancela", index, Net.gameDuration(h.downSeconds)), "critical")
			end
		else
			h.downSeconds = 0
			h.cancelWarned = false
		end
		refreshHousePrompts(h)
	end

	for _, p in pending do
		if #p.houses == 1 then
			Net.addAlarm(p.slot, "ONU " .. p.houses[1], p.text, p.severity)
		else
			local list = {}
			for _, i in p.houses do
				table.insert(list, tostring(i))
			end
			Net.addAlarm(p.slot, "ONUs " .. table.concat(list, ","), p.text .. " (" .. #p.houses .. " clientes)", p.severity)
		end
	end
end

-- Segundos reais em horas de jogo, ex.: "6h00".
function Net.gameDuration(seconds: number): string
	local hours = seconds / Config.HourSeconds
	local h = math.floor(hours)
	return string.format("%dh%02d", h, math.floor((hours - h) * 60))
end

-- Clientes ativos de um provedor (sem slot: de todos)
function Net.activeCount(slot: number?): number
	local n = 0
	for _, h in Net.houses do
		if h.contract == "active" and (slot == nil or h.slot == slot) then
			n += 1
		end
	end
	return n
end

-- Soma das mensalidades do dia: cada cliente paga o preço do próprio contrato
function Net.feesOf(slot: number): number
	local total = 0
	for _, h in Net.houses do
		if h.contract == "active" and h.slot == slot then
			total += h.price or Config.DailyFeePerCustomer
		end
	end
	return total
end

-- Cliente desistiu: tira o drop e a ONU.
function Net.cancel(index: number)
	local h = Net.houses[index]
	if not h or h.contract ~= "active" then
		return
	end
	local slot = h.slot
	disconnectHouse(h)
	h.contract = "cancelled"
	h.status = "nocontract"
	h.downSeconds = 0
	h.cancelWarned = false
	h.slot = nil
	h.price = nil
	local P = slot and Providers.slots[slot]
	if P then
		P.game.count("cancellations")
	end
	Net.addAlarm(slot, "Cancelamento", "Casa " .. index .. " cancelou o plano", "critical")
end

-- Dados para as telas do NOC.
-- Dados para as telas do NOC de um provedor. Casas do concorrente aparecem como "rival".
function Net.snapshot(slot: number)
	local houses = {}
	for index, h in Net.houses do
		local rival = h.contract == "active" and h.slot ~= slot
		table.insert(houses, {
			index = index,
			x = h.house.position.X,
			z = h.house.position.Z,
			status = if rival then "nocontract" else h.status,
			signal = if rival then nil else h.signal,
			contract = if rival then "rival" else h.contract,
			ticket = not rival and h.ticketOpen,
			down = if rival then 0 else h.downSeconds,
			price = if rival then nil else h.price,
			choice = h.choice,
		})
	end
	local nodes = {}
	for id, n in Net.graph.nodes do
		if (n.kind == "olt" and n.provider == slot) or n.kind == "splitter" then
			table.insert(nodes, { id = if n.kind == "olt" then "OLT" else id, kind = n.kind, label = n.label, x = n.x, z = n.z })
		end
	end
	local edges = {}
	for id, e in Net.graph.edges do
		if e.kind ~= "core" and (e.provider == nil or e.provider == slot) then
			local a, b = Net.graph.nodes[e.from], Net.graph.nodes[e.to]
			if a and b then
				table.insert(edges, { id = id, kind = e.kind, state = e.state, x1 = a.x, z1 = a.z, x2 = b.x, z2 = b.z })
			end
		end
	end
	local d = Net.bySlot[slot]
	local alarms = {}
	for i = 1, math.min(12, #d.alarms) do
		alarms[i] = d.alarms[i]
	end
	return {
		houses = houses,
		nodes = nodes,
		edges = edges,
		alarms = alarms,
		trafficMbps = d.trafficMbps,
		demandMbps = d.demandMbps,
		capacityMbps = d.upstreamMbps,
		slot = slot,
	}
end

function Net.init(worldData: any, gameService: any)
	world = worldData
	game_ = gameService
	buildNetwork()
	for _, h in Net.houses do
		setupHousePrompts(h)
		refreshHousePrompts(h)
	end
	setupBoxPrompts()

	toolTemplates = {
		PowerMeter = makeTool(ToolNames.PowerMeter, Color3.fromRGB(240, 200, 40), "Mede o sinal óptico em dBm"),
		Fusion = makeTool(ToolNames.Fusion, Color3.fromRGB(40, 120, 220), "Emenda fibra, refaz conectores e instala drops"),
		Notebook = makeNotebook(),
	}
	-- quem nasce ou renasce recebe as ferramentas que o provedor já comprou
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function()
			task.wait(0.5)
			giveTools(player)
		end)
		if player.Character then
			giveTools(player)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return Net
