-- Guerra dos provedores: ataque DDoS entre provedores, defesa e denúncia na Delegacia.
--
-- Regras aprovadas pelo Caio (12/11/2026):
--   - a força do ataque vem dos clientes online de quem ataca (cada ONU vira um bot);
--   - custa para quem ataca: o upload dos bots satura e a internet deles fica lenta;
--   - dois tipos: SYN flood (esgota a CPU do roteador) e volumétrico com
--     amplificação DNS (entope o link);
--   - duração de 1 a 8 horas de jogo (o cliente cancela com 12h sem internet);
--   - provedor no prazo de implantação não ataca nem é atacado;
--   - o ataque é anônimo, mas a vítima rastreia a origem no terminal (/tool torch no
--     roteador e whois no PC do NOC) ou pelo relatório da operadora, e denuncia na
--     Delegacia: multa e perda de estrelas para o atacante;
--   - a defesa usa comandos reais do RouterOS (tcp-syncookies, connection-limit,
--     detect-ddos com dst-limit, address-list com drop na raw, fechar a porta 53 na
--     WAN) e serviços da operadora (blackhole/RTBH e anti-DDoS pago por dia);
--   - equipamentos de guerra caros em R$ do jogo (Config.Ddos.Items).
--
-- O efeito na rede é calculado aqui a cada segundo e gravado em Net.ddos[slot]; o
-- NetworkService aplica (internet lenta, instável ou fora do ar).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local Providers = require(script.Parent.Providers)
local Game = require(script.Parent.GameService)
local Net = require(script.Parent.NetworkService)
local World = require(script.Parent.WorldBuilder)
local RouterCli = require(script.Parent.Cli.RouterCli)

local D = Config.Ddos
local S = D.Shield

local Ddos = {}
Ddos.attacks = {} :: { any } -- ativos e recentes, mais novo primeiro
local nextId = 1

local WAN_IP = RouterCli.Upstream.wanAddress -- IP público do roteador da vítima (o alvo)
local KIND_NAME = { syn = "SYN flood", dns = "Volumétrico (amplificação DNS)" }

-- servidores DNS abertos da internet usados como refletores (nomes fictícios)
local OPEN_RESOLVERS = {
	{ ip = "177.53.140.53", owner = "Hospedagem Serra Azul Ltda", asn = 52611 },
	{ ip = "189.112.40.10", owner = "Condomínio Digital Ipê", asn = 61904 },
	{ ip = "200.98.161.8", owner = "Rede Acadêmica do Vale", asn = 28202 },
	{ ip = "187.45.77.3", owner = "Lan House Pixel", asn = 53077 },
}

-- ---------------------------------------------------------------------------
-- Relógio e endereços
-- ---------------------------------------------------------------------------

local HOURS_PER_DAY = Config.DayEndHour - Config.DayStartHour

-- horas de jogo corridas desde o começo do servidor (a noite não conta)
local function now(): number
	return (Game.day - 1) * HOURS_PER_DAY + (Game.hour - Config.DayStartHour)
end
Ddos.now = now

local function hoursText(h: number): string
	h = math.max(0, h)
	local whole = math.floor(h)
	return string.format("%dh%02d", whole, math.floor((h - whole) * 60))
end
Ddos.hoursText = hoursText

-- cada provedor tem um bloco /24 público (o NAT dos clientes sai por ele)
function Ddos.prefix(slot: number): string
	return string.format("45.170.%d.", 80 + slot)
end
function Ddos.publicIp(slot: number, host: number?): string
	return Ddos.prefix(slot) .. tostring(host or 1)
end
function Ddos.asn(slot: number): number
	return 263800 + slot
end

local function slotOfIp(ip: string): number?
	local third = tonumber(string.match(ip, "^45%.170%.(%d+)%.%d+$") or "")
	if not third then
		return nil
	end
	local slot = third - 80
	return if slot >= 1 and slot <= Providers.SlotCount then slot else nil
end

-- ---------------------------------------------------------------------------
-- Estado de guerra de cada provedor (some quando o provedor fecha)
-- ---------------------------------------------------------------------------

local function sec(P: any): any
	if not P.sec then
		P.sec = { items = {}, antiDdos = false, cooldownUntil = -1e9, shieldUntil = -1e9, rtbhUntil = -1e9 }
		local s = P.sec
		-- mensalidade do anti-DDoS da operadora, cobrada no fechamento do dia
		table.insert(P.game.dailyCosts, function()
			if s.antiDdos then
				return D.AntiDdosDaily, "Segurança", "Anti-DDoS da operadora"
			end
			return 0, "Segurança", ""
		end)
	end
	return P.sec
end
Ddos.sec = sec

local function routerOf(P: any): any
	return P.rack and P.rack.activeOf("router")
end

local function shieldOf(P: any): (any, any)
	local router = routerOf(P)
	if not router then
		return nil, nil
	end
	return RouterCli.shield(router.cfg), router
end

