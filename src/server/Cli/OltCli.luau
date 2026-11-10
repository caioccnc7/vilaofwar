-- Console da OLT. A sintaxe imita a das OLTs GPON mais usadas em provedores
-- (modos enable/config/interface gpon, "ont add ... sn-auth", "service-port", "display ...").

local Complete = require(script.Parent.Complete)

local OltCli = {}

OltCli.Model = "MA5800-X7"
OltCli.Brand = "Huawei"
OltCli.Version = "MA5800V100R021C10"
OltCli.LineProfile = 10
OltCli.SrvProfile = 10
OltCli.Vlan = 100
OltCli.Gemport = 1
OltCli.Ports = 8

export type Ont = { sn: string, desc: string }
export type ServicePort = { index: number, vlan: number, port: number, ont: number, gemport: number, userVlan: number }

function OltCli.factoryConfig()
	return { sysname = "MA5800-X7", onts = {}, servicePorts = {} }
end

-- ---------------------------------------------------------------------------
-- Consultas usadas pelo jogo
-- ---------------------------------------------------------------------------

function OltCli.findOnt(cfg: any, port: number, sn: string): number?
	local list = cfg.onts[port]
	if not list then
		return nil
	end
	for id, o in list do
		if o.sn == sn then
			return id
		end
	end
	return nil
end

function OltCli.hasService(cfg: any, port: number, ontId: number): boolean
	for _, sp in cfg.servicePorts do
		if sp.port == port and sp.ont == ontId and sp.vlan == OltCli.Vlan and sp.gemport == OltCli.Gemport and sp.userVlan == OltCli.Vlan then
			return true
		end
	end
	return false
end

function OltCli.addOnt(cfg: any, port: number, id: number?, sn: string, desc: string): number?
	cfg.onts[port] = cfg.onts[port] or {}
	local list = cfg.onts[port]
	if id == nil then
		id = 0
		while list[id] do
			id += 1
		end
	end
	if list[id] or (id :: number) > 127 then
		return nil
	end
	list[id :: number] = { sn = sn, desc = desc }
	return id
end

function OltCli.addServicePort(cfg: any, index: number?, vlan: number, port: number, ont: number, gemport: number, userVlan: number): number
	if index == nil then
		index = 0
		local used = {}
		for _, sp in cfg.servicePorts do
			used[sp.index] = true
		end
		while used[index] do
			index += 1
		end
	end
	table.insert(cfg.servicePorts, { index = index :: number, vlan = vlan, port = port, ont = ont, gemport = gemport, userVlan = userVlan })
	return index :: number
end

-- ---------------------------------------------------------------------------
-- Parser
-- ---------------------------------------------------------------------------

local function tokenize(line: string): { string }
	local tokens = {}
	local i, n = 1, #line
	while i <= n do
		local c = string.sub(line, i, i)
		if c == " " then
			i += 1
		elseif c == "\"" then
			local close = string.find(line, "\"", i + 1, true) or (n + 1)
			table.insert(tokens, string.sub(line, i + 1, close - 1))
			i = close + 1
		else
			local j = string.find(line, " ", i, true) or (n + 1)
			table.insert(tokens, string.sub(line, i, j - 1))
			i = j
		end
	end
	return tokens
end

-- largura do prompt da linha atual, para o ^ ficar embaixo do erro
local caretBase = 0

local function err(tokens: { string }, at: number): string
	local col = 0
	for i = 1, at - 1 do
		col += #tokens[i] + 1
	end
	return string.rep(" ", caretBase + col) .. "^\n  % Unknown command, the error locates at '^'"
end

