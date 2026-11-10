-- Direção do carro da equipe. Quando o jogador senta no banco do motorista, o cliente
-- dele é dono da física do carro e move o alvo do AlignPosition/AlignOrientation:
-- W/S acelera e freia (ré), A/D vira. Bater de frente em parede ou poste para o carro.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local C = Config.Car
local player = Players.LocalPlayer

local HOVER = 1.8
local conn: RBXScriptConnection? = nil
local lastSeat: BasePart? = nil

local function stop()
	if conn then
		conn:Disconnect()
		conn = nil
	end
end

local function drive(seat: VehicleSeat)
	stop()
	local model = seat.Parent :: Model
	local chassis = model:FindFirstChild("Chassi") :: BasePart
	if not chassis then
		return
	end
	local ap = chassis:FindFirstChildOfClass("AlignPosition")
	local ao = chassis:FindFirstChildOfClass("AlignOrientation")
	if not ap or not ao then
		return
	end
	local look = chassis.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local pos = chassis.Position
	local speed = 0
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true

	local function refreshFilter()
		local ignore: { Instance } = { model }
		for _, p in Players:GetPlayers() do
			if p.Character then
				table.insert(ignore, p.Character)
			end
		end
		local vila = workspace:FindFirstChild("VilaAurora")
		local npcs = vila and vila:FindFirstChild("Moradores")
		if npcs then
			table.insert(ignore, npcs)
		end
		params.FilterDescendantsInstances = ignore
	end
	refreshFilter()
	local filterClock = 0

	local function groundY(p: Vector3): number
		local hit = workspace:Raycast(Vector3.new(p.X, 5, p.Z), Vector3.new(0, -12, 0), params)
		return if hit then hit.Position.Y else p.Y - HOVER
	end

	conn = RunService.Heartbeat:Connect(function(dt)
		local occ = seat.Occupant
		if not occ or occ.Parent ~= player.Character then
			stop()
			return
		end
		filterClock += dt
		if filterClock > 2 then
			filterClock = 0
			refreshFilter()
		end
		local throttle = seat.ThrottleFloat
		local steer = seat.SteerFloat
		if throttle > 0 then
			speed = math.min(C.MaxSpeed, speed + C.Accel * dt * (if speed < 0 then 3 else 1))
		elseif throttle < 0 then
			speed = math.max(-C.ReverseSpeed, speed - C.Accel * dt * (if speed > 0 then 3 else 1))
		else
			speed *= 1 - math.min(1, dt * 1.5)
			if math.abs(speed) < 0.3 then
				speed = 0
			end
		end
		local grip = math.clamp(math.abs(speed) / 20, 0, 1)
		yaw += -steer * C.TurnRate * grip * (if speed < 0 then -1 else 1) * dt
		local fwd = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
		local step = fwd * speed * dt
		if math.abs(speed) > 0.1 then
			-- para ao encostar em parede, poste ou árvore
			local dirSign = if speed > 0 then 1 else -1
			local hit = workspace:Raycast(pos + Vector3.new(0, 0.9, 0), fwd * dirSign * (6.6 + math.abs(speed * dt)), params)
			if hit then
				speed = 0
				step = Vector3.zero
			end
		end
		local np = pos + step
		local y = groundY(np) + HOVER
		pos = Vector3.new(np.X, pos.Y + (y - pos.Y) * math.min(1, dt * 12), np.Z)
		ap.Position = pos
		ao.CFrame = CFrame.Angles(0, yaw, 0)
	end)
end

local function hookCharacter(char: Model)
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	hum.Seated:Connect(function(active, seatPart)
		if active and seatPart and seatPart:IsA("VehicleSeat") and seatPart.Parent and seatPart.Parent.Name == "CarroEquipe" then
			lastSeat = seatPart
			-- espera o servidor passar a física do carro para este cliente
			task.wait(0.15)
			drive(seatPart)
		elseif active and seatPart and seatPart.Parent and seatPart.Parent.Name == "CarroEquipe" then
			lastSeat = seatPart
		else
			stop()
			-- saiu do carro: desce ao lado da porta, parado (sem ser arremessado)
			local seat = lastSeat
			lastSeat = nil
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if seat and root then
				task.wait()
				local side = if seat.Name == "Carona" then 1 else -1
				local p = seat.Position + seat.CFrame.RightVector * (4.5 * side)
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
				char:PivotTo(CFrame.new(Vector3.new(p.X, 3.5, p.Z)) * seat.CFrame.Rotation)
			end
		end
	end)
end

if player.Character then
	hookCharacter(player.Character)
end
player.CharacterAdded:Connect(hookCharacter)