-- bots = clientes online de quem ataca (prédio público não entra)
local function botsOf(P: any): number
	local n = 0
	for _, h in Net.houses do
		if h.contract == "active" and h.slot == P.slot and not h.house.public and (h.status == "online" or h.status == "slow") then
			n += 1
		end
	end
	return n
end
Ddos.bots = botsOf

local function clientsOf(P: any): number
	local n = 0
	for _, h in Net.houses do
		if h.contract == "active" and h.slot == P.slot then
			n += 1
		end
	end
	return n
end

-- roteadores da cidade com DNS aberto para a internet (viram refletores)
local function openResolvers(exceptSlot: number): { number }
	local out = {}
	for _, P in Providers.list() do
		if P.slot ~= exceptSlot then
			local sh = shieldOf(P)
			if sh and sh.openResolver then
				table.insert(out, P.slot)
			end
		end
	end
	return out
end

local function activeAgainst(slot: number): { any }
	local out = {}
	for _, a in Ddos.attacks do
		if a.status == "ativo" and a.victim == slot then
			table.insert(out, a)
		end
	end
	return out
end
Ddos.activeAgainst = activeAgainst

local function activeBy(slot: number): any
	for _, a in Ddos.attacks do
		if a.status == "ativo" and a.attacker == slot then
			return a
		end
	end
	return nil
end

-- força bruta do ataque, antes das defesas: kpps (SYN) ou Mbps (volumétrico)
local function rawForce(a: any, A: any): (number, number, { number })
	local bots = a.testBots or botsOf(A)
	local c2 = if sec(A).items.c2 then 2 else 1
	if a.kind == "syn" then
		return bots * D.SynKppsPerBot * c2, bots, {}
	end
	local resolvers = openResolvers(a.victim)
	local amp = D.BaseAmp + D.AmpPerOpenResolver * #resolvers
	return bots * D.UdpMbpsPerBot * amp * c2, bots, resolvers
end

-- ---------------------------------------------------------------------------
-- Fim do ataque
-- ---------------------------------------------------------------------------

local function notifyTeam(P: any?, text: string, kind: string)
	if P then
		Providers.notify(P, nil, text, kind)
	end
end

local REASON = {
	tempo = "acabou o tempo",
	mitigado = "a vítima mitigou e a botnet desistiu",
	rtbh = "a vítima pediu blackhole (RTBH) à operadora",
	bots = "os bots ficaram sem internet",
	parado = "o atacante parou",
	fechou = "um dos provedores fechou",
	teste = "fim do teste",
}

local function finish(a: any, reason: string)
	if a.status ~= "ativo" then
		return
	end
	local t = now()
	a.status = "encerrado"
	a.endReason = reason
	a.endedAt = t
	local A, V = Providers.slots[a.attacker], Providers.slots[a.victim]
	if A and A.id ~= a.attackerId then
		A = nil
	end
	if V and V.id ~= a.victimId then
		V = nil
	end
	local hitPct = if a.totalSeconds > 0 then math.floor(a.hitSeconds * 100 / a.totalSeconds + 0.5) else 0
	if A then
		sec(A).cooldownUntil = t + D.CooldownHours
		notifyTeam(A, string.format("Ataque contra o %s encerrado: %s. Ele ficou prejudicado %d%% do tempo. Próximo ataque em %dh de jogo.", a.victimName, REASON[reason] or reason, hitPct, D.CooldownHours), "info")
	end
	if V then
		local vs = sec(V)
		vs.shieldUntil = t + D.VictimShieldHours
		Net.addAlarm(V.slot, "DDoS", "Ataque encerrado (" .. (REASON[reason] or reason) .. ")", "ok")
		local text = string.format("O ataque DDoS acabou: %s. Seu provedor fica protegido de novos ataques por %dh de jogo.", REASON[reason] or reason, D.VictimShieldHours)
		-- quem segurou o ataque quase o tempo todo ganha reputação
		if a.totalSeconds >= Config.HourSeconds * 0.5 and hitPct < 25 and reason ~= "rtbh" then
			V.game.repAdjust = (V.game.repAdjust or 0) + D.RepBonus
			text ..= string.format(" Mitigação rápida: +%.1f estrela de reputação.", D.RepBonus)
		end
		if a.traced and not a.reported then
			text ..= " Você tem a prova: denuncie na Delegacia (casa 27)."
		end
		notifyTeam(V, text, "success")
	end
	-- guarda só os últimos ataques
	while #Ddos.attacks > 20 do
		table.remove(Ddos.attacks)
	end
end
Ddos.finish = finish

-- ---------------------------------------------------------------------------
-- Rastreio e prova
-- ---------------------------------------------------------------------------

local function markTraced(a: any, how: string)
	if a.traced then
		return
	end
	a.traced = true
	a.tracedBy = how
	local V = Providers.slots[a.victim]
	if V and V.id == a.victimId then
		Net.addAlarm(V.slot, "DDoS", "Origem identificada: AS" .. Ddos.asn(a.attacker) .. " (" .. a.attackerName .. ")", "warning")
		notifyTeam(V, string.format("Origem do ataque identificada (%s): %s, bloco %s0/24. Prova registrada. Denuncie na Delegacia (casa 27) em até %dh de jogo.", how, a.attackerName, Ddos.prefix(a.attacker), D.ReportHours), "alarm")
	end
