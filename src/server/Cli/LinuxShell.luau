-- Terminal dos PCs do NOC e do Notebook TI: um bash de Ubuntu 24.04 simplificado.
-- Tem sistema de arquivos pequeno (home, /etc, /dev), TAB do bash e os comandos de rede
-- que um técnico de provedor usa: ip, ping, tracepath, nslookup, dig, ssh, telnet e screen.

local Complete = require(script.Parent.Complete)

local Shell = {}

Shell.Distro = "Ubuntu 24.04.1 LTS"
Shell.Kernel = "6.8.0-48-generic"

-- nomes da internet que os PCs conseguem resolver (quando o DNS funciona)
local KnownNames = {
	["google.com"] = "142.250.79.46",
	["www.google.com"] = "142.250.79.36",
	["youtube.com"] = "142.250.218.14",
	["roblox.com"] = "128.116.123.3",
	["www.roblox.com"] = "128.116.123.3",
	["cloudflare.com"] = "104.16.132.229",
	["ubuntu.com"] = "185.125.190.20",
	["mikrotik.com"] = "159.148.147.196",
	["huawei.com"] = "121.36.37.240",
}
local ReverseNames = {
	["142.250.79.46"] = "gru14s32-in-f14.1e100.net",
	["8.8.8.8"] = "dns.google",
	["8.8.4.4"] = "dns.google",
	["1.1.1.1"] = "one.one.one.one",
	["1.0.0.1"] = "one.one.one.one",
}

local COMMANDS = {
	"alias", "apt", "cat", "cd", "clear", "date", "dig", "echo", "exit", "head", "help", "history", "host",
	"hostname", "id", "ifconfig", "ip", "less", "logout", "ls", "man", "more", "nslookup", "ping", "pwd",
	"screen", "ssh", "sudo", "tail", "telnet", "tracepath", "traceroute", "uname", "uptime", "whoami", "whois",
}

-- ---------------------------------------------------------------------------
-- Sistema de arquivos
-- ---------------------------------------------------------------------------

local function dir(children: { [string]: any }): any
	return { kind = "dir", children = children }
end
local function file(content: string): any
	return { kind = "file", content = content }
end

local function bashrc(env: any): string
	local lines = {
		"# ~/.bashrc: executado pelo bash em cada terminal novo",
		"HISTSIZE=1000",
		"PS1='\\u@\\h:\\w\\$ '",
		"",
		"# atalhos da equipe",
		"alias ll='ls -alF'",
		"alias hosts='cat /etc/hosts'",
	}
	if env.isNotebook then
		table.insert(lines, "alias console='screen /dev/ttyUSB0 115200'")
	end
	return table.concat(lines, "\n")
end

local function hostsFile(env: any): string
	local lines = {
		"127.0.0.1\tlocalhost",
		"127.0.1.1\t" .. env.host,
		"",
		"# Equipamentos da Fibra da Vila (rede de gerência 10.100.0.0/22)",
	}
	for _, h in env.hosts do
		table.insert(lines, h.ip .. "\t" .. table.concat(h.names, "\t") .. "\t# " .. h.info)
	end
	table.insert(lines, "")
	table.insert(lines, "# The following lines are desirable for IPv6 capable hosts")
	table.insert(lines, "::1     ip6-localhost ip6-loopback")
	return table.concat(lines, "\n")
end

local function readme(env: any): string
	local lines = {
		"LEIA-ME · " .. (if env.isNotebook then "Notebook do TI" else "estação de operação do NOC"),
		"",
		"Este computador roda " .. Shell.Distro .. ". A tecla TAB completa comandos, nomes e",
		"arquivos; dois TAB seguidos (ou TAB sem saída única) listam as opções.",
		"",
		"Equipamentos (cat /etc/hosts):",
		"  ssh admin@borda-vila        roteador MikroTik (ou ssh admin@10.100.0.1)",
		"  telnet olt-vila             OLT Huawei (ou telnet 10.100.0.2)",
		"",
		"Rede:",
		"  ip a / ip r                 IP e rotas deste computador",
		"  ping -c 4 olt-vila          testa se o equipamento responde",
		"  ping google.com             testa internet e DNS de uma vez",
		"  tracepath 8.8.8.8           mostra por onde o pacote passa",
		"  nslookup google.com         testa só o DNS",
		"",
		"Manuais: man routeros  ·  man ma5800  ·  cat ficha-do-link.txt",
	}
	if env.isNotebook then
		table.insert(lines, "")
		table.insert(lines, "Cabo de console (USB-serial em /dev/ttyUSB0):")
		table.insert(lines, "  screen /dev/ttyUSB0 115200  (ou só: console)")
		table.insert(lines, "  Chegue a até 3 m do equipamento no rack. Funciona sem IP, só precisa de energia.")
		table.insert(lines, "  Para sair: /quit no roteador, quit na OLT.")
	end
	return table.concat(lines, "\n")
end

