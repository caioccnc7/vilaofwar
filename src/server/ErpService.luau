-- ERP do provedor: ordens de serviço (OS), agenda dos técnicos, atendente do balcão,
-- receitas e despesas e estoque. Cada provedor tem o seu (ErpModule.new(P, world, net)).
--
-- Fluxo de uma instalação:
--   1. O morador escolhe o provedor (o mais barato que ele aceita) e vai até a recepção
--      pedir a internet: abre uma OS de instalação "aguardando agendamento".
--   2. A atendente (se contratada e no expediente) registra e agenda a OS. Sem atendente,
--      quem agenda é o jogador, pelo ERP (tecla O, botão ERP ou computador do balcão).
--   3. A OS agendada vai para a fila do técnico com menos serviço. Sem técnico, ela fica
--      com a equipe (os jogadores fazem com a Máquina de Fusão na caixa da casa).
--   4. O técnico vê a fila no celular (ERP), vai até a casa, instala e encerra a OS.
-- Os reparos seguem o mesmo caminho: o cliente sem internet liga (chamado) e vira OS.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local World = require(script.Parent.WorldBuilder)
local Looks = require(script.Parent.Looks)
local Providers = require(script.Parent.Providers)
local OltCli = require(script.Parent.Cli.OltCli)

local ErpModule = {}

local KindText = { instalacao = "Instalação", reparo = "Reparo" }
local StatusText = {
	pendente = "aguardando agendamento",
	agendada = "agendada",
	execucao = "em execução",
	concluida = "concluída",
	cancelada = "cancelada",
}
local OriginText = { balcao = "no balcão", telefone = "por telefone", erp = "pelo ERP" }

local function residentName(index: number): string
	local ok, Residents = pcall(require, script.Parent.ResidentService)
	local r = ok and Residents.list and Residents.list[index]
	if r and r.index == index then
		return r.name
	end
	-- prédio público (licitação): o nome do órgão
	local okNet, Net = pcall(require, script.Parent.NetworkService)
	local h = okNet and Net.houses and Net.houses[index]
	if h and h.house.label then
		return h.house.label
	end
	return "Casa " .. index
end