end

-- relatório da operadora (vem junto com RTBH e com o anti-DDoS contratado)
local function operatorReport(V: any)
	for _, a in activeAgainst(V.slot) do
		markTraced(a, "relatório da operadora")
	end
end

-- whois no PC do NOC (LinuxShell). Devolve o texto do registro.
function Ddos.whois(P: any, ip: string?): string
	if not ip or ip == "" then
		return "Usage: whois <IP ou AS>   (ex.: whois 45.170.81.23)"
	end
	local header = "% Joint Whois - whois.lacnic.net\n%  This server accepts single ASN, IPv4 or IPv6 queries\n"
	local slot = slotOfIp(ip)
	if not slot then
		local asn = tonumber(string.match(ip, "^[Aa][Ss](%d+)$") or "")
		if asn and asn > 263800 and asn <= 263800 + Providers.SlotCount then
			slot = asn - 263800
		end
	end
	if slot then
		local O = Providers.slots[slot]
		local owner = if O then O.name else "(bloco sem uso no momento)"
		local lines = {
			header,
			string.format("inetnum:     %s0/24", Ddos.prefix(slot)),
			"status:      allocated",
			string.format("aut-num:     AS%d", Ddos.asn(slot)),
			"owner:       " .. owner,
			string.format("ownerid:     BR-VILA%d-LACNIC", slot),
			"responsible: NOC " .. owner,
			"country:     BR",
			string.format("abuse-c:     ABU%d", 80 + slot),
			"created:     20261110",
			"changed:     " .. string.format("202611%02d", math.clamp(Game.day, 1, 30)),
		}
		if P and O and slot ~= P.slot then
			local found = false
			for _, a in Ddos.attacks do
				local recent = a.status == "ativo" or (a.endedAt and now() - a.endedAt <= D.ReportHours)
				if a.victim == P.slot and a.victimId == P.id and a.attacker == slot and a.kind == "syn" and recent then
					markTraced(a, "whois do IP visto no torch")
					found = true
				end
			end
			if found then
				table.insert(lines, "")
				table.insert(lines, "% Os IPs do ataque saem deste bloco. Prova registrada: denuncie na Delegacia (casa 27).")
			else
				-- o bloco é de um refletor (DNS aberto), não de quem atacou
				for _, a in activeAgainst(P.slot) do
					if a.kind == "dns" and table.find(a.reflectors or {}, slot) then
						table.insert(lines, "")
						table.insert(lines, "% Este IP é o roteador de um provedor com DNS aberto (refletor). Ele não é o atacante:")
						table.insert(lines, "% quem forjou as consultas não aparece no torch. Peça o relatório à operadora (RTBH ou anti-DDoS).")
						break
					end
				end
			end
		end
		return table.concat(lines, "\n")
	end
	for _, r in OPEN_RESOLVERS do
		if r.ip == ip then
			return table.concat({
				header,
				"inetnum:     " .. string.match(ip, "^(%d+%.%d+%.%d+%.)") .. "0/24",
				"status:      reassigned",
				string.format("aut-num:     AS%d", r.asn),
				"owner:       " .. r.owner,
				"country:     BR",
				"",
				"% Servidor DNS aberto para a internet (usado como refletor). Ele não é o atacante:",
				"% quem forjou as consultas não aparece no torch. Peça o relatório à operadora (RTBH ou anti-DDoS).",
			}, "\n")
		end
	end
	if ip == "8.8.8.8" or ip == "8.8.4.4" then
		return header .. "\nNetRange:    8.8.8.0 - 8.8.8.255\nOrgName:     Google LLC\nCountry:     US"
	end
	return header .. "\n% No match for \"" .. ip .. "\""
end

-- ---------------------------------------------------------------------------
-- O que o roteador da vítima mostra (torch, conexões, CPU, address-list dinâmica)
-- ---------------------------------------------------------------------------

local function seeded(a: any, i: number, lo: number, hi: number): number
	return lo + ((a.id * 7919 + i * 104729) % (hi - lo + 1))
end

