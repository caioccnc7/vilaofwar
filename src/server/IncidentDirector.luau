-- Sorteia os incidentes do dia. Ele só muda o estado de nós e arestas do grafo:
-- os sintomas (casas offline, falas dos moradores, alarmes) saem da propagação.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Providers = require(script.Parent.Providers)

local Director = {}

local net: any

-- Rack de um provedor aberto sorteado entre os que aceitam aquele incidente
local function rackWhere(test: (any) -> boolean): any
	local ok = {}
	for _, P in Providers.list() do
		if P.rack and test(P.rack) then
			table.insert(ok, P.rack)
		end
	end
	return if #ok > 0 then ok[math.random(1, #ok)] else nil
end

local function dnsRack(): any
	return rackWhere(function(r)
		return r.canKillDns()
	end)
end

local function hwRack(): any
	return rackWhere(function(r)
		return r.canFailHardware()
	end)
end
local nextIn = 40 -- o primeiro incidente demora um pouco, para dar tempo de explorar

local function pickWeighted(options: { { weight: number, value: any } }): any
	local total = 0
	for _, o in options do
		total += o.weight
	end
	if total <= 0 then
		return nil
	end
	local r = math.random() * total
	for _, o in options do
		r -= o.weight
		if r <= 0 then
			return o.value
		end
	end
	return options[#options].value
end

local function candidates()
	local cuts, dirty, onus = {}, {}, {}
	for id, e in net.graph.edges do
		-- só quebra o que está no ar: cabo da rua ou tronco de um provedor aberto
		if e.state ~= "ok" or (e.provider and not Providers.slots[e.provider]) then
			continue
		end
		if e.kind == "trunk" then
			table.insert(cuts, { weight = 0.15, value = id })
		elseif e.kind == "distribution" then
			table.insert(cuts, { weight = 0.3, value = id })
		elseif e.kind == "drop" then
			table.insert(cuts, { weight = 0.25, value = id })
			table.insert(dirty, { weight = 1, value = id })
		end
	end
	-- ONU só queima depois de Config.Onu.MinAgeDays dias de uso (desde a instalação ou a última troca)
	for _, h in net.houses do
		local n = h.onuId and net.graph.nodes[h.onuId]
		if n and n.state == "ok" and net.onuCanFail(h) then
			table.insert(onus, { weight = 1, value = h.onuId })
		end
	end
	return cuts, dirty, onus
end

local function spawnIncident()
	local cuts, dirty, onus = candidates()
	local kind = pickWeighted({
		{ weight = if #cuts > 0 then 0.4 else 0, value = "cut" },
		{ weight = if #onus > 0 then 0.3 else 0, value = "onu" },
		{ weight = if #dirty > 0 then 0.3 else 0, value = "dirty" },
		{ weight = if dnsRack() then 0.15 else 0, value = "dns" },
		{ weight = if hwRack() then 0.06 else 0, value = "hw" },
	})
	if kind == "cut" then
		net.breakEdge(pickWeighted(cuts))
	elseif kind == "onu" then
		net.burnOnu(pickWeighted(onus))
	elseif kind == "dirty" then
		net.dirtyEdge(pickWeighted(dirty))
	elseif kind == "dns" then
		dnsRack().killUpstreamDns()
	elseif kind == "hw" then
		hwRack().failHardware()
	end
end

function Director.init(netService: any)
	net = netService
end

function Director.tick(dt: number)
	nextIn -= dt
	if nextIn > 0 then
		return
	end
	-- mais gente no servidor = incidentes mais frequentes
	local players = math.max(1, #Players:GetPlayers())
	local scale = 1 + 0.4 * (players - 1)
	nextIn = (Config.IncidentMinSeconds + math.random() * (Config.IncidentMaxSeconds - Config.IncidentMinSeconds)) / scale
	-- sem nenhum cliente ligado não há o que quebrar (começo do jogo)
	if net.activeCount() > 0 and net.activeIncidents() < Config.MaxActiveIncidents then
		spawnIncident()
	end
end

-- Para testar no Studio: força um incidente agora.
function Director.force(kind: string)
	local cuts, dirty, onus = candidates()
	if kind == "cut" and #cuts > 0 then
		net.breakEdge(pickWeighted(cuts))
	elseif kind == "onu" and #onus > 0 then
		net.burnOnu(pickWeighted(onus))
	elseif kind == "dirty" and #dirty > 0 then
		net.dirtyEdge(pickWeighted(dirty))
	elseif kind == "dns" then
		local r = dnsRack()
		if r then
			r.killUpstreamDns()
		end
	elseif kind == "hw" then
		local r = hwRack()
		if r then
			r.failHardware()
		end
	end
end

return Director