local function buildFs(env: any): any
	local homeName = env.user
	local home = dir({
		["LEIA-ME.txt"] = file(readme(env)),
		["ficha-do-link.txt"] = file(env.ficha or ""),
		[".bashrc"] = file(bashrc(env)),
		[".bash_history"] = file(""),
		["Downloads"] = dir({}),
		["Documentos"] = dir({ ["manual-routeros.txt"] = file(env.man.routeros or ""), ["manual-ma5800.txt"] = file(env.man.ma5800 or "") }),
	})
	local devChildren = { null = file(""), tty = file(""), zero = file("") }
	if env.isNotebook then
		devChildren.ttyUSB0 = file("")
	end
	return dir({
		bin = dir({ bash = file(""), ls = file(""), cat = file(""), ping = file(""), ip = file("") }),
		dev = dir(devChildren),
		etc = dir({
			hosts = file(hostsFile(env)),
			hostname = file(env.host),
			["os-release"] = file(table.concat({
				"PRETTY_NAME=\"" .. Shell.Distro .. "\"",
				"NAME=\"Ubuntu\"",
				"VERSION_ID=\"24.04\"",
				"VERSION=\"24.04.1 LTS (Noble Numbat)\"",
				"VERSION_CODENAME=noble",
				"ID=ubuntu",
				"ID_LIKE=debian",
				"HOME_URL=\"https://www.ubuntu.com/\"",
			}, "\n")),
			["resolv.conf"] = file("# This is /run/systemd/resolve/stub-resolv.conf managed by man:systemd-resolved(8).\nnameserver 127.0.0.53\noptions edns0 trust-ad\nsearch ."),
			netplan = dir({
				["01-network-manager-all.yaml"] = file(table.concat({
					"network:",
					"  version: 2",
					"  ethernets:",
					"    " .. env.iface .. ":",
					"      addresses: [" .. env.myIp .. "/22]",
					"      routes:",
					"        - to: default",
					"          via: 10.100.0.1",
					"      nameservers:",
					"        addresses: [10.100.0.1]",
				}, "\n")),
			}),
		}),
		home = dir({ [homeName] = home }),
		tmp = dir({}),
		usr = dir({ bin = dir({}), share = dir({ doc = dir({}) }) }),
		var = dir({ log = dir({ syslog = file("") }) }),
	})
end

local function split(path: string): { string }
	local out = {}
	for part in string.gmatch(path, "[^/]+") do
		table.insert(out, part)
	end
	return out
end

-- caminho absoluto normalizado
local function absPath(st: any, env: any, path: string): string
	local home = "/home/" .. env.user
	if path == "~" then
		path = home
	elseif string.sub(path, 1, 2) == "~/" then
		path = home .. string.sub(path, 2)
	elseif string.sub(path, 1, 1) ~= "/" then
		path = st.cwd .. "/" .. path
	end
	local parts = {}
	for _, p in split(path) do
		if p == ".." then
			table.remove(parts)
		elseif p ~= "." then
			table.insert(parts, p)
		end
	end
	return "/" .. table.concat(parts, "/")
end

local function lookup(fs: any, abs: string): any
	local node = fs
	for _, p in split(abs) do
		if node.kind ~= "dir" then
			return nil
		end
		node = node.children[p]
		if not node then
			return nil
		end
	end
	return node
end