function ErpModule.new(P: any, worldData: any, netService: any): any
	local Erp = {}
	local net: any = netService
	local game_: any = P.game
	local isp = worldData.isps[P.slot]
	local A = Config.Attendant
	local tech: any = nil -- TechService do provedor (ligado pelo Main)

	Erp.orders = {} :: { any } -- OS abertas e as últimas encerradas, em ordem de abertura
	local nextId = 0
	local ticketed: { [number]: boolean } = {} -- chamado atual da casa já virou OS
	local viewers: { [Player]: boolean } = {} -- quem está com o ERP aberto
	local closedToday = 0
	local conns: { RBXScriptConnection } = {}

	local runtime = Instance.new("Folder")
	runtime.Name = "ERP"
	runtime.Parent = isp.model

	local function stamp(): string
		return string.format("Dia %d %s", game_.day, game_.clockText())
	end

	local function isOpen(o: any): boolean
		return o.status == "pendente" or o.status == "agendada" or o.status == "execucao"
	end

	function Erp.statusText(o: any): string
		local t = StatusText[o.status] or o.status
		if o.techName and (o.status == "agendada" or o.status == "execucao") then
			t ..= " · " .. o.techName
		end
		return t
	end

	local function findOpen(kind: string, index: number): any
		for _, o in Erp.orders do
			if o.kind == kind and o.index == index and isOpen(o) then
				return o
			end
		end
		return nil
	end

	function Erp.openInstallFor(index: number): any
		return findOpen("instalacao", index)
	end

	function Erp.openRepairFor(index: number): any
		return findOpen("reparo", index)
	end

	function Erp.byId(id: number): any
		for _, o in Erp.orders do
			if o.id == id then
				return o
			end
		end
		return nil
	end

	-- só guarda as últimas OS encerradas
	local function prune()
		local closed = 0
		for i = #Erp.orders, 1, -1 do
			local o = Erp.orders[i]
			if not isOpen(o) then
				closed += 1
				if closed > Config.Erp.KeepClosed then
					table.remove(Erp.orders, i)
				end
			end
		end
	end

	local function newOrder(kind: string, index: number, origin: string): any
		nextId += 1
		local o = {
			id = nextId,
			kind = kind,
			index = index,
			client = residentName(index),
			status = "pendente",
			origin = origin,
			opened = stamp(),
			scheduled = nil,
			closed = nil,
			by = nil,
			techId = nil,
			techName = nil,
			note = "",
		}
		table.insert(Erp.orders, o)
		net.addAlarm(P.slot, "ERP", string.format("OS #%d aberta %s: %s da casa %d (%s)", o.id, OriginText[origin] or "", string.lower(KindText[kind]), index, o.client), if kind == "reparo" then "warning" else "ok")
		return o
	end

	local function close(o: any, status: string, note: string?)
		if not isOpen(o) then
			return
		end
		o.status = status
		o.closed = stamp()
		o.note = note or o.note
		if status == "concluida" then
			closedToday += 1
		end
		prune()
	end

	function Erp.finish(o: any, note: string?)
		close(o, "concluida", note)
	end

	function Erp.cancel(o: any, note: string?)
		close(o, "cancelada", note)
	end

	-- ---------------------------------------------------------------------------
	-- Agenda: cada OS agendada vai para o técnico com menos serviço
	-- ---------------------------------------------------------------------------

	local function teamMember(id: number?): any
		if not tech or not id then
			return nil
		end
		for _, m in tech.team do
			if m.id == id and m.active then
				return m
			end
		end
		return nil
	end

	local function loadOf(id: number): number
		local n = 0
		for _, o in Erp.orders do
			if o.techId == id and (o.status == "agendada" or o.status == "execucao") then
				n += 1
			end
		end
		return n
	end

	local function leastBusy(): any
		if not tech then
			return nil
		end
		local best, bestN = nil, math.huge
		for _, m in tech.team do
			if m.active then
				local n = loadOf(m.id)
				if n < bestN then
					best, bestN = m, n
				end
			end
		end
		return best
	end

	local function assign(o: any)
		local m = leastBusy()
		o.techId = if m then m.id else nil
		o.techName = if m then m.name else nil
	end

	function Erp.schedule(o: any, by: string): boolean
		if not o or o.status ~= "pendente" then
			return false
		end
		o.status = "agendada"
		o.scheduled = stamp()
		o.by = by
		assign(o)
		net.addAlarm(P.slot, "ERP", string.format("OS #%d agendada por %s: %s da casa %d%s", o.id, by, string.lower(KindText[o.kind]), o.index, if o.techName then " · " .. o.techName else " · sem técnico, fica com a equipe"), "ok")
		return true
	end

	-- Fila do técnico no celular: a OS em execução primeiro, depois reparos, depois instalações
	function Erp.queueOf(techId: number): { any }
		local out = {}
		for _, o in Erp.orders do
			if o.techId == techId and (o.status == "agendada" or o.status == "execucao") then
				table.insert(out, o)
			end
		end
		table.sort(out, function(a, b)
			if (a.status == "execucao") ~= (b.status == "execucao") then
				return a.status == "execucao"
			end
			if a.kind ~= b.kind then
				return a.kind == "reparo"
			end
			return a.id < b.id
		end)
		return out
	end

	function Erp.start(o: any, m: any)
		if o.status == "agendada" or o.status == "execucao" then
			o.status = "execucao"
			o.techId = m.id
			o.techName = m.name
			o.started = stamp()
		end
	end

	-- o técnico largou a OS (fim do turno, demissão, falta de material): volta para a agenda
	function Erp.release(o: any)
		if o.status == "execucao" then
			o.status = "agendada"
		end
	end

	function Erp.releaseTech(techId: number)
		for _, o in Erp.orders do
			if o.techId == techId and o.status == "execucao" then
				o.status = "agendada"
			end
		end
	end

	-- equipe mudou (contratação ou demissão): redistribui as OS
	function Erp.teamChanged()
		for _, o in Erp.orders do
			if o.status == "agendada" or o.status == "execucao" then
				if not teamMember(o.techId) then
					o.status = "agendada"
					assign(o)
				end
			end
		end
	end

	-- ---------------------------------------------------------------------------
	-- Pedidos e chamados
	-- ---------------------------------------------------------------------------

	local sayAttendant: (string, number?) -> () = function() end
	local attendantOnDuty: () -> boolean = function()
		return false
	end

	-- O morador chegou no balcão pedindo internet. Devolve a OS e se ela é nova.
	function Erp.request(index: number): (any, boolean)
		local h = net.houses[index]
		if not h or h.contract == "active" then
			return nil, false
		end
		local o = Erp.openInstallFor(index)
		if o then
			return o, false
		end
		o = newOrder("instalacao", index, "balcao")
		if attendantOnDuty() then
			sayAttendant(string.format("Olá, %s! Vou registrar o seu pedido de instalação.", o.client), 5)
		end
		return o, true
	end

	-- Abre uma OS de reparo para um cliente com problema (pelo ERP ou por telefone)
	function Erp.openRepair(index: number, origin: string): any
		local h = net.houses[index]
		if not h or h.contract ~= "active" or h.slot ~= P.slot then
			return nil
		end
		return Erp.openRepairFor(index) or newOrder("reparo", index, origin)
	end

	-- A casa foi instalada (pelo técnico ou pelo jogador): encerra a OS
	function Erp.installed(index: number, who: string, sn: string?)
		local o = Erp.openInstallFor(index)
		if o then
			Erp.finish(o, string.format("Instalada por %s. ONU SN %s: falta ativar na OLT", who, sn or "?"))
		end
	end

	-- Reparo feito por um jogador na casa: encerra a OS de reparo dela
	function Erp.fieldWork(index: number, note: string)
		local o = Erp.openRepairFor(index)
		if o then
			Erp.finish(o, note)
		end
	end

	-- ---------------------------------------------------------------------------
	-- Ativação na OLT (ont add + service-port) depois da instalação
	-- ---------------------------------------------------------------------------

	local OLT_REASONS = { unauth = true, noservice = true }

	local function oltDev(): any
		local rack = P.rack
		return if rack and rack.activeOf then rack.activeOf("olt") else nil
	end

	-- A OLT está "configurada" quando está ativa no rack e já tem o primeiro cliente
	-- ativado à mão pelo terminal (ont add + service-port). A partir daí o ERP repete o modelo.
	function Erp.oltStatus(): (boolean, string)
		local olt = oltDev()
		if not olt then
			return false, "Nenhuma OLT ativa no rack (ligada, com cabos e inicializada)."
		end
		if #olt.cfg.servicePorts == 0 then
			return false, "OLT ainda não configurada: ative o primeiro cliente pelo terminal da OLT (ont add + service-port). Depois disso o ERP ativa os próximos."
		end
		return true, "OLT configurada: clientes instalados são ativados por aqui (ont add + service-port automáticos)."
	end

	-- "unauth" (falta ont add) | "noservice" (falta service-port) | nil (ok ou não se aplica)
	local function oltPending(h: any): string?
		if h.contract ~= "active" or h.slot ~= P.slot or not h.onuId or not h.sn then
			return nil
		end
		local olt = oltDev()
		if not olt then
			return nil
		end
		local port = net.ponPortOf(h)
		local id = OltCli.findOnt(olt.cfg, port, h.sn)
		if not id then
			return "unauth"
		end
		if not OltCli.hasService(olt.cfg, port, id) then
			return "noservice"
		end
		return nil
	end

	local function activationList(): { any }
		local out = {}
		for index, h in net.houses do
			local why = oltPending(h)
			if why then
				table.insert(out, {
					index = index,
					client = residentName(index),
					sn = h.sn,
					port = net.ponPortOf(h),
					state = if why == "unauth" then "ONU não autorizada (falta ont add)" else "Sem service-port",
				})
			end
		end
		table.sort(out, function(a, b)
			return a.index < b.index
		end)
		return out
	end

	-- última OS de instalação da casa (para registrar a ativação nela)
	local function lastInstallOf(index: number): any
		for i = #Erp.orders, 1, -1 do
			local o = Erp.orders[i]
			if o.kind == "instalacao" and o.index == index and o.status == "concluida" then
				return o
			end
		end
		return nil
	end

	-- Faz na OLT o mesmo que o jogador faria no terminal
	function Erp.activate(index: number, by: string): (boolean, string)
		local ready, why = Erp.oltStatus()
		if not ready then
			return false, why
		end
		local h = net.houses[index]
		if not h or not oltPending(h) then
			return false, "A casa " .. index .. " não tem ativação pendente."
		end
		local cfg = oltDev().cfg
		local port = net.ponPortOf(h)
		local desc = "casa" .. index
		local done = {}
		local id = OltCli.findOnt(cfg, port, h.sn)
		if not id and cfg.onts[port] then
			-- ONU trocada: a ONT da casa já existe com o SN velho, troca só o SN (ont modify)
			for oid, o in cfg.onts[port] do
				if o.desc == desc then
					o.sn = h.sn
					id = oid
					table.insert(done, string.format("ont modify %d %d sn %s", port, oid, h.sn))
					break
				end
			end
		end
		if not id then
			id = OltCli.addOnt(cfg, port, nil, h.sn, desc)
			if not id then
				return false, "A porta PON " .. port .. " está cheia."
			end
			table.insert(done, string.format("ont add %d %d sn-auth %s desc %s", port, id, h.sn, desc))
		end
		if not OltCli.hasService(cfg, port, id :: number) then
			local sp = OltCli.addServicePort(cfg, nil, OltCli.Vlan, port, id :: number, OltCli.Gemport, OltCli.Vlan)
			table.insert(done, string.format("service-port %d vlan %d gpon 0/1/%d ont %d", sp, OltCli.Vlan, port, id :: number))
		end
		local text = string.format("Ativada na OLT por %s: %s", by, table.concat(done, " · "))
		local o = lastInstallOf(index)
		if o then
			o.note = (if o.note and o.note ~= "" then o.note .. "\n" else "") .. text
		end
		net.addAlarm(P.slot, "OLT", string.format("Casa %d ativada por %s (ONT %d, porta %d)", index, by, id :: number, port), "ok")
		return true, text
	end

	-- ---------------------------------------------------------------------------
	-- Atendente do balcão
	-- ---------------------------------------------------------------------------

	local att: any = nil
	local spot = isp.reception + Vector3.new(0, 0, -7.5) -- atrás do balcão, de frente para a porta

	local function attendantSeverance(): number
		return if att then math.max(A.SeveranceMin, att.daysWorked * A.SeverancePerDay) else 0
	end

	local function buildAttendant(a: any)
		local body = Looks.attendant()
		if not body then
			body = Instance.new("Model")
			local root = Instance.new("Part")
			root.Name = "HumanoidRootPart"
			root.Size = Vector3.new(2, 4, 1)
			root.Color = Color3.fromRGB(45, 110, 200)
			root.Parent = body
			local head = Instance.new("Part")
			head.Name = "Head"
			head.Size = Vector3.new(1.4, 1.4, 1.4)
			head.Color = Color3.fromRGB(160, 102, 60)
			head.CFrame = root.CFrame * CFrame.new(0, 2.7, 0)
			head.Parent = body
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = head
			w.Parent = root
			Instance.new("Humanoid").Parent = body
			body.PrimaryPart = root
		end
		body.Name = a.name
		local hum = body:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
		local root = body:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.Anchored = true -- fica parada atrás do balcão
		end
		local head = body:FindFirstChild("Head") :: BasePart?
		if head then
			local tag = Instance.new("BillboardGui")
			tag.Name = "NameTag"
			tag.Size = UDim2.fromOffset(220, 40)
			tag.StudsOffset = Vector3.new(0, 2.6, 0)
			tag.MaxDistance = 60
			tag.Parent = head
			local name = Instance.new("TextLabel")
			name.Size = UDim2.fromScale(1, 0.55)
			name.BackgroundTransparency = 1
			name.Font = Enum.Font.GothamBold
			name.TextScaled = true
			name.TextColor3 = Color3.fromRGB(120, 190, 255)
			name.TextStrokeTransparency = 0.4
			name.Text = a.name
			name.Parent = tag
			local st = Instance.new("TextLabel")
			st.Position = UDim2.fromScale(0, 0.55)
			st.Size = UDim2.fromScale(1, 0.45)
			st.BackgroundTransparency = 1
			st.Font = Enum.Font.Gotham
			st.TextScaled = true
			st.TextColor3 = Color3.new(1, 1, 1)
			st.TextStrokeTransparency = 0.4
			st.Text = a.state
			st.Parent = tag
			a.stateLabel = st

			local b = Instance.new("BillboardGui")
			b.Name = "Bubble"
			b.Size = UDim2.fromOffset(250, 58)
			b.StudsOffset = Vector3.new(0, 5, 0)
			b.MaxDistance = 70
			b.Enabled = false
			b.Parent = head
			local frame = Instance.new("Frame")
			frame.Size = UDim2.fromScale(1, 1)
			frame.BackgroundColor3 = Color3.new(1, 1, 1)
			frame.Parent = b
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 12)
			corner.Parent = frame
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 3
			stroke.Color = Color3.fromRGB(45, 110, 200)
			stroke.Parent = frame
			local t = Instance.new("TextLabel")
			t.Size = UDim2.new(1, -12, 1, -6)
			t.Position = UDim2.fromOffset(6, 3)
			t.BackgroundTransparency = 1
			t.Font = Enum.Font.Gotham
			t.TextScaled = true
			t.TextWrapped = true
			t.TextColor3 = Color3.fromRGB(30, 30, 35)
			t.Parent = frame
			a.bubble = b
			a.bubbleText = t
		end
		a.model = body
	end

	local function setAttState(text: string)
		if not att then
			return
		end
		att.state = text
		if att.stateLabel then
			att.stateLabel.Text = text
		end
	end

	sayAttendant = function(text: string, seconds: number?)
		if not att or not att.bubble then
			return
		end
		att.bubbleText.Text = text
		att.bubble.Enabled = true
		att.sayToken += 1
		local token = att.sayToken
		task.delay(seconds or 5, function()
			if att and att.sayToken == token and att.bubble then
				att.bubble.Enabled = false
			end
		end)
	end

	local function workHours(): boolean
		return game_.hour >= A.WorkStartHour and game_.hour < A.WorkEndHour
	end

	attendantOnDuty = function(): boolean
		return att ~= nil and att.model ~= nil and att.model.Parent ~= nil
	end

	-- monta o boneco fora do laço principal (criar o modelo pode demorar um pouco)
	local function spawnAttendant()
		if not att.model then
			if not att.building then
				att.building = true
				local me = att
				task.spawn(function()
					buildAttendant(me)
					me.building = false
				end)
			end
			return
		end
		if att.model.Parent ~= runtime then
			att.model.Parent = runtime
			att.model:PivotTo(CFrame.lookAt(spot + Vector3.new(0, 2.9, 0), spot + Vector3.new(0, 2.9, 1)))
		end
	end

	function Erp.hireAttendant(player: Player?): boolean
		if att then
			Remotes.notify(player, "O provedor já tem atendente.", "info")
			return false
		end
		if not game_.spend(A.HireFee, "contratação: " .. A.Name, player, "Equipe") then
			return false
		end
		att = { name = A.Name, daysWorked = 0, done = 0, state = "Contratada", sayToken = 0, current = nil, busy = 0 }
		net.addAlarm(P.slot, "Equipe", string.format("%s contratada. Salário de R$ %d por dia. Ela agenda as OS no ERP das %dh às %dh", A.Name, A.DailySalary, A.WorkStartHour, A.WorkEndHour), "ok")
		return true
	end

	function Erp.fireAttendant(player: Player?): boolean
		if not att then
			return false
		end
		local cost = attendantSeverance()
		if not game_.spend(cost, "rescisão: " .. att.name .. " (" .. att.daysWorked .. " dias)", player, "Equipe") then
			return false
		end
		if att.model then
			att.model:Destroy()
		end
		net.addAlarm(P.slot, "Equipe", att.name .. " demitida. Rescisão de R$ " .. cost, "warning")
		att = nil
		return true
	end

	-- OS mais antiga esperando agendamento (reparo antes de instalação)
	local function nextPending(): any
		local best = nil
		for _, o in Erp.orders do
			if o.status == "pendente" then
				if not best or (o.kind == "reparo" and best.kind ~= "reparo") or (o.kind == best.kind and o.id < best.id) then
					best = o
				end
			end
		end
		return best
	end

	local function attendantTick(dt: number)
		if not att then
			return
		end
		if not workHours() then
			if attendantOnDuty() and not att.leaving then
				att.leaving = true
				att.current = nil
				sayAttendant("Fim do expediente. Até amanhã!", 3)
				local me = att
				task.delay(3, function()
					if me.model then
						me.model.Parent = nil
					end
					me.leaving = false
				end)
			end
			setAttState(string.format("Fora do expediente (volta às %dh)", A.WorkStartHour))
			return
		end
		if not attendantOnDuty() then
			spawnAttendant()
			if attendantOnDuty() then
				sayAttendant("Bom dia! ERP aberto, pode chegar.", 4)
			end
			return
		end
		if att.current then
			att.busy -= dt
			if att.busy > 0 then
				return
			end
			local o = att.current
			att.current = nil
			if o.activate then
				local ok = Erp.activate(o.activate, att.name)
				if ok then
					att.done += 1
					sayAttendant(string.format("Casa %d ativada na OLT. Internet liberada!", o.activate), 5)
				end
				return
			end
			if Erp.schedule(o, att.name) then
				att.done += 1
				if o.techName then
					sayAttendant(string.format("OS #%d agendada! %s vai até a casa %d.", o.id, o.techName, o.index), 6)
				else
					sayAttendant(string.format("OS #%d agendada. Ainda não temos técnico: fica com a equipe.", o.id), 6)
				end
			end
			return
		end
		-- primeiro quem já tem ONU na casa e só falta a OLT
		if Erp.oltStatus() then
			local pend = activationList()[1]
			if pend then
				att.current = { activate = pend.index }
				att.busy = A.ActivateSeconds
				setAttState(string.format("Ativando a casa %d na OLT", pend.index))
				sayAttendant(string.format("Casa %d instalada: ativando na OLT...", pend.index), A.ActivateSeconds)
				return
			end
		end
		local o = nextPending()
		if o then
			att.current = o
			att.busy = A.ScheduleSeconds
			setAttState(string.format("Registrando a OS #%d", o.id))
			sayAttendant(string.format("%s da casa %d: registrando no ERP...", KindText[o.kind], o.index), A.ScheduleSeconds)
		else
			setAttState("Atendendo no balcão")
		end
	end

	function Erp.attendantStatus(): any
		return {
			hired = att ~= nil,
			name = if att then att.name else A.Name,
			state = if att then att.state else "Não contratada",
			daysWorked = if att then att.daysWorked else 0,
			done = if att then att.done else 0,
			severance = attendantSeverance(),
			hireFee = A.HireFee,
			salary = A.DailySalary,
			workStart = A.WorkStartHour,
			workEnd = A.WorkEndHour,
		}
	end

	-- salário: pago no fechamento de cada dia
	table.insert(game_.dailyCosts, function(): (number, string?, string?)
		if not att then
			return 0
		end
		att.daysWorked += 1
		att.done = 0
		return A.DailySalary, "Salários", "Salário da " .. att.name
	end)

	-- ---------------------------------------------------------------------------
	-- Computador da recepção (abre o ERP)
	-- ---------------------------------------------------------------------------

	do
		local pos = isp.reception + Vector3.new(4, 4.75, -4.4)
		local monitor = World.part({ Name = "ComputadorERP", Size = Vector3.new(2.2, 1.4, 0.15), CFrame = CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1)), Color = Color3.fromRGB(15, 18, 25), Parent = runtime })
		World.textOn(monitor, Enum.NormalId.Back, "ERP", Color3.fromRGB(80, 190, 255))
		World.part({ Name = "PeERP", Size = Vector3.new(0.5, 0.5, 0.4), CFrame = CFrame.new(pos - Vector3.new(0, 0.9, 0)), Color = Color3.fromRGB(40, 40, 46), Parent = runtime })
		local pp = Instance.new("ProximityPrompt")
		pp.ActionText = "Abrir ERP"
		pp.ObjectText = "Computador da recepção"
		pp.KeyboardKeyCode = Enum.KeyCode.E
		pp.HoldDuration = 0
		pp.MaxActivationDistance = 10
		pp.RequiresLineOfSight = false
		pp.Parent = monitor
		pp.Triggered:Connect(function(player)
			if Providers.of(player) == P then
				Erp.openFor(player)
			else
				Remotes.notify(player, "Esse ERP é do " .. P.name .. ".", "error")
			end
		end)
	end

	-- ---------------------------------------------------------------------------
	-- Tela do ERP (cliente)
	-- ---------------------------------------------------------------------------

	local function orderRow(o: any): any
		return {
			id = o.id,
			kind = o.kind,
			kindText = KindText[o.kind],
			index = o.index,
			client = o.client,
			status = o.status,
			statusText = Erp.statusText(o),
			origin = OriginText[o.origin] or "",
			opened = o.opened,
			scheduled = o.scheduled,
			closed = o.closed,
			by = o.by,
			techName = o.techName,
			note = o.note,
		}
	end

	local function sortedCategories(t: { [string]: number }): ({ any }, number)
		local out, total = {}, 0
		for cat, v in t do
			table.insert(out, { name = cat, amount = v })
			total += v
		end
		table.sort(out, function(a, b)
			return a.amount > b.amount
		end)
		return out, total
	end

	local function payload(): any
		local open, closed = {}, {}
		local counts = { pendente = 0, agendada = 0, execucao = 0, concluidas = closedToday }
		for _, o in Erp.orders do
			if isOpen(o) then
				counts[o.status] += 1
				table.insert(open, orderRow(o))
			else
				table.insert(closed, 1, orderRow(o))
			end
		end
		-- clientes com problema e sem OS (o jogador pode abrir uma)
		local problems = {}
		for index, h in net.houses do
			if h.contract == "active" and h.slot == P.slot and (h.status == "offline" or h.status == "nodns" or h.status == "unstable") and not Erp.openRepairFor(index) and not oltPending(h) then
				table.insert(problems, { index = index, client = residentName(index), status = Config.StatusLabels[h.status] or h.status, reason = net.reasonText(index) })
			end
		end
		-- equipe
		local techs = {}
		local ts = if tech then tech.status() else nil
		if tech then
			for _, m in tech.team do
				local queue = {}
				for _, o in Erp.queueOf(m.id) do
					table.insert(queue, string.format("#%d %s casa %d%s", o.id, KindText[o.kind], o.index, if o.status == "execucao" then " (agora)" else ""))
				end
				table.insert(techs, { id = m.id, name = m.name, state = m.state, jobsToday = m.jobsToday, queue = queue })
			end
		end
		local unassigned = 0
		for _, o in Erp.orders do
			if o.status == "agendada" and not o.techId then
				unassigned += 1
			end
		end
		-- financeiro
		local today = game_.daily[game_.day] or { receita = {}, despesa = {} }
		local yesterday = game_.daily[game_.day - 1]
		local rec, recTotal = sortedCategories(today.receita)
		local des, desTotal = sortedCategories(today.despesa)
		local yRec, yDes = 0, 0
		if yesterday then
			local _r, tr = sortedCategories(yesterday.receita)
			local _d, td = sortedCategories(yesterday.despesa)
			yRec, yDes = tr, td
		end
		local ledger = {}
		for i = 1, math.min(20, #game_.ledger) do
			ledger[i] = game_.ledger[i]
		end
		-- estoque
		local items = {}
		for _, k in Config.SupplyOrder do
			local sp = Config.Supplies[k]
			table.insert(items, { key = k, name = sp.name, qty = game_.stock[k] or 0, min = Config.Erp.MinStock[k] or 0, used = game_.usedToday[k] or 0, pack = sp.pack, price = sp.price })
		end
		local tools = {}
		for _, k in Config.ToolOrder do
			table.insert(tools, { name = Config.ToolNames[k], owned = game_.owned[k] == true, price = Config.ToolPrices[k] })
		end
		local moves = {}
		for i = 1, math.min(15, #game_.moves) do
			local mv = game_.moves[i]
			moves[i] = { time = string.format("Dia %d %s", mv.day, mv.time), name = Config.Supplies[mv.kind] and Config.Supplies[mv.kind].name or mv.kind, delta = mv.delta, reason = mv.reason, after = mv.after }
		end
		local oltReady, oltText = Erp.oltStatus()
		return {
			olt = { ready = oltReady, text = oltText, pending = activationList() },
			provider = P.name,
			clock = stamp(),
			money = math.floor(game_.money),
			orders = open,
			closed = closed,
			counts = counts,
			problems = problems,
			attendant = Erp.attendantStatus(),
			techs = techs,
			unassigned = unassigned,
			canHireTech = ts ~= nil and ts.canHire,
			nextTech = ts and ts.nextName,
			techHireFee = Config.Tech.HireFee,
			techSalary = Config.Tech.DailySalary,
			finance = {
				day = game_.day,
				receitas = rec,
				despesas = des,
				totalReceitas = recTotal,
				totalDespesas = desTotal,
				ontemReceitas = yRec,
				ontemDespesas = yDes,
				temOntem = yesterday ~= nil,
				ledger = ledger,
				debt = math.floor(game_.debt),
			},
			stock = { items = items, tools = tools, moves = moves },
		}
	end

	function Erp.openFor(player: Player)
		viewers[player] = true
		Remotes.ErpOpen:FireClient(player, payload())
	end

	local function push()
		local data = nil
		for player in viewers do
			if player.Parent and Providers.of(player) == P then
				data = data or payload()
				Remotes.ErpOpen:FireClient(player, data)
			else
				viewers[player] = nil
			end
		end
	end

	-- Ação escolhida na tela do ERP
	function Erp.action(player: Player, action: string, arg: any)
		if action == "open" then
			Erp.openFor(player)
			return
		elseif action == "close" then
			viewers[player] = nil
			return
		end
		if action == "schedule" then
			local o = Erp.byId(tonumber(arg) or 0)
			if o and Erp.schedule(o, player.DisplayName) then
				Remotes.notify(player, string.format("OS #%d agendada%s.", o.id, if o.techName then " para " .. o.techName else " (sem técnico: fica com a equipe)"), "success")
			end
		elseif action == "cancel" then
			local o = Erp.byId(tonumber(arg) or 0)
			if o and (o.status == "pendente" or o.status == "agendada") then
				Erp.cancel(o, "Cancelada por " .. player.DisplayName)
			end
		elseif action == "repair" then
			local o = Erp.openRepair(tonumber(arg) or 0, "erp")
			if o then
				Remotes.notify(player, string.format("OS #%d de reparo aberta para a casa %d. Agende para mandar o técnico.", o.id, o.index), "success")
			end
		elseif action == "activate" then
			local ok, msg = Erp.activate(tonumber(arg) or 0, player.DisplayName)
			Remotes.notify(player, msg, if ok then "success" else "error")
		elseif action == "buy" and typeof(arg) == "string" then
			local sp = Config.Supplies[arg]
			if sp and game_.spend(sp.price, sp.name .. " (pacote com " .. sp.pack .. ")", player, "Insumos") then
				game_.addStock(arg, sp.pack, "Compra pelo ERP (" .. player.DisplayName .. ")")
			end
		elseif action == "att_hire" then
			Erp.hireAttendant(player)
		elseif action == "att_fire" then
			Erp.fireAttendant(player)
		elseif action == "tech_hire" and tech then
			tech.hire(player)
		end
		Remotes.ErpOpen:FireClient(player, payload())
	end

	-- ---------------------------------------------------------------------------
	-- Uma vez por segundo
	-- ---------------------------------------------------------------------------

	function Erp.tick(dt: number)
		for index, h in net.houses do
			-- instalação: o morador desistiu ou virou cliente de outro provedor
			local inst = Erp.openInstallFor(index)
			if inst and inst.status ~= "execucao" then
				if h.contract == "active" then
					if h.slot == P.slot then
						Erp.finish(inst, "Casa já instalada")
					else
						Erp.cancel(inst, "Virou cliente do concorrente")
					end
				elseif h.choice ~= P.slot then
					Erp.cancel(inst, "O morador desistiu: escolheu outro provedor ou achou o preço caro")
				end
			end
			-- chamado: cliente sem internet há um tempo liga para o provedor
			local mine = h.contract == "active" and h.slot == P.slot
			if mine and h.ticketOpen and not OLT_REASONS[h.reason] then
				if not ticketed[index] then
					ticketed[index] = true
					Erp.openRepair(index, "telefone")
				end
			else
				ticketed[index] = nil
			end
			-- reparo: a internet voltou antes da visita, ou o cliente saiu
			local rep = Erp.openRepairFor(index)
			if rep and rep.status ~= "execucao" then
				if not mine then
					Erp.cancel(rep, "O cliente cancelou o contrato")
				elseif h.status == "online" or h.status == "slow" then
					Erp.finish(rep, "Normalizado antes da visita")
				end
			end
		end
		-- OS agendada sem técnico vai para quem foi contratado depois
		if tech and #tech.team > 0 then
			for _, o in Erp.orders do
				if o.status == "agendada" and not teamMember(o.techId) then
					assign(o)
				end
			end
		end
		attendantTick(dt)
		push()
	end

	-- vira o dia: zera o contador de OS concluídas
	table.insert(game_.dailyCosts, function(): number
		closedToday = 0
		return 0
	end)

	function Erp.setTech(t: any)
		tech = t
	end

	table.insert(
		conns,
		Players.PlayerRemoving:Connect(function(player)
			viewers[player] = nil
		end)
	)

	-- Provedor fechou: a atendente vai embora e o ERP some
	function Erp.destroy()
		for _, c in conns do
			c:Disconnect()
		end
		for player in viewers do
			Remotes.ErpOpen:FireClient(player, nil)
		end
		table.clear(viewers)
		att = nil
		runtime:Destroy()
	end

	return Erp
end

-- Um Remote só para o jogo inteiro: cada pedido vai para o ERP do provedor do jogador
function ErpModule.start()
	Remotes.ErpAction.OnServerEvent:Connect(function(player, action, arg)
		if typeof(action) ~= "string" then
			return
		end
		local P = Providers.of(player)
		if not P or not P.erp then
			if action == "open" then
				Remotes.notify(player, "Abra o seu provedor ou entre como sócio (tecla P) para usar o ERP.", "info")
			end
			return
		end
		P.erp.action(player, action, arg)
	end)
end

return ErpModule
