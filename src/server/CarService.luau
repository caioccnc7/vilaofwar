-- Carro da equipe: comprado no terminal de compras, mora na garagem ao lado do prédio.
-- O chefe (jogador) dirige sentando no banco do motorista. O técnico NPC só pega o
-- carro quando ele está parado na garagem; se o carro estiver na rua, ele vai a pé.
--
-- Física: o carro inteiro é uma montagem solta (sem colisão) presa a um AlignPosition e
-- um AlignOrientation rígidos. Quem dirige só move o alvo desses dois:
--   * jogador: o cliente dele é o dono da física e move o alvo (Client/Carro);
--   * técnico ou carro parado: o servidor move o alvo.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local Providers = require(script.Parent.Providers)
local World = require(script.Parent.WorldBuilder)

local CarModule = {}

function CarModule.new(P: any, worldData: any, netService: any): any
	local Car = {}

	local C = Config.Car
	local world: any = worldData
	local net: any = netService
	local game_: any = P.game
	local isp = worldData.isps[P.slot]
	local keyPrompt: ProximityPrompt? = nil

	local function own(player: Player): boolean
		if Providers.of(player) == P then
			return true
		end
		Remotes.notify(player, "Esse carro é do " .. P.name .. ".", "error")
		return false
	end

	Car.owned = false
	Car.state = "none" -- none | garage | away | player | tech
	Car.driverName = "" -- quem está com o carro (técnico ou jogador)

	local model: Model? = nil
	local chassis: BasePart? = nil
	local seat: VehicleSeat? = nil
	local alignPos: AlignPosition? = nil
	local alignRot: AlignOrientation? = nil
	local reservedBy: any = nil -- técnico que pegou o carro
	local serverControl = true

	local HOVER = 1.8 -- altura do centro do chassi acima do chão

	-- ---------------------------------------------------------------------------
	-- Modelo
	-- ---------------------------------------------------------------------------

	local function weld(a: BasePart, b: BasePart)
		local w = Instance.new("WeldConstraint")
		w.Part0 = a
		w.Part1 = b
		w.Parent = b
	end

	local function build(): Model
		local m = Instance.new("Model")
		m.Name = "CarroEquipe"
		local base = World.part({ Name = "Chassi", Size = Vector3.new(6, 1, 12), CFrame = CFrame.new(), Color = Color3.fromRGB(40, 40, 45), Parent = m })
		local function add(props: { [string]: any }): BasePart
			props.Parent = m
			local p = World.part(props)
			weld(base, p)
			return p
		end
		local white = Color3.fromRGB(245, 245, 245)
		local glass = Color3.fromRGB(40, 60, 80)
		add({ Name = "Cabine", Size = Vector3.new(6, 3.4, 4.6), CFrame = CFrame.new(0, 2.2, -3.4), Color = white })
		add({ Name = "Bau", Size = Vector3.new(6, 4.6, 7.2), CFrame = CFrame.new(0, 2.8, 2.4), Color = white })
		add({ Name = "Capo", Size = Vector3.new(5.8, 1.4, 1.4), CFrame = CFrame.new(0, 1.2, -6.2), Color = white })
		add({ Name = "ParaBrisa", Size = Vector3.new(5.4, 1.8, 0.2), CFrame = CFrame.new(0, 3, -5.72), Color = glass, Material = Enum.Material.Glass, Transparency = 0.15 })
		for _, x in { -3.02, 3.02 } do
			add({ Name = "Janela", Size = Vector3.new(0.1, 1.6, 2.4), CFrame = CFrame.new(x, 3, -3.6), Color = glass, Material = Enum.Material.Glass, Transparency = 0.15 })
		end
		local stripe = add({ Name = "Faixa", Size = Vector3.new(6.08, 1.2, 7), CFrame = CFrame.new(0, 2.4, 2.4), Color = Color3.fromRGB(255, 120, 20) })
		World.textOn(stripe, Enum.NormalId.Left, "FIBRA DA VILA", Color3.new(1, 1, 1))
		World.textOn(stripe, Enum.NormalId.Right, "FIBRA DA VILA", Color3.new(1, 1, 1))
		add({ Name = "Escada", Size = Vector3.new(1.4, 0.3, 7), CFrame = CFrame.new(0, 5.3, 2.4), Color = Color3.fromRGB(190, 160, 60), Material = Enum.Material.Metal })
		for _, x in { -2, 2 } do
			add({ Name = "Farol", Size = Vector3.new(1.2, 0.6, 0.2), CFrame = CFrame.new(x, 1.4, -6.95), Color = Color3.fromRGB(255, 250, 220), Material = Enum.Material.Neon })
			add({ Name = "Lanterna", Size = Vector3.new(1, 0.6, 0.2), CFrame = CFrame.new(x, 1.4, 6.05), Color = Color3.fromRGB(220, 30, 30), Material = Enum.Material.Neon })
		end
		add({ Name = "Giroflex", Size = Vector3.new(2.4, 0.4, 0.8), CFrame = CFrame.new(0, 4.1, -3.4), Color = Color3.fromRGB(255, 150, 20), Material = Enum.Material.Neon })
		for _, w in { Vector3.new(-3, -0.6, -4), Vector3.new(3, -0.6, -4), Vector3.new(-3, -0.6, 4), Vector3.new(3, -0.6, 4) } do
			add({ Name = "Roda", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 2.4, 2.4), CFrame = CFrame.new(w), Color = Color3.fromRGB(25, 25, 25) })
		end

		-- bancos: motorista (VehicleSeat) e carona
		local s = Instance.new("VehicleSeat")
		s.Name = "Motorista"
		s.Size = Vector3.new(2, 1, 2)
		s.CFrame = CFrame.new(-1.3, 1.4, -3.2)
		s.Transparency = 1
		s.MaxSpeed = 0
		s.Torque = 0
		s.HeadsUpDisplay = false
		s.Anchored = true
		s.Parent = m
		weld(base, s)
		local passenger = Instance.new("Seat")
		passenger.Name = "Carona"
		passenger.Size = Vector3.new(2, 1, 2)
		passenger.CFrame = CFrame.new(1.3, 1.4, -3.2)
		passenger.Transparency = 1
		passenger.Anchored = true
		passenger.Parent = m
		weld(base, passenger)

		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
				-- ninguém senta encostando: só pelos avisos Dirigir e Carona (evita morador sentar sozinho)
				d.CanTouch = false
				d.Massless = d ~= base
				d.Anchored = false
			end
		end

		local att = Instance.new("Attachment")
		att.Name = "Guia"
		att.Parent = base
		local ap = Instance.new("AlignPosition")
		ap.Mode = Enum.PositionAlignmentMode.OneAttachment
		ap.Attachment0 = att
		ap.RigidityEnabled = true
		ap.Parent = base
		local ao = Instance.new("AlignOrientation")
		ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
		ao.Attachment0 = att
		ao.RigidityEnabled = true
		ao.Parent = base

		m.PrimaryPart = base
		CollectionService:AddTag(m, "CarroEquipe")
		model = m
		chassis = base
		seat = s
		alignPos = ap
		alignRot = ao
		return m
	end

	-- ---------------------------------------------------------------------------
	-- Movimento controlado pelo servidor
	-- ---------------------------------------------------------------------------

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.RespectCanCollide = true

	local function groundY(pos: Vector3): number
		local ignore: { Instance } = {}
		if model then
			table.insert(ignore, model)
		end
		if world then
			table.insert(ignore, world.npcFolder)
		end
		for _, p in Players:GetPlayers() do
			if p.Character then
				table.insert(ignore, p.Character)
			end
		end
		rayParams.FilterDescendantsInstances = ignore
		-- começa baixo (o chão da vila não passa de 1,5) para não pegar teto de garagem ou marquise
		local hit = workspace:Raycast(Vector3.new(pos.X, 5, pos.Z), Vector3.new(0, -12, 0), rayParams)
		return if hit then hit.Position.Y else 0
	end

	local function setTarget(cf: CFrame)
		if alignPos and alignRot then
			alignPos.Position = cf.Position
			alignRot.CFrame = cf.Rotation
		end
	end

	-- coloca o carro num ponto (CFrame no chão), sem animação
	local function place(cf: CFrame)
		if not model then
			return
		end
		local pos = cf.Position
		local target = CFrame.new(pos.X, groundY(pos) + HOVER, pos.Z) * cf.Rotation
		setTarget(target)
		model:PivotTo(target)
	end

	local function takeServerControl()
		serverControl = true
		if chassis then
			pcall(function()
				(chassis :: BasePart):SetNetworkOwner(nil)
			end)
			-- o alvo passa a ser onde o carro está agora (evita um tranco)
			local look = chassis.CFrame.LookVector
			local flatLook = Vector3.new(look.X, 0, look.Z)
			if flatLook.Magnitude < 0.1 then
				flatLook = Vector3.new(0, 0, -1)
			end
			setTarget(CFrame.lookAt(chassis.Position, chassis.Position + flatLook.Unit))
		end
	end

	local function nearGarage(): boolean
		if not chassis then
			return false
		end
		local spot = isp.garage.spot.Position
		local p = chassis.Position
		return (Vector3.new(p.X, 0, p.Z) - Vector3.new(spot.X, 0, spot.Z)).Magnitude < 14
	end

	local function refreshState()
		if not Car.owned then
			Car.state = "none"
			return
		end
		if reservedBy then
			Car.state = "tech"
			Car.driverName = reservedBy.name
			return
		end
		local occ = seat and seat.Occupant
		if occ then
			local p = Players:GetPlayerFromCharacter(occ.Parent)
			Car.state = "player"
			Car.driverName = if p then p.DisplayName else "?"
			return
		end
		Car.driverName = ""
		Car.state = if nearGarage() then "garage" else "away"
	end

	-- Dirige pelo caminho até o ponto (o técnico vai sentado). Para antes se abort() for verdade.
	-- Devolve false se alguém tomou o carro no meio do caminho.
	local function driveAlong(points: { Vector3 }, speed: number, abort: (() -> boolean)?): boolean
		if not chassis then
			return false
		end
		local pos = chassis.Position
		local yaw = chassis.CFrame.LookVector
		for _, wp in points do
			local target = Vector3.new(wp.X, 0, wp.Z)
			while true do
				if abort and abort() then
					return false
				end
				if not serverControl then
					return false
				end
				local flat = Vector3.new(pos.X, 0, pos.Z)
				local delta = target - flat
				local dist = delta.Magnitude
				if dist < 0.5 then
					break
				end
				local dt = RunService.Heartbeat:Wait()
				local step = math.min(dist, speed * dt)
				local dir = delta.Unit
				yaw = yaw:Lerp(dir, math.clamp(dt * 6, 0, 1))
				flat += dir * step
				local y = groundY(flat)
				pos = Vector3.new(flat.X, pos.Y + (y + HOVER - pos.Y) * math.clamp(dt * 10, 0, 1), flat.Z)
				local fy = Vector3.new(yaw.X, 0, yaw.Z)
				if fy.Magnitude < 0.05 then
					fy = dir
				end
				setTarget(CFrame.lookAt(pos, pos + fy.Unit))
			end
		end
		return true
	end

	-- ---------------------------------------------------------------------------
	-- API usada pelo TechService
	-- ---------------------------------------------------------------------------

	function Car.available(): boolean
		refreshState()
		return Car.state == "garage"
	end

	function Car.position(): Vector3?
		return if chassis then chassis.Position else nil
	end

	-- ponto ao lado da porta do motorista, onde o técnico entra e sai
	function Car.doorPoint(): Vector3?
		if not chassis then
			return nil
		end
		local p = (chassis.CFrame * CFrame.new(-4.5, 0, -3)).Position
		return Vector3.new(p.X, 0.6, p.Z)
	end

	function Car.reserve(member: any): boolean
		if not Car.available() then
			return false
		end
		reservedBy = member
		refreshState()
		return true
	end

	function Car.heldBy(member: any): boolean
		return reservedBy == member and seat ~= nil and (seat.Occupant == nil or seat.Occupant == member.humanoid)
	end

	function Car.release(member: any)
		if reservedBy == member then
			reservedBy = nil
		end
		refreshState()
	end

	function Car.board(member: any): boolean
		if not seat or not member.humanoid or not Car.heldBy(member) then
			return false
		end
		if seat.Occupant and seat.Occupant ~= member.humanoid then
			return false
		end
		member.model:PivotTo((seat :: VehicleSeat).CFrame * CFrame.new(0, 2.5, 0))
		seat:Sit(member.humanoid)
		task.wait(0.3)
		return seat.Occupant == member.humanoid
	end

	function Car.leave(member: any)
		if member.humanoid then
			member.humanoid.Sit = false
			local weldInst = seat and seat:FindFirstChild("SeatWeld")
			if weldInst and (weldInst :: Weld).Part1 and (weldInst :: Weld).Part1:IsDescendantOf(member.model) then
				weldInst:Destroy()
			end
		end
		task.wait(0.1)
		local door = Car.doorPoint()
		if door and member.model then
			member.model:PivotTo(CFrame.new(door + Vector3.new(0, 3, 0)))
			local r = member.model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if r then
				r.AssemblyLinearVelocity = Vector3.zero
				r.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end

	-- leva o carro (com o técnico dentro) até a pista mais perto do destino
	function Car.driveNear(member: any, dest: Vector3, abort: (() -> boolean)?): boolean
		if not chassis or not Car.heldBy(member) then
			return false
		end
		local pts = World.path(chassis.Position, dest)
		table.remove(pts) -- o último ponto é a porta da casa: o carro para na pista
		return driveAlong(pts, C.TechSpeed, abort)
	end

	-- volta para a garagem e estaciona de frente para a rua
	function Car.driveHome(member: any, abort: (() -> boolean)?): boolean
		if not chassis or not Car.heldBy(member) then
			return false
		end
		local spot = isp.garage.spot
		local pts = World.path(chassis.Position, spot.Position)
		if not driveAlong(pts, C.TechSpeed, abort) then
			return false
		end
		place(spot)
		return true
	end

	-- ---------------------------------------------------------------------------
	-- Compra, recolher e estado
	-- ---------------------------------------------------------------------------

	local function spawnCar()
		local m = build()
		m.Parent = workspace:FindFirstChild("VilaAurora") or workspace
		place(isp.garage.spot)
		takeServerControl()

		local s = seat :: VehicleSeat
		s:GetPropertyChangedSignal("Occupant"):Connect(function()
			local occ = s.Occupant
			local player = if occ then Players:GetPlayerFromCharacter(occ.Parent) else nil
			if player then
				-- jogador assumiu o volante: o cliente dele passa a mover o carro
				if reservedBy then
					net.addAlarm(P.slot, "Carro", player.DisplayName .. " pegou o carro que estava com " .. reservedBy.name, "warning")
					reservedBy = nil
				end
				serverControl = false
				pcall(function()
					(chassis :: BasePart):SetNetworkOwner(player)
				end)
			elseif not serverControl then
				takeServerControl()
			end
			refreshState()
		end)

		-- prompt para entrar dirigindo (mais fácil que encostar no banco)
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Dirigir"
		prompt.ObjectText = C.Name
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0.2
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = s
		s:GetPropertyChangedSignal("Occupant"):Connect(function()
			prompt.Enabled = s.Occupant == nil
		end)
		-- carona: o chefe pode ir junto com o técnico
		local seat2 = model and model:FindFirstChild("Carona") :: Seat
		if seat2 then
			local p2 = Instance.new("ProximityPrompt")
			p2.ActionText = "Carona"
			p2.ObjectText = C.Name
			p2.KeyboardKeyCode = Enum.KeyCode.F
			p2.HoldDuration = 0.2
			p2.MaxActivationDistance = 10
			p2.RequiresLineOfSight = false
			p2.Parent = seat2
			seat2:GetPropertyChangedSignal("Occupant"):Connect(function()
				p2.Enabled = seat2.Occupant == nil
			end)
			p2.Triggered:Connect(function(player)
				local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if hum and not seat2.Occupant and own(player) then
					seat2:Sit(hum)
				end
			end)
		end
		prompt.Triggered:Connect(function(player)
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if not hum or not own(player) then
				return
			end
			if s.Occupant then
				Remotes.notify(player, "Tem alguém dirigindo. Sente no banco do carona (lado direito).", "info")
				return
			end
			s:Sit(hum)
		end)
	end

	function Car.buy(player: Player?): boolean
		if Car.owned then
			Remotes.notify(player, "O provedor já tem o " .. C.Name .. ". Ele fica na garagem ao lado do prédio.", "info")
			return false
		end
		if not game_.spend(C.Price, C.Name, player) then
			return false
		end
		Car.owned = true
		spawnCar()
		refreshState()
		net.addAlarm(P.slot, "Equipe", C.Name .. " comprado. Está na garagem", "ok")
		game_.notify(nil, C.Name .. " chegou na garagem, ao lado do prédio. Aperte E perto da porta do motorista para dirigir.", "success")
		return true
	end

	-- traz o carro de volta para a garagem (se ninguém estiver usando)
	function Car.recall(player: Player?): boolean
		refreshState()
		if Car.state == "player" or Car.state == "tech" then
			Remotes.notify(player, "O carro está com " .. Car.driverName .. " agora.", "info")
			return false
		end
		if Car.state == "away" then
			takeServerControl()
			place(isp.garage.spot)
			Remotes.notify(player, "Carro recolhido para a garagem.", "success")
			refreshState()
			return true
		end
		return false
	end

	local StateText = {
		none = "o provedor não tem carro",
		garage = "na garagem",
		away = "estacionado na rua (fora da garagem)",
	}

	function Car.status()
		refreshState()
		local text = StateText[Car.state]
		if Car.state == "player" then
			text = "com " .. Car.driverName .. " (dirigindo)"
		elseif Car.state == "tech" then
			text = "com " .. Car.driverName
		end
		local p = if chassis and Car.owned then chassis.Position else nil
		return {
			owned = Car.owned,
			name = C.Name,
			price = C.Price,
			dailyCost = C.DailyCost,
			state = Car.state,
			stateText = text,
			x = if p then p.X else nil,
			z = if p then p.Z else nil,
		}
	end

	-- Provedor fechou: o carro some e o quadro de chaves fica sem uso
	function Car.destroy()
		Car.owned = false
		reservedBy = nil
		if model then
			model:Destroy()
			model = nil
		end
		chassis, seat = nil, nil
		if keyPrompt then
			keyPrompt:Destroy()
		end
	end

	table.insert(game_.dailyCosts, function(): number
		return if Car.owned then C.DailyCost else 0
	end)

	-- quadro de chaves na garagem: recolher o carro deixado na rua
	do
		local board = isp.garage.keyBoard
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Recolher carro"
		prompt.ObjectText = "Quadro de chaves"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Parent = board
		keyPrompt = prompt
		prompt.Triggered:Connect(function(player)
			if not own(player) then
				return
			end
			if not Car.owned then
				Remotes.notify(player, "O provedor ainda não tem carro. Compre no terminal de compras, aba Equipe.", "info")
				return
			end
			refreshState()
			if Car.state == "garage" then
				Remotes.notify(player, "O carro já está na garagem.", "info")
				return
			end
			Car.recall(player)
		end)
	end

	return Car
end

return CarModule