local function prettyCwd(st: any, env: any): string
	local home = "/home/" .. env.user
	if st.cwd == home then
		return "~"
	elseif string.sub(st.cwd, 1, #home + 1) == home .. "/" then
		return "~" .. string.sub(st.cwd, #home + 1)
	end
	return st.cwd
end

function Shell.prompt(st: any, env: any): string
	return string.format("%s@%s:%s$ ", env.user, env.host, prettyCwd(st, env))
end

function Shell.newSession(env: any): any
	return { cwd = "/home/" .. env.user, history = {}, known = {} }
end

function Shell.banner(env: any): string
	return table.concat({
		"Welcome to " .. Shell.Distro .. " (GNU/Linux " .. Shell.Kernel .. " x86_64)",
		"",
		" * Documentation:  https://help.ubuntu.com",
		" * Management:     https://landscape.canonical.com",
		" * Support:        https://ubuntu.com/pro",
		"",
		"Last login: " .. (env.dateLong or "Tue Nov 10 08:00:00 2026") .. " from 10.100.0.50",
		"Leia o guia rápido:  cat LEIA-ME.txt     (TAB completa comandos e nomes)",
		"",
	}, "\n")
end

-- ---------------------------------------------------------------------------
-- Rede
-- ---------------------------------------------------------------------------

local function isIp(s: string): boolean
	local a, b, c, d = string.match(s, "^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	if not a then
		return false
	end
	for _, v in { a, b, c, d } do
		if (tonumber(v) :: number) > 255 then
			return false
		end
	end
	return true
end

local function inMgmt(ip: string): boolean
	local a, b, c = string.match(ip, "^(%d+)%.(%d+)%.(%d+)%.")
	return a == "10" and b == "100" and tonumber(c) ~= nil and (tonumber(c) :: number) <= 3
end

local function hostByName(env: any, name: string): string?
	if name == "localhost" or name == env.host then
		return "127.0.0.1"
	end
	for _, h in env.hosts do
		if table.find(h.names, name) then
			return h.ip
		end
	end
	return nil
end

-- resolve um nome: /etc/hosts primeiro, depois o DNS (roteador 10.100.0.1)
-- retorna (ip | nil, erro)
local function resolve(env: any, name: string): (string?, string?)
	if isIp(name) then
		return name, nil
	end
	local local_ = hostByName(env, name)
	if local_ then
		return local_, nil
	end
	local n = env.net()
	if not n.dnsOk then
		return nil, "tempfail"
	end
	local ip = KnownNames[string.lower(name)]
	if not ip then
		return nil, "nxdomain"
	end
	return ip, nil
end

-- o IP responde a ping deste computador?
local function answers(env: any, ip: string): (boolean, string)
	if ip == "127.0.0.1" or ip == env.myIp then
		return true, "local"
	end
	if inMgmt(ip) then
		return env.deviceAt(ip) ~= nil or env.isPc(ip), "lan"
	end
	local n = env.net()
	if not n.gw then
		return false, "nogw"
	end
	if ip == "100.64.10.2" then
		return true, "wan"
	end
	if not (n.routeOk and n.natOk) then
		return false, "noroute"
	end
	if n.deadDns[ip] then
		return false, "dead"
	end
	return true, "internet"
end

local function rtt(kind: string): number
	if kind == "local" then
		return 0.03 + math.random() * 0.03
	elseif kind == "lan" or kind == "wan" then
		return 0.3 + math.random() * 0.4
	end
	return 9 + math.random() * 8
end

local function ping(env: any, args: { string }): string
	local count = 4
	local target = nil
	local i = 1
	while i <= #args do
		local a = args[i]
		if a == "-c" then
			count = tonumber(args[i + 1] or "") or 0
			i += 1
		elseif string.sub(a, 1, 2) == "-c" and tonumber(string.sub(a, 3)) then
			count = tonumber(string.sub(a, 3)) :: number
		elseif string.sub(a, 1, 1) == "-" then
			-- outras opções são ignoradas
		else
			target = a
		end
		i += 1
	end
	if not target then
		return "ping: usage error: Destination address required"
	end
	if count < 1 then
		return "ping: invalid argument: '" .. tostring(args[2]) .. "': out of range: 1 <= value <= 9223372036854775807"
	end
	local stopped = count == 4 and not table.find(args, "-c")
	count = math.min(count, 10)
	local ip, why = resolve(env, target)
	if not ip then
		if why == "tempfail" then
			return "ping: " .. target .. ": Temporary failure in name resolution"
		end
		return "ping: " .. target .. ": Name or service not known"
	end
	local ok, kind = answers(env, ip)
	local shown = if isIp(target) then ip else (ReverseNames[ip] or target) .. " (" .. ip .. ")"
	local out = { string.format("PING %s (%s) 56(84) bytes of data.", target, ip) }
	local times = {}
	for seq = 1, count do
		if ok then
			local t = rtt(kind)
			table.insert(times, t)
			table.insert(out, string.format("64 bytes from %s: icmp_seq=%d ttl=%d time=%s ms", shown, seq, if kind == "internet" then 116 else 64, if t < 1 then string.format("%.3f", t) else string.format("%.1f", t)))
		elseif kind == "lan" or kind == "nogw" then
			table.insert(out, string.format("From %s icmp_seq=%d Destination Host Unreachable", env.myIp, seq))
		end
	end
	if stopped then
		table.insert(out, "^C")
	end
	table.insert(out, "--- " .. target .. " ping statistics ---")
	local errors = if not ok and (kind == "lan" or kind == "nogw") then string.format(", +%d errors", count) else ""
	table.insert(out, string.format("%d packets transmitted, %d received%s, %d%% packet loss, time %dms", count, #times, errors, math.floor((count - #times) * 100 / count), (count - 1) * 1001 + math.random(0, 9)))
	if #times > 0 then
		local mn, mx, sum = math.huge, 0, 0
		for _, t in times do
			mn = math.min(mn, t)
			mx = math.max(mx, t)
			sum += t
		end
		table.insert(out, string.format("rtt min/avg/max/mdev = %.3f/%.3f/%.3f/%.3f ms", mn, sum / #times, mx, (mx - mn) / 2))
	end
	return table.concat(out, "\n")
end

local function tracepath(env: any, args: { string }): string
	local target = args[#args]
	if not target or string.sub(target, 1, 1) == "-" then
		return "Usage: tracepath [-4] [-6] [-n] [-b] [-l <len>] [-p port] <destination>"
	end
	local ip, why = resolve(env, target)
	if not ip then
		return "tracepath: " .. target .. ": " .. (if why == "tempfail" then "Temporary failure in name resolution" else "Name or service not known")
	end
	local out = { " 1?: [LOCALHOST]                      pmtu 1500" }
	local function hop(n: number, name: string, ms: number)
		table.insert(out, string.format(" %d:  %s%s%.3fms", n, name, string.rep(" ", math.max(1, 34 - #name)), ms))
	end
	if inMgmt(ip) then
		if env.deviceAt(ip) or env.isPc(ip) then
			hop(1, ip, rtt("lan"))
			table.insert(out, "     Resume: pmtu 1500 hops 1 back 1")
		else
			table.insert(out, " 1:  " .. env.myIp .. "                                  3062.112ms !H")
			table.insert(out, "     Resume: pmtu 1500")
		end
		return table.concat(out, "\n")
	end
	local n = env.net()
	if not n.gw then
		table.insert(out, " 1:  " .. env.myIp .. "                                  3071.204ms !H")
		table.insert(out, "     Resume: pmtu 1500")
		return table.concat(out, "\n")
	end
	hop(1, "_gateway (10.100.0.1)", rtt("lan"))
	if not n.routeOk then
		table.insert(out, " 2:  _gateway (10.100.0.1)                                 0.701ms !N")
		table.insert(out, "     Resume: pmtu 1500")
		return table.concat(out, "\n")
	end
	if not n.natOk then
		-- sai com IP privado: ninguém lá fora consegue responder
		for k = 2, 5 do
			table.insert(out, string.format(" %d:  no reply", k))
		end
		table.insert(out, "     Too many hops: pmtu 1500")
		return table.concat(out, "\n")
	end
	hop(2, "100.64.10.1", 1.8 + math.random())
	hop(3, "200.200.200.1", 4 + math.random() * 2)
	hop(4, "187.16.216.10", 7 + math.random() * 2)
	if n.deadDns[ip] then
		table.insert(out, " 5:  no reply")
		table.insert(out, " 6:  no reply")
		table.insert(out, "     Too many hops: pmtu 1500")
	else
		hop(5, (ReverseNames[ip] or ip) .. " (" .. ip .. ")", rtt("internet"))
		table.insert(out, "     Resume: pmtu 1500 hops 5 back 5")
	end
	return table.concat(out, "\n")
end

local function isDnsServer(ip: string): boolean
	return ip == "8.8.8.8" or ip == "8.8.4.4" or ip == "1.1.1.1" or ip == "1.0.0.1" or ip == "9.9.9.9" or ip == "200.200.200.53"
end

-- consulta DNS: server = nil usa o resolvedor do sistema (127.0.0.53 -> roteador)
local function dnsQuery(env: any, name: string, server: string?): (string, string?)
	local n = env.net()
	if server and server ~= "127.0.0.53" and server ~= "10.100.0.1" then
		local reach = answers(env, server)
		if not reach or not isDnsServer(server) then
			return "timeout", nil
		end
	elseif server == "10.100.0.1" then
		if not n.gw then
			return "timeout", nil
		end
		if not n.dnsOk then
			return "servfail", nil
		end
	else
		local h = hostByName(env, name)
		if h then
			return "hosts", h
		end
		if not n.gw then
			return "timeout", nil
		end
		if not n.dnsOk then
			return "servfail", nil
		end
	end
	local ip = KnownNames[string.lower(name)]
	if not ip then
		return "nxdomain", nil
	end
	return "ok", ip
end

local function nslookup(env: any, args: { string }): string
	local name, server = args[1], args[2]
	if not name then
		return "Uso: nslookup <nome> [servidor]   (o modo interativo não está disponível)"
	end
	local srv = server or "127.0.0.53"
	local status, ip = dnsQuery(env, name, server)
	local head = "Server:\t\t" .. srv .. "\nAddress:\t" .. srv .. "#53\n"
	if status == "timeout" then
		return ";; communications error to " .. srv .. "#53: timed out\n;; communications error to " .. srv .. "#53: timed out\n;; no servers could be reached"
	elseif status == "servfail" then
		return head .. "\n** server can't find " .. name .. ": SERVFAIL"
	elseif status == "nxdomain" then
		return head .. "\n** server can't find " .. name .. ": NXDOMAIN"
	elseif status == "hosts" then
		return head .. "\nName:\t" .. name .. "\nAddress: " .. ip
	end
	return head .. "\nNon-authoritative answer:\nName:\t" .. name .. "\nAddress: " .. ip
end

local function dig(env: any, args: { string }): string
	local server, name = nil, nil
	local short = false
	for _, a in args do
		if string.sub(a, 1, 1) == "@" then
			server = string.sub(a, 2)
		elseif a == "+short" then
			short = true
		elseif string.sub(a, 1, 1) ~= "+" and string.sub(a, 1, 1) ~= "-" and string.upper(a) ~= "A" then
			name = a
		end
	end
	if not name then
		name = "."
	end
	local srv = server or "127.0.0.53"
	local status, ip = dnsQuery(env, name, server)
	if status == "hosts" then
		status = "ok"
	end
	if short then
		return if status == "ok" then ip :: string else ""
	end
	if status == "timeout" then
		return ";; communications error to " .. srv .. "#53: timed out\n\n; <<>> DiG 9.18.28-0ubuntu0.24.04.1-Ubuntu <<>> " .. table.concat(args, " ") .. "\n;; global options: +cmd\n;; no servers could be reached"
	end
	local code = if status == "ok" then "NOERROR" elseif status == "nxdomain" then "NXDOMAIN" else "SERVFAIL"
	local out = {
		"; <<>> DiG 9.18.28-0ubuntu0.24.04.1-Ubuntu <<>> " .. table.concat(args, " "),
		";; global options: +cmd",
		";; Got answer:",
		";; ->>HEADER<<- opcode: QUERY, status: " .. code .. ", id: " .. math.random(1000, 65000),
		";; flags: qr rd ra; QUERY: 1, ANSWER: " .. (if status == "ok" then 1 else 0) .. ", AUTHORITY: 0, ADDITIONAL: 1",
		"",
		";; QUESTION SECTION:",
		";" .. name .. ".\t\t\tIN\tA",
	}
	if status == "ok" then
		table.insert(out, "")
		table.insert(out, ";; ANSWER SECTION:")
		table.insert(out, name .. ".\t\t" .. math.random(60, 300) .. "\tIN\tA\t" .. ip)
	end
	table.insert(out, "")
	table.insert(out, ";; Query time: " .. math.random(8, 40) .. " msec")
	table.insert(out, ";; SERVER: " .. srv .. "#53(" .. srv .. ") (UDP)")
	table.insert(out, ";; WHEN: " .. (env.dateLong or "Tue Nov 10 08:00:00 -03 2026"))
	table.insert(out, ";; MSG SIZE  rcvd: 55")
	return table.concat(out, "\n")
end

local function ipCmd(env: any, args: { string }): string
	local obj = args[1] or ""
	local sub = args[2] or "show"
	local mac = if env.isNotebook then "d4:6a:6a:2b:91:0c" else string.format("3c:52:82:1a:0b:%02x", 0x50 + (env.idx or 1))
	if obj == "" then
		return "Usage: ip [ OPTIONS ] OBJECT { COMMAND | help }\nwhere  OBJECT := { address | route | link | neigh | ... }"
	end
	if Complete.startsWith("address", obj) or obj == "a" then
		return table.concat({
			"1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000",
			"    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00",
			"    inet 127.0.0.1/8 scope host lo",
			"       valid_lft forever preferred_lft forever",
			"2: " .. env.iface .. ": <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc " .. (if env.isNotebook then "noqueue" else "fq_codel") .. " state UP group default qlen 1000",
			"    link/ether " .. mac .. " brd ff:ff:ff:ff:ff:ff",
			"    inet " .. env.myIp .. "/22 brd 10.100.3.255 scope global noprefixroute " .. env.iface,
			"       valid_lft forever preferred_lft forever",
		}, "\n")
	elseif Complete.startsWith("route", obj) or obj == "r" then
		return table.concat({
			"default via 10.100.0.1 dev " .. env.iface .. " proto static metric " .. (if env.isNotebook then 600 else 100),
			"10.100.0.0/22 dev " .. env.iface .. " proto kernel scope link src " .. env.myIp .. " metric " .. (if env.isNotebook then 600 else 100),
		}, "\n")
	elseif Complete.startsWith("link", obj) or obj == "l" then
		return table.concat({
			"1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000",
			"    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00",
			"2: " .. env.iface .. ": <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP mode DEFAULT group default qlen 1000",
			"    link/ether " .. mac .. " brd ff:ff:ff:ff:ff:ff",
		}, "\n")
	elseif Complete.startsWith("neighbour", obj) or Complete.startsWith("neighbor", obj) or obj == "n" then
		local out = {}
		for _, h in env.hosts do
			if env.deviceAt(h.ip) then
				table.insert(out, h.ip .. " dev " .. env.iface .. " lladdr " .. h.mac .. " REACHABLE")
			else
				table.insert(out, h.ip .. " dev " .. env.iface .. " FAILED")
			end
		end
		return table.concat(out, "\n")
	end
	return "Object \"" .. obj .. "\" is unknown, try \"ip help\"."
end

-- ---------------------------------------------------------------------------
-- Manuais
-- ---------------------------------------------------------------------------

local MiniMan = {
	ping = "PING(8)                         iputils                         PING(8)\n\nNAME\n       ping - send ICMP ECHO_REQUEST to network hosts\n\nSYNOPSIS\n       ping [-c count] [-i interval] destination\n\nDESCRIPTION\n       ping usa o ICMP ECHO_REQUEST para pedir uma resposta ao destino.\n       Sem -c, roda até Ctrl+C (aqui ele para sozinho depois de 4 pacotes).\n\n       -c count   para depois de enviar count pacotes",
	ssh = "SSH(1)                    General Commands Manual                   SSH(1)\n\nNAME\n       ssh - OpenSSH remote login client\n\nSYNOPSIS\n       ssh [-p port] [user@]hostname\n\nDESCRIPTION\n       Abre um terminal seguro no equipamento. Sem user@, usa o seu usuário\n       local, que os equipamentos não conhecem: use admin@.",
	telnet = "TELNET(1)                 General Commands Manual                TELNET(1)\n\nNAME\n       telnet - user interface to the TELNET protocol\n\nSYNOPSIS\n       telnet host [port]\n\nDESCRIPTION\n       Abre um terminal sem criptografia (porta 23). A OLT usa telnet na gerência.",
	ip = "IP(8)                                Linux                               IP(8)\n\nNAME\n       ip - show / manipulate routing, network devices, interfaces\n\nSYNOPSIS\n       ip a       endereços IP\n       ip r       tabela de rotas\n       ip link    interfaces\n       ip neigh   vizinhos (ARP)",
	tracepath = "TRACEPATH(8)                    iputils                    TRACEPATH(8)\n\nNAME\n       tracepath - traces path to a network host discovering MTU\n\nSYNOPSIS\n       tracepath destination\n\nDESCRIPTION\n       Mostra cada roteador no caminho até o destino. 'no reply' significa\n       que ninguém respondeu naquele salto.",
	nslookup = "NSLOOKUP(1)                       BIND 9                      NSLOOKUP(1)\n\nNAME\n       nslookup - query Internet name servers\n\nSYNOPSIS\n       nslookup name [server]\n\nDESCRIPTION\n       Pergunta ao DNS o IP de um nome. Com server, pergunta direto àquele\n       servidor (ex.: nslookup google.com 8.8.8.8).",
	dig = "DIG(1)                            BIND 9                           DIG(1)\n\nNAME\n       dig - DNS lookup utility\n\nSYNOPSIS\n       dig [@server] name [+short]",
	screen = "SCREEN(1)                 General Commands Manual                SCREEN(1)\n\nNAME\n       screen - screen manager with VT100/ANSI terminal emulation\n\nSYNOPSIS\n       screen /dev/ttyUSB0 115200\n\nDESCRIPTION\n       Abre a porta serial do cabo de console (USB) a 115200 bauds.",
	whois = "WHOIS(1)                    Debian GNU/Linux                    WHOIS(1)\n\nNAME\n       whois - client for the whois directory service\n\nSYNOPSIS\n       whois IP | ASnúmero\n\nDESCRIPTION\n       Mostra quem é o dono de um IP ou de um sistema autônomo (AS) no\n       registro da LACNIC. Use com os IPs que o /tool torch do roteador mostrou\n       para descobrir de que provedor vem um ataque (ex.: whois 45.170.81.23).",
	man = "MAN(1)                       Manual pager utils                       MAN(1)\n\nNAME\n       man - an interface to the system reference manuals\n\nSYNOPSIS\n       man page\n\nPáginas deste computador: routeros, ma5800, ping, ssh, telnet, ip, tracepath,\nnslookup, dig, whois, screen, man",
}

local function manPages(env: any): { string }
	local out = { "routeros", "ma5800" }
	for k in MiniMan do
		table.insert(out, k)
	end
	table.sort(out)
	local _ = env
	return out
end

-- ---------------------------------------------------------------------------
-- Comandos
-- ---------------------------------------------------------------------------

local function lsCmd(st: any, env: any, fs: any, args: { string }): string
	local all, long = false, false
	local targets = {}
	for _, a in args do
		if string.sub(a, 1, 1) == "-" then
			if string.find(a, "a", 2, true) then
				all = true
			end
			if string.find(a, "l", 2, true) then
				long = true
			end
		else
			table.insert(targets, a)
		end
	end
	if #targets == 0 then
		targets = { "." }
	end
	local out = {}
	for _, t in targets do
		local abs = absPath(st, env, t)
		local node = lookup(fs, abs)
		if not node then
			table.insert(out, "ls: cannot access '" .. t .. "': No such file or directory")
		elseif node.kind == "file" then
			table.insert(out, t)
		else
			local names = {}
			for name in node.children do
				if all or string.sub(name, 1, 1) ~= "." then
					table.insert(names, name)
				end
			end
			table.sort(names, function(a, b)
				return string.lower((string.gsub(a, "^%.", ""))) < string.lower((string.gsub(b, "^%.", "")))
			end)
			if all then
				table.insert(names, 1, "..")
				table.insert(names, 1, ".")
			end
			if long then
				table.insert(out, "total " .. (#names * 4))
				for _, name in names do
					local child = node.children[name]
					local isDir = name == "." or name == ".." or (child and child.kind == "dir")
					local size = if isDir then 4096 else #(child and child.content or "")
					local owner = if string.sub(abs, 1, 6) == "/home/" then env.user else "root"
					table.insert(out, string.format("%s %2d %s %s %6d Nov 10 08:00 %s", if isDir then "drwxr-xr-x" else "-rw-r--r--", if isDir then 2 else 1, owner, owner, size, name))
				end
			else
				local shown = {}
				for _, name in names do
					local child = node.children[name]
					table.insert(shown, if child and child.kind == "dir" then name .. "/" else name)
				end
				table.insert(out, Complete.columns(shown))
			end
		end
	end
	return table.concat(out, "\n")
end

local function catCmd(st: any, env: any, fs: any, args: { string }, cmd: string): string
	local out = {}
	local files = {}
	local count = nil
	local i = 1
	while i <= #args do
		local a = args[i]
		if a == "-n" and (cmd == "head" or cmd == "tail") then
			count = tonumber(args[i + 1] or "")
			i += 1
		elseif string.sub(a, 1, 1) ~= "-" then
			table.insert(files, a)
		end
		i += 1
	end
	if #files == 0 then
		return ""
	end
	for _, f in files do
		local node = lookup(fs, absPath(st, env, f))
		if not node then
			table.insert(out, cmd .. ": " .. f .. ": No such file or directory")
		elseif node.kind == "dir" then
			table.insert(out, cmd .. ": " .. f .. ": Is a directory")
		else
			local text = node.content
			if cmd == "head" or cmd == "tail" then
				local lines = string.split(text, "\n")
				local n = count or 10
				local from = if cmd == "head" then 1 else math.max(1, #lines - n + 1)
				local to = if cmd == "head" then math.min(#lines, n) else #lines
				text = table.concat(lines, "\n", from, to)
			end
			table.insert(out, text)
		end
	end
	return table.concat(out, "\n")
end

local HELP_TEXT = table.concat({
	"GNU bash, version 5.2.21(1)-release (x86_64-pc-linux-gnu)",
	"Comandos úteis neste computador (TAB completa, man <comando> explica):",
	"",
	"  arquivos   ls  cd  pwd  cat  less  head  tail  echo",
	"  sistema    whoami  hostname  uname -a  uptime  date  history  clear  exit",
	"  rede       ip a  ip r  ip neigh  ping  tracepath  nslookup  dig  whois",
	"  acesso     ssh admin@borda-vila   telnet olt-vila",
	"  manuais    man routeros   man ma5800   cat ficha-do-link.txt",
}, "\n")

-- Executa uma linha do bash.
-- Retorna { output, connect = { kind = "ssh"|"telnet"|"serial", ip, user }?, closed? }
function Shell.run(st: any, env: any, line: string): any
	line = string.gsub(line, "^%s+", "")
	line = string.gsub(line, "%s+$", "")
	if line == "" then
		return { output = "" }
	end
	table.insert(st.history, line)
	if #st.history > 200 then
		table.remove(st.history, 1)
	end
	-- aliases do .bashrc
	local first = string.match(line, "^(%S+)")
	local aliases = { ll = "ls -alF", hosts = "cat /etc/hosts" }
	if env.isNotebook then
		aliases.console = "screen /dev/ttyUSB0 115200"
	end
	if first and aliases[first] then
		line = aliases[first] .. string.sub(line, #first + 1)
	end
	local args = {}
	for t in string.gmatch(line, "%S+") do
		table.insert(args, t)
	end
	local cmd = table.remove(args, 1) :: string
	if cmd == "sudo" then
		return { output = "[sudo] password for " .. env.user .. ": \nSorry, user " .. env.user .. " is not allowed to execute '" .. table.concat(args, " ") .. "' as root on " .. env.host .. "." }
	end
	local fs = buildFs(env)

	if cmd == "help" then
		return { output = HELP_TEXT .. (if env.isNotebook then "\n  console    screen /dev/ttyUSB0 115200 (cabo de console)" else "") }
	elseif cmd == "exit" or cmd == "logout" then
		return { output = "logout", closed = true }
	elseif cmd == "pwd" then
		return { output = st.cwd }
	elseif cmd == "cd" then
		local target = args[1] or "~"
		if target == "-" then
			target = st.prev or st.cwd
		end
		local abs = absPath(st, env, target)
		local node = lookup(fs, abs)
		if not node then
			return { output = "bash: cd: " .. target .. ": No such file or directory" }
		elseif node.kind ~= "dir" then
			return { output = "bash: cd: " .. target .. ": Not a directory" }
		end
		st.prev = st.cwd
		st.cwd = abs
		return { output = "" }
	elseif cmd == "ls" then
		return { output = lsCmd(st, env, fs, args) }
	elseif cmd == "cat" or cmd == "less" or cmd == "more" or cmd == "head" or cmd == "tail" then
		if #args == 0 and (cmd == "less" or cmd == "more") then
			return { output = "Missing filename (\"" .. cmd .. " --help\" for help)" }
		end
		return { output = catCmd(st, env, fs, args, cmd) }
	elseif cmd == "echo" then
		local text = table.concat(args, " ")
		text = string.gsub(text, "%$USER", env.user)
		text = string.gsub(text, "%$HOME", "/home/" .. env.user)
		text = string.gsub(text, "%$HOSTNAME", env.host)
		text = string.gsub(text, "%$PWD", st.cwd)
		text = string.gsub(text, "[\"']", "")
		return { output = text }
	elseif cmd == "whoami" then
		return { output = env.user }
	elseif cmd == "id" then
		return { output = string.format("uid=1000(%s) gid=1000(%s) groups=1000(%s),20(dialout),46(plugdev)", env.user, env.user, env.user) }
	elseif cmd == "hostname" then
		if args[1] == "-I" then
			return { output = env.myIp .. " " }
		end
		return { output = env.host }
	elseif cmd == "uname" then
		if args[1] == "-a" then
			return { output = "Linux " .. env.host .. " " .. Shell.Kernel .. " #48-Ubuntu SMP PREEMPT_DYNAMIC Fri Sep 27 14:04:52 UTC 2024 x86_64 x86_64 x86_64 GNU/Linux" }
		elseif args[1] == "-r" then
			return { output = Shell.Kernel }
		end
		return { output = "Linux" }
	elseif cmd == "date" then
		return { output = env.dateLong or "Tue Nov 10 08:00:00 -03 2026" }
	elseif cmd == "uptime" then
		return { output = " " .. (env.time or "08:00:00") .. " up 3 days,  2:41,  1 user,  load average: 0.08, 0.12, 0.09" }
	elseif cmd == "history" then
		local out = {}
		for i, h in st.history do
			table.insert(out, string.format("%5d  %s", i, h))
		end
		return { output = table.concat(out, "\n") }
	elseif cmd == "alias" then
		local out = {}
		local names = {}
		for k in aliases do
			table.insert(names, k)
		end
		table.sort(names)
		for _, k in names do
			table.insert(out, "alias " .. k .. "='" .. aliases[k] .. "'")
		end
		return { output = table.concat(out, "\n") }
	elseif cmd == "apt" or cmd == "apt-get" then
		if args[1] == "install" or args[1] == "update" or args[1] == "remove" or args[1] == "upgrade" then
			return { output = "E: Could not open lock file /var/lib/dpkg/lock-frontend - open (13: Permission denied)\nE: Unable to acquire the dpkg frontend lock (/var/lib/dpkg/lock-frontend), are you root?" }
		end
		return { output = "apt 2.7.14 (amd64)\nUsage: apt [options] command" }
	elseif cmd == "ifconfig" then
		return { output = "Command 'ifconfig' not found, but can be installed with:\nsudo apt install net-tools\n(no Ubuntu atual use: ip a)" }
	elseif cmd == "traceroute" then
		return { output = "Command 'traceroute' not found, but can be installed with:\nsudo apt install inetutils-traceroute\n(já vem instalado: tracepath " .. (args[1] or "8.8.8.8") .. ")" }
	elseif cmd == "ip" then
		return { output = ipCmd(env, args) }
	elseif cmd == "ping" then
		return { output = ping(env, args) }
	elseif cmd == "tracepath" then
		return { output = tracepath(env, args) }
	elseif cmd == "nslookup" then
		return { output = nslookup(env, args) }
	elseif cmd == "whois" then
		-- consulta o dono de um IP ou AS (registro da LACNIC): rastreia a origem de um ataque
		if not env.whois then
			return { output = "whois: comando indisponível" }
		end
		local n = env.net()
		if not (n.gw and n.routeOk and n.natOk) then
			return { output = "whois: connect: Network is unreachable (o PC precisa de internet: confira o roteador)" }
		end
		return { output = env.whois(args[1]) }
	elseif cmd == "dig" then
		return { output = dig(env, args) }
	elseif cmd == "host" then
		local name = args[1]
		if not name then
			return { output = "Usage: host [-v] name [server]" }
		end
		local status, ip = dnsQuery(env, name, args[2])
		if status == "ok" or status == "hosts" then
			return { output = name .. " has address " .. ip }
		elseif status == "nxdomain" then
			return { output = "Host " .. name .. " not found: 3(NXDOMAIN)" }
		elseif status == "servfail" then
			return { output = "Host " .. name .. " not found: 2(SERVFAIL)" }
		end
		return { output = ";; communications error to 127.0.0.53#53: timed out\n;; no servers could be reached" }
	elseif cmd == "man" then
		local page = args[1]
		if not page then
			return { output = "What manual page do you want?\nFor example, try 'man man'." }
		end
		page = string.lower(page)
		if page == "routeros" or page == "mikrotik" then
			return { output = env.man.routeros }
		elseif page == "ma5800" or page == "huawei" or page == "olt" then
			return { output = env.man.ma5800 }
		elseif MiniMan[page] then
			return { output = MiniMan[page] }
		end
		return { output = "No manual entry for " .. page }
	elseif cmd == "ssh" or cmd == "telnet" then
		local target = nil
		for _, a in args do
			if string.sub(a, 1, 1) ~= "-" and not tonumber(a) then
				target = a
			end
		end
		if not target then
			if cmd == "ssh" then
				return { output = "usage: ssh [-46AaCfGgKkMNnqsTtVvXxYy] [-p port] [user@]hostname [command]" }
			end
			return { output = "usage: telnet [-l user] host [port]" }
		end
		local user, hostName = string.match(target, "^([^@]+)@(.+)$")
		if not user then
			user, hostName = env.user, target
		end
		local ip, why = resolve(env, hostName :: string)
		if not ip then
			if cmd == "ssh" then
				return { output = "ssh: Could not resolve hostname " .. hostName .. ": " .. (if why == "tempfail" then "Temporary failure in name resolution" else "Name or service not known") }
			end
			return { output = "telnet: could not resolve " .. hostName .. "/telnet: " .. (if why == "tempfail" then "Temporary failure in name resolution" else "Name or service not known") }
		end
		local kind = env.deviceAt(ip)
		if not kind then
			if cmd == "ssh" then
				return { output = "ssh: connect to host " .. hostName .. " port 22: No route to host" }
			end
			return { output = "Trying " .. ip .. "...\ntelnet: Unable to connect to remote host: No route to host" }
		end
		if cmd == "ssh" and kind == "olt" then
			return { output = "ssh: connect to host " .. hostName .. " port 22: Connection refused\n(a OLT só aceita telnet na gerência: telnet " .. hostName .. ")" }
		end
		if cmd == "ssh" and user ~= "admin" then
			return { output = user .. "@" .. hostName .. "'s password: \nPermission denied, please try again.\n" .. user .. "@" .. hostName .. ": Permission denied (password).\n(o usuário dos equipamentos é admin: ssh admin@" .. hostName .. ")" }
		end
		local hello
		if cmd == "ssh" then
			hello = ""
			if not st.known[ip] then
				st.known[ip] = true
				hello = "The authenticity of host '" .. hostName .. " (" .. ip .. ")' can't be established.\nED25519 key fingerprint is SHA256:q3Zk8fXr2aLw0pVb6YtN1eHs9cGm4uJd7oKi5TzQx0E.\nAre you sure you want to continue connecting (yes/no/[fingerprint])? yes\nWarning: Permanently added '" .. hostName .. "' (ED25519) to the list of known hosts.\n"
			end
			hello ..= "admin@" .. hostName .. "'s password: ********\n"
		elseif kind == "olt" then
			hello = "Trying " .. ip .. "...\nConnected to " .. hostName .. ".\nEscape character is '^]'.\n\n>>User name:admin\n>>User password:********\n"
		else
			hello = "Trying " .. ip .. "...\nConnected to " .. hostName .. ".\nEscape character is '^]'.\n\nLogin: admin\nPassword: ********\n"
		end
		return { output = hello, connect = { kind = cmd, ip = ip } }
	elseif cmd == "screen" or cmd == "minicom" or cmd == "picocom" then
		if not env.isNotebook then
			return { output = "Cannot exec '/dev/ttyUSB0': No such file or directory\n(este PC não tem cabo de console: use o Notebook TI perto do rack)" }
		end
		local devPath = args[1]
		if cmd == "minicom" or cmd == "picocom" then
			devPath = "/dev/ttyUSB0"
		end
		if devPath ~= "/dev/ttyUSB0" then
			return { output = "Cannot exec '" .. tostring(devPath) .. "': No such file or directory\n(o cabo USB-serial aparece como /dev/ttyUSB0: screen /dev/ttyUSB0 115200)" }
		end
		return { output = "", connect = { kind = "serial" } }
	end
	return { output = cmd .. ": command not found" }
end

-- ---------------------------------------------------------------------------
-- TAB do bash
-- ---------------------------------------------------------------------------

local function pathCandidates(st: any, env: any, partial: string, dirsOnly: boolean): { string }
	local fs = buildFs(env)
	local dirPart, namePart = string.match(partial, "^(.*/)([^/]*)$")
	if not dirPart then
		dirPart, namePart = "", partial
	end
	local base = if dirPart == "" then st.cwd else absPath(st, env, dirPart)
	local node = lookup(fs, base)
	local out = {}
	if not node or node.kind ~= "dir" then
		return out
	end
	for name, child in node.children do
		if Complete.startsWith(name, namePart :: string) and (string.sub(name, 1, 1) ~= "." or string.sub(namePart :: string, 1, 1) == ".") then
			if child.kind == "dir" then
				table.insert(out, dirPart .. name .. "/")
			elseif not dirsOnly then
				table.insert(out, dirPart .. name)
			end
		end
	end
	table.sort(out)
	return out
end

local function hostCandidates(env: any, partial: string, withUser: boolean): { string }
	local prefix = ""
	local word = partial
	local u, rest = string.match(partial, "^([^@]+@)(.*)$")
	if u then
		prefix, word = u, rest
	elseif withUser and (partial == "" or Complete.startsWith("admin@", partial)) then
		return { "admin@" }
	end
	local out = {}
	for _, h in env.hosts do
		for _, n in h.names do
			if Complete.startsWith(n, word :: string) then
				table.insert(out, prefix .. n)
			end
		end
		if Complete.startsWith(h.ip, word :: string) then
			table.insert(out, prefix .. h.ip)
		end
	end
	table.sort(out)
	return out
end

function Shell.complete(st: any, env: any, line: string): any
	local partial = ""
	if line ~= "" and string.sub(line, -1) ~= " " then
		partial = string.match(line, "(%S+)$") or ""
	end
	local before = string.sub(line, 1, #line - #partial)
	local words = {}
	for t in string.gmatch(before, "%S+") do
		table.insert(words, t)
	end
	local cands: { string }
	local noSpaceIfDir = true
	if #words == 0 then
		cands = {}
		local all = table.clone(COMMANDS)
		for _, a in { "ll", "hosts" } do
			table.insert(all, a)
		end
		if env.isNotebook then
			table.insert(all, "console")
		end
		table.sort(all)
		for _, c in all do
			if Complete.startsWith(c, partial) then
				table.insert(cands, c)
			end
		end
		if string.find(partial, "/", 1, true) then
			cands = pathCandidates(st, env, partial, false)
		end
	else
		local cmd = words[1]
		if cmd == "ssh" then
			cands = hostCandidates(env, partial, true)
			if #cands == 1 and string.sub(cands[1], -1) == "@" then
				return { line = before .. cands[1] }
			end
		elseif cmd == "telnet" or cmd == "ping" or cmd == "tracepath" or cmd == "nslookup" or cmd == "dig" or cmd == "host" then
			cands = hostCandidates(env, partial, false)
			if string.sub(partial, 1, 1) == "-" then
				cands = {}
			end
		elseif cmd == "man" then
			cands = {}
			for _, p in manPages(env) do
				if Complete.startsWith(p, partial) then
					table.insert(cands, p)
				end
			end
		elseif cmd == "ip" and #words == 1 then
			cands = {}
			for _, o in { "address", "link", "neighbour", "route" } do
				if Complete.startsWith(o, partial) then
					table.insert(cands, o)
				end
			end
		elseif cmd == "screen" or cmd == "minicom" then
			cands = pathCandidates(st, env, if partial == "" then "/dev/tty" else partial, false)
			if partial == "" then
				local base = before
				local only = {}
				for _, c in cands do
					table.insert(only, c)
				end
				if #only == 1 then
					return { line = base .. only[1] .. " " }
				elseif #only > 1 then
					return { show = Complete.columns(only) }
				end
				return {}
			end
		elseif cmd == "cd" then
			cands = pathCandidates(st, env, partial, true)
		else
			cands = pathCandidates(st, env, partial, false)
		end
	end
	if #cands == 0 then
		return {}
	end
	if #cands == 1 then
		local c = cands[1]
		local space = not (noSpaceIfDir and string.sub(c, -1) == "/")
		return { line = before .. c .. (if space then " " else "") }
	end
	local cp = Complete.commonPrefix(cands)
	if #cp > #partial then
		return { line = before .. cp }
	end
	-- o bash mostra só o nome final dos caminhos
	local shown = {}
	for _, c in cands do
		local tail = string.match(c, "([^/]+/?)$") or c
		table.insert(shown, tail)
	end
	return { show = Complete.columns(shown) }
end

return Shell