function Ddos.routerEnv(P: any): any
	local env = {}
	local attacks = activeAgainst(P.slot)
	env.cpuLoad = nil
	for _, a in attacks do
		if a.cpu then
			env.cpuLoad = math.max(env.cpuLoad or 0, a.cpu)
		end
	end
	env.torch = function(iface: string): { any }
		local d = Net.slot(P.slot)
		local flows = {}
		local normal = math.max(0, d.trafficMbps or 0) * 1e6
		if iface == "ether1" then
			-- tráfego normal dos clientes (respostas da internet para o IP do NAT)
			if normal > 0 then
				table.insert(flows, { proto = "tcp", src = "142.250.79.46", sport = 443, dst = WAN_IP, dport = 51744, rx = normal * 0.45, tx = normal * 0.03, rxp = math.floor(normal * 0.45 / 12000), txp = math.floor(normal * 0.03 / 600) })
				table.insert(flows, { proto = "udp", src = "142.250.218.14", sport = 443, dst = WAN_IP, dport = 60112, rx = normal * 0.35, tx = normal * 0.02, rxp = math.floor(normal * 0.35 / 10000), txp = math.floor(normal * 0.02 / 600) })
				table.insert(flows, { proto = "tcp", src = "128.116.123.3", sport = 443, dst = WAN_IP, dport = 49320, rx = normal * 0.2, tx = normal * 0.02, rxp = math.floor(normal * 0.2 / 10000), txp = math.floor(normal * 0.02 / 600) })
			end
			for _, a in attacks do
				if a.kind == "syn" then
					local pps = (a.kpps or 0) * 1000 / 8
					for i = 1, 8 do
						local src = Ddos.publicIp(a.attacker, seeded(a, i, 2, 250))
						table.insert(flows, { proto = "tcp", src = src, sport = seeded(a, i + 20, 1024, 65000), dst = WAN_IP, dport = if i % 3 == 0 then 80 else 443, rx = pps * 60 * 8, tx = 0, rxp = math.floor(pps), txp = 0 })
					end
				else
					local list = {}
					for _, slot in a.reflectors or {} do
						table.insert(list, Ddos.publicIp(slot, 1))
					end
					for _, r in OPEN_RESOLVERS do
						table.insert(list, r.ip)
					end
					local each = (a.mbps or 0) * 1e6 / #list
					for i, src in list do
						table.insert(flows, { proto = "udp", src = src, sport = 53, dst = WAN_IP, dport = seeded(a, i, 1024, 65000), rx = each, tx = 0, rxp = math.floor(each / (3000 * 8)), txp = 0 })
					end
				end
			end
		elseif iface == "ether2" and normal > 0 then
			table.insert(flows, { proto = "tcp", src = "10.100.0.21", sport = 51744, dst = "142.250.79.46", dport = 443, rx = normal * 0.03, tx = normal * 0.45, rxp = 0, txp = math.floor(normal * 0.45 / 12000) })
			table.insert(flows, { proto = "udp", src = "10.100.0.34", sport = 60112, dst = "142.250.218.14", dport = 443, rx = normal * 0.02, tx = normal * 0.35, rxp = 0, txp = math.floor(normal * 0.35 / 10000) })
		end
		table.sort(flows, function(x, y)
			return (x.rx or 0) > (y.rx or 0)
		end)
		return flows
	end
	env.connections = function(): any
		local count = 40 + clientsOf(P) * 35
		local sample = {
			{ proto = "tcp", src = "10.100.0.21:51744", dst = "142.250.79.46:443", state = "established", timeout = "23h59m" },
			{ proto = "udp", src = "10.100.0.34:60112", dst = "142.250.218.14:443", state = "", timeout = "2m58s" },
			{ proto = "udp", src = "10.100.0.1:41020", dst = "8.8.8.8:53", state = "", timeout = "9s" },
		}
		local sh = shieldOf(P)
		for _, a in attacks do
			if a.kind == "syn" then
				-- com tcp-syncookies o roteador não guarda o SYN pela metade
				local half = if sh and sh.syncookies then 0.1 else 1
				count += math.floor(math.min(250000, (a.kpps or 0) * 600 * half))
				for i = 1, 5 do
					table.insert(sample, 1, { flags = "C", proto = "tcp", src = Ddos.publicIp(a.attacker, seeded(a, i, 2, 250)) .. ":" .. seeded(a, i + 20, 1024, 65000), dst = WAN_IP .. ":443", state = "syn-received", timeout = "5s" })
				end
			end
		end
		return { count = count, sample = sample }
	end
	env.dynamicLists = function(): { any }
		local out = {}
		local sh = shieldOf(P)
		if not sh or not sh.blacklist then
			return out
		end
		local listName = next(sh.autoLists) or "ddos-attackers"
		for _, a in attacks do
			if a.kind == "syn" then
				for i = 1, 4 do
					table.insert(out, { list = listName, address = Ddos.publicIp(a.attacker, seeded(a, i, 2, 250)), timeout = "9m" .. (50 + i) .. "s" })
				end
			end
		end
		return out
	end
	return env
end

-- ---------------------------------------------------------------------------
-- Laço: efeito de cada ataque na rede (chamado pelo Main antes do Net.tick)
-- ---------------------------------------------------------------------------

local LEVEL_RANK = { slow = 1, unstable = 2, offline = 3 }

local function worse(a: string?, b: string?): string?
	if not a then
		return b
	end
	if not b then
		return a
	end
	return if LEVEL_RANK[b] > LEVEL_RANK[a] then b else a
end

local function effectOf(slot: number): any
	local e = Net.ddos[slot]
	if not e then
		e = { level = nil, extraMbps = 0, bot = false }
		Net.ddos[slot] = e
	end
	return e
