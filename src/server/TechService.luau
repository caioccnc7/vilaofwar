-- Equipe de rua: técnicos NPC que o dono do provedor contrata (quantos quiser, até
-- Config.Tech.Max). Cada um trabalha pela fila de ordens de serviço (OS) que recebe no
-- ERP do celular: instala casas novas e atende chamados de reparo (fibra rompida,
-- conector ruim, ONU queimada), usando o estoque. Trabalha só de dia e recebe salário
-- diário. Demitir custa uma rescisão pelos dias que aquele técnico trabalhou.
-- Se o carro da equipe estiver na garagem, o técnico vai de carro; se não, vai a pé.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local World = require(script.Parent.WorldBuilder)
local CarModule = require(script.Parent.CarService)
local Looks = require(script.Parent.Looks)

local TechModule = {}

function TechModule.new(P: any, worldData: any, netService: any): any
	local Tech = {}

	local T = Config.Tech
	local net: any = netService
	local game_: any = P.game
	local world: any = worldData
	local isp = worldData.isps[P.slot]
	local erp: any = P.erp -- ERP do provedor: a fila de OS de cada técnico
	local Car = CarModule.new(P, worldData, netService)

	Tech.team = {} -- técnicos contratados, na ordem de contratação
	local nextId = 0
	local claims: { [string]: any } = {} -- serviço -> técnico que está indo fazer

	local JobVerb = {
		["break"] = "Emendando a fibra",
		dirty = "Refazendo o conector",
		onu = "Trocando a ONU",
		install = "Instalando drop e ONU",
		visit = "Verificando a instalação",
	}

	-- ---------------------------------------------------------------------------
	-- Corpo do NPC
	-- ---------------------------------------------------------------------------

	local Skins = { Color3.fromRGB(198, 134, 66), Color3.fromRGB(255, 213, 170), Color3.fromRGB(141, 85, 36), Color3.fromRGB(234, 192, 134), Color3.fromRGB(105, 64, 40), Color3.fromRGB(224, 172, 105), Color3.fromRGB(160, 102, 60), Color3.fromRGB(255, 205, 148) }

	local function makeBody(slot: number): Model
		-- uniforme completo (capacete, colete refletivo, cinto de ferramentas, botas)
		local styled = Looks.technician(slot)
		if styled then
			return styled
		end
		local desc = Instance.new("HumanoidDescription")
		local skin = Skins[(slot - 1) % #Skins + 1]
		desc.HeadColor = skin
		desc.LeftArmColor = skin
		desc.RightArmColor = skin
		desc.TorsoColor = Color3.fromRGB(255, 120, 20) -- uniforme laranja
		desc.LeftLegColor = Color3.fromRGB(40, 50, 80)
		desc.RightLegColor = Color3.fromRGB(40, 50, 80)
		local ok, m = pcall(function()
			return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
		end)
		if ok and m then
			return m
		end
		local fallback = Instance.new("Model")
		local r = Instance.new("Part")
		r.Name = "HumanoidRootPart"
		r.Size = Vector3.new(2, 4, 1)
		r.Color = Color3.fromRGB(255, 120, 20)
		r.Parent = fallback
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Size = Vector3.new(1.4, 1.4, 1.4)
		head.Color = skin
		head.Parent = fallback
		local w = Instance.new("WeldConstraint")
		w.Part0 = r
		w.Part1 = head
		w.Parent = r
		head.CFrame = r.CFrame * CFrame.new(0, 2.7, 0)
		Instance.new("Humanoid").Parent = fallback
		fallback.PrimaryPart = r
		return fallback
	end

	local function build(m: any)
		local body = makeBody(m.slot)
		body.Name = m.name
		local hum = body:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			hum.WalkSpeed = T.WalkSpeed
		end
		local head = body:FindFirstChild("Head") :: BasePart
		if head then
			if not body:FindFirstChild("Capacete") then
				local helmet = Instance.new("Part")
				helmet.Name = "Capacete"
				helmet.Shape = Enum.PartType.Ball
				helmet.Size = Vector3.new(1.5, 0.9, 1.5)
				helmet.Color = Color3.fromRGB(250, 200, 30)
				helmet.CanCollide = false
				helmet.Massless = true
				helmet.CFrame = head.CFrame * CFrame.new(0, 0.45, 0)
				helmet.Parent = body
				local w = Instance.new("WeldConstraint")
				w.Part0 = head
				w.Part1 = helmet
				w.Parent = helmet
			end

			local tag = Instance.new("BillboardGui")
			tag.Name = "NameTag"
			tag.Size = UDim2.fromOffset(220, 40)
			tag.StudsOffset = Vector3.new(0, 2.6, 0)
			tag.MaxDistance = 80
			tag.Parent = head
			local name = Instance.new("TextLabel")
			name.Size = UDim2.fromScale(1, 0.55)
			name.BackgroundTransparency = 1
			name.Font = Enum.Font.GothamBold
			name.TextScaled = true
			name.TextColor3 = Color3.fromRGB(255, 170, 60)
			name.TextStrokeTransparency = 0.4
			name.Text = m.name
			name.Parent = tag
			local st = Instance.new("TextLabel")
			st.Position = UDim2.fromScale(0, 0.55)
			st.Size = UDim2.fromScale(1, 0.45)
			st.BackgroundTransparency = 1
			st.Font = Enum.Font.Gotham
			st.TextScaled = true
			st.TextColor3 = Color3.new(1, 1, 1)
			st.TextStrokeTransparency = 0.4
			st.Text = m.state
			st.Parent = tag
			m.nameLabel = st

			local b = Instance.new("BillboardGui")
			b.Name = "Bubble"
			b.Size = UDim2.fromOffset(240, 54)
			b.StudsOffset = Vector3.new(0, 5, 0)
			b.MaxDistance = 90
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
			stroke.Color = Color3.fromRGB(255, 120, 20)
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
			m.bubble = b
			m.bubbleText = t
		end
		m.model = body
		m.humanoid = hum
		m.root = body:FindFirstChild("HumanoidRootPart")
	end

	local function setState(m: any, text: string)
		m.state = text
		if m.nameLabel then
			m.nameLabel.Text = text
		end
	end

	local function say(m: any, text: string, seconds: number?)
		if not m.bubble or not m.bubbleText then
			return
		end
		m.bubbleText.Text = text
		m.bubble.Enabled = true
		m.sayToken += 1
		local token = m.sayToken
		task.delay(seconds or 5, function()
			if m.sayToken == token and m.bubble then
				m.bubble.Enabled = false
			end
		end)
	end

	-- cada técnico espera num ponto diferente da calçada do provedor
	local function waitSpot(m: any): Vector3
		return isp.entrance + Vector3.new((m.slot - 1) % 4 * 3.5 - 5, 0, if m.slot > 4 then 3 else 0)
	end

	local function spawnAtWork(m: any)
		if not m.model then
			build(m)
		end
		if m.model.Parent ~= world.npcFolder then
			m.model.Parent = world.npcFolder
			m.model:PivotTo(CFrame.new(waitSpot(m) + Vector3.new(0, 3, 0)))
			if m.root then
				pcall(function()
					m.root:SetNetworkOwner(nil)
				end)
			end
		end
	end

	local function despawn(m: any)
		if m.model then
			m.model.Parent = nil
		end
	end

	-- ---------------------------------------------------------------------------
	-- Andar e dirigir
	-- ---------------------------------------------------------------------------

	local function flat(v: Vector3): Vector3
		return Vector3.new(v.X, 0, v.Z)
	end

	local function walk(m: any, target: Vector3): boolean
		local hum, r = m.humanoid, m.root
		if not hum or not r then
			return false
		end
		-- MoveTo desiste depois de 8 s; em trechos longos tenta de novo
		local tries = 3 + math.ceil((flat(r.Position) - flat(target)).Magnitude / (T.WalkSpeed * 7))
		for _ = 1, tries do
			if not m.active then
				return false
			end
			hum:MoveTo(target)
			hum.MoveToFinished:Wait()
			if (flat(r.Position) - flat(target)).Magnitude < 4 then
				return true
			end
		end
		-- travou em algum obstáculo: pula para o destino
		if m.model then
			m.model:PivotTo(CFrame.new(target + Vector3.new(0, 3, 0)))
		end
		return true
	end

	-- a pé, sempre pela pista (Rua Principal e Rua das Palmeiras)
	local function walkRoute(m: any, target: Vector3): boolean
		if not m.root then
			return false
		end
		for _, p in World.path(m.root.Position, target) do
			if not walk(m, p) then
				return false
			end
		end
		return true
	end

	local function abortFor(m: any): () -> boolean
		return function()
			return not m.active
		end
	end

	local function dropCar(m: any)
		if m.hasCar then
			m.hasCar = false
			Car.release(m)
		end
	end

	-- leva o carro de volta para a garagem (se ainda estiver com ele)
	local function returnCar(m: any)
		if not m.hasCar then
			return
		end
		if Car.heldBy(m) then
			setState(m, "Levando o carro para a garagem")
			local door = Car.doorPoint()
			if door and walkRoute(m, door) and Car.heldBy(m) and Car.board(m) then
				Car.driveHome(m, abortFor(m))
				Car.leave(m)
			end
		end
		dropCar(m)
	end

	-- vai até o destino: de carro se der, senão a pé
	local function goTo(m: any, dest: Vector3, label: string)
		if not m.root then
			return
		end
		local far = (flat(m.root.Position) - flat(dest)).Magnitude > T.CarMinDistance
		if not m.hasCar and far and Car.available() and Car.reserve(m) then
			m.hasCar = true
			setState(m, "Pegando o carro na garagem")
		end
		if m.hasCar and not Car.heldBy(m) then
			dropCar(m)
			say(m, "Cadê o carro? Vou a pé mesmo.", 5)
		end
		if m.hasCar then
			local carPos = Car.position()
			if carPos and (flat(carPos) - flat(dest)).Magnitude > 40 then
				local door = Car.doorPoint()
				if door and walkRoute(m, door) and Car.heldBy(m) and Car.board(m) then
					setState(m, "Dirigindo até " .. label)
					local ok = Car.driveNear(m, dest, abortFor(m))
					Car.leave(m)
					if not ok then
						dropCar(m)
					end
				else
					dropCar(m)
					say(m, "Pegaram o carro. Vou a pé.", 5)
				end
			end
		end
		if not m.active then
			return
		end
		setState(m, (if m.hasCar then "Indo até " else "Indo a pé até ") .. label)
		walkRoute(m, dest)
	end

	local function workHours(): boolean
		return game_.hour >= T.WorkStartHour and game_.hour < T.WorkEndHour
	end

	-- Próxima OS da fila do técnico no ERP, já com o serviço que ele vai fazer no local.
	-- Reparo: ele procura o defeito físico do caminho (rompimento, ONU, conector). Se não
	-- acha nada na rua, vai até a casa verificar e devolve a OS com o diagnóstico.
	local function nextWork(m: any): (any, any)
		if not erp then
			return nil, nil
		end
		for _, o in erp.queueOf(m.id) do
			local h = net.houses[o.index]
			if not h then
				erp.cancel(o, "Casa não encontrada")
				continue
			end
			local door = h.house.doorPoint
			if o.kind == "instalacao" then
				if h.contract == "active" then
					if h.slot == P.slot then
						erp.finish(o, "Casa já estava instalada")
					else
						erp.cancel(o, "Virou cliente do concorrente")
					end
					continue
				end
				return o, { kind = "install", key = "install:" .. o.index, index = o.index, pos = door, label = "instalação da casa " .. o.index, priority = 2, needs = { onu = 1, drop = 1 } }
			end
			local job = net.diagnose(o.index, P.slot)
			if job then
				local owner = claims[job.key]
				if owner ~= nil and owner ~= m and owner.active then
					continue -- outro técnico já está nesse defeito (ex.: tronco rompido)
				end
				return o, job
			end
			return o, { kind = "visit", key = "visit:" .. o.index, index = o.index, pos = door, label = "casa " .. o.index, priority = 3, needs = {} }
		end
		return nil, nil
	end

	local function hasStock(needs: { [string]: number }): (boolean, string)
		for kind, n in needs do
			if (game_.stock[kind] or 0) < n then
				return false, Config.Supplies[kind].name
			end
		end
		return true, ""
	end

	local function unclaim(m: any)
		for key, owner in claims do
			if owner == m then
				claims[key] = nil
			end
		end
	end

	-- ---------------------------------------------------------------------------
	-- Rotina de cada técnico
	-- ---------------------------------------------------------------------------

	local function loop(m: any)
		m.atHome = true
		while m.active do
			if not workHours() then
				if not m.atHome then
					if erp then
						erp.releaseTech(m.id)
					end
					m.osId = nil
					say(m, "Fim do meu turno. Até amanhã!", 4)
					returnCar(m)
					setState(m, "Indo para casa descansar")
					walkRoute(m, isp.entrance)
					despawn(m)
					m.atHome = true
				end
				setState(m, string.format("Descansando (volta às %dh)", T.WorkStartHour))
				task.wait(2)
				continue
			end
			if m.atHome then
				spawnAtWork(m)
				m.atHome = false
				setState(m, "Chegou para o turno")
				say(m, "Bom dia! Vou ver a minha fila no ERP.", 4)
			end

			local order, job = nextWork(m)
			if not order then
				m.osId = nil
				returnCar(m)
				setState(m, "Sem OS na fila (olhando o ERP no celular)")
				if m.root and (flat(m.root.Position) - flat(waitSpot(m))).Magnitude > 6 then
					walkRoute(m, waitSpot(m))
				end
				task.wait(2)
				continue
			end

			local ok, missing = hasStock(job.needs)
			if not ok then
				setState(m, string.format("Parado na OS #%d: sem %s no estoque", order.id, missing))
				if not m.warned[job.key] then
					m.warned[job.key] = true
					net.addAlarm(P.slot, "Técnico", string.format("%s parado na OS #%d (%s): falta %s no estoque", m.name, order.id, job.label, missing), "warning")
					say(m, "Sem " .. missing .. " no estoque. Compra pra mim?", 6)
				end
				task.wait(3)
				continue
			end
			m.warned[job.key] = nil
			claims[job.key] = m
			m.osId = order.id
			erp.start(order, m)

			say(m, string.format("ERP: OS #%d, %s. Partiu!", order.id, job.label), 4)
			goTo(m, job.pos, job.label)
			if not m.active then
				erp.release(order)
				break
			end
			if order.status ~= "execucao" then
				-- a OS foi encerrada enquanto ele ia (jogador resolveu, cliente cancelou)
				say(m, "O ERP diz que essa OS já foi encerrada. Beleza!", 4)
				claims[job.key] = nil
				m.osId = nil
				continue
			end
			local verb = JobVerb[job.kind] or "Consertando"
			local seconds = if job.kind == "install" then T.InstallSeconds else T.RepairSeconds
			setState(m, string.format("%s (OS #%d)", verb, order.id))
			say(m, verb .. "...", seconds)
			task.wait(seconds)
			if not m.active then
				erp.release(order)
				break
			end
			local h = net.houses[order.index]
			if job.kind == "install" then
				if h.contract ~= "active" and h.choice == P.slot then
					if net.install(order.index, P, nil, m.name) then
						m.jobsToday += 1
						say(m, string.format("Casa %d instalada! Falta autorizar a ONU na OLT.", order.index), 6)
					else
						erp.release(order)
					end
				else
					erp.cancel(order, "O morador desistiu na hora da instalação")
					say(m, "O morador desistiu. OS cancelada.", 5)
				end
			elseif job.kind == "visit" then
				if net.diagnose(order.index, P.slot) then
					erp.release(order) -- apareceu um defeito na rua: volta para a fila
				elseif h.status == "online" or h.status == "slow" then
					erp.finish(order, "Visita: o cliente já estava com internet")
					say(m, "Tá funcionando. OS encerrada.", 5)
				else
					local why = net.reasonText(order.index)
					erp.finish(order, "Sem defeito na rua: " .. why .. ". Resolver no provedor (rack/OLT)")
					net.addAlarm(P.slot, "Técnico", string.format("%s: casa %d sem defeito físico (%s). Resolva no rack ou na OLT", m.name, order.index, why), "warning")
					say(m, "Na rua está tudo certo. O problema é no provedor: " .. why .. ".", 7)
				end
			elseif not net.jobOpen(job) then
				if h and (h.status == "online" or h.status == "slow") then
					erp.finish(order, "Já estava resolvido quando o técnico chegou")
					say(m, "Já resolveram aqui. Beleza!", 4)
				else
					erp.release(order)
				end
			elseif net.techFix(job, m.name, P, order.id) then
				m.jobsToday += 1
				local note = if job.kind == "break" then "Fibra emendada: " .. job.label elseif job.kind == "dirty" then "Conector refeito" else string.format("ONU trocada. SN novo %s: autorizar na OLT", h.sn or "?")
				erp.finish(order, note .. " (" .. m.name .. ")")
				say(m, "Pronto! " .. job.label .. " resolvido.", 5)
			else
				erp.release(order)
			end
			claims[job.key] = nil
			m.osId = nil
		end
		if erp then
			erp.releaseTech(m.id)
		end
		unclaim(m)
	end

	-- ---------------------------------------------------------------------------
	-- Contratar e demitir
	-- ---------------------------------------------------------------------------

	local function severanceOf(m: any): number
		return math.max(T.SeveranceMin, m.daysWorked * T.SeverancePerDay)
	end

	local function freeName(): (string?, number)
		for slot, name in T.Names do
			local used = false
			for _, m in Tech.team do
				if m.name == name then
					used = true
				end
			end
			if not used then
				return name, slot
			end
		end
		return nil, 0
	end

	function Tech.status()
		local team = {}
		for _, m in Tech.team do
			local p = if m.model and m.model.Parent and m.root then m.root.Position else nil
			table.insert(team, {
				id = m.id,
				name = m.name,
				state = m.state,
				daysWorked = m.daysWorked,
				jobsToday = m.jobsToday,
				severance = severanceOf(m),
				car = m.hasCar,
				osId = m.osId,
				queue = if erp then #erp.queueOf(m.id) else 0,
				x = if p then p.X else nil,
				z = if p then p.Z else nil,
			})
		end
		local nextName = freeName()
		local car = Car.status()
		return {
			team = team,
			max = T.Max,
			canHire = #Tech.team < T.Max and nextName ~= nil,
			nextName = nextName,
			hireFee = T.HireFee,
			salary = T.DailySalary,
			dailyTotal = #Tech.team * T.DailySalary + (if car.owned then car.dailyCost else 0),
			severancePerDay = T.SeverancePerDay,
			severanceMin = T.SeveranceMin,
			workStart = T.WorkStartHour,
			workEnd = T.WorkEndHour,
			car = car,
		}
	end

	function Tech.hire(player: Player?): boolean
		local name, slot = freeName()
		if #Tech.team >= T.Max or not name then
			Remotes.notify(player, "A equipe já está completa (" .. T.Max .. " técnicos).", "info")
			return false
		end
		if not game_.spend(T.HireFee, "contratação: " .. name, player, "Equipe") then
			return false
		end
		nextId += 1
		local m = {
			id = nextId,
			slot = slot,
			name = name,
			active = true,
			daysWorked = 0,
			jobsToday = 0,
			state = "Contratado",
			sayToken = 0,
			warned = {},
			hasCar = false,
		}
		table.insert(Tech.team, m)
		net.addAlarm(P.slot, "Equipe", string.format("%s contratado. Salário de R$ %d por dia (equipe: %d)", name, T.DailySalary, #Tech.team), "ok")
		task.spawn(loop, m)
		if erp then
			erp.teamChanged()
		end
		return true
	end

	function Tech.fire(player: Player?, id: number?): boolean
		local index = nil
		for i, m in Tech.team do
			if id == nil or m.id == id then
				index = i
			end
		end
		if not index then
			return false
		end
		local m = Tech.team[index]
		local cost = severanceOf(m)
		if not game_.spend(cost, "rescisão: " .. m.name .. " (" .. m.daysWorked .. " dias)", player, "Equipe") then
			return false
		end
		m.active = false
		table.remove(Tech.team, index)
		unclaim(m)
		if m.hasCar then
			if m.humanoid and m.humanoid.SeatPart then
				Car.leave(m)
			end
			dropCar(m)
		end
		despawn(m)
		if erp then
			erp.teamChanged()
		end
		net.addAlarm(P.slot, "Equipe", m.name .. " demitido. Rescisão de R$ " .. cost, "warning")
		return true
	end

	-- salário: pago no fechamento de cada dia, para cada técnico contratado
	table.insert(game_.dailyCosts, function(): number
		local total = 0
		for _, m in Tech.team do
			m.daysWorked += 1
			m.jobsToday = 0
			total += T.DailySalary
		end
		return total, "Salários", string.format("Salário dos técnicos (%d)", #Tech.team)
	end)

	-- Provedor fechou: a equipe vai embora e o carro some
	function Tech.destroy()
		for _, m in Tech.team do
			m.active = false
			unclaim(m)
			if m.model then
				m.model:Destroy()
				m.model = nil
			end
		end
		Tech.team = {}
		Car.destroy()
	end

	Tech.Car = Car

	return Tech
end

return TechModule
