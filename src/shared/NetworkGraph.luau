-- (sem modo estrito)
-- Rede do provedor como grafo. Luau puro: não toca no mundo 3D.
--
-- Da OLT para baixo a rede é uma árvore (como num PON real): cada nó tem no
-- máximo uma aresta "pai". O estado de cada casa é calculado em camadas:
--   1. energia   2. física (caminho até a OLT)   3. sinal (dBm)
--   4. roteamento (upstream)   5. DNS   6. capacidade (feita no NetworkService)

local Config = require(script.Parent.Config)

export type NodeKind = "upstream" | "router" | "dns" | "olt" | "splitter" | "onu"
export type NodeState = "ok" | "failed"
export type EdgeState = "ok" | "broken" | "dirty"

export type Node = {
	id: string,
	kind: NodeKind,
	label: string,
	state: NodeState,
	powered: boolean,
	lossDb: number, -- perda de inserção (splitters)
	parentEdge: string?,
	x: number,
	z: number,
	authorized: boolean?, -- ONU: autorizada na OLT (ont add)
	service: boolean?, -- ONU: tem service-port válido
	provider: number?, -- núcleo (upstream/roteador/DNS/OLT) e ONU: prédio do provedor (1 ou 2)
	parentBy: { [number]: string }?, -- splitter da rua compartilhada: aresta pai de cada provedor
}

export type Edge = {
	id: string,
	kind: string, -- "trunk" | "distribution" | "drop" | "core"
	label: string,
	from: string, -- lado da OLT
	to: string, -- lado do cliente
	lossDb: number,
	extraLossDb: number,
	state: EdgeState,
}

export type OnuResult = {
	status: string, -- "online" | "unstable" | "offline" | "nodns"
	signalDbm: number?, -- nil = sem luz (LOS)
	reason: string, -- "ok" | "los" | "onu" | "power" | "lowsignal" | "unstable" | "noroute" | "dns"
}

local Graph = {}
Graph.__index = Graph

export type Graph = typeof(setmetatable(
	{} :: { nodes: { [string]: Node }, edges: { [string]: Edge }, version: number },
	Graph
))

function Graph.new(): Graph
	return setmetatable({ nodes = {}, edges = {}, version = 0 }, Graph)
end

function Graph.addNode(self: Graph, id: string, kind: NodeKind, props: { [string]: any }?): Node
	local p = props or {}
	local node: Node = {
		id = id,
		kind = kind,
		label = p.label or id,
		state = "ok",
		powered = true,
		lossDb = p.lossDb or 0,
		parentEdge = nil,
		x = p.x or 0,
		z = p.z or 0,
		provider = p.provider,
	}
	self.nodes[id] = node
	self.version += 1
	return node
end

function Graph.addEdge(self: Graph, id: string, fromId: string, toId: string, props: { [string]: any }?): Edge
	assert(self.nodes[fromId], "nó de origem não existe: " .. fromId)
	assert(self.nodes[toId], "nó de destino não existe: " .. toId)
	local p = props or {}
	-- Rede neutra: o tronco de cada provedor chega ao mesmo splitter da rua. Cada
	-- provedor enxerga a sua própria árvore (parentBy[provedor]).
	if p.provider == nil then
		assert(self.nodes[toId].parentEdge == nil, "nó já tem pai (a rede abaixo da OLT é uma árvore): " .. toId)
	end
	local edge: Edge = {
		id = id,
		kind = p.kind or "drop",
		label = p.label or id,
		from = fromId,
		to = toId,
		lossDb = p.lossDb or 0,
		extraLossDb = 0,
		state = "ok",
	}
	self.edges[id] = edge
	if p.provider ~= nil then
		local to = self.nodes[toId]
		to.parentBy = to.parentBy or {}
		to.parentBy[p.provider] = id
	else
		self.nodes[toId].parentEdge = id
	end
	edge.provider = p.provider
	self.version += 1
	return edge
end

-- Aresta pai de um nó, vista por um provedor
local function parentEdgeOf(node: Node, provider: number?): string?
	if node.parentBy then
		return if provider then node.parentBy[provider] else nil
	end
	return node.parentEdge
end
Graph.parentEdgeOf = parentEdgeOf

function Graph.removeEdge(self: Graph, id: string)
	local edge = self.edges[id]
	if not edge then
		return
	end
	local child = self.nodes[edge.to]
	if child and child.parentEdge == id then
		child.parentEdge = nil
	end
	if child and child.parentBy then
		for k, v in child.parentBy do
			if v == id then
				child.parentBy[k] = nil
			end
		end
	end
	self.edges[id] = nil
	self.version += 1
end

function Graph.setNodeState(self: Graph, id: string, state: NodeState)
	self.nodes[id].state = state
	self.version += 1
end

function Graph.setEdgeState(self: Graph, id: string, state: EdgeState, extraLossDb: number?)
	local e = self.edges[id]
	e.state = state
	e.extraLossDb = if state == "dirty" then (extraLossDb or 10) else 0
	self.version += 1
end

function Graph.parentOf(self: Graph, id: string, provider: number?): Node?
	local n = self.nodes[id]
	if not n then
		return nil
	end
	local pe = parentEdgeOf(n, provider)
	if not pe then
		return nil
	end
	return self.nodes[self.edges[pe].from]