end

function Ddos.tick(dt: number)
	table.clear(Net.ddos)
	local t = now()
	for _, a in Ddos.attacks do
		if a.status ~= "ativo" then
			continue
		end
		local A, V = Providers.slots[a.attacker], Providers.slots[a.victim]
		if not A or A.id ~= a.attackerId or not V or V.id ~= a.victimId then
			finish(a, "fechou")
			continue
		end
		if t >= a.endsAt then
			finish(a, "tempo")
			continue
		end
		local force, bots, resolvers = rawForce(a, A)
		if bots < 1 then
			finish(a, "bots")
			continue
		end
		a.bots = bots
		a.reflectors = resolvers
		local vs = sec(V)
		local cap = Net.slot(V.slot).upstreamMbps
		local sh, router = shieldOf(V)
		local level: string? = nil
		local extra = 0
		if a.kind == "syn" then
			local f = 1
			if sh then
				if sh.syncookies then
					f *= S.syncookies
				end
				if sh.synLimit then
					f *= S.synLimit
				end
				if sh.blacklist or RouterCli.blocks(router.cfg, sh, Ddos.publicIp(a.attacker, 77)) then
					f *= S.blacklist
				end
			end
			if vs.items.firewall then
				f *= S.firewall
			end
			if vs.antiDdos then
				f *= S.antiDdos
			end
			a.kpps = force
			local load = if router then force * f / D.RouterSynKpps else 0
			a.load = load
			a.cpu = math.clamp(math.floor(6 + 94 * math.min(load, 1)), 0, 100)
			if load >= 1 then
				level = "offline"
			elseif load >= 0.5 then
				level = "unstable"
			elseif load >= 0.25 then
				level = "slow"
			end
		else
			local mbps = force
			if not sec(A).items.amp and cap > 0 then
				mbps = math.min(mbps, cap * D.CapWithoutAmp)
			end
			a.mbps = mbps
			local f = 1
			if vs.items.scrubber then
				f *= S.scrubber
			end
			if vs.antiDdos then
				f *= S.antiDdos
			end
			local resid = mbps * f
			a.resid = resid
			a.cpu = nil
			if cap > 0 and router then
				extra = resid
				if resid > cap * D.DownAbove then
					level = "offline"
				elseif resid > cap * 0.2 then
					-- sem o filtro de DNS amplificado, o roteador também sofre com o lixo
					level = if sh and sh.ampDrop then "slow" else "unstable"
					a.cpu = if sh and sh.ampDrop then 35 else 85
				end
			end
			-- refletores gastam banda respondendo as consultas forjadas
			for _, r in resolvers do
				effectOf(r).extraMbps += D.ReflectorMbps
			end
		end
		a.level = level
		a.totalSeconds += dt
		if level then
			a.hitSeconds += dt
			a.mitigatedFor = 0
		else
			a.mitigatedFor += dt
		end
		-- primeiro sintoma: alarme no NOC da vítima
		if not a.alarmed and router then
			a.alarmed = true
			if a.kind == "syn" then
				Net.addAlarm(V.slot, "Roteador", "CPU do roteador alta: milhares de conexões TCP novas por segundo na ether1", "critical")
			else
				Net.addAlarm(V.slot, "Upstream", string.format("Pico de tráfego UDP na ether1 (%d Mbps de entrada)", math.floor(a.mbps or 0)), "critical")
			end
			notifyTeam(V, "ATAQUE DDoS contra o " .. V.name .. "! Abra o console do roteador e rode /tool torch interface=ether1. Passo a passo na wiki (J): Defesa contra DDoS.", "alarm")
		end
		local ve = effectOf(V.slot)
		ve.level = worse(ve.level, level)
		ve.extraMbps += extra
		effectOf(A.slot).bot = true
		if vs.antiDdos then
			operatorReport(V)
		end
		-- 100% mitigado por um tempo: a botnet desiste
		if a.mitigatedFor >= D.GiveUpMinutes / 60 * Config.HourSeconds then
			finish(a, "mitigado")
		end
	end
	-- blackhole (RTBH) em andamento: o IP público fica fora do ar
	for _, P in Providers.list() do
		if P.sec and t < P.sec.rtbhUntil then
			local e = effectOf(P.slot)
			e.level = "offline"
			e.rtbh = true
		end
	end
end

-- ---------------------------------------------------------------------------
-- Ações dos jogadores
-- ---------------------------------------------------------------------------

