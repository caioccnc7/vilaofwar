-- Console do roteador de borda. A sintaxe imita a de roteadores usados em provedores
-- brasileiros (menus com "/", comandos print/add/set/remove e parâmetros nome=valor),
-- para o jogador treinar comandos de verdade.

local RouterCli = {}

RouterCli.Model = "CCR2004-16G-2S+"
RouterCli.Brand = "MikroTik"
RouterCli.OsName = "RouterOS"
RouterCli.Version = "7.16 (stable)"

-- Dados do contrato com o upstream (ficam na ficha colada no rack)
RouterCli.Upstream = {
	wanAddress = "100.64.10.2",
	wanPrefix = 30,
	gateway = "100.64.10.1",
	lanAddress = "10.100.0.1",
	lanPrefix = 22,
	upstreamDns = "200.200.200.53",
}

RouterCli.PublicDns = { ["8.8.8.8"] = true, ["8.8.4.4"] = true, ["1.1.1.1"] = true, ["1.0.0.1"] = true, ["9.9.9.9"] = true }

-- ---------------------------------------------------------------------------
-- Configuração
-- ---------------------------------------------------------------------------

function RouterCli.factoryConfig()
	return {
		identity = RouterCli.Brand,
		addresses = {},
		routes = {},
		dns = { servers = {}, allowRemote = false },
		nat = {},
		filter = {},
		raw = {},
		addressList = {},
		settings = { tcpSyncookies = false },
	}
end

function RouterCli.productionConfig()
	local U = RouterCli.Upstream
	return {
		identity = "BORDA-VILA",
		addresses = {
			{ address = U.wanAddress .. "/" .. U.wanPrefix, interface = "ether1", comment = "upstream" },
			{ address = U.lanAddress .. "/" .. U.lanPrefix, interface = "ether2", comment = "clientes" },
		},
		routes = { { dst = "0.0.0.0/0", gateway = U.gateway } },
		dns = { servers = { U.upstreamDns }, allowRemote = true },
		nat = { { chain = "srcnat", action = "masquerade", outInterface = "ether1" } },
		filter = {},
		raw = {},
		addressList = {},
		settings = { tcpSyncookies = false },
	}
end

-- Configuração antiga (antes do firewall) ganha as tabelas que faltam.
local function fw(cfg: any): any
	cfg.filter = cfg.filter or {}
	cfg.raw = cfg.raw or {}
	cfg.addressList = cfg.addressList or {}
	cfg.settings = cfg.settings or { tcpSyncookies = false }
	return cfg
end
RouterCli.ensureFirewall = fw

-- ---------------------------------------------------------------------------
-- IP
-- ---------------------------------------------------------------------------