end

-- Caminho físico de um nó até a OLT. Retorna (ok, perdaTotalDb, motivo).
-- A perda inclui as arestas e os splitters do caminho, inclusive o próprio nó se ele for splitter.
-- provider: prédio do provedor (1 ou 2). Sem ele, usa o provedor da própria ONU.
function Graph.traceToOlt(self: Graph, id: string, provider: number?): (boolean, number, string)
	local loss = 0
	local current = self.nodes[id]
	provider = provider or (current and current.provider)
	local guard = 0
	while current and current.kind ~= "olt" do
		guard += 1
		if guard > 64 then
			return false, loss, "loop"
		end
		if not current.powered then
			return false, loss, "power"
		end
		if current.kind == "splitter" then
			if current.state == "failed" then
				return false, loss, "los"
			end
			loss += current.lossDb
		end
		local pe = parentEdgeOf(current, provider)
		if not pe then
			return false, loss, "los"
		end
		local edge = self.edges[pe]
		if edge.state == "broken" then
			return false, loss, "los"
		end
		loss += edge.lossDb + edge.extraLossDb
		current = self.nodes[edge.from]
	end
	if not current then
		return false, loss, "los"
	end
	if not current.powered then
		return false, loss, "power"
	end
	if current.state == "failed" then
		return false, loss, "olt"
	end
	return true, loss, "ok"
end

-- Potência óptica (dBm) na saída de um nó, ou nil se não chega luz.
function Graph.signalAt(self: Graph, id: string, provider: number?): number?
	local ok, loss = self:traceToOlt(id, provider)
	if not ok then
		return nil
	end
	return Config.OltTxDbm - loss
end

function Graph.firstOfKind(self: Graph, kind: NodeKind): Node?
	for _, n in self.nodes do
		if n.kind == kind then
			return n
		end
	end
	return nil
end

-- Calcula o estado de cada ONU (camadas 1 a 5).
function Graph.computeOnus(self: Graph): { [string]: OnuResult }
	-- núcleo de cada provedor (roteador, upstream e DNS)
	local core: { [number]: { router: Node?, upstream: Node?, dns: Node? } } = {}
	for _, n in self.nodes do
		if n.kind == "router" or n.kind == "upstream" or n.kind == "dns" then
			local key = n.provider or 1
			core[key] = core[key] or {}
			core[key][n.kind] = n
		end
	end
	local function coreOk(provider: number?): (boolean, boolean)
		local c = core[provider or 1]
		if not c then
			return false, false
		end
		local router, upstream, dns = c.router, c.upstream, c.dns
		local hasRoute = router ~= nil and router.state == "ok" and router.powered and upstream ~= nil and upstream.state == "ok"
		local dnsOk = dns ~= nil and dns.state == "ok" and dns.powered
		return hasRoute, dnsOk
	end

	local results: { [string]: OnuResult } = {}
	for id, node in self.nodes do
		if node.kind ~= "onu" then
			continue
		end
		-- 1. energia na casa
		if not node.powered then
			results[id] = { status = "offline", signalDbm = nil, reason = "power" }
			continue
		end
		local hasRoute, dnsOk = coreOk(node.provider)
		-- 2. física
		local ok, loss, why = self:traceToOlt(id, node.provider)
		if not ok then
			results[id] = { status = "offline", signalDbm = nil, reason = why }
			continue
		end
		local dbm = Config.OltTxDbm - loss
		-- ONU queimada: chega luz, mas o equipamento não responde
		if node.state == "failed" then
			results[id] = { status = "offline", signalDbm = dbm, reason = "onu" }
			continue
		end
		-- 3. sinal
		if dbm < Config.SignalDownDbm then
			results[id] = { status = "offline", signalDbm = dbm, reason = "lowsignal" }
			continue
		end
		local unstable = dbm < Config.SignalUnstableDbm
		-- 3b. provisionamento na OLT
		if node.authorized == false then
			results[id] = { status = "offline", signalDbm = dbm, reason = "unauth" }
			continue
		end
		if node.service == false then
			results[id] = { status = "offline", signalDbm = dbm, reason = "noservice" }
			continue
		end
		-- 4. roteamento
		if not hasRoute then
			results[id] = { status = "offline", signalDbm = dbm, reason = "noroute" }
			continue
		end
		-- 5. DNS
		if not dnsOk then
			results[id] = { status = "nodns", signalDbm = dbm, reason = "dns" }
			continue
		end
		if unstable then
			results[id] = { status = "unstable", signalDbm = dbm, reason = "unstable" }
		else
			results[id] = { status = "online", signalDbm = dbm, reason = "ok" }
		end
	end
	return results
end

-- Lista de ONUs abaixo de um nó (útil para dizer "4 casas da CTO B").
function Graph.onusBelow(self: Graph, id: string, provider: number?): { string }
	local out = {}
	for onuId, node in self.nodes do
		if node.kind ~= "onu" then
			continue
		end
		local current: Node? = node
		local guard = 0
		while current and guard < 64 do
			guard += 1
			if current.id == id then
				table.insert(out, onuId)
				break
			end
			current = self:parentOf(current.id, provider or node.provider)
		end
	end
	table.sort(out)
	return out
end

return Graph