-- Pode atacar? (A = provedor de quem ataca, V = alvo). force = atalho de teste
function Ddos.check(A: any, V: any, force: boolean?): (boolean, string)
	if not A then
		return false, "Você precisa fazer parte de um provedor."
	end
	if not V or V.game.bankrupt then
		return false, "Esse provedor não existe mais."
	end
	if V == A then
		return false, "Não dá para atacar o próprio provedor."
	end
	if force then
		return true, ""
	end
	local t = now()
	if not A.game.pastDeadline() then
		return false, "Seu provedor ainda está no prazo de implantação: não pode atacar nem ser atacado."
	end
	if not V.game.pastDeadline() then
		return false, "O " .. V.name .. " ainda está no prazo de implantação e não pode ser atacado."
	end
	if activeBy(A.slot) then
		return false, "Você já tem um ataque em andamento."
	end
	if t < sec(A).cooldownUntil then
		return false, "A botnet está em recarga. Próximo ataque em " .. hoursText(sec(A).cooldownUntil - t) .. " de jogo."
	end
	if #activeAgainst(V.slot) > 0 then
		return false, "O " .. V.name .. " já está sob ataque."
	end
	if t < sec(V).shieldUntil then
		return false, "O " .. V.name .. " acabou de sofrer um ataque. Protegido por mais " .. hoursText(sec(V).shieldUntil - t) .. "."
	end
	if botsOf(A) < D.MinBots then
		return false, string.format("Precisa de pelo menos %d clientes online para formar a botnet (você tem %d).", D.MinBots, botsOf(A))
	end
	return true, ""
end

function Ddos.launch(A: any, V: any, kind: string, hours: number, player: Player?, force: boolean?, testBots: number?): any
	local ok, why = Ddos.check(A, V, force)
	if not ok then
		if player then
			Remotes.notify(player, why, "error")
		end
		return nil
	end
	if kind ~= "syn" and kind ~= "dns" then
		kind = "syn"
	end
	hours = math.clamp(math.floor(tonumber(hours) or D.DefaultHours), D.MinHours, D.MaxHours)
	local t = now()
	local a = {
		id = nextId,
		kind = kind,
		attacker = A.slot,
		attackerId = A.id,
		attackerName = A.name,
		victim = V.slot,
		victimId = V.id,
		victimName = V.name,
		startAt = t,
		endsAt = t + hours,
		hours = hours,
		status = "ativo",
		hitSeconds = 0,
		totalSeconds = 0,
		mitigatedFor = 0,
		traced = false,
		reported = false,
		testBots = testBots,
		reflectors = {},
	}
	nextId += 1
	table.insert(Ddos.attacks, 1, a)
	notifyTeam(A, string.format("Ataque %s contra o %s por %dh de jogo. Seus clientes viram bots: a internet deles fica lenta durante o ataque.", KIND_NAME[kind], V.name, hours), "alarm")
	return a
end

function Ddos.stop(player: Player)
	local P = Providers.of(player)
	if not P or P.owner ~= player then
		return
	end
	local a = activeBy(P.slot)
	if a then
		finish(a, "parado")
	end
end

function Ddos.buy(player: Player, key: string)
	local P = Providers.of(player)
	if not P then
		Remotes.notify(player, "Você precisa fazer parte de um provedor.", "error")
		return
	end
	for _, it in D.Items do
		if it.key == key then
			local s = sec(P)
			if s.items[key] then
				Remotes.notify(player, "O provedor já tem " .. it.name .. ".", "info")
				return
			end
			if P.game.spend(it.price, it.name, player, "Segurança") then
				s.items[key] = true
				notifyTeam(P, it.name .. " instalado. " .. it.info, "success")
			end
			return
		end
	end
end

function Ddos.setAntiDdos(player: Player, want: boolean)
	local P = Providers.of(player)
	if not P then
		return
	end
	local s = sec(P)
	if want == s.antiDdos then
		return
	end
	if want then
		if not P.game.spend(D.AntiDdosFee, "Ativação do anti-DDoS da operadora", player, "Segurança") then
			return
		end
		s.antiDdos = true
		notifyTeam(P, string.format("Anti-DDoS da operadora ativo: o tráfego de ataque é limpo antes de chegar no seu link. R$ %d por dia.", D.AntiDdosDaily), "success")
		operatorReport(P)
	else
		s.antiDdos = false
		notifyTeam(P, "Anti-DDoS da operadora cancelado.", "info")
	end
end

function Ddos.rtbh(player: Player)
	local P = Providers.of(player)
	if not P then
		return
	end
	local list = activeAgainst(P.slot)
	if #list == 0 then
		Remotes.notify(player, "Não há ataque em andamento contra o seu provedor. O blackhole derrubaria o seu IP à toa.", "error")
		return
	end
	operatorReport(P)
	for _, a in list do
		finish(a, "rtbh")
	end
	sec(P).rtbhUntil = now() + D.RtbhHours
	Net.addAlarm(P.slot, "Upstream", string.format("Blackhole (RTBH) na operadora para %s/32 por %dh", WAN_IP, D.RtbhHours), "warning")
	notifyTeam(P, string.format("Blackhole pedido: a operadora descarta tudo para %s. O ataque parou, mas seus clientes ficam sem internet por %dh de jogo.", WAN_IP, D.RtbhHours), "alarm")
end