local function parseIp(s: string): number?
	local a, b, c, d = string.match(s, "^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	if not a then
		return nil
	end
	local parts = { tonumber(a), tonumber(b), tonumber(c), tonumber(d) }
	for _, p in parts do
		if p == nil or p > 255 then
			return nil
		end
	end
	return ((parts[1] * 256 + parts[2]) * 256 + parts[3]) * 256 + parts[4]
end

local function ipToString(n: number): string
	local d = n % 256
	n = (n - d) / 256
	local c = n % 256
	n = (n - c) / 256
	local b = n % 256
	local a = (n - b) / 256
	return string.format("%d.%d.%d.%d", a, b, c, d)
end

local function parseCidr(s: string): (number?, number?)
	local ip, prefix = string.match(s, "^([%d%.]+)/(%d+)$")
	if not ip then
		local only = parseIp(s)
		if only then
			return only, 32
		end
		return nil, nil
	end
	local n = parseIp(ip)
	local p = tonumber(prefix)
	if not n or not p or p > 32 then
		return nil, nil
	end
	return n, p
end

local function network(n: number, prefix: number): number
	local size = 2 ^ (32 - prefix)
	return n - (n % size)
end

local function sameNet(a: number, b: number, prefix: number): boolean
	return network(a, prefix) == network(b, prefix)
end

-- o IP está dentro do endereço ou rede (ex.: 45.170.81.9 em 45.170.81.0/24)?
local function inCidr(ip: string, cidr: string?): boolean
	if not cidr then
		return false
	end
	local n = parseIp(ip)
	local net, prefix = parseCidr(cidr)
	if not n or not net or not prefix then
		return false
	end
	return sameNet(n, net, prefix)
end
RouterCli.inCidr = inCidr

-- ---------------------------------------------------------------------------
-- Firewall: o que as regras fazem na rede do jogo
-- Regras ficam como { kv = { chain=, action=, protocol=, ... }, disabled = bool }.
-- ---------------------------------------------------------------------------

local function on(r: any): boolean
	return not r.disabled
end

local function listHas(cfg: any, name: string, ip: string): boolean
	for _, e in cfg.addressList do
		if on(e) and e.kv.list == name and inCidr(ip, e.kv.address) then
			return true
		end
	end
	return false
end

-- A regra vale para pacotes vindos deste IP? (src-address e src-address-list, com "!")
local function matchesSrc(cfg: any, r: any, ip: string): boolean
	local sal, sa = r.kv["src-address-list"], r.kv["src-address"]
	if sal then
		local neg = string.sub(sal, 1, 1) == "!"
		local hit = listHas(cfg, if neg then string.sub(sal, 2) else sal, ip)
		if hit == neg then
			return false
		end
	end
	if sa then
		local neg = string.sub(sa, 1, 1) == "!"
		local hit = inCidr(ip, if neg then string.sub(sa, 2) else sa)
		if hit == neg then
			return false
		end
	end
	return true
end

-- regras que pegam o tráfego que chega no roteador (raw prerouting e filter input)
local function inboundRules(cfg: any): { any }
	local out = {}
	for _, r in cfg.raw do
		if on(r) and (r.kv.chain == "prerouting" or r.kv.chain == nil) then
			table.insert(out, r)
		end
	end
	for _, r in cfg.filter do
		if on(r) and r.kv.chain == "input" then
			table.insert(out, r)
		end
	end
	return out
end

local function isDrop(r: any): boolean
	return r.kv.action == "drop" or r.kv.action == "reject"
end

-- regra que derruba respostas de DNS (udp src-port=53 chegando pela WAN)
local function dropsDnsFrom(cfg: any, server: string): boolean
	for _, r in inboundRules(cfg) do
		local kv = r.kv
		if isDrop(r) and kv.protocol == "udp" and kv["src-port"] == "53" and (kv["in-interface"] == nil or kv["in-interface"] == "ether1") and matchesSrc(cfg, r, server) then
			return true
		end
	end
	return false
end

-- regra que fecha a porta 53 do roteador: só na WAN (certo) ou em todas (derruba o DNS dos clientes)
local function dnsPortRules(cfg: any): (boolean, boolean)
	local wanClosed, lanClosed = false, false
	for _, r in inboundRules(cfg) do
		local kv = r.kv
		if isDrop(r) and kv.protocol == "udp" and kv["dst-port"] == "53" and kv["src-address-list"] == nil and kv["src-address"] == nil then
			if kv["in-interface"] == "ether1" then
				wanClosed = true
			elseif kv["in-interface"] == nil or kv["in-interface"] == "ether2" then
				lanClosed = true
				if kv["in-interface"] == nil then
					wanClosed = true
				end
			end
		end
	end
	return wanClosed, lanClosed
end

-- O que o firewall do roteador faz contra DDoS. Usado pelo DdosService.
function RouterCli.shield(cfg: any): any
	fw(cfg)
	local s = {
		syncookies = cfg.settings.tcpSyncookies == true,
		synLimit = false,
		blacklist = false,
		ampDrop = false,
		openResolver = false,
		dropLists = {},
		dropNets = {},
	}
	local jumps, autoList, detectReturn = {}, {}, {}
	for _, r in cfg.filter do
		local kv = r.kv
		if on(r) and kv.action == "jump" and kv["jump-target"] and (kv.chain == "forward" or kv.chain == "input") then
			jumps[kv["jump-target"]] = true
		end
	end
	for _, r in cfg.filter do
		local kv = r.kv
		if not on(r) then
			continue
		end
		local flags = kv["tcp-flags"] or ""
		local synOnly = string.find(flags, "syn", 1, true) ~= nil and string.find(flags, "!syn", 1, true) == nil
		-- limite direto: protocol=tcp tcp-flags=syn connection-limit=100,32 action=drop
		if isDrop(r) and (kv.chain == "input" or kv.chain == "forward") and kv.protocol == "tcp" and (kv["connection-limit"] or (synOnly and kv["dst-limit"])) then
			s.synLimit = true
		end
		-- cadeia detect-ddos: quem passa do dst-limit cai nas regras de baixo
		if kv["dst-limit"] and kv.action == "return" and kv.chain and jumps[kv.chain] then
			detectReturn[kv.chain] = true
		end
		if kv.action == "add-src-to-address-list" and kv["address-list"] then
			autoList[kv["address-list"]] = kv.chain or ""
		end
	end
	local function collectDrops(r: any)
		local kv = r.kv
		if not on(r) or not isDrop(r) then
			return
		end
		local sal, sa = kv["src-address-list"], kv["src-address"]
		if sal and string.sub(sal, 1, 1) ~= "!" then
			s.dropLists[sal] = true
		end
		if sa and string.sub(sa, 1, 1) ~= "!" then
			table.insert(s.dropNets, sa)
		end
		if kv.protocol == "udp" and kv["src-port"] == "53" then
			s.ampDrop = true
		end
	end
	for _, r in cfg.raw do
		if r.kv.chain == "prerouting" or r.kv.chain == nil then
			collectDrops(r)
		end
	end
	for _, r in cfg.filter do
		if r.kv.chain == "input" or r.kv.chain == "forward" then
			collectDrops(r)
		end
	end
	s.autoLists = {}
	for name, chain in autoList do
		if s.dropLists[name] then
			s.blacklist = true
			s.autoLists[name] = true
			if detectReturn[chain] then
				s.synLimit = true
			end
		end
	end
	local wanClosed = dnsPortRules(cfg)
	s.openResolver = cfg.dns.allowRemote and not wanClosed
	return s
end

-- O firewall descarta pacotes vindos deste IP? (address-list manual ou src-address no drop)
function RouterCli.blocks(cfg: any, sh: any, ip: string): boolean
	for name in sh.dropLists do
		if listHas(cfg, name, ip) then
			return true
		end
	end
	for _, net in sh.dropNets do
		if inCidr(ip, net) then
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Avaliação: o que a configuração atual permite na rede do jogo
-- ---------------------------------------------------------------------------

export type Eval = {
	wanOk: boolean,
	routeOk: boolean,
	lanOk: boolean,
	natOk: boolean,
	dnsOk: boolean,
	problems: { string },
}

function RouterCli.evaluate(cfg: any, ifaces: { [string]: boolean }, deadDns: { [string]: boolean }): Eval
	fw(cfg)
	local U = RouterCli.Upstream
	local wanIp, gw, lanIp = parseIp(U.wanAddress), parseIp(U.gateway), parseIp(U.lanAddress)
	local problems = {}

	local wanOk, lanOk = false, false
	for _, a in cfg.addresses do
		local n, p = parseCidr(a.address)
		if n and p and not a.disabled then
			if a.interface == "ether1" and n == wanIp and p == U.wanPrefix then
				wanOk = true
			elseif a.interface == "ether2" and n == lanIp and p >= 16 and p <= 24 then
				lanOk = true
			end
		end
	end
	if not ifaces.ether1 then
		wanOk = false
		table.insert(problems, "ether1 sem link (cabo do upstream)")
	elseif not wanOk then
		table.insert(problems, "sem IP do upstream na ether1")
	end
	if not ifaces.ether2 then
		lanOk = false
		table.insert(problems, "ether2 sem link (cabo da OLT)")
	elseif not lanOk then
		table.insert(problems, "sem gateway dos clientes na ether2")
	end

	local routeOk = false
	for _, r in cfg.routes do
		if (r.dst == "0.0.0.0/0" or r.dst == nil) and parseIp(r.gateway or "") == gw then
			routeOk = true
		end
	end
	if not routeOk then
		table.insert(problems, "sem rota padrão")
	end
	routeOk = routeOk and wanOk

	local natOk = false
	for _, n in cfg.nat do
		if n.chain == "srcnat" and n.action == "masquerade" and (n.outInterface == nil or n.outInterface == "ether1") and not n.disabled then
			natOk = true
		end
	end
	if not natOk then
		table.insert(problems, "sem NAT para os clientes")
	end

	local anyAlive, blockedByFw = false, false
	for _, sv in cfg.dns.servers do
		if (RouterCli.PublicDns[sv] or sv == U.upstreamDns) and not deadDns[sv] then
			if dropsDnsFrom(cfg, sv) then
				blockedByFw = true
			else
				anyAlive = true
			end
		end
	end
	local _, lanClosed = dnsPortRules(cfg)
	local dnsOk = cfg.dns.allowRemote and anyAlive and routeOk and not lanClosed
	if not cfg.dns.allowRemote then
		table.insert(problems, "DNS não aceita consultas dos clientes")
	elseif lanClosed then
		table.insert(problems, "firewall fechou a porta 53 também para os clientes (use in-interface=ether1)")
	elseif not anyAlive and blockedByFw then
		table.insert(problems, "firewall descartando as respostas do DNS (udp src-port=53): ponha os servidores DNS numa exceção")
	elseif not anyAlive then
		table.insert(problems, "nenhum servidor DNS respondendo")
	end

	return { wanOk = wanOk, routeOk = routeOk, lanOk = lanOk, natOk = natOk, dnsOk = dnsOk, problems = problems }
end

-- ---------------------------------------------------------------------------
-- Parser
-- ---------------------------------------------------------------------------

local Complete = require(script.Parent.Complete)

local function tokenize(line: string): { string }
	local tokens = {}
	local i, n = 1, #line
	while i <= n do
		local c = string.sub(line, i, i)
		if c == " " or c == "\t" then
			i += 1
		else
			local buf = ""
			while i <= n do
				c = string.sub(line, i, i)
				if c == " " or c == "\t" then
					break
				elseif c == "\"" then
					local close = string.find(line, "\"", i + 1, true) or (n + 1)
					buf ..= string.sub(line, i + 1, close - 1)
					i = close + 1
				else
					buf ..= c
					i += 1
				end
			end
			table.insert(tokens, buf)
		end
	end
	return tokens
end

local function pad(s: string, w: number): string
	s = tostring(s)
	if #s >= w then
		return s .. " "
	end
	return s .. string.rep(" ", w - #s)
end

-- interfaces físicas do CCR2004-16G-2S+
RouterCli.Interfaces = {}
for i = 1, 16 do
	table.insert(RouterCli.Interfaces, "ether" .. i)
end
table.insert(RouterCli.Interfaces, "sfp-sfpplus1")
table.insert(RouterCli.Interfaces, "sfp-sfpplus2")
local IFACES = RouterCli.Interfaces
local YESNO = { "yes", "no" }

-- ---------------------------------------------------------------------------
-- Árvore de menus. Cada verbo lista seus parâmetros (nome=valor): texto livre ou lista de valores.
-- ---------------------------------------------------------------------------

local PRINT = { desc = "Print values of item properties", params = { detail = "", where = "" } }
local ACTIONS = { "accept", "drop", "reject", "jump", "return", "add-src-to-address-list", "add-dst-to-address-list", "log", "passthrough" }
local FILTER_PARAMS = {
	chain = { "input", "forward", "output", "detect-ddos" },
	action = ACTIONS,
	protocol = { "tcp", "udp", "icmp" },
	["src-address"] = "Source address",
	["dst-address"] = "Destination address",
	["src-port"] = "Source port",
	["dst-port"] = "Destination port",
	["in-interface"] = IFACES,
	["out-interface"] = IFACES,
	["tcp-flags"] = { "syn", "!syn", "syn,!ack", "ack", "fin", "rst" },
	["connection-state"] = { "new", "established", "related", "invalid", "established,related" },
	["connection-limit"] = "Connections per address (ex.: 100,32)",
	["dst-limit"] = "Rate limit (ex.: 32,32,src-and-dst-addresses/10s)",
	["jump-target"] = "Chain to jump to",
	["address-list"] = "Address list to add to",
	["address-list-timeout"] = "Time to keep the address in the list",
	["src-address-list"] = "Source address list (! = not)",
	["dst-address-list"] = "Destination address list (! = not)",
	comment = "Short description",
	disabled = YESNO,
}
local RAW_PARAMS = {
	chain = { "prerouting", "output" },
	action = { "drop", "accept", "notrack", "jump", "return" },
	protocol = { "tcp", "udp", "icmp" },
	["src-address"] = "Source address",
	["dst-address"] = "Destination address",
	["src-port"] = "Source port",
	["dst-port"] = "Destination port",
	["in-interface"] = IFACES,
	["src-address-list"] = "Source address list (! = not)",
	["dst-address-list"] = "Destination address list (! = not)",
	comment = "Short description",
	disabled = YESNO,
}
local EXPORT = { desc = "Print or save an export script", params = { file = "Name of the file" } }
local function REMOVE(): any
	return { desc = "Remove item", params = { numbers = "List of item numbers" }, positional = "numbers" }
end
local function TOGGLE(desc: string): any
	return { desc = desc, params = { numbers = "List of item numbers" }, positional = "numbers" }
end

local Menus: { [string]: any } = {
	[""] = {
		sub = { interface = "Interface configuration", ip = "IP options", log = "System logs", system = "System information and utilities", tool = "Diagnostic tools" },
		verbs = {
			export = EXPORT,
			ping = { desc = "Send ICMP Echo packets", params = { address = "Destination address", count = "Number of packets", interval = "Time between packets" }, positional = "address" },
			quit = { desc = "Quit console", params = {} },
		},
	},
	["interface"] = { sub = { ethernet = "Ethernet interfaces" }, verbs = { print = PRINT, export = EXPORT } },
	["interface ethernet"] = { sub = {}, verbs = { print = PRINT, export = EXPORT } },
	["ip"] = {
		sub = { address = "Address management", arp = "ARP entries management", dns = "DNS settings", firewall = "Firewall", route = "Route management", settings = "IP settings" },
		verbs = { export = EXPORT },
	},
	["ip address"] = {
		sub = {},
		verbs = {
			print = PRINT,
			export = EXPORT,
			add = { desc = "Create a new item", params = { address = "Local IP address/prefix", interface = IFACES, comment = "Short description", disabled = YESNO, network = "Network prefix" } },
			remove = REMOVE(),
			disable = TOGGLE("Disable items"),
			enable = TOGGLE("Enable items"),
		},
	},
	["ip route"] = {
		sub = {},
		verbs = {
			print = PRINT,
			export = EXPORT,
			add = { desc = "Create a new item", params = { ["dst-address"] = "Destination prefix", gateway = "Gateway address", distance = "Route distance", comment = "Short description" } },
			remove = REMOVE(),
		},
	},
	["ip dns"] = {
		sub = { cache = "DNS cache" },
		verbs = {
			print = PRINT,
			export = EXPORT,
			set = { desc = "Change item properties", params = { servers = "DNS server addresses (comma separated)", ["allow-remote-requests"] = YESNO, ["cache-size"] = "Cache size in KiB" } },
		},
	},
	["ip dns cache"] = { sub = {}, verbs = { print = PRINT, flush = { desc = "Flush DNS cache", params = {} } } },
	["ip firewall"] = {
		sub = { nat = "Network address translation", filter = "Firewall filters", raw = "Raw (antes do connection tracking)", ["address-list"] = "Address lists", connection = "Connection tracking" },
		verbs = { export = EXPORT },
	},
	["ip firewall filter"] = {
		sub = {},
		verbs = {
			print = PRINT,
			export = EXPORT,
			add = { desc = "Create a new item", params = FILTER_PARAMS },
			remove = REMOVE(),
			disable = TOGGLE("Disable items"),
			enable = TOGGLE("Enable items"),
		},
	},
	["ip firewall raw"] = {
		sub = {},
		verbs = {
			print = PRINT,
			export = EXPORT,
			add = { desc = "Create a new item", params = RAW_PARAMS },
			remove = REMOVE(),
			disable = TOGGLE("Disable items"),
			enable = TOGGLE("Enable items"),
		},
	},
	["ip firewall address-list"] = {
		sub = {},
		verbs = {
			print = PRINT,
			export = EXPORT,
			add = { desc = "Create a new item", params = { list = "Name of the address list", address = "IP address or network", timeout = "Time to keep the entry", comment = "Short description" } },
			remove = REMOVE(),
			disable = TOGGLE("Disable items"),
			enable = TOGGLE("Enable items"),
		},
	},
	["ip firewall connection"] = { sub = {}, verbs = { print = { desc = "Print tracked connections", params = { ["count-only"] = "", where = "" } } } },
	["ip settings"] = {
		sub = {},
		verbs = {
			print = PRINT,
			export = EXPORT,
			set = { desc = "Change item properties", params = { ["tcp-syncookies"] = YESNO, ["rp-filter"] = { "no", "strict", "loose" } } },
		},
	},
	["ip firewall nat"] = {
		sub = {},
		verbs = {
			print = PRINT,
			export = EXPORT,
			add = {
				desc = "Create a new item",
				params = {
					chain = { "srcnat", "dstnat" },
					action = { "masquerade", "src-nat", "dst-nat", "accept", "redirect", "netmap" },
					["out-interface"] = IFACES,
					["in-interface"] = IFACES,
					["src-address"] = "Source address",
					["dst-address"] = "Destination address",
					comment = "Short description",
				},
			},
			remove = REMOVE(),
			disable = TOGGLE("Disable items"),
			enable = TOGGLE("Enable items"),
		},
	},
	["ip arp"] = { sub = {}, verbs = { print = PRINT } },
	["log"] = { sub = {}, verbs = { print = PRINT } },
	["system"] = {
		sub = { clock = "System clock", identity = "System identity", resource = "System resources", routerboard = "RouterBOARD information" },
		verbs = { reboot = { desc = "Reboot the system", params = {} }, export = EXPORT },
	},
	["system identity"] = { sub = {}, verbs = { print = PRINT, export = EXPORT, set = { desc = "Change item properties", params = { name = "System name" } } } },
	["system resource"] = { sub = {}, verbs = { print = PRINT } },
	["system clock"] = { sub = {}, verbs = { print = PRINT } },
	["system routerboard"] = { sub = {}, verbs = { print = PRINT } },
	["tool"] = {
		sub = {},
		verbs = {
			traceroute = { desc = "Traceroute", params = { address = "Destination address", count = "Number of probes" }, positional = "address" },
			torch = { desc = "Realtime traffic monitor", params = { interface = IFACES, ["src-address"] = "Source address", ["dst-address"] = "Destination address", port = "Port", ["ip-protocol"] = { "tcp", "udp", "icmp", "any" }, duration = "Time to run" } },
		},
	},
}

-- comandos da raiz que também valem dentro de qualquer menu
local GLOBALS = { ping = true, quit = true }

local function menuOf(path: { string }): any
	return Menus[table.concat(path, " ")]
end

local function sortedKeys(t: { [string]: any }): { string }
	local out = {}
	for k in t do
		table.insert(out, k)
	end
	table.sort(out)
	return out
end

-- nomes possíveis num menu: submenus, verbos e comandos globais
local function menuNames(path: { string }): { { w: string, d: string, kind: string } }
	local m = menuOf(path)
	local out = {}
	if not m then
		return out
	end
	for _, k in sortedKeys(m.sub) do
		table.insert(out, { w = k, d = m.sub[k], kind = "menu" })
	end
	for _, k in sortedKeys(m.verbs) do
		table.insert(out, { w = k, d = m.verbs[k].desc, kind = "verb" })
	end
	if #path > 0 then
		for _, k in { "ping", "quit" } do
			if not m.verbs[k] then
				table.insert(out, { w = k, d = Menus[""].verbs[k].desc, kind = "global" })
			end
		end
	end
	return out
end

local function pick(list: { any }, tok: string): (any, string)
	local hits = {}
	for _, e in list do
		if e.w == tok then
			return e, "ok"
		end
		if Complete.startsWith(e.w, tok) then
			table.insert(hits, e)
		end
	end
	if #hits == 1 then
		return hits[1], "ok"
	end
	return nil, if #hits > 1 then "ambiguous" else "none"
end

local function verbSpec(path: { string }, verb: string, global: boolean): any
	if global then
		return Menus[""].verbs[verb]
	end
	return menuOf(path).verbs[verb]
end

local function paramList(spec: any): { any }
	local out = {}
	for _, k in sortedKeys(spec.params) do
		local v = spec.params[k]
		table.insert(out, { w = k, d = if type(v) == "table" then table.concat(v, " | ") else v })
	end
	return out
end

export type Parsed = {
	path: { string },
	verb: string?,
	global: boolean,
	kv: { [string]: string },
	loose: { string },
	err: string?,
}

-- Entende a linha como o RouterOS: caminho de menus, verbo e parâmetros nome=valor.
-- Aceita abreviações sem ambiguidade (/ip ad pr = /ip address print).
local function parse(session: any, line: string): Parsed
	local tokens = tokenize(line)
	local raw = Complete.tokens(line)
	local path: { string } = table.clone(session.path)
	local res: Parsed = { path = path, verb = nil, global = false, kv = {}, loose = {}, err = nil }
	if tokens[1] and string.sub(tokens[1], 1, 1) == "/" then
		table.clear(path)
		tokens[1] = string.sub(tokens[1], 2)
		if tokens[1] == "" then
			table.remove(tokens, 1)
			table.remove(raw, 1)
		end
	end
	local offset = #raw - #tokens
	for i, t in tokens do
		local col = Complete.column(line, i + offset)
		if res.verb == nil then
			if t == ".." then
				table.remove(path)
			elseif string.find(t, "=", 1, true) then
				res.err = string.format("expected command name (line 1 column %d)", col)
				return res
			else
				local e, how = pick(menuNames(path), string.lower(t))
				if not e then
					if how == "ambiguous" then
						res.err = string.format("ambiguous value of command name %s (line 1 column %d)", t, col)
					else
						res.err = string.format("bad command name %s (line 1 column %d)", t, col)
					end
					return res
				end
				if e.kind == "menu" then
					table.insert(path, e.w)
				else
					res.verb = e.w
					res.global = e.kind == "global"
				end
			end
		else
			local spec = verbSpec(path, res.verb :: string, res.global)
			local k, v = string.match(t, "^([%w%-]+)=(.*)$")
			if k then
				local e, how = pick(paramList(spec), string.lower(k))
				if not e then
					res.err = string.format("%s (line 1 column %d)", if how == "ambiguous" then "ambiguous value of argument name " .. k else "expected end of command", col)
					return res
				end
				res.kv[e.w] = v
			else
				table.insert(res.loose, t)
			end
		end
	end
	return res
end

-- ---------------------------------------------------------------------------
-- TAB e "?"
-- ---------------------------------------------------------------------------

local function listing(entries: { any }, withDesc: boolean): string
	if withDesc then
		local out = {}
		for _, e in entries do
			table.insert(out, e.w .. " -- " .. (e.d or ""))
		end
		return table.concat(out, "\n")
	end
	local words = {}
	for _, e in entries do
		table.insert(words, e.w)
	end
	return Complete.columns(words)
end

-- o que pode vir na posição do cursor: { entradas, parcial, tipo }
local function contextAt(cfg: any, session: any, line: string): (any, string, { any }, boolean)
	local partial = ""
	if line ~= "" and string.sub(line, -1) ~= " " then
		partial = string.match(line, "(%S+)$") or ""
	end
	local before = string.sub(line, 1, #line - #partial)
	local slash = false
	local p = parse(session, before)
	if p.err then
		return nil, partial, {}, false
	end
	local entries = {}
	if p.verb == nil then
		local path = p.path
		local word = partial
		if string.sub(word, 1, 1) == "/" and string.gsub(before, "%s", "") == "" then
			slash = true
			path = {}
			word = string.sub(word, 2)
		end
		for _, e in menuNames(path) do
			if Complete.startsWith(e.w, string.lower(word)) then
				table.insert(entries, { w = e.w, d = e.d, insert = (if slash then "/" else "") .. e.w, space = true })
			end
		end
		if word == "" and #path > 0 then
			table.insert(entries, 1, { w = "..", d = "go up to " .. (if #path > 1 then path[#path - 1] else "root"), insert = "..", space = true })
		end
		return p, word, entries, slash
	end
	local spec = verbSpec(p.path, p.verb :: string, p.global)
	local k, v = string.match(partial, "^([%w%-]+)=(.*)$")
	if k then
		local values = spec.params[k]
		if type(values) == "table" then
			for _, val in values do
				if Complete.startsWith(val, v :: string) then
					table.insert(entries, { w = val, d = "", insert = k .. "=" .. val, space = true })
				end
			end
		end
		return p, partial, entries, false
	end
	for _, e in paramList(spec) do
		if Complete.startsWith(e.w, string.lower(partial)) and not p.kv[e.w] then
			table.insert(entries, { w = e.w, d = e.d, insert = e.w .. "=", space = false })
		end
	end
	if spec.positional == "numbers" and partial == "" then
		local where = table.concat(p.path, " ")
		fw(cfg)
		local list = if where == "ip address" then cfg.addresses elseif where == "ip route" then cfg.routes elseif where == "ip firewall filter" then cfg.filter elseif where == "ip firewall raw" then cfg.raw elseif where == "ip firewall address-list" then cfg.addressList else cfg.nat
		for i = 1, #list do
			table.insert(entries, { w = tostring(i - 1), d = "item number", insert = tostring(i - 1), space = true })
		end
	end
	return p, partial, entries, false
end

function RouterCli.complete(cfg: any, session: any, line: string): any
	local p, partial, entries = contextAt(cfg, session, line)
	if not p or #entries == 0 then
		return {}
	end
	local base = string.sub(line, 1, #line - #partial)
	if #entries == 1 then
		return { line = base .. entries[1].insert .. (if entries[1].space then " " else "") }
	end
	local inserts = {}
	for _, e in entries do
		table.insert(inserts, e.insert)
	end
	local cp = Complete.commonPrefix(inserts)
	if #cp > #partial then
		return { line = base .. cp }
	end
	return { show = listing(entries, false) }
end

local function questionHelp(cfg: any, session: any, line: string): string
	local body = string.sub(line, 1, #line - 1)
	local p, _, entries = contextAt(cfg, session, body)
	if not p then
		local q = parse(session, body)
		return q.err or "syntax error"
	end
	if p.verb == nil then
		local key = table.concat(p.path, " ")
		local head = if key == "" then "" else "/" .. key .. "\n"
		return head .. listing(entries, true)
	end
	local spec = verbSpec(p.path, p.verb :: string, p.global)
	return spec.desc .. "\n" .. listing(entries, true) .. "\n<cr> -- run the command"
end

-- ---------------------------------------------------------------------------
-- Saídas
-- ---------------------------------------------------------------------------

local function removeByNumber(list: { any }, kv: { [string]: string }, loose: { string }): string
	local num = tonumber(kv.numbers or loose[1] or "")
	if num == nil then
		return "expected numbers (ex.: remove 0)"
	end
	if not list[num + 1] then
		return "no such item"
	end
	table.remove(list, num + 1)
	return ""
end

local function setDisabled(list: { any }, kv: { [string]: string }, loose: { string }, value: boolean): string
	local num = tonumber(kv.numbers or loose[1] or "")
	if num == nil then
		return "expected numbers (ex.: disable 0)"
	end
	local item = list[num + 1]
	if not item then
		return "no such item"
	end
	item.disabled = value
	return ""
end

local IFACE_COMMENT = { ether1 = "upstream", ether2 = "OLT / clientes" }

local function interfacePrint(ifaces: { [string]: boolean }, ethernet: boolean): string
	local lines
	if ethernet then
		lines = { "Flags: R - RUNNING", "Columns: NAME, MTU, MAC-ADDRESS, ARP, SWITCH", " #   NAME            MTU  MAC-ADDRESS        ARP" }
	else
		lines = { "Flags: R - RUNNING", "Columns: NAME, TYPE, ACTUAL-MTU, L2MTU, MAX-L2MTU, MAC-ADDRESS", " #    NAME            TYPE   ACTUAL-MTU  L2MTU  MAC-ADDRESS        COMMENT" }
	end
	for i, name in IFACES do
		local flag = if ifaces[name] then "R" else " "
		local mac = string.format("48:A9:8A:3C:1E:%02X", i)
		if ethernet then
			table.insert(lines, string.format("%2d %s %s %s %s enabled", i - 1, flag, pad(name, 15), pad("1500", 4), pad(mac, 18)))
		else
			table.insert(lines, string.format("%2d %s  %s ether  %s 1568   %s %s", i - 1, flag, pad(name, 15), pad("1500", 11), pad(mac, 18), IFACE_COMMENT[name] or ""))
		end
	end
	return table.concat(lines, "\n")
end

-- ordem em que os parâmetros de uma regra aparecem no print e no export
local RULE_ORDER = { "chain", "action", "protocol", "src-address", "src-address-list", "dst-address", "dst-address-list", "src-port", "dst-port", "in-interface", "out-interface", "tcp-flags", "connection-state", "connection-limit", "dst-limit", "jump-target", "address-list", "address-list-timeout", "comment" }
local ADDR_ORDER = { "list", "address", "timeout", "comment" }

local function ruleText(kv: { [string]: string }, order: { string }): string
	local parts = {}
	for _, k in order do
		local v = kv[k]
		if v and k ~= "comment" then
			table.insert(parts, k .. "=" .. (if string.find(v, " ", 1, true) then "\"" .. v .. "\"" else v))
		end
	end
	if kv.comment then
		table.insert(parts, "comment=\"" .. kv.comment .. "\"")
	end
	return table.concat(parts, " ")
end

-- print de regras no formato do RouterOS (comentário em cima, parâmetros embaixo)
local function rulesPrint(list: { any }, order: { string }): string
	local out = { "Flags: X - disabled, I - invalid; D - dynamic" }
	for i, r in list do
		if r.kv.comment then
			table.insert(out, string.format("%2d %s  ;;; %s", i - 1, if r.disabled then "X" else " ", r.kv.comment))
			table.insert(out, "      " .. ruleText(r.kv, order):gsub(" ?comment=\"[^\"]*\"", ""))
		else
			table.insert(out, string.format("%2d %s   %s", i - 1, if r.disabled then "X" else " ", ruleText(r.kv, order)))
		end
	end
	return table.concat(out, "\n")
end

local function addRule(list: { any }, kv: { [string]: string }, needChain: boolean): string
	if needChain and not kv.chain then
		return "failure: value of chain must be specified"
	end
	if kv.action == nil then
		kv.action = "accept"
	end
	if (kv.action == "add-src-to-address-list" or kv.action == "add-dst-to-address-list") and not kv["address-list"] then
		return "failure: address-list must be specified"
	end
	if kv.action == "jump" and not kv["jump-target"] then
		return "failure: jump-target must be specified"
	end
	if (kv["src-port"] or kv["dst-port"]) and kv.protocol ~= "tcp" and kv.protocol ~= "udp" then
		return "failure: port can be specified only for tcp or udp protocols"
	end
	local disabled = kv.disabled == "yes"
	kv.disabled = nil
	table.insert(list, { kv = kv, disabled = disabled })
	return ""
end

local function fmtBps(bps: number): string
	if bps >= 1e9 then
		return string.format("%.1fGbps", bps / 1e9)
	elseif bps >= 1e6 then
		return string.format("%.1fMbps", bps / 1e6)
	elseif bps >= 1e3 then
		return string.format("%.1fkbps", bps / 1e3)
	end
	return string.format("%dbps", math.floor(bps))
end

-- /tool torch: tráfego ao vivo da interface, agrupado por origem e porta
local function torch(kv: { [string]: string }, env: any): string
	local iface = kv.interface
	if not iface then
		return "failure: value of interface must be specified (ex.: /tool torch interface=ether1)"
	end
	if not table.find(IFACES, iface) then
		return "input does not match any value of interface"
	end
	local flows = {}
	if env.ifaces[iface] then
		for _, f in (env.torch and env.torch(iface)) or {} do
			if kv["ip-protocol"] and kv["ip-protocol"] ~= "any" and f.proto ~= kv["ip-protocol"] then
				continue
			end
			if kv.port and tostring(f.sport) ~= kv.port and tostring(f.dport) ~= kv.port then
				continue
			end
			if kv["src-address"] and not inCidr(f.src, kv["src-address"]) then
				continue
			end
			table.insert(flows, f)
		end
	end
	local out = {
		"Columns: ETH-PROTOCOL, IP-PROTOCOL, SRC-ADDRESS, SRC-PORT, DST-ADDRESS, DST-PORT, TX, RX, TX-PACKETS, RX-PACKETS",
		"ETH-PROTOCOL  IP-PROTOCOL  SRC-ADDRESS      SRC-PORT  DST-ADDRESS      DST-PORT  TX        RX          TX-PACKETS  RX-PACKETS",
	}
	local tx, rx, txp, rxp = 0, 0, 0, 0
	for _, f in flows do
		tx += f.tx or 0
		rx += f.rx or 0
		txp += f.txp or 0
		rxp += f.rxp or 0
		table.insert(out, string.format("ip            %s %s %s %s %s %s %s %s %s", pad(f.proto, 12), pad(f.src, 16), pad(tostring(f.sport), 9), pad(f.dst, 16), pad(tostring(f.dport), 9), pad(fmtBps(f.tx or 0), 9), pad(fmtBps(f.rx or 0), 11), pad(tostring(f.txp or 0), 11), tostring(f.rxp or 0)))
	end
	table.insert(out, string.format("%s%s %s %s %d", pad("", 82), pad(fmtBps(tx), 9), pad(fmtBps(rx), 11), pad(tostring(txp), 11), rxp))
	table.insert(out, "-- [Q quit|D dump|C-z pause] (amostra de 1 segundo)")
	return table.concat(out, "\n")
end

local function exportConfig(cfg: any, env: any): string
	local out = {
		string.format("# %s by %s %s", env.dateTime or "2026-11-10 08:00:00", RouterCli.OsName, RouterCli.Version),
		"# software id = V7KQ-3XRM",
		"#",
		"# model = " .. RouterCli.Model,
		"# serial number = HG4091Q8ZPX",
	}
	table.insert(out, "/ip address")
	for _, a in cfg.addresses do
		table.insert(out, string.format("add address=%s interface=%s network=%s%s", a.address, a.interface, a.network or "", if a.disabled then " disabled=yes" else ""))
	end
	table.insert(out, "/ip dns")
	table.insert(out, string.format("set allow-remote-requests=%s servers=%s", if cfg.dns.allowRemote then "yes" else "no", table.concat(cfg.dns.servers, ",")))
	table.insert(out, "/ip firewall nat")
	for _, n in cfg.nat do
		table.insert(out, string.format("add action=%s chain=%s%s%s", n.action, n.chain, if n.outInterface then " out-interface=" .. n.outInterface else "", if n.disabled then " disabled=yes" else ""))
	end
	fw(cfg)
	if #cfg.addressList > 0 then
		table.insert(out, "/ip firewall address-list")
		for _, e in cfg.addressList do
			table.insert(out, "add " .. ruleText(e.kv, ADDR_ORDER) .. (if e.disabled then " disabled=yes" else ""))
		end
	end
	if #cfg.filter > 0 then
		table.insert(out, "/ip firewall filter")
		for _, r in cfg.filter do
			table.insert(out, "add " .. ruleText(r.kv, RULE_ORDER) .. (if r.disabled then " disabled=yes" else ""))
		end
	end
	if #cfg.raw > 0 then
		table.insert(out, "/ip firewall raw")
		for _, r in cfg.raw do
			table.insert(out, "add " .. ruleText(r.kv, RULE_ORDER) .. (if r.disabled then " disabled=yes" else ""))
		end
	end
	if cfg.settings.tcpSyncookies then
		table.insert(out, "/ip settings")
		table.insert(out, "set tcp-syncookies=yes")
	end
	table.insert(out, "/ip route")
	for _, r in cfg.routes do
		table.insert(out, string.format("add disabled=no dst-address=%s gateway=%s", r.dst, r.gateway))
	end
	table.insert(out, "/system identity")
	table.insert(out, "set name=" .. cfg.identity)
	return table.concat(out, "\n")
end

local function ping(target: string, ev: Eval, cfg: any, deadDns: { [string]: boolean }, count: number?): string
	local U = RouterCli.Upstream
	local ip = parseIp(target)
	local label = target
	if not ip then
		-- nome: o próprio roteador resolve usando os servidores configurados
		local resolver = false
		for _, sv in cfg.dns.servers do
			-- a regra src-port=53 sem exceção também descarta as respostas que o roteador recebe
			if (RouterCli.PublicDns[sv] or sv == U.upstreamDns) and not deadDns[sv] and not dropsDnsFrom(cfg, sv) then
				resolver = true
			end
		end
		if not (resolver and ev.routeOk) then
			return "failure: dns server failure"
		end
		ip = parseIp("142.250.79.46")
		label = "142.250.79.46"
	end
	local reachable
	if ip == parseIp(U.gateway) then
		reachable = ev.wanOk
	elseif sameNet(ip :: number, parseIp(U.lanAddress) :: number, 22) then
		reachable = ev.lanOk
	elseif RouterCli.PublicDns[ipToString(ip :: number)] and deadDns[ipToString(ip :: number)] then
		reachable = false
	elseif ipToString(ip :: number) == U.upstreamDns and deadDns[U.upstreamDns] then
		reachable = false
	else
		reachable = ev.routeOk
	end
	local n = math.clamp(count or 4, 1, 10)
	local lines = { "  SEQ HOST                                     SIZE TTL TIME       STATUS" }
	local got = 0
	for seq = 0, n - 1 do
		if reachable then
			got += 1
			local ms = if ip == parseIp(U.gateway) then 1 else 8 + math.random(0, 9)
			table.insert(lines, string.format("  %3d %s 56  %d %dms%d%d     ", seq, pad(label, 40), if ms < 3 then 64 else 117, ms, math.random(0, 9), math.random(0, 9)))
		else
			table.insert(lines, string.format("  %3d %s                     timeout", seq, pad(label, 40)))
		end
	end
	local stats = string.format("    sent=%d received=%d packet-loss=%d%%", n, got, math.floor((n - got) * 100 / n))
	if got > 0 then
		stats ..= " min-rtt=1ms avg-rtt=9ms max-rtt=17ms"
	end
	table.insert(lines, stats)
	return table.concat(lines, "\n")
end

local function traceroute(target: string, ev: Eval, cfg: any, deadDns: { [string]: boolean }): string
	local ip = parseIp(target)
	if not ip then
		local alive = false
		for _, sv in cfg.dns.servers do
			if (RouterCli.PublicDns[sv] or sv == RouterCli.Upstream.upstreamDns) and not deadDns[sv] then
				alive = true
			end
		end
		if not (alive and ev.routeOk) then
			return "failure: dns server failure"
		end
		target = "142.250.79.46"
	end
	local hops = { RouterCli.Upstream.gateway, "200.200.200.1", "187.16.216.10", target }
	local out = { "Columns: ADDRESS, LOSS, SENT, LAST, AVG, BEST, WORST", "#  ADDRESS          LOSS  SENT  LAST    AVG  BEST  WORST" }
	for i, h in hops do
		-- o tráfego do próprio roteador sai com o IP público: não depende do NAT
		local ok = if i == 1 then ev.wanOk else ev.routeOk
		if ok then
			local ms = i * 3 + math.random(0, 4)
			table.insert(out, string.format("%d  %s 0%%       3  %dms   %d.%d  %d     %d", i, pad(h, 16), ms, ms, math.random(0, 9), ms - 1, ms + 2))
		else
			table.insert(out, string.format("%d  %s 100%%     3  timeout", i, pad("", 16)))
			break
		end
	end
	return table.concat(out, "\n")
end

local HELP = table.concat({
	"Menus: /interface  /ip address  /ip route  /ip dns  /ip firewall (nat filter raw address-list connection)  /ip settings  /ip arp  /log  /system",
	"Verbos: print  add  set  remove  enable  disable  export    Comandos: /ping  /tool traceroute  /tool torch  /system reboot  /quit",
	"TAB completa (/ip ad<TAB> vira /ip address). Dois nomes parecidos? O TAB lista as opções.",
	"? no fim da linha mostra o que pode vir ali, com descrição (ex.: /ip address add ?).",
	"Abreviações valem: /ip ad pr = /ip address print. '..' sobe um menu e '/' volta à raiz.",
}, "\n")

-- Executa uma linha.
-- env = { ifaces = {ether1=bool,...}, deadDns = {...}, reboot = function(), uptime, time, date, arp = {...}, log = {...} }
function RouterCli.run(cfg: any, session: any, line: string, env: any): string
	line = string.gsub(line, "^%s+", "")
	line = string.gsub(line, "%s+$", "")
	if line == "" then
		return ""
	end
	if line == "help" then
		return HELP
	end
	if string.sub(line, -1) == "?" then
		return questionHelp(cfg, session, line)
	end
	if line == "/" then
		session.path = {}
		return ""
	end

	local p = parse(session, line)
	if p.err then
		return p.err
	end
	local path, verb, kv, loose = p.path, p.verb, p.kv, p.loose
	local key = table.concat(path, " ")
	local ev = RouterCli.evaluate(cfg, env.ifaces, env.deadDns)

	-- só o caminho: entra no menu
	if not verb then
		session.path = path
		return ""
	end

	if verb == "quit" then
		return "interrupted"
	elseif verb == "ping" then
		local target = kv.address or loose[1]
		if not target then
			return "expected address (ex.: /ping 8.8.8.8)"
		end
		return ping(target, ev, cfg, env.deadDns, tonumber(kv.count or ""))
	elseif verb == "export" then
		return exportConfig(cfg, env)
	elseif key == "system" and verb == "reboot" then
		env.reboot()
		return "Reboot, yes? [y/N]: y\nsystem will reboot shortly"
	elseif key == "tool" and verb == "torch" then
		return torch(kv, env)
	elseif key == "tool" and verb == "traceroute" then
		local target = kv.address or loose[1]
		if not target then
			return "expected address (ex.: /tool traceroute 8.8.8.8)"
		end
		return traceroute(target, ev, cfg, env.deadDns)
	end

	if key == "interface" and verb == "print" then
		return interfacePrint(env.ifaces, false)
	elseif key == "interface ethernet" and verb == "print" then
		return interfacePrint(env.ifaces, true)
	elseif key == "ip address" then
		if verb == "print" then
			local out = { "Flags: X - DISABLED", "Columns: ADDRESS, NETWORK, INTERFACE", " #   ADDRESS            NETWORK         INTERFACE" }
			for i, a in cfg.addresses do
				local n, pr = parseCidr(a.address)
				local net = if n and pr then ipToString(network(n, pr)) else "?"
				table.insert(out, string.format("%2d %s %s %s %s", i - 1, if a.disabled then "X" else " ", pad(a.address, 18), pad(net, 15), a.interface))
			end
			return table.concat(out, "\n")
		elseif verb == "add" then
			if not kv.address then
				return "failure: value of address must be specified"
			end
			if not kv.interface then
				return "failure: value of interface must be specified"
			end
			local n, pr = parseCidr(kv.address)
			if not n or not pr then
				return "invalid value for argument address"
			end
			if not table.find(IFACES, kv.interface) then
				return "input does not match any value of interface"
			end
			table.insert(cfg.addresses, { address = kv.address, interface = kv.interface, comment = kv.comment, network = ipToString(network(n, pr)), disabled = kv.disabled == "yes" })
			return ""
		elseif verb == "remove" then
			return removeByNumber(cfg.addresses, kv, loose)
		elseif verb == "disable" or verb == "enable" then
			return setDisabled(cfg.addresses, kv, loose, verb == "disable")
		end
	elseif key == "ip route" then
		if verb == "print" then
			local out = { "Flags: D - DYNAMIC; A - ACTIVE; c - CONNECT, s - STATIC", "Columns: DST-ADDRESS, GATEWAY, DISTANCE", "    DST-ADDRESS     GATEWAY       DISTANCE" }
			for i, r in cfg.routes do
				local active = parseIp(r.gateway or "") == parseIp(RouterCli.Upstream.gateway) and ev.wanOk
				table.insert(out, string.format("%d %s %s %s 1", i - 1, if active then "As" else " s", pad(r.dst, 15), pad(r.gateway, 13)))
			end
			if ev.wanOk then
				table.insert(out, "  DAc 100.64.10.0/30  ether1         0")
			end
			if ev.lanOk then
				table.insert(out, "  DAc 10.100.0.0/22   ether2         0")
			end
			return table.concat(out, "\n")
		elseif verb == "add" then
			if not kv.gateway or not parseIp(kv.gateway) then
				return "failure: value of gateway must be specified (ex.: add gateway=100.64.10.1)"
			end
			table.insert(cfg.routes, { dst = kv["dst-address"] or "0.0.0.0/0", gateway = kv.gateway })
			return ""
		elseif verb == "remove" then
			return removeByNumber(cfg.routes, kv, loose)
		end
	elseif key == "ip dns" then
		if verb == "print" then
			return string.format(
				"                      servers: %s\n              dynamic-servers: \n               use-doh-server: \n  allow-remote-requests: %s\n           cache-size: 2048KiB\n        cache-max-ttl: 1w\n           cache-used: %dKiB",
				table.concat(cfg.dns.servers, ","),
				if cfg.dns.allowRemote then "yes" else "no",
				if ev.dnsOk then 112 else 24
			)
		elseif verb == "set" then
			if kv.servers then
				local list = {}
				for sv in string.gmatch(kv.servers, "[^,]+") do
					if not parseIp(sv) then
						return "invalid value for argument servers"
					end
					table.insert(list, sv)
				end
				cfg.dns.servers = list
			end
			if kv["allow-remote-requests"] then
				if kv["allow-remote-requests"] ~= "yes" and kv["allow-remote-requests"] ~= "no" then
					return "invalid value for argument allow-remote-requests"
				end
				cfg.dns.allowRemote = kv["allow-remote-requests"] == "yes"
			end
			return ""
		end
	elseif key == "ip dns cache" then
		if verb == "flush" then
			return ""
		end
		return "Columns: NAME, TYPE, DATA, TTL\n#  NAME         TYPE  DATA            TTL\n" .. (if ev.dnsOk then "0  google.com   A     142.250.79.46   4m12s" else "")
	elseif key == "ip firewall nat" then
		if verb == "print" then
			local out = { "Flags: X - disabled, I - invalid; D - dynamic", " #    CHAIN    ACTION      OUT-INTERFACE" }
			for i, n in cfg.nat do
				table.insert(out, string.format("%2d %s  %s %s %s", i - 1, if n.disabled then "X" else " ", pad(n.chain, 8), pad(n.action, 11), n.outInterface or ""))
			end
			return table.concat(out, "\n")
		elseif verb == "add" then
			if not kv.chain then
				return "failure: value of chain must be specified"
			end
			if not kv.action then
				kv.action = "accept"
			end
			table.insert(cfg.nat, { chain = kv.chain, action = kv.action, outInterface = kv["out-interface"] })
			return ""
		elseif verb == "remove" then
			return removeByNumber(cfg.nat, kv, loose)
		elseif verb == "disable" or verb == "enable" then
			return setDisabled(cfg.nat, kv, loose, verb == "disable")
		end
	elseif key == "ip firewall filter" or key == "ip firewall raw" then
		fw(cfg)
		local list = if key == "ip firewall filter" then cfg.filter else cfg.raw
		if verb == "print" then
			return rulesPrint(list, RULE_ORDER)
		elseif verb == "add" then
			return addRule(list, kv, true)
		elseif verb == "remove" then
			return removeByNumber(list, kv, loose)
		elseif verb == "disable" or verb == "enable" then
			return setDisabled(list, kv, loose, verb == "disable")
		end
	elseif key == "ip firewall address-list" then
		fw(cfg)
		if verb == "print" then
			local out = { "Flags: X - disabled, D - dynamic", "Columns: LIST, ADDRESS, CREATION-TIME, TIMEOUT", " #   LIST              ADDRESS             TIMEOUT" }
			for i, e in cfg.addressList do
				table.insert(out, string.format("%2d %s %s %s %s", i - 1, if e.disabled then "X" else " ", pad(e.kv.list, 17), pad(e.kv.address, 19), e.kv.timeout or ""))
			end
			for i, d in (env.dynamicLists and env.dynamicLists()) or {} do
				table.insert(out, string.format("%2d D %s %s %s", #cfg.addressList + i - 1, pad(d.list, 17), pad(d.address, 19), d.timeout or ""))
			end
			return table.concat(out, "\n")
		elseif verb == "add" then
			if not kv.list then
				return "failure: value of list must be specified"
			end
			if not kv.address or not parseCidr(kv.address) then
				return "failure: value of address must be specified (ex.: address=45.170.81.0/24)"
			end
			return addRule(cfg.addressList, kv, false)
		elseif verb == "remove" then
			return removeByNumber(cfg.addressList, kv, loose)
		elseif verb == "disable" or verb == "enable" then
			return setDisabled(cfg.addressList, kv, loose, verb == "disable")
		end
	elseif key == "ip firewall connection" and verb == "print" then
		local c = (env.connections and env.connections()) or { count = 40, sample = {} }
		if table.find(loose, "count-only") or kv["count-only"] then
			return tostring(c.count)
		end
		local out = { "Flags: S - SEEN-REPLY, A - ASSURED, C - CONFIRMED", "Columns: PROTOCOL, SRC-ADDRESS, DST-ADDRESS, TCP-STATE, TIMEOUT", " #      PROTOCOL  SRC-ADDRESS            DST-ADDRESS          TCP-STATE    TIMEOUT" }
		for i, e in c.sample do
			table.insert(out, string.format("%2d %s %s %s %s %s %s", i - 1, pad(e.flags or "SAC", 5), pad(e.proto, 9), pad(e.src, 22), pad(e.dst, 20), pad(e.state or "", 12), e.timeout or "23h59m"))
		end
		if c.count > #c.sample then
			table.insert(out, string.format("... e mais %d conexões (use count-only para contar)", c.count - #c.sample))
		end
		return table.concat(out, "\n")
	elseif key == "ip settings" then
		fw(cfg)
		if verb == "print" then
			return table.concat({
				"              ip-forward: yes",
				"          send-redirects: yes",
				"     accept-source-route: no",
				"        accept-redirects: no",
				"        secure-redirects: yes",
				"               rp-filter: no",
				"          tcp-syncookies: " .. (if cfg.settings.tcpSyncookies then "yes" else "no"),
				"    max-neighbor-entries: 16384",
				"             arp-timeout: 30s",
				"         icmp-rate-limit: 10",
			}, "\n")
		elseif verb == "set" then
			local v = kv["tcp-syncookies"]
			if v then
				if v ~= "yes" and v ~= "no" then
					return "invalid value for argument tcp-syncookies"
				end
				cfg.settings.tcpSyncookies = v == "yes"
			end
			return ""
		end
	elseif key == "ip arp" and verb == "print" then
		local out = { "Flags: D - DYNAMIC; C - COMPLETE", "Columns: ADDRESS, MAC-ADDRESS, INTERFACE", "#    ADDRESS       MAC-ADDRESS        INTERFACE" }
		for i, a in env.arp or {} do
			table.insert(out, string.format("%d DC %s %s %s", i - 1, pad(a.ip, 13), pad(a.mac, 18), a.iface))
		end
		return table.concat(out, "\n")
	elseif key == "log" and verb == "print" then
		local out = {}
		for _, l in env.log or {} do
			table.insert(out, l)
		end
		return table.concat(out, "\n")
	elseif key == "system identity" then
		if verb == "print" then
			return "  name: " .. cfg.identity
		elseif verb == "set" then
			if not kv.name then
				return "failure: value of name must be specified"
			end
			cfg.identity = kv.name
			return ""
		end
	elseif key == "system resource" and verb == "print" then
		return table.concat({
			"                   uptime: " .. (env.uptime or "1h12m"),
			"                  version: " .. RouterCli.Version,
			"               build-time: 2024-09-20 13:00:27",
			"         factory-software: 7.10",
			"              free-memory: 3404.1MiB",
			"             total-memory: 4096.0MiB",
			"                      cpu: ARM64",
			"                cpu-count: 4",
			"            cpu-frequency: 1700MHz",
			"                 cpu-load: " .. (if env.cpuLoad then env.cpuLoad else math.random(3, 18)) .. "%",
			"           free-hdd-space: 98.3MiB",
			"          total-hdd-space: 128.0MiB",
			"        architecture-name: arm64",
			"               board-name: " .. RouterCli.Model,
			"                 platform: " .. RouterCli.Brand,
		}, "\n")
	elseif key == "system clock" and verb == "print" then
		return string.format("                  time: %s\n                  date: %s\n  time-zone-autodetect: yes\n        time-zone-name: America/Sao_Paulo\n            gmt-offset: -03:00", env.time or "08:00:00", env.date or "2026-11-10")
	elseif key == "system routerboard" and verb == "print" then
		return table.concat({
			"       routerboard: yes",
			"             model: " .. RouterCli.Model,
			"     serial-number: HG4091Q8ZPX",
			"     firmware-type: al2",
			"  factory-firmware: 7.10",
			"  current-firmware: 7.16",
			"  upgrade-firmware: 7.16",
		}, "\n")
	end
	if verb == "print" then
		return ""
	end
	return "syntax error (line 1 column 1)"
end

function RouterCli.prompt(cfg: any, session: any): string
	local where = if #session.path > 0 then "/" .. table.concat(session.path, " ") else ""
	return string.format("[admin@%s] %s> ", cfg.identity, where)
end

function RouterCli.banner(cfg: any): string
	return table.concat({
		"",
		"  MMM      MMM       KKK                          TTTTTTTTTTT      KKK",
		"  MMMM    MMMM       KKK                          TTTTTTTTTTT      KKK",
		"  MMM MMMM MMM  III  KKK  KKK  RRRRRR     OOOOOO      TTT     III  KKK  KKK",
		"  MMM  MM  MMM  III  KKKKK     RRR  RRR  OOO  OOO     TTT     III  KKKKK",
		"  MMM      MMM  III  KKK KKK   RRRRRR    OOO  OOO     TTT     III  KKK KKK",
		"  MMM      MMM  III  KKK  KKK  RRR  RRR   OOOOOO      TTT     III  KKK  KKK",
		"",
		"  " .. RouterCli.Brand .. " " .. RouterCli.OsName .. " " .. RouterCli.Version .. " (c) 1999-2024       https://www.mikrotik.com/",
		"",
		"TAB completa o comando · ? mostra as opções · help resume os menus · " .. cfg.identity .. " (" .. RouterCli.Model .. ")",
		"",
	}, "\n")
end

return RouterCli