local function pad(s: any, w: number): string
	s = tostring(s)
	if #s >= w then
		return s .. " "
	end
	return s .. string.rep(" ", w - #s)
end

local DASH = "  " .. string.rep("-", 72)

local function ontInfoTable(cfg: any, port: number, env: any, only: number?): string
	local list = cfg.onts[port] or {}
	local ids = {}
	for id in list do
		if only == nil or id == only then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	if #ids == 0 then
		return "  Failure: There is not any ONT available"
	end
	local out = { DASH, "  F/S/P   ONT  SN                Control     Run      Config   Match    Desc", "          ID                     flag        state    state    state", DASH }
	local online = 0
	for _, id in ids do
		local o = list[id]
		local st = env.ontState(port, o.sn)
		if st.run == "online" then
			online += 1
		end
		table.insert(out, string.format("  0/1/%d   %s %s active      %s %s %s %s", port, pad(id, 4), pad(o.sn, 17), pad(st.run, 8), pad(if st.run == "online" then "normal" else "initial", 8), pad(if st.run == "online" then "match" else "initial", 8), o.desc))
	end
	table.insert(out, DASH)
	table.insert(out, string.format("  In port 0/1/%d, the total of ONTs are: %d, online: %d", port, #ids, online))
	table.insert(out, DASH)
	return table.concat(out, "\n")
end

local function autofindTable(env: any, port: number?): string
	local list = env.autofind(port)
	if #list == 0 then
		return "  Failure: The automatically found ONTs do not exist"
	end
	local out = {}
	for i, a in list do
		table.insert(out, DASH)
		table.insert(out, "  Number              : " .. i)
		table.insert(out, "  F/S/P               : 0/1/" .. a.port)
		table.insert(out, "  Ont SN              : " .. a.sn)
		table.insert(out, "  VendorID            : " .. string.sub(a.sn, 1, 4))
		table.insert(out, "  Ont EquipmentID     : LM-ONU-110")
		table.insert(out, "  Ont autofind time   : " .. a.time)
	end
	table.insert(out, DASH)
	table.insert(out, "  The number of GPON autofind ONT is " .. #list)
	table.insert(out, DASH)
	return table.concat(out, "\n")
end

local function servicePortTable(cfg: any): string
	if #cfg.servicePorts == 0 then
		return "  Failure: No service virtual port can be operated"
	end
	local out = { DASH, "   INDEX VLAN  PORT    F/S/P   VPI  VCI   FLOW  RX  TX  STATE", DASH }
	table.sort(cfg.servicePorts, function(a, b)
		return a.index < b.index
	end)
	for _, sp in cfg.servicePorts do
		table.insert(out, string.format("   %s %s gpon    0/1/%d   %d    %d     vlan  -   -   up", pad(sp.index, 5), pad(sp.vlan, 5), sp.port, sp.ont, sp.gemport))
	end
	table.insert(out, DASH)
	table.insert(out, "   Total : " .. #cfg.servicePorts)
	return table.concat(out, "\n")
end

local function find(tokens: { string }, word: string): number?
	for i, t in tokens do
		if t == word then
			return i
		end
	end
	return nil
end

-- service-port [index] vlan V gpon 0/1/P ont O gemport G multi-service user-vlan U [tag-transform translate]
local function servicePortCmd(cfg: any, tokens: { string }): string
	local idx = nil
	local vi = find(tokens, "vlan")
	if not vi then
		return err(tokens, 2)
	end
	if vi == 3 then
		idx = tonumber(tokens[2])
	end
	local vlan = tonumber(tokens[vi + 1] or "")
	local gi = find(tokens, "gpon")
	local fsp = gi and tokens[gi + 1] or ""
	local port = tonumber(string.match(fsp, "^0/1/(%d+)$") or "")
	local oi = find(tokens, "ont")
	local ont = oi and tonumber(tokens[oi + 1] or "")
	local gpi = find(tokens, "gemport")
	local gem = gpi and tonumber(tokens[gpi + 1] or "")
	local ui = find(tokens, "user-vlan")
	local uvlan = ui and tonumber(tokens[ui + 1] or "")
	if not (vlan and port and ont and gem) then
		return "  % Incomplete command\n  Ex.: service-port vlan 100 gpon 0/1/0 ont 3 gemport 1 multi-service user-vlan 100 tag-transform translate"
	end
	if not find(tokens, "multi-service") or not uvlan then
		return "  % Incomplete command (faltou: multi-service user-vlan <vlan>)"
	end
	if vlan ~= OltCli.Vlan then
		return "  Failure: The VLAN does not exist"
	end
	if not (cfg.onts[port] and cfg.onts[port][ont]) then
		return "  Failure: The ONT does not exist"
	end
	for _, sp in cfg.servicePorts do
		if idx ~= nil and sp.index == idx then
			return "  Failure: The service virtual port index has existed"
		end
	end
	OltCli.addServicePort(cfg, idx, vlan :: number, port :: number, ont :: number, gem :: number, uvlan :: number)
	return ""
end

-- ---------------------------------------------------------------------------
-- Árvore de comandos (abreviação, TAB e "?"), com as descrições em inglês como no equipamento
-- ---------------------------------------------------------------------------

local CR = { cr = true }
local function K(w: string, d: string, n: any?): any
	return { w = w, d = d, n = n or CR }
end
local function A(name: string, d: string, n: any?, opts: any?): any
	local a = { name = name, d = d, n = n or CR }
	if opts then
		for k, v in opts do
			a[k] = v
		end
	end
	return a
end

-- ont add <portid> [<ontid>] sn-auth <sn> omci ont-lineprofile-id <id> ont-srvprofile-id <id> [desc <text>]
local ontAddTail = { kw = { K("desc", "Describe the ONT", { arg = A("<desc>", "STRING<1-64> ONT description") }) }, cr = true }
local ontAddSrv = { kw = { K("ont-srvprofile-id", "ONT service profile ID", { arg = A("<profile-id>", "INTEGER<0-8192> Profile ID", ontAddTail, { num = true }) }) } }
local ontAddLine = { kw = { K("ont-lineprofile-id", "ONT line profile ID", { arg = A("<profile-id>", "INTEGER<0-8192> Profile ID", ontAddSrv, { num = true }) }) } }
local ontAddSn = { kw = { K("sn-auth", "SN authentication", { arg = A("<sn>", "STRING<12-16> ONT serial number", { kw = { K("omci", "OMCI management mode", ontAddLine) } }) }) } }
local ontAddPort = {
	kw = ontAddSn.kw,
	arg = A("<ontid>", "INTEGER<0-127> ONT ID", ontAddSn, { num = true }),
}

-- service-port [<index>] vlan <vlanid> gpon <F/S/P> ont <ontid> gemport <id> multi-service user-vlan <vlan> [tag-transform translate]
local spTail = { kw = { K("tag-transform", "Tag transform", { kw = { K("translate", "Translate the VLAN tag") } }) }, cr = true }
local spUser = { kw = { K("multi-service", "Multi-service mode", { kw = { K("user-vlan", "User VLAN", { arg = A("<vlanid>", "INTEGER<1-4095> User VLAN ID", spTail, { num = true }) }) } }) } }
local spGem = { kw = { K("gemport", "GEM port index", { arg = A("<gemport>", "INTEGER<0-1023> GEM port index", spUser, { num = true }) }) } }
local spOnt = { kw = { K("ont", "ONT", { arg = A("<ontid>", "INTEGER<0-127> ONT ID", spGem, { num = true }) }) } }
local spVlan = { kw = { K("vlan", "VLAN", { arg = A("<vlanid>", "INTEGER<1-4093> VLAN ID", { kw = { K("gpon", "GPON port", { arg = A("<F/S/P>", "Frame/Slot/Port", spOnt, { pattern = "^%d+/%d+/%d+$" }) }) } }, { num = true }) }) } }
local servicePortNode = { kw = spVlan.kw, arg = A("<index>", "INTEGER<0-65534> Service virtual port index", spVlan, { num = true }) }

local displayCommon = {
	K("version", "Display system version"),
	K("board", "Display board information", { arg = A("<frameid>", "INTEGER<0-0> Frame ID", nil, { num = true }) }),
}

local function displayNode(extra: { any }): any
	local list = table.clone(displayCommon)
	for _, e in extra do
		table.insert(list, e)
	end
	table.sort(list, function(a, b)
		return a.w < b.w
	end)
	return { kw = list }
end

-- consultas de config: valem também nos modos usuário (>) e privilegiado (#), como na OLT real
local cfgDisplay = displayNode({
	K("current-configuration", "Display current configuration"),
	K("ont", "ONT information", {
		kw = {
			K("autofind", "Display the automatically found ONTs", { kw = { K("all", "All ports") } }),
			K("info", "Display ONT information", {
				kw = { K("by-sn", "Query by SN", { arg = A("<sn>", "STRING<12-16> ONT serial number") }) },
				arg = A("<frameid>", "INTEGER<0-0> Frame ID", {
					arg = A("<slotid>", "INTEGER<0-17> Slot ID", {
						arg = A("<portid>", "INTEGER<0-7> Port ID", {
							kw = { K("all", "All ONTs") },
							arg = A("<ontid>", "INTEGER<0-127> ONT ID", nil, { num = true }),
						}, { num = true }),
					}, { num = true }),
				}, { num = true }),
			}),
		},
	}),
	K("ont-lineprofile", "ONT line profile", { kw = { K("gpon", "GPON", { kw = { K("all", "All profiles") } }) } }),
	K("ont-srvprofile", "ONT service profile", { kw = { K("gpon", "GPON", { kw = { K("all", "All profiles") } }) } }),
	K("service-port", "Service virtual port", { kw = { K("all", "All service virtual ports") }, arg = A("<index>", "INTEGER<0-65534> Index", nil, { num = true }) }),
})

local Tree = {}
Tree.user = {
	kw = {
		K("display", "Display information", cfgDisplay),
		K("enable", "Turn on privileged mode command"),
		K("quit", "Exit from current mode and enter prior mode"),
	},
}
Tree.enable = {
	kw = {
		K("config", "Enter the configuration mode"),
		K("display", "Display information", cfgDisplay),
		K("quit", "Exit from current mode and enter prior mode"),
		K("save", "Save current configuration"),
	},
}
Tree.config = {
	kw = {
		K("display", "Display information", cfgDisplay),
		K("interface", "Enter an interface view", { kw = { K("gpon", "GPON interface", { arg = A("<frameid/slotid>", "Frame/Slot, ex.: 0/1", nil, { pattern = "^%d+/%d+$" }) }) } }),
		K("quit", "Exit from current mode and enter prior mode"),
		K("return", "Return to privileged mode"),
		K("save", "Save current configuration"),
		K("service-port", "Create a service virtual port", servicePortNode),
		K("sysname", "Set the host name", { arg = A("<name>", "STRING<1-64> Host name") }),
		K("undo", "Negate a command or set its default", { kw = { K("service-port", "Delete a service virtual port", { arg = A("<index>", "INTEGER<0-65534> Index", nil, { num = true }) }) } }),
	},
}
Tree.gpon = {
	kw = {
		K("display", "Display information", displayNode({
			K("ont", "ONT information", {
				kw = {
					K("autofind", "Display the automatically found ONTs", { kw = { K("all", "All ports") }, arg = A("<portid>", "INTEGER<0-7> Port ID", nil, { num = true }) }),
					K("info", "Display ONT information", {
						arg = A("<portid>", "INTEGER<0-7> Port ID", { kw = { K("all", "All ONTs") }, arg = A("<ontid>", "INTEGER<0-127> ONT ID", nil, { num = true }) }, { num = true }),
					}),
					K("optical-info", "Display ONT optical information", {
						arg = A("<portid>", "INTEGER<0-7> Port ID", { arg = A("<ontid>", "INTEGER<0-127> ONT ID", nil, { num = true }) }, { num = true }),
					}),
				},
			}),
		})),
		K("ont", "ONT configuration", {
			kw = {
				K("add", "Add an ONT", { arg = A("<portid>", "INTEGER<0-7> Port ID", ontAddPort, { num = true }) }),
				K("delete", "Delete an ONT", { arg = A("<portid>", "INTEGER<0-7> Port ID", { arg = A("<ontid>", "INTEGER<0-127> ONT ID", nil, { num = true }) }, { num = true }) }),
				K("modify", "Modify ONT parameters", {
					arg = A("<portid>", "INTEGER<0-7> Port ID", {
						arg = A("<ontid>", "INTEGER<0-127> ONT ID", { kw = { K("sn", "Serial number", { arg = A("<sn>", "STRING<12-16> New serial number") }) } }, { num = true }),
					}, { num = true }),
				}),
			},
		}),
		K("quit", "Exit from current mode and enter prior mode"),
		K("return", "Return to privileged mode"),
	},
}

local function errAt(line: string, idx: number, kind: string?): string
	local col = caretBase + Complete.column(line, idx) - 1
	local msg = if kind == "ambiguous" then "% Ambiguous command, the error locates at '^'" elseif kind == "param" then "% Parameter error, the error locates at '^'" else "% Unknown command, the error locates at '^'"
	return string.rep(" ", col) .. "^\n  " .. msg
end

-- lista no formato do "?" da Huawei
local function helpList(entries: { any }, arg: any, cr: boolean): string
	local out = {}
	for _, e in entries do
		table.insert(out, "  " .. e.w .. string.rep(" ", math.max(2, 24 - #e.w)) .. (e.d or ""))
	end
	if arg then
		table.insert(out, "  " .. arg.name .. string.rep(" ", math.max(2, 24 - #arg.name)) .. (arg.d or ""))
	end
	if cr then
		table.insert(out, "  <cr>")
	end
	return table.concat(out, "\n")
end

-- "?" no fim da linha: "display ?" lista o próximo nível, "dis?" lista o que começa com "dis"
local function questionHelp(mode: string, line: string): string
	local body = string.sub(line, 1, #line - 1)
	local tokens = Complete.tokens(body)
	local partial = ""
	if body ~= "" and string.sub(body, -1) ~= " " then
		partial = table.remove(tokens) :: string
	end
	local node, _, bad, kind = Complete.walk(Tree[mode], tokens)
	if bad then
		return errAt(body, bad, kind)
	end
	local list, arg = Complete.candidates(node, partial)
	if #list == 0 and not arg and not (partial == "" and node.cr) then
		return errAt(body .. "x", #tokens + 1, "unknown")
	end
	return helpList(list, if partial == "" then arg else nil, partial == "" and node.cr == true)
end

-- TAB: completa a palavra ou lista as parecidas
function OltCli.complete(_cfg: any, session: any, line: string): any
	local tokens = Complete.tokens(line)
	local partial = ""
	if line ~= "" and string.sub(line, -1) ~= " " then
		partial = table.remove(tokens) :: string
	end
	local node, _, bad = Complete.walk(Tree[session.mode] or Tree.user, tokens)
	if bad or not node then
		return {}
	end
	local list, arg = Complete.candidates(node, partial)
	local words = {}
	for _, e in list do
		table.insert(words, e.w)
	end
	if #words == 0 then
		if arg and partial == "" then
			return { show = helpList({}, arg, node.cr == true) }
		end
		return {}
	end
	if arg and partial == "" then
		return { show = helpList(list, arg, node.cr == true) }
	end
	local newLine, many = Complete.decide(line, partial, words)
	if newLine then
		return { line = newLine }
	end
	local shown = {}
	for _, e in list do
		if table.find(many :: { string }, e.w) then
			table.insert(shown, e)
		end
	end
	return { show = helpList(shown, nil, false) }
end

local HELP = {
	user = table.concat({
		"  display ont autofind all          ONUs novas aguardando autorização",
		"  display ont info 0 1 <porta> all  ONUs cadastradas numa porta",
		"  display service-port all          Serviços (VLAN) das ONUs",
		"  display version                   Versão do sistema",
		"  enable                            Entrar no modo privilegiado (para configurar)",
		"  quit                              Sair",
		"  Para autorizar ONU: enable, config, interface gpon 0/1",
	}, "\n"),
	enable = table.concat({
		"  config                            Entrar no modo de configuração",
		"  display ont autofind all          ONUs novas aguardando autorização",
		"  display ont info 0 1 <porta> all  ONUs cadastradas numa porta",
		"  display service-port all",
		"  display board 0                   Placas instaladas",
		"  save                              Salvar configuração",
		"  quit",
	}, "\n"),
	config = table.concat({
		"  interface gpon 0/1                         Entrar na placa GPON",
		"  display ont autofind all                   ONUs novas aguardando autorização",
		"  display ont info 0 1 <porta> all           ONUs cadastradas numa porta",
		"  display ont-lineprofile gpon all           Perfis de linha",
		"  service-port vlan 100 gpon 0/1/<porta> ont <id> gemport 1 multi-service user-vlan 100 tag-transform translate",
		"  display service-port all",
		"  undo service-port <index>",
		"  sysname <nome>",
		"  save / quit",
	}, "\n"),
	gpon = table.concat({
		"  display ont autofind <porta>",
		"  ont add <porta> sn-auth <SN> omci ont-lineprofile-id 10 ont-srvprofile-id 10 desc \"casa7\"",
		"  ont add <porta> <id> sn-auth <SN> omci ont-lineprofile-id 10 ont-srvprofile-id 10",
		"  ont modify <porta> <id> sn <SN-novo>",
		"  ont delete <porta> <id>",
		"  display ont info <porta> all | display ont info <porta> <id>",
		"  display ont optical-info <porta> <id>",
		"  quit",
	}, "\n"),
}

-- consultas do modo config (também aceitas em > e #). nil = não é uma delas
local function configDisplay(cfg: any, tokens: { string }, line: string, env: any): string?
	local cmd = tokens[1]
	if cmd == "display" and tokens[2] == "ont" and tokens[3] == "autofind" then
		return autofindTable(env, nil)
	elseif cmd == "display" and tokens[2] == "ont" and tokens[3] == "info" and tokens[4] ~= "by-sn" then
		-- display ont info 0 1 <porta> all|<id>
		local port = tonumber(tokens[6] or "")
		if tokens[4] ~= "0" or tokens[5] ~= "1" or not port then
			return "  % Parameter error. Ex.: display ont info 0 1 0 all"
		end
		return ontInfoTable(cfg, port, env, tonumber(tokens[7] or ""))
	elseif cmd == "display" and tokens[2] == "ont" and tokens[3] == "info" and tokens[4] == "by-sn" then
		local sn = string.upper(tokens[5] or "")
		for port = 0, OltCli.Ports - 1 do
			local id = OltCli.findOnt(cfg, port, sn)
			if id then
				local st = env.ontState(port, sn)
				return table.concat({
					DASH,
					"  F/S/P                   : 0/1/" .. port,
					"  ONT-ID                  : " .. id,
					"  Control flag            : active",
					"  Run state               : " .. st.run,
					"  Config state            : " .. (if st.run == "online" then "normal" else "initial"),
					"  Match state             : " .. (if st.run == "online" then "match" else "initial"),
					"  SN                      : " .. sn,
					"  Description             : " .. cfg.onts[port][id].desc,
					"  Line profile ID         : " .. OltCli.LineProfile,
					"  Service profile ID      : " .. OltCli.SrvProfile,
					DASH,
				}, "\n")
			end
		end
		return "  Failure: The ONT does not exist"
	elseif cmd == "display" and tokens[2] == "ont-srvprofile" then
		return DASH .. "\n  Profile-ID  Profile-name                    Binding times\n" .. DASH .. "\n  10          FTTH-VILA-SRV                   -\n" .. DASH
	elseif cmd == "display" and tokens[2] == "ont-lineprofile" then
		return DASH .. "\n  Profile-ID  Profile-name                    Binding times\n" .. DASH .. "\n  10          FTTH-VILA                       " .. "-\n" .. DASH
	elseif cmd == "display" and tokens[2] == "service-port" then
		return servicePortTable(cfg)
	elseif line == "display current-configuration" then
		local out = { "  #", "  sysname " .. cfg.sysname, "  #", "  interface gpon 0/1" }
		for port = 0, OltCli.Ports - 1 do
			local list = cfg.onts[port]
			if list then
				local ids = {}
				for id in list do
					table.insert(ids, id)
				end
				table.sort(ids)
				for _, id in ids do
					table.insert(out, string.format("   ont add %d %d sn-auth \"%s\" omci ont-lineprofile-id 10 ont-srvprofile-id 10 desc \"%s\"", port, id, list[id].sn, list[id].desc))
				end
			end
		end
		table.insert(out, "  #")
		for _, sp in cfg.servicePorts do
			table.insert(out, string.format("  service-port %d vlan %d gpon 0/1/%d ont %d gemport %d multi-service user-vlan %d tag-transform translate", sp.index, sp.vlan, sp.port, sp.ont, sp.gemport, sp.userVlan))
		end
		table.insert(out, "  #\n  return")
		return table.concat(out, "\n")
	end
	return nil
end

-- Comando certo no modo errado ("ont add" no >, "service-port" dentro da placa):
-- em vez de só "Unknown command", diz em que modo ele roda e o caminho até lá
local ModeName = {
	user = "usuário (>)",
	enable = "privilegiado (#)",
	config = "configuração ((config)#)",
	gpon = "placa GPON ((config-if-gpon-0/1)#)",
}
local ModeDepth = { user = 1, enable = 2, config = 3, gpon = 4 }
local ModeStep = { "enable", "config", "interface gpon 0/1" }

local function pathTo(from: string, to: string): string
	local a, b = ModeDepth[from], ModeDepth[to]
	local steps = {}
	if b > a then
		for i = a, b - 1 do
			table.insert(steps, ModeStep[i])
		end
	else
		if to == "enable" and a >= 3 then
			return "return"
		end
		for _ = b, a - 1 do
			table.insert(steps, "quit")
		end
	end
	return table.concat(steps, ", ")
end

local function wrongMode(cfg: any, mode: string, raw: { string }): string?
	if #raw == 0 then
		return nil
	end
	for _, other in { "gpon", "config", "enable" } do
		if other ~= mode and Tree[other] then
			local _, _, bad = Complete.walk(Tree[other], raw)
			if not bad then
				return string.format(
					"  %% Esse comando não existe no modo %s.\n  Ele roda no modo %s. Digite, um por linha: %s\n  (O prompt mostra o modo: %s> usuário, %s# privilegiado, %s(config)# configuração, %s(config-if-gpon-0/1)# placa.)",
					ModeName[mode],
					ModeName[other],
					pathTo(mode, other),
					cfg.sysname,
					cfg.sysname,
					cfg.sysname,
					cfg.sysname
				)
			end
		end
	end
	return nil
end

local runInner

-- env = { autofind = fn(port?) -> list, ontState = fn(port, sn) -> {run, rx}, uptime }
function OltCli.run(cfg: any, session: any, line: string, env: any): string
	caretBase = #OltCli.prompt(cfg, session) + #(string.match(line, "^%s*") or "")
	local out = runInner(cfg, session, line, env)
	-- comando que parou no meio ("display ont"): a OLT avisa que está incompleto
	if string.find(out, "Unknown command", 1, true) then
		local clean = string.gsub(string.gsub(line, "^%s+", ""), "%s+$", "")
		local node = Complete.walk(Tree[session.mode] or Tree.user, Complete.tokens(clean))
		if node and not node.cr then
			return string.rep(" ", caretBase + #clean + 1) .. "^\n  % Incomplete command, the error locates at '^'"
		end
	end
	return out
end

function runInner(cfg: any, session: any, line: string, env: any): string
	line = string.gsub(line, "^%s+", "")
	line = string.gsub(line, "%s+$", "")
	if line == "" then
		return ""
	end
	local mode = session.mode
	if line == "help" then
		return HELP[mode] or ""
	end
	if string.sub(line, -1) == "?" then
		return questionHelp(mode, line)
	end
	-- abreviações: "disp ont autof all" vira "display ont autofind all"
	local raw = Complete.tokens(line)
	local _, full, bad, kind = Complete.walk(Tree[mode] or Tree.user, raw)
	if bad then
		return wrongMode(cfg, mode, raw) or errAt(line, bad, kind)
	end
	line = table.concat(full, " ")
	local tokens = tokenize(line)
	local cmd = tokens[1]
	if cmd == "return" then
		if mode == "config" or mode == "gpon" then
			session.mode = "enable"
		end
		return ""
	end
	if cmd == "quit" then
		if mode == "gpon" then
			session.mode = "config"
		elseif mode == "config" then
			session.mode = "enable"
		elseif mode == "enable" then
			session.mode = "user"
		else
			return "  Check whether system data has been changed. Please save data before logout.\n  Configuration console exit, please retry to log on"
		end
		return ""
	end
	if line == "display version" then
		return string.format("  %s %s\n  VERSION : %s\n  PRODUCT : %s\n  Uptime is %s", OltCli.Brand, OltCli.Model, OltCli.Version, OltCli.Model, env.uptime or "0 day(s), 1 hour(s)")
	end
	if cmd == "save" and mode ~= "user" then
		return "  { <cr>|configuration<K>|data<K> }:\n  Command:\n          save\n  The data of the configuration is saved successfully"
	end

	if (mode == "user" or mode == "enable") and cmd == "display" and tokens[2] ~= "board" then
		return configDisplay(cfg, tokens, line, env) or err(tokens, 1)
	end

	if cmd == "display" and tokens[2] == "board" then
		if tokens[3] ~= "0" then
			return "  % Parameter error, the error locates at '^' (o chassi é o frame 0: display board 0)"
		end
		return table.concat({
			DASH,
			"  SlotID  BoardName  Status          SubType0 SubType1    Online/Offline",
			DASH,
			"  0",
			"  1       H901GPHF   Normal",
			"  2",
			"  8       H901MPLA   Active_normal",
			"  10      H901PILA   Normal",
			DASH,
		}, "\n")
	end

	if mode == "user" then
		if cmd == "enable" then
			session.mode = "enable"
			return ""
		end
		return err(tokens, 1)
	end


	if mode == "enable" then
		if cmd == "config" then
			session.mode = "config"
			return ""
		end
		return err(tokens, 1)
	end

	if mode == "config" then
		if cmd == "interface" and tokens[2] == "gpon" then
			if tokens[3] ~= "0/1" then
				return "  Failure: The board does not exist (a placa GPON está no slot 0/1)"
			end
			session.mode = "gpon"
			return ""
		elseif cmd == "sysname" and tokens[2] then
			cfg.sysname = tokens[2]
			return ""
		elseif cmd == "display" then
			local out = configDisplay(cfg, tokens, line, env)
			if out then
				return out
			end
		elseif cmd == "service-port" then
			return servicePortCmd(cfg, tokens)
		elseif cmd == "undo" and tokens[2] == "service-port" then
			local index = tonumber(tokens[3] or "")
			for i, sp in cfg.servicePorts do
				if sp.index == index then
					table.remove(cfg.servicePorts, i)
					return ""
				end
			end
			return "  Failure: The service virtual port does not exist"
		end
		return err(tokens, 1)
	end

	if mode == "gpon" then
		if cmd == "display" and tokens[2] == "ont" and tokens[3] == "autofind" then
			return autofindTable(env, tonumber(tokens[4] or ""))
		elseif cmd == "display" and tokens[2] == "ont" and tokens[3] == "info" then
			local port = tonumber(tokens[4] or "")
			if not port then
				return "  % Parameter error. Ex.: display ont info 0 all"
			end
			return ontInfoTable(cfg, port, env, tonumber(tokens[5] or ""))
		elseif cmd == "display" and tokens[2] == "ont" and tokens[3] == "optical-info" then
			local port, id = tonumber(tokens[4] or ""), tonumber(tokens[5] or "")
			local o = port and id and cfg.onts[port] and cfg.onts[port][id]
			if not o then
				return "  Failure: The ONT does not exist"
			end
			local st = env.ontState(port, o.sn)
			if st.run ~= "online" or not st.rx then
				return "  Failure: The ONT is not online"
			end
			return string.format("  %s\n  ONU NNI port ID       : 0\n  Rx optical power(dBm) : %.2f\n  Tx optical power(dBm) : 2.13\n  OLT Rx ONT optical power(dBm) : %.2f\n  Temperature(C)        : 41\n  %s", string.rep("-", 50), st.rx, st.rx - 3.1, string.rep("-", 50))
		elseif cmd == "ont" and tokens[2] == "add" then
			local port = tonumber(tokens[3] or "")
			if not port or port >= OltCli.Ports then
				return "  % Parameter error, the error locates at port"
			end
			local si = find(tokens, "sn-auth")
			if not si or not tokens[si + 1] then
				return "  % Incomplete command (faltou: sn-auth <SN>)"
			end
			local explicitId = if si == 5 then tonumber(tokens[4]) else nil
			local sn = string.upper(tokens[si + 1])
			if not find(tokens, "omci") then
				return "  % Incomplete command (faltou: omci ont-lineprofile-id 10 ont-srvprofile-id 10)"
			end
			local li = find(tokens, "ont-lineprofile-id")
			local ri = find(tokens, "ont-srvprofile-id")
			if not li or not ri then
				return "  % Incomplete command (faltou: ont-lineprofile-id / ont-srvprofile-id)"
			end
			if tonumber(tokens[li + 1] or "") ~= OltCli.LineProfile then
				return "  Failure: The line profile does not exist"
			end
			if tonumber(tokens[ri + 1] or "") ~= OltCli.SrvProfile then
				return "  Failure: The service profile does not exist"
			end
			for p, list in cfg.onts do
				for _, o in list do
					if o.sn == sn then
						return "  Failure: SN already exists (porta " .. p .. ")"
					end
				end
			end
			local di = find(tokens, "desc")
			local desc = if di then (tokens[di + 1] or "") else ""
			local id = OltCli.addOnt(cfg, port, explicitId, sn, desc)
			if not id then
				return "  Failure: The ONT ID has already existed"
			end
			return string.format("  Number of ONTs that can be added: 1, success: 1\n  PortID :%d, ONTID :%d", port, id)
		elseif cmd == "ont" and tokens[2] == "delete" then
			local port, id = tonumber(tokens[3] or ""), tonumber(tokens[4] or "")
			if not (port and id and cfg.onts[port] and cfg.onts[port][id]) then
				return "  Failure: The ONT does not exist"
			end
			for _, sp in cfg.servicePorts do
				if sp.port == port and sp.ont == id then
					return "  Failure: This configured object has some service virtual ports (apague com undo service-port " .. sp.index .. ")"
				end
			end
			cfg.onts[port][id] = nil
			return "  Number of ONTs that can be deleted: 1, success: 1"
		elseif cmd == "ont" and tokens[2] == "modify" then
			local port, id = tonumber(tokens[3] or ""), tonumber(tokens[4] or "")
			local si = find(tokens, "sn")
			if not (port and id and cfg.onts[port] and cfg.onts[port][id]) then
				return "  Failure: The ONT does not exist"
			end
			if not si or not tokens[si + 1] then
				return "  % Incomplete command (ex.: ont modify 0 3 sn HWTC1A2B3C4D)"
			end
			cfg.onts[port][id].sn = string.upper(tokens[si + 1])
			return ""
		end
		return err(tokens, 1)
	end
	return err(tokens, 1)
end

function OltCli.prompt(cfg: any, session: any): string
	local m = session.mode
	if m == "user" then
		return cfg.sysname .. ">"
	elseif m == "enable" then
		return cfg.sysname .. "#"
	elseif m == "config" then
		return cfg.sysname .. "(config)#"
	end
	return cfg.sysname .. "(config-if-gpon-0/1)#"
end

function OltCli.banner(_cfg: any): string
	return table.concat({
		"  " .. OltCli.Brand .. " " .. OltCli.Model .. "  " .. OltCli.Version,
		"  Huawei Integrated Access Software (MA5800).",
		"  Equipamento simulado para fins didáticos.",
		"",
		"  Digite ? ou help em qualquer modo para ajuda.",
		"  Consultas (display ...) funcionam em qualquer modo.",
		"  Para configurar: enable, depois config (e interface gpon 0/1 para as ONUs).",
		"",
	}, "\n")
end

return OltCli