-- Denúncia na Delegacia: precisa ter rastreado a origem
function Ddos.report(player: Player)
	local P = Providers.of(player)
	if not P then
		Remotes.notify(player, "Só um provedor pode registrar ocorrência de ataque à rede.", "error")
		return
	end
	local t = now()
	local done = 0
	local untraced = 0
	for _, a in Ddos.attacks do
		if a.victim ~= P.slot or a.victimId ~= P.id or a.reported then
			continue
		end
		local recent = a.status == "ativo" or (a.endedAt and t - a.endedAt <= D.ReportHours)
		if not recent then
			continue
		end
		if not a.traced then
			untraced += 1
			continue
		end
		a.reported = true
		done += 1
		local A = Providers.slots[a.attacker]
		if A and A.id == a.attackerId then
			A.game.money -= D.Fine
			A.game.record("despesa", "Multas", "Multa por ataque DDoS (Delegacia)", D.Fine)
			A.game.repAdjust = (A.game.repAdjust or 0) - D.RepPenalty
			A.game.publish()
			notifyTeam(A, string.format("A Delegacia multou o seu provedor em R$ %d pelo ataque DDoS contra o %s. Reputação -%.0f estrela.", D.Fine, a.victimName, D.RepPenalty), "alarm")
		end
		P.game.earn(D.Indemnity, "Indenização por ataque DDoS", player, "Indenização")
		Remotes.notify(nil, string.format("Delegacia: o %s foi multado por um ataque DDoS contra o %s.", a.attackerName, a.victimName), "info")
	end
	if done == 0 then
		if untraced > 0 then
			Remotes.notify(player, "O delegado precisa de prova: descubra a origem (torch no roteador e whois no PC do NOC, ou o relatório da operadora).", "error")
		else
			Remotes.notify(player, string.format("Nenhum ataque recente contra o seu provedor para denunciar (prazo de %dh de jogo).", D.ReportHours), "info")
		end
	end
end

-- ---------------------------------------------------------------------------
-- Tela Guerra (tecla K)
-- ---------------------------------------------------------------------------

local SYMPTOM = { syn = "CPU do roteador alta, conexões TCP novas aos milhares", dns = "Link da operadora cheio de tráfego UDP" }
local LEVEL_TEXT = { slow = "internet lenta", unstable = "internet instável", offline = "internet fora do ar" }

function Ddos.state(player: Player): any
	local P = Providers.of(player)
	local t = now()
	local out: any = {
		clock = Game.clockText(),
		day = Game.day,
		minHours = D.MinHours,
		maxHours = D.MaxHours,
		defaultHours = D.DefaultHours,
		minBots = D.MinBots,
		items = {},
		targets = {},
		incoming = {},
		history = {},
		fine = D.Fine,
		antiDdosFee = D.AntiDdosFee,
		antiDdosDaily = D.AntiDdosDaily,
		rtbhHours = D.RtbhHours,
	}
	for _, it in D.Items do
		table.insert(out.items, { key = it.key, side = it.side, name = it.name, price = it.price, info = it.info, owned = P ~= nil and sec(P).items[it.key] == true })
	end
	if not P then
		return out
	end
	local s = sec(P)
	out.provider = P.name
	out.owner = P.owner == player
	out.money = math.floor(P.game.money)
	out.pastDeadline = P.game.pastDeadline()
	out.bots = botsOf(P)
	out.cooldown = if t < s.cooldownUntil then hoursText(s.cooldownUntil - t) else nil
	out.antiDdos = s.antiDdos
	out.rtbh = if t < s.rtbhUntil then hoursText(s.rtbhUntil - t) else nil
	-- força estimada
	local c2 = if s.items.c2 then 2 else 1
	out.synKpps = out.bots * D.SynKppsPerBot * c2
	out.synLoad = math.floor(out.synKpps * 100 / D.RouterSynKpps)
	local resolvers = openResolvers(-1)
	out.dnsMbps = out.bots * D.UdpMbpsPerBot * (D.BaseAmp + D.AmpPerOpenResolver * #resolvers) * c2
	out.hasAmp = s.items.amp == true
	-- alvos
	for _, V in Providers.list() do
		if V == P then
			continue
		end
		local ok, why = Ddos.check(P, V)
		local status = "disponível"
		if not V.game.pastDeadline() then
			status = "em implantação"
		elseif #activeAgainst(V.slot) > 0 then
			status = "sob ataque"
		elseif t < sec(V).shieldUntil then
			status = "protegido por " .. hoursText(sec(V).shieldUntil - t)
		end
		table.insert(out.targets, { slot = V.slot, name = V.name, status = status, can = ok, why = why, link = Net.slot(V.slot).upstreamMbps, clients = clientsOf(V) })
	end
	-- ataque meu em andamento
	local mine = activeBy(P.slot)
	if mine then
		out.outgoing = {
			victim = mine.victimName,
			kind = KIND_NAME[mine.kind],
			left = hoursText(mine.endsAt - t),
			effect = if mine.level then LEVEL_TEXT[mine.level] else "sem efeito (a vítima está segurando)",
			bots = mine.bots or 0,
			hit = if mine.totalSeconds > 0 then math.floor(mine.hitSeconds * 100 / mine.totalSeconds) else 0,
		}
	end
	-- ataques contra mim (anônimos até rastrear)
	for _, a in activeAgainst(P.slot) do
		table.insert(out.incoming, {
			symptom = SYMPTOM[a.kind],
			effect = if a.level then LEVEL_TEXT[a.level] else "contido pelas suas defesas",
			origin = if a.traced then a.attackerName .. " (AS" .. Ddos.asn(a.attacker) .. ")" else "desconhecida",
			running = hoursText(t - a.startAt),
		})
	end
	-- defesas do roteador
	local sh = shieldOf(P)
	out.router = sh ~= nil
	if sh then
		out.shield = { syncookies = sh.syncookies, synLimit = sh.synLimit, blacklist = sh.blacklist, ampDrop = sh.ampDrop, closedDns = not sh.openResolver }
	end
	-- histórico (ataques feitos e sofridos)
	for _, a in Ddos.attacks do
		if #out.history >= 8 then
			break
		end
		local recent = a.status == "ativo" or (a.endedAt and t - a.endedAt <= D.ReportHours)
		if a.victim == P.slot and a.victimId == P.id then
			local line = string.format("Dia %d: ataque sofrido de %dh, origem %s", math.floor(a.startAt / HOURS_PER_DAY) + 1, a.hours, if a.traced then a.attackerName else "desconhecida")
			if a.reported then
				line ..= " · denunciado"
			elseif a.traced and recent then
				line ..= " · DENUNCIE na Delegacia (casa 27)"
			end
			table.insert(out.history, line)
		elseif a.attacker == P.slot and a.attackerId == P.id then
			table.insert(out.history, string.format("Dia %d: você atacou o %s (%s)%s", math.floor(a.startAt / HOURS_PER_DAY) + 1, a.victimName, KIND_NAME[a.kind], if a.reported then " · você foi denunciado" else ""))
		end
	end
	return out
end

-- ---------------------------------------------------------------------------
-- Início
-- ---------------------------------------------------------------------------

-- balcão de ocorrências na frente da Delegacia (casa do órgão "policia")
local function buildDesk()
	for _, h in Net.houses do
		if h.house.org == "policia" then
			local pos = h.house.doorPoint + Vector3.new(6, 0, 0)
			local desk = World.part({ Name = "BalcaoOcorrencias", Size = Vector3.new(4, 3.2, 1.2), CFrame = CFrame.new(pos + Vector3.new(0, 1.6, 0)), Color = Color3.fromRGB(40, 70, 140), Parent = h.house.model })
			World.textOn(desk, Enum.NormalId.Front, "OCORRÊNCIAS\nCrimes de internet", Color3.new(1, 1, 1))
			World.textOn(desk, Enum.NormalId.Back, "OCORRÊNCIAS\nCrimes de internet", Color3.new(1, 1, 1))
			local pp = Instance.new("ProximityPrompt")
			pp.ActionText = "Denunciar ataque DDoS"
			pp.ObjectText = "Delegacia de Polícia"
			pp.HoldDuration = 0.5
			pp.MaxActivationDistance = 12
			pp.RequiresLineOfSight = false
			pp.Parent = desk
			pp.Triggered:Connect(function(player)
				Ddos.report(player)
			end)
			return
		end
	end
end

function Ddos.start(loja: any)
	Net.ddos = Net.ddos or {}
	buildDesk()
	Remotes.GuerraState.OnServerInvoke = function(player)
		local st = Ddos.state(player)
		if loja then
			st.robux = loja.info(player)
		end
		return st
	end
	Remotes.GuerraAction.OnServerEvent:Connect(function(player, action, a, b, c)
		if typeof(action) ~= "string" then
			return
		end
		if action == "attack" then
			local A = Providers.of(player)
			if not A or A.owner ~= player then
				Remotes.notify(player, "Só o dono do provedor decide um ataque.", "error")
				return
			end
			local V = typeof(a) == "number" and Providers.slots[a] or nil
			Ddos.launch(A, V, if b == "dns" then "dns" else "syn", tonumber(c) or D.DefaultHours, player)
		elseif action == "stop" then
			Ddos.stop(player)
		elseif action == "buy" and typeof(a) == "string" then
			Ddos.buy(player, a)
		elseif action == "antiddos" then
			Ddos.setAntiDdos(player, a == true)
		elseif action == "rtbh" then
			Ddos.rtbh(player)
		elseif action == "robux" and loja and typeof(a) == "string" then
			loja.prompt(player, a)
		end
	end)
end

-- o reajuste de reputação volta ao normal aos poucos (chamado no fechamento do dia)
function Ddos.newDay()
	for _, P in Providers.list() do
		local r = P.game.repAdjust or 0
		if r > 0 then
			P.game.repAdjust = math.max(0, r - D.RepDecayPerDay)
		elseif r < 0 then
			P.game.repAdjust = math.min(0, r + D.RepDecayPerDay)
		end
	end
end

return Ddos
