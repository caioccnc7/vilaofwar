-- Constrói a Vila Aurora por código: chão, rua, casas, postes, praça e o prédio do provedor.
-- Tudo é gerado quando o servidor inicia, então o mapa vive no código e é fácil de ajustar.

local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local World = {}

local SMOOTH = Enum.SurfaceType.Smooth

local function part(props: { [string]: any }): BasePart
	local p = Instance.new(props.Class or "Part") :: BasePart
	p.Anchored = true
	p.TopSurface = SMOOTH
	p.BottomSurface = SMOOTH
	p.Material = Enum.Material.SmoothPlastic
	if props.Size then
		p.Size = props.Size
	end
	for k, v in props do
		if k ~= "Class" and k ~= "Parent" and k ~= "Size" then
			(p :: any)[k] = v
		end
	end
	p.Parent = props.Parent
	return p
end
World.part = part

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function textOn(target: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3?, font: Enum.Font?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = target
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = if bg then 0 else 1
	label.BackgroundColor3 = bg or Color3.new(0, 0, 0)
	label.Text = text
	label.TextScaled = true
	label.Font = font or Enum.Font.GothamBold
	label.TextColor3 = color
	label.Parent = gui
	return label
end
World.textOn = textOn

-- Cabo como uma sequência de cilindros finos entre os pontos.
function World.cable(points: { Vector3 }, color: Color3, parent: Instance, name: string): { BasePart }
	local segs = {}
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local len = (b - a).Magnitude
		local seg = part({
			Name = name .. "_" .. i,
			Size = Vector3.new(0.22, 0.22, len),
			CFrame = CFrame.lookAt((a + b) / 2, b),
			Color = color,
			CanCollide = false,
			CastShadow = false,
			Parent = parent,
		})
		table.insert(segs, seg)
	end
	return segs
end

local function setupLighting()
	Lighting.ClockTime = 8
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(70, 70, 80)
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 120, 130)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atm = Instance.new("Atmosphere")
		atm.Density = 0.28
		atm.Haze = 1.2
		atm.Color = Color3.fromRGB(199, 214, 230)
		atm.Decay = Color3.fromRGB(106, 112, 125)
		atm.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("BloomEffect") then
		local bloom = Instance.new("BloomEffect")
		bloom.Intensity = 0.35
		bloom.Size = 30
		bloom.Threshold = 2.2
		bloom.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("ColorCorrectionEffect") then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Saturation = 0.08
		cc.Contrast = 0.05
		cc.Parent = Lighting
	end
end

local function streetLamp(pos: Vector3, facing: number | Vector3, parent: Instance)
	-- facing: -1/1 (braço no eixo Z, rua principal) ou um vetor (ruas transversais)
	local dir = if typeof(facing) == "Vector3" then facing else Vector3.new(0, 0, facing :: number)
	part({ Name = "LampPole", Size = Vector3.new(0.6, 14, 0.6), CFrame = CFrame.new(pos + Vector3.new(0, 7, 0)), Color = Color3.fromRGB(45, 45, 50), Material = Enum.Material.Metal, Parent = parent })
	part({ Name = "LampArm", Size = Vector3.new(0.4, 0.4, 4), CFrame = CFrame.lookAt(pos + Vector3.new(0, 13.8, 0) + dir * 2, pos + Vector3.new(0, 13.8, 0) + dir * 3), Color = Color3.fromRGB(45, 45, 50), Material = Enum.Material.Metal, Parent = parent })
	local head = part({ Name = "LampHead", Size = Vector3.new(1.6, 0.5, 1.2), CFrame = CFrame.new(pos + Vector3.new(0, 13.5, 0) + dir * 3.8), Color = Color3.fromRGB(255, 236, 190), Material = Enum.Material.Neon, CastShadow = false, Parent = parent })
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Angle = 110
	light.Range = 30
	light.Brightness = 2
	light.Color = Color3.fromRGB(255, 226, 170)
	light.Parent = head
	CollectionService:AddTag(head, "StreetLight")
end

local function tree(pos: Vector3, parent: Instance, scale: number?)
	local s = scale or 1
	part({ Name = "Trunk", Size = Vector3.new(1.4 * s, 8 * s, 1.4 * s), CFrame = CFrame.new(pos + Vector3.new(0, 4 * s, 0)), Color = Color3.fromRGB(105, 74, 49), Material = Enum.Material.Wood, Parent = parent })
	part({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(9, 9, 9) * s, CFrame = CFrame.new(pos + Vector3.new(0, 10 * s, 0)), Color = Color3.fromRGB(76, 145, 65), Material = Enum.Material.Grass, Parent = parent })
	part({ Name = "Leaves2", Shape = Enum.PartType.Ball, Size = Vector3.new(6, 6, 6) * s, CFrame = CFrame.new(pos + Vector3.new(2 * s, 12.5 * s, 1 * s)), Color = Color3.fromRGB(92, 160, 72), Material = Enum.Material.Grass, Parent = parent })
end

local function bench(cf: CFrame, parent: Instance)
	part({ Name = "BenchSeat", Size = Vector3.new(6, 0.4, 2), CFrame = cf * CFrame.new(0, 1.6, 0), Color = Color3.fromRGB(140, 96, 58), Material = Enum.Material.Wood, Parent = parent })
	part({ Name = "BenchBack", Size = Vector3.new(6, 1.6, 0.3), CFrame = cf * CFrame.new(0, 2.6, 0.9), Color = Color3.fromRGB(140, 96, 58), Material = Enum.Material.Wood, Parent = parent })
	for _, dx in { -2.6, 2.6 } do
		part({ Name = "BenchLeg", Size = Vector3.new(0.3, 1.5, 1.8), CFrame = cf * CFrame.new(dx, 0.75, 0), Color = Color3.fromRGB(40, 40, 45), Material = Enum.Material.Metal, Parent = parent })
	end
end

-- Rua Principal (eixo X, z = 0) vai do provedor até a esquina com a Rua das Palmeiras.
-- A Rua das Palmeiras (eixo Z, x = 300) sobe para o norte, longe do provedor.
World.MainRoadX = { -210, 330 }
World.PalmX = 300 -- eixo da Rua das Palmeiras
World.PalmZ = { -262, -12 }

local function buildGround(parent: Instance)
	part({ Name = "Grass", Size = Vector3.new(820, 2, 600), CFrame = CFrame.new(60, -1, -50), Color = Color3.fromRGB(96, 158, 78), Material = Enum.Material.Grass, Parent = parent })
	local rx0, rx1 = World.MainRoadX[1], World.MainRoadX[2]
	local rlen, rcx = rx1 - rx0, (rx0 + rx1) / 2
	part({ Name = "Road", Size = Vector3.new(rlen, 0.2, 24), CFrame = CFrame.new(rcx, 0.1, 0), Color = Color3.fromRGB(52, 54, 58), Material = Enum.Material.Asphalt, Parent = parent })
	for x = rx0 + 10, rx1 - 10, 14 do
		part({ Name = "LaneDash", Size = Vector3.new(6, 0.05, 0.5), CFrame = CFrame.new(x, 0.22, 0), Color = Color3.fromRGB(240, 220, 120), CanCollide = false, Parent = parent })
	end
	-- calçada sul inteira; a do norte é cortada na esquina da Rua das Palmeiras
	local px = World.PalmX
	local function walkway(x0: number, x1: number, z: number)
		part({ Name = "Sidewalk", Size = Vector3.new(x1 - x0, 0.5, 6), CFrame = CFrame.new((x0 + x1) / 2, 0.25, z), Color = Color3.fromRGB(196, 192, 184), Material = Enum.Material.Concrete, Parent = parent })
		part({ Name = "Curb", Size = Vector3.new(x1 - x0, 0.6, 0.4), CFrame = CFrame.new((x0 + x1) / 2, 0.3, z - 3 * math.sign(z)), Color = Color3.fromRGB(160, 156, 150), Material = Enum.Material.Concrete, Parent = parent })
	end
	walkway(rx0, rx1, 15)
	walkway(rx0, px - 12, -15)
	walkway(px + 12, rx1, -15)
	-- postes de luz e árvores ao longo da rua
	for x = -170, rx1 - 30, 50 do
		streetLamp(Vector3.new(x, 0.5, 17), -1, parent)
		if x + 25 < px - 20 then
			streetLamp(Vector3.new(x + 25, 0.5, -17), 1, parent)
		end
	end
	for _, x in { -165, 140, 165, 190, 215, 240 } do
		-- o lado norte entre x 140 e 240 é o terreno do prédio 2
		if x < 135 then
			tree(Vector3.new(x, 0, -30), parent)
		end
		tree(Vector3.new(x, 0, 30), parent, 0.9)
	end
	for _, x in { 265, 290, 315 } do
		tree(Vector3.new(x, 0, 32), parent, 1.1)
	end

	-- Rua das Palmeiras
	local z0, z1 = World.PalmZ[1], World.PalmZ[2]
	local plen, pcz = z1 - z0, (z0 + z1) / 2
	part({ Name = "RoadPalmeiras", Size = Vector3.new(24, 0.2, plen), CFrame = CFrame.new(px, 0.1, pcz), Color = Color3.fromRGB(52, 54, 58), Material = Enum.Material.Asphalt, Parent = parent })
	for z = z1 - 12, z0 + 8, -14 do
		part({ Name = "LaneDash", Size = Vector3.new(0.5, 0.05, 6), CFrame = CFrame.new(px, 0.22, z), Color = Color3.fromRGB(240, 220, 120), CanCollide = false, Parent = parent })
	end
	for _, side in { -1, 1 } do
		local sx = px + side * 15
		local slen = (z1 - 6) - z0
		part({ Name = "Sidewalk", Size = Vector3.new(6, 0.5, slen), CFrame = CFrame.new(sx, 0.25, z0 + slen / 2), Color = Color3.fromRGB(196, 192, 184), Material = Enum.Material.Concrete, Parent = parent })
		part({ Name = "Curb", Size = Vector3.new(0.4, 0.6, slen), CFrame = CFrame.new(sx - 3 * side, 0.3, z0 + slen / 2), Color = Color3.fromRGB(160, 156, 150), Material = Enum.Material.Concrete, Parent = parent })
	end
	-- fim da rua: canteiro com palmeiras
	part({ Name = "Canteiro", Size = Vector3.new(40, 1.2, 6), CFrame = CFrame.new(px, 0.6, z0 - 3), Color = Color3.fromRGB(150, 120, 90), Material = Enum.Material.Brick, Parent = parent })
	for z = z1 - 40, z0 + 10, -50 do
		streetLamp(Vector3.new(px - 17, 0.5, z), Vector3.new(1, 0, 0), parent)
		streetLamp(Vector3.new(px + 17, 0.5, z - 25), Vector3.new(-1, 0, 0), parent)
	end
	local function palm(pos: Vector3)
		part({ Name = "PalmTrunk", Size = Vector3.new(1.1, 13, 1.1), CFrame = CFrame.new(pos + Vector3.new(0, 6.5, 0)), Color = Color3.fromRGB(140, 110, 75), Material = Enum.Material.Wood, Parent = parent })
		for a = 0, 300, 60 do
			local cf = CFrame.new(pos + Vector3.new(0, 13, 0)) * CFrame.Angles(0, math.rad(a), 0) * CFrame.Angles(math.rad(-25), 0, 0) * CFrame.new(0, 0, -2.6)
			part({ Name = "PalmLeaf", Size = Vector3.new(1.4, 0.2, 5.5), CFrame = cf, Color = Color3.fromRGB(60, 140, 60), Material = Enum.Material.Grass, CanCollide = false, Parent = parent })
		end
	end
	for _, dx in { -14, -4, 6, 16 } do
		palm(Vector3.new(px + dx, 1.2, z0 - 3))
	end
	for _, z in { -85, -135, -185, -235 } do
		tree(Vector3.new(232, 0, z), parent, 1.1)
		tree(Vector3.new(368, 0, z + 20), parent)
	end
	-- placas de rua na esquina
	local function streetSign(pos: Vector3, text: string, yaw: number)
		part({ Name = "StreetSignPost", Size = Vector3.new(0.3, 8, 0.3), CFrame = CFrame.new(pos + Vector3.new(0, 4, 0)), Color = Color3.fromRGB(60, 60, 60), Parent = parent })
		local plate = part({ Name = "StreetSign", Size = Vector3.new(7, 1.3, 0.2), CFrame = CFrame.new(pos + Vector3.new(0, 7.6, 0)) * CFrame.Angles(0, math.rad(yaw), 0), Color = Color3.fromRGB(30, 80, 150), Parent = parent })
		textOn(plate, Enum.NormalId.Front, text, Color3.new(1, 1, 1))
		textOn(plate, Enum.NormalId.Back, text, Color3.new(1, 1, 1))
	end
	streetSign(Vector3.new(px - 16, 0.5, -19), "Rua das Palmeiras", 90)
	streetSign(Vector3.new(px - 20, 0.5, -16), "Rua Principal", 0)

	-- placa de entrada da cidade, no fim da Rua Principal
	local sign = part({ Name = "CitySign", Size = Vector3.new(12, 4, 0.4), CFrame = CFrame.new(rx1 + 4, 6, 20) * CFrame.Angles(0, math.rad(-90), 0), Color = Color3.fromRGB(30, 110, 70), Parent = parent })
	textOn(sign, Enum.NormalId.Front, "Bem-vindo à " .. Config.CityName, Color3.new(1, 1, 1))
	textOn(sign, Enum.NormalId.Back, "Bem-vindo à " .. Config.CityName, Color3.new(1, 1, 1))
	part({ Name = "CitySignPost", Size = Vector3.new(0.5, 4, 0.5), CFrame = CFrame.new(rx1 + 4, 2, 20), Color = Color3.fromRGB(60, 60, 60), Parent = parent })
end

-- Caminho a pé (ou de carro) entre dois pontos, sempre pela pista: anda pela faixa
-- da Rua Principal (z = ±8) e, se precisar, entra na Rua das Palmeiras (x = 300 ± 8).
local function onPalm(p: Vector3): boolean
	return p.X > World.PalmX - 30 and p.Z < -14
end
local function mainLane(p: Vector3): number
	return if math.abs(p.Z) < 12 then p.Z else math.sign(p.Z) * 8
end
local function palmLane(p: Vector3): number
	local dx = p.X - World.PalmX
	return if math.abs(dx) < 12 then p.X else World.PalmX + math.sign(dx) * 8
end
function World.path(from: Vector3, to: Vector3, y: number?): { Vector3 }
	local h = y or 0.6
	local pts = {}
	local function add(x: number, z: number)
		table.insert(pts, Vector3.new(x, h, z))
	end
	local a, b = onPalm(from), onPalm(to)
	if a and b then
		add(palmLane(from), from.Z)
		add(palmLane(to), to.Z)
	else
		if a then
			add(palmLane(from), from.Z)
			add(palmLane(from), -8)
		else
			add(from.X, mainLane(from))
		end
		if b then
			add(palmLane(to), -8)
			add(palmLane(to), to.Z)
		else
			add(to.X, mainLane(to))
		end
	end
	table.insert(pts, Vector3.new(to.X, h, to.Z))
	return pts
end

local function buildPlaza(parent: Instance): { Vector3 }
	local c = Vector3.new(-120, 0, 42)
	part({ Name = "PlazaFloor", Size = Vector3.new(44, 0.4, 28), CFrame = CFrame.new(c + Vector3.new(0, 0.2, 0)), Color = Color3.fromRGB(205, 186, 160), Material = Enum.Material.Pebble, Parent = parent })
	part({ Name = "Fountain", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 10, 10), CFrame = CFrame.new(c + Vector3.new(0, 0.9, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(170, 170, 175), Material = Enum.Material.Marble, Parent = parent })
	part({ Name = "Water", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 8.6, 8.6), CFrame = CFrame.new(c + Vector3.new(0, 1.55, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(80, 160, 220), Material = Enum.Material.Glass, Transparency = 0.3, CanCollide = false, Parent = parent })
	tree(c + Vector3.new(-16, 0.4, 8), parent)
	tree(c + Vector3.new(16, 0.4, 8), parent)
	bench(CFrame.new(c + Vector3.new(-8, 0.4, -9)) * CFrame.Angles(0, math.rad(180), 0), parent)
	bench(CFrame.new(c + Vector3.new(8, 0.4, -9)) * CFrame.Angles(0, math.rad(180), 0), parent)
	bench(CFrame.new(c + Vector3.new(0, 0.4, 11)), parent)
	-- pontos onde os moradores param na praça
	return {
		c + Vector3.new(-8, 0.5, -6),
		c + Vector3.new(8, 0.5, -6),
		c + Vector3.new(-12, 0.5, 2),
		c + Vector3.new(12, 0.5, 2),
		c + Vector3.new(0, 0.5, 8),
	}
end

-- ---------------------------------------------------------------------------
-- Casas
-- ---------------------------------------------------------------------------

local HouseColors = {
	Color3.fromRGB(240, 214, 170),
	Color3.fromRGB(176, 214, 230),
	Color3.fromRGB(240, 190, 180),
	Color3.fromRGB(200, 226, 186),
	Color3.fromRGB(245, 235, 200),
	Color3.fromRGB(215, 196, 230),
	Color3.fromRGB(250, 220, 150),
	Color3.fromRGB(190, 205, 220),
}
local RoofColors = {
	Color3.fromRGB(150, 70, 55),
	Color3.fromRGB(80, 80, 90),
	Color3.fromRGB(120, 60, 50),
	Color3.fromRGB(70, 90, 110),
}

export type House = {
	index: number,
	model: Model,
	position: Vector3,
	doorPoint: Vector3, -- calçada em frente à porta
	yardPoint: Vector3, -- quintal, em frente à casa
	box: BasePart, -- caixa da ONU na fachada
	led: BasePart,
	wantSign: BasePart,
	side: number, -- -1 = Principal norte, 1 = Principal sul, 2 = Palmeiras oeste, 3 = Palmeiras leste
	street: string, -- "Rua Principal" ou "Rua das Palmeiras"
	cto: string, -- id da CTO que atende a casa
	dropMid: Vector3, -- ponto no alinhamento dos postes por onde o drop passa
}

local function buildHouse(index: number, center: Vector3, facing: Vector3, side: number, parent: Instance): House
	local model = Instance.new("Model")
	model.Name = "Casa" .. index
	model.Parent = parent
	local base = CFrame.lookAt(center, center + facing) -- local -Z = frente (aponta para a rua)
	local wall = HouseColors[(index - 1) % #HouseColors + 1]
	local roof = RoofColors[(index - 1) % #RoofColors + 1]
	local white = Color3.fromRGB(248, 248, 245)

	local function lp(name: string, size: Vector3, offset: CFrame, color: Color3, extra: { [string]: any }?)
		local props: { [string]: any } = { Name = name, Size = size, CFrame = base * offset, Color = color, Parent = model }
		if extra then
			for k, v in extra do
				props[k] = v
			end
		end
		return part(props)
	end

	lp("Foundation", Vector3.new(22, 1, 18), CFrame.new(0, 0.5, 0), Color3.fromRGB(150, 145, 140), { Material = Enum.Material.Concrete })
	lp("Body", Vector3.new(20, 11, 16), CFrame.new(0, 6.5, 0), wall, { Material = Enum.Material.Plaster })
	lp("Trim", Vector3.new(20.6, 0.6, 16.6), CFrame.new(0, 12.2, 0), white)
	lp("RoofFront", Vector3.new(22, 5, 9.2), CFrame.new(0, 15, -4.6), roof, { Class = "WedgePart", Material = Enum.Material.Slate })
	lp("RoofBack", Vector3.new(22, 5, 9.2), CFrame.new(0, 15, 4.6) * CFrame.Angles(0, math.rad(180), 0), roof, { Class = "WedgePart", Material = Enum.Material.Slate })
	lp("Chimney", Vector3.new(2, 5, 2), CFrame.new(6, 16, 3), Color3.fromRGB(150, 90, 80), { Material = Enum.Material.Brick })
	-- porta, janelas e varanda
	lp("Door", Vector3.new(4, 7, 0.3), CFrame.new(-4, 4.5, -8.1), Color3.fromRGB(110, 70, 45), { Material = Enum.Material.Wood })
	lp("DoorKnob", Vector3.new(0.4, 0.4, 0.3), CFrame.new(-2.6, 4.5, -8.3), Color3.fromRGB(220, 190, 90), { Material = Enum.Material.Metal })
	lp("Porch", Vector3.new(10, 0.5, 4), CFrame.new(-4, 1.25, -10), Color3.fromRGB(170, 140, 110), { Material = Enum.Material.WoodPlanks })
	for _, wx in { 4.5 } do
		lp("WindowFrame", Vector3.new(5, 4, 0.2), CFrame.new(wx, 7, -8.05), white)
		lp("Window", Vector3.new(4.4, 3.4, 0.2), CFrame.new(wx, 7, -8.15), Color3.fromRGB(170, 210, 235), { Material = Enum.Material.Glass, Transparency = 0.25 })
	end
	for _, wz in { -3, 3 } do
		lp("SideWindowL", Vector3.new(0.2, 3.4, 4), CFrame.new(-10.1, 7, wz), Color3.fromRGB(170, 210, 235), { Material = Enum.Material.Glass, Transparency = 0.25 })
		lp("SideWindowR", Vector3.new(0.2, 3.4, 4), CFrame.new(10.1, 7, wz), Color3.fromRGB(170, 210, 235), { Material = Enum.Material.Glass, Transparency = 0.25 })
	end
	-- número da casa
	local plate = lp("Number", Vector3.new(2.4, 1.2, 0.2), CFrame.new(-4, 9, -8.2), Color3.fromRGB(30, 60, 110))
	textOn(plate, Enum.NormalId.Front, tostring(index), Color3.new(1, 1, 1))
	-- jardim e cerca baixa
	lp("Hedge", Vector3.new(8, 2, 1.5), CFrame.new(6, 1, -11), Color3.fromRGB(70, 130, 60), { Material = Enum.Material.Grass })
	lp("Path", Vector3.new(4, 0.2, 8), CFrame.new(-4, 0.1, -14), Color3.fromRGB(190, 180, 165), { Material = Enum.Material.Slate })
	local mail = lp("Mailbox", Vector3.new(1.2, 1, 1.6), CFrame.new(-8, 3.5, -16), Color3.fromRGB(200, 60, 50), { Material = Enum.Material.Metal })
	mail.Name = "Mailbox"
	lp("MailPost", Vector3.new(0.3, 3, 0.3), CFrame.new(-8, 1.5, -16), Color3.fromRGB(60, 60, 60))

	-- caixa da ONU na fachada, com LED de status
	local box = lp("OnuBox", Vector3.new(1.6, 2, 0.7), CFrame.new(7.5, 8, -8.4), white)
	local led = lp("OnuLed", Vector3.new(0.35, 0.35, 0.1), CFrame.new(7.5, 8.4, -8.8), Color3.fromRGB(80, 80, 80), { Material = Enum.Material.Neon, CastShadow = false })
	-- detalhes da ONU: placa de fixação, antenas do Wi-Fi, LEDs fixos e etiqueta
	lp("OnuPlaca", Vector3.new(2, 2.4, 0.08), CFrame.new(7.5, 8, -8.06), Color3.fromRGB(150, 150, 155), { CanCollide = false })
	for _, ax in { 6.95, 8.05 } do
		lp("OnuAntena", Vector3.new(0.14, 0.9, 0.14), CFrame.new(ax, 9.45, -8.4), Color3.fromRGB(235, 235, 235), { CanCollide = false })
	end
	lp("OnuLedPwr", Vector3.new(0.18, 0.18, 0.06), CFrame.new(7.0, 8.45, -8.78), Color3.fromRGB(60, 220, 90), { Material = Enum.Material.Neon, CastShadow = false, CanCollide = false })
	lp("OnuBotao", Vector3.new(0.22, 0.22, 0.06), CFrame.new(8.0, 8.45, -8.78), Color3.fromRGB(70, 72, 78), { CastShadow = false, CanCollide = false })
	local onuTag = lp("OnuEtiqueta", Vector3.new(1.3, 0.55, 0.04), CFrame.new(7.5, 7.6, -8.77), Color3.fromRGB(248, 248, 248), { CanCollide = false })
	textOn(onuTag, Enum.NormalId.Front, "ONU GPON", Color3.fromRGB(90, 95, 105))
	CollectionService:AddTag(box, "OnuBox")

	-- placa "Quero internet!" para casas sem contrato
	local want = lp("WantSign", Vector3.new(5, 2.4, 0.2), CFrame.new(5, 3, -15.5), Color3.fromRGB(255, 250, 230))
	textOn(want, Enum.NormalId.Front, "Quero internet!", Color3.fromRGB(200, 60, 40))
	lp("WantSignPost", Vector3.new(0.3, 2, 0.3), CFrame.new(5, 1, -15.4), Color3.fromRGB(110, 80, 50), { Name = "WantSignPost" })

	return {
		index = index,
		model = model,
		position = center,
		doorPoint = (base * CFrame.new(-4, 0.5, -19.5)).Position,
		yardPoint = (base * CFrame.new(-4, 0.5, -13)).Position,
		box = box,
		led = led,
		wantSign = want,
		side = side,
		street = if side >= 2 then "Rua das Palmeiras" else "Rua Principal",
		cto = "",
		dropMid = if side >= 2 then Vector3.new(World.PalmX + (if side == 2 then -16.5 else 16.5), 14, box.Position.Z) else Vector3.new(box.Position.X, 14, side * 16.5),
	}
end

-- ---------------------------------------------------------------------------
-- Postes e caixas (splitter / CTO)
-- ---------------------------------------------------------------------------

export type Pole = { name: string, top: Vector3, base: Vector3 }

local function buildPole(name: string, x: number, z: number, parent: Instance): Pole
	local base = Vector3.new(x, 0.5, z)
	part({ Name = name, Shape = Enum.PartType.Cylinder, Size = Vector3.new(18, 1.1, 1.1), CFrame = CFrame.new(base + Vector3.new(0, 9, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(150, 145, 135), Material = Enum.Material.Concrete, Parent = parent })
	part({ Name = name .. "_Arm", Size = Vector3.new(0.5, 0.5, 5), CFrame = CFrame.new(base + Vector3.new(0, 16.5, 0)), Color = Color3.fromRGB(80, 80, 80), Material = Enum.Material.Metal, Parent = parent })
	return { name = name, top = base + Vector3.new(0, 16, 0), base = base }
end

local function buildBox(name: string, label: string, pole: Pole, color: Color3, parent: Instance, offset: Vector3?): BasePart
	local off = offset or Vector3.new(0, 0, 0.9 * -math.sign(pole.base.Z))
	local center = pole.base + Vector3.new(0, 12, 0) + off
	local bcf = CFrame.lookAt(center, center + Vector3.new(off.X, 0, off.Z).Unit) -- frente (-Z) para a rua
	local box = part({ Name = name, Size = Vector3.new(1.8, 2.6, 1.2), CFrame = bcf, Color = color, Material = Enum.Material.SmoothPlastic, Parent = parent })
	local function bp(pname: string, size: Vector3, offCf: CFrame, pcolor: Color3, extra: { [string]: any }?)
		local props: { [string]: any } = { Name = pname, Size = size, CFrame = bcf * offCf, Color = pcolor, CanCollide = false, CastShadow = false, Parent = parent }
		if extra then
			for k, v in extra do
				props[k] = v
			end
		end
		return part(props)
	end
	local darker = color:Lerp(Color3.new(0, 0, 0), 0.25)
	-- tampa, fecho, emenda da porta e etiqueta
	bp(name .. "_Tampa", Vector3.new(1.95, 0.22, 1.32), CFrame.new(0, 1.38, 0), darker)
	bp(name .. "_Emenda", Vector3.new(1.82, 0.04, 0.02), CFrame.new(0, 0.75, -0.61), darker)
	bp(name .. "_Fecho", Vector3.new(0.18, 0.32, 0.08), CFrame.new(0.65, 0.35, -0.64), Color3.fromRGB(170, 172, 178), { Material = Enum.Material.Metal })
	local plate = bp(name .. "_Etiqueta", Vector3.new(1.3, 0.5, 0.02), CFrame.new(0, -0.35, -0.61), Color3.fromRGB(245, 245, 240))
	textOn(plate, Enum.NormalId.Front, label .. "\nREDE DA VILA", Color3.fromRGB(30, 40, 70))
	local warn = bp(name .. "_Laser", Vector3.new(0.4, 0.4, 0.02), CFrame.new(-0.55, 0.35, -0.61), Color3.fromRGB(250, 205, 30))
	textOn(warn, Enum.NormalId.Front, "⚠", Color3.fromRGB(20, 20, 20))
	-- prensa-cabos embaixo, por onde saem os drops
	for i = 0, 3 do
		bp(name .. "_Prensa", Vector3.new(0.12, 0.22, 0.22), CFrame.new(-0.6 + i * 0.4, -1.38, -0.1) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(25, 25, 28), { Shape = Enum.PartType.Cylinder })
	end
	-- cintas de aço prendendo a caixa no poste
	for _, y in { -0.8, 0.8 } do
		bp(name .. "_Cinta", Vector3.new(1.4, 0.1, 0.1), CFrame.new(0, y, 0.95), Color3.fromRGB(150, 152, 158), { Material = Enum.Material.Metal })
		for _, x in { -0.65, 0.65 } do
			bp(name .. "_Cinta", Vector3.new(0.1, 0.1, 0.7), CFrame.new(x, y, 0.75), Color3.fromRGB(150, 152, 158), { Material = Enum.Material.Metal })
		end
	end
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(110, 26)
	bb.StudsOffset = Vector3.new(0, 2.2, 0)
	bb.MaxDistance = 70
	bb.AlwaysOnTop = false
	bb.Parent = box
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
	t.BackgroundTransparency = 0.2
	t.TextColor3 = Color3.new(1, 1, 1)
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.Text = label
	t.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = t
	return box
end

-- ---------------------------------------------------------------------------
-- Prédio do provedor
-- ---------------------------------------------------------------------------

export type Isp = {
	model: Model,
	spawn: SpawnLocation,
	trunkExit: Vector3,
	entrance: Vector3, -- calçada em frente à porta
	reception: Vector3, -- onde moradores reclamam
	rackFront: Vector3, -- centro da frente do rack principal, no chão do datacenter
	floorY: number, -- piso do térreo
	dcFloorY: number, -- piso do datacenter (2º andar)
	dc: { [string]: any }, -- pontos do datacenter usados pelos cabos (DIO, operadora, eletrocalha)
	rack: BasePart,
	shelf: BasePart,
	signNeon: { BasePart },
	garage: { [string]: any },
	slot: number, -- 1 = prédio da Rua Principal oeste, 2 = prédio da Rua Principal leste
	offset: Vector3, -- deslocamento deste prédio em relação ao prédio 1 (as coordenadas fixas dos serviços somam isso)
	nameLabels: { TextLabel }, -- letreiro e parede da recepção, com o nome do provedor
}

-- Deslocamento de cada prédio. O prédio 2 é uma cópia do 1, mais a leste na mesma calçada.
World.IspOffsets = { Vector3.new(0, 0, 0), Vector3.new(290, 0, 0) }

local function buildIsp(parent: Instance, slot: number): Isp
	local model = Instance.new("Model")
	model.Name = if slot == 1 then "Provedor" else "Provedor" .. slot
	model.Parent = parent
	local x0, x1, zb, zf = -148, -92, -58, -22
	local cx, cz = (x0 + x1) / 2, (zb + zf) / 2
	local W, D = x1 - x0, zf - zb -- 56 x 36
	local concrete = Color3.fromRGB(232, 232, 228)
	local dark = Color3.fromRGB(38, 42, 52)
	local metal = Color3.fromRGB(70, 74, 82)
	local glassColor = Color3.fromRGB(150, 200, 230)
	local f1, slab, f2top = 0.5, 15, 29

	local function P(props: { [string]: any })
		props.Parent = props.Parent or model
		return part(props)
	end

	-- base e calçada da frente
	P({ Name = "Foundation", Size = Vector3.new(W + 4, 1, D + 4), CFrame = CFrame.new(cx, 0, cz), Color = Color3.fromRGB(120, 120, 125), Material = Enum.Material.Concrete })
	P({ Name = "FloorTiles", Size = Vector3.new(W - 1, 0.1, D - 1), CFrame = CFrame.new(cx, 0.55, cz), Color = Color3.fromRGB(225, 222, 215), Material = Enum.Material.Marble })
	P({ Name = "Forecourt", Size = Vector3.new(W, 0.3, 4.5), CFrame = CFrame.new(cx, 0.15, zf + 2.25), Color = Color3.fromRGB(90, 92, 98), Material = Enum.Material.Slate })

	-- paredes do térreo (fundos e laterais)
	P({ Name = "BackWall1", Size = Vector3.new(W, slab - f1, 1), CFrame = CFrame.new(cx, (f1 + slab) / 2, zb + 0.5), Color = concrete, Material = Enum.Material.Concrete })
	P({ Name = "WestWall1", Size = Vector3.new(1, slab - f1, D), CFrame = CFrame.new(x0 + 0.5, (f1 + slab) / 2, cz), Color = concrete, Material = Enum.Material.Concrete })
	P({ Name = "EastWall1", Size = Vector3.new(1, slab - f1, D), CFrame = CFrame.new(x1 - 0.5, (f1 + slab) / 2, cz), Color = concrete, Material = Enum.Material.Concrete })

	-- fachada de vidro do térreo, com vão da porta (x -124 a -116)
	local doorL, doorR = -124, -116
	local h1 = 10.5
	P({ Name = "GlassL", Size = Vector3.new(doorL - x0 - 1, h1, 0.4), CFrame = CFrame.new((x0 + 1 + doorL) / 2, f1 + h1 / 2, zf - 0.5), Color = glassColor, Material = Enum.Material.Glass, Transparency = 0.55 })
	P({ Name = "GlassR", Size = Vector3.new(x1 - 1 - doorR, h1, 0.4), CFrame = CFrame.new((doorR + x1 - 1) / 2, f1 + h1 / 2, zf - 0.5), Color = glassColor, Material = Enum.Material.Glass, Transparency = 0.55 })
	P({ Name = "GlassTop", Size = Vector3.new(W - 2, slab - f1 - h1, 0.4), CFrame = CFrame.new(cx, f1 + h1 + (slab - f1 - h1) / 2, zf - 0.5), Color = glassColor, Material = Enum.Material.Glass, Transparency = 0.45 })
	for mx = x0 + 1, x1 - 1, 6 do
		if mx > doorL - 0.5 and mx < doorR + 0.5 then
			continue
		end
		P({ Name = "Mullion", Size = Vector3.new(0.4, slab - f1, 0.6), CFrame = CFrame.new(mx, (f1 + slab) / 2, zf - 0.5), Color = metal, Material = Enum.Material.Metal })
	end
	for _, dx in { doorL, doorR } do
		P({ Name = "DoorFrame", Size = Vector3.new(0.6, slab - f1, 0.8), CFrame = CFrame.new(dx, (f1 + slab) / 2, zf - 0.5), Color = metal, Material = Enum.Material.Metal })
	end
	P({ Name = "DoorBeam", Size = Vector3.new(doorR - doorL, 0.6, 0.8), CFrame = CFrame.new((doorL + doorR) / 2, f1 + h1, zf - 0.5), Color = metal, Material = Enum.Material.Metal })

	-- marquise sobre a entrada, com fita de LED
	P({ Name = "Canopy", Size = Vector3.new(16, 0.6, 6), CFrame = CFrame.new((doorL + doorR) / 2, 11.8, zf + 3), Color = dark, Material = Enum.Material.Metal })
	local canopyLed = P({ Name = "CanopyLed", Size = Vector3.new(16, 0.25, 0.2), CFrame = CFrame.new((doorL + doorR) / 2, 11.6, zf + 6.05), Color = Config.FiberColors[1], Material = Enum.Material.Neon, CastShadow = false })
	local entranceSign = P({ Name = "EntranceSign", Size = Vector3.new(10, 1.6, 0.2), CFrame = CFrame.new((doorL + doorR) / 2, 12.9, zf + 5.9), Color = dark })
	textOn(entranceSign, Enum.NormalId.Back, "ATENDIMENTO", Color3.fromRGB(255, 255, 255))
	local entranceLight = Instance.new("PointLight")
	entranceLight.Range = 16
	entranceLight.Brightness = 1.2
	entranceLight.Color = Color3.fromRGB(255, 240, 210)
	entranceLight.Parent = canopyLed

	-- laje do 1º andar, com vão para a escada (x -147 a -139, z -52 a -24)
	local hx0, hx1, hz0, hz1 = -147, -139, -52, -24
	local slabColor = Color3.fromRGB(200, 200, 198)
	P({ Name = "SlabA", Size = Vector3.new(x1 - hx1, 1, D), CFrame = CFrame.new((hx1 + x1) / 2, slab - 0.5, cz), Color = slabColor, Material = Enum.Material.Concrete })
	P({ Name = "SlabB", Size = Vector3.new(hx1 - x0, 1, hz0 - zb), CFrame = CFrame.new((x0 + hx1) / 2, slab - 0.5, (zb + hz0) / 2), Color = slabColor, Material = Enum.Material.Concrete })
	P({ Name = "SlabC", Size = Vector3.new(hx1 - x0, 1, zf - hz1), CFrame = CFrame.new((x0 + hx1) / 2, slab - 0.5, (hz1 + zf) / 2), Color = slabColor, Material = Enum.Material.Concrete })
	-- escada: degraus subindo em direção aos fundos
	local steps = 15
	local rise = (slab - f1) / steps
	local depth = (hz1 - hz0) / steps
	for i = 1, steps do
		local topY = f1 + rise * i
		local zc = hz1 - depth * (i - 0.5)
		P({ Name = "Step" .. i, Size = Vector3.new(hx1 - hx0, topY, depth), CFrame = CFrame.new((hx0 + hx1) / 2, topY / 2, zc), Color = Color3.fromRGB(180, 175, 170), Material = Enum.Material.Concrete })
	end
	P({ Name = "StairRail", Size = Vector3.new(0.3, 3.5, hz1 - hz0), CFrame = CFrame.new(hx1 + 0.2, slab + 1.75, (hz0 + hz1) / 2), Color = glassColor, Material = Enum.Material.Glass, Transparency = 0.5 })

	-- recepção
	P({ Name = "ReceptionCounter", Size = Vector3.new(14, 3.6, 2.6), CFrame = CFrame.new(-120, f1 + 1.8, -34), Color = Color3.fromRGB(150, 105, 70), Material = Enum.Material.Wood })
	P({ Name = "ReceptionTop", Size = Vector3.new(14.4, 0.3, 3), CFrame = CFrame.new(-120, f1 + 3.75, -34), Color = Color3.fromRGB(240, 240, 240), Material = Enum.Material.Marble })
	P({ Name = "ReceptionLed", Size = Vector3.new(14, 0.2, 0.1), CFrame = CFrame.new(-120, f1 + 0.4, -32.65), Color = Config.FiberColors[2], Material = Enum.Material.Neon, CastShadow = false })
	local logoWall = P({ Name = "LogoWall", Size = Vector3.new(16, 7, 0.4), CFrame = CFrame.new(-120, f1 + 6, -41.6), Color = dark })
	local logoLabel = textOn(logoWall, Enum.NormalId.Back, "PRÉDIO DISPONÍVEL", Color3.fromRGB(80, 190, 255))
	P({ Name = "LogoWallBack", Size = Vector3.new(16, 7, 0.4), CFrame = CFrame.new(-120, f1 + 6, -42), Color = concrete })
	-- vasos de planta
	for _, px in { -130, -110 } do
		P({ Name = "Vase", Size = Vector3.new(2, 2.4, 2), CFrame = CFrame.new(px, f1 + 1.2, -26), Color = Color3.fromRGB(60, 60, 64) })
		P({ Name = "Plant", Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3), CFrame = CFrame.new(px, f1 + 3.6, -26), Color = Color3.fromRGB(70, 140, 70), Material = Enum.Material.Grass })
	end

	-- sala de equipamentos (vidro na frente), x -137 a -121, z -57.5 a -48
	-- parede de vidro com porta (vão entre x -125 e -121)
	P({ Name = "EquipGlass", Size = Vector3.new(12, slab - f1, 0.3), CFrame = CFrame.new(-131, (f1 + slab) / 2, -48), Color = glassColor, Material = Enum.Material.Glass, Transparency = 0.6 })
	P({ Name = "EquipGlassTop", Size = Vector3.new(4, slab - f1 - 8, 0.3), CFrame = CFrame.new(-123, f1 + 8 + (slab - f1 - 8) / 2, -48), Color = glassColor, Material = Enum.Material.Glass, Transparency = 0.6 })
	P({ Name = "EquipDoorFrame", Size = Vector3.new(0.4, 8, 0.5), CFrame = CFrame.new(-125, f1 + 4, -48), Color = metal, Material = Enum.Material.Metal })
	P({ Name = "EquipWallE", Size = Vector3.new(0.5, slab - f1, 9.5), CFrame = CFrame.new(-121, (f1 + slab) / 2, -52.75), Color = concrete })
	P({ Name = "EquipWallW", Size = Vector3.new(0.5, slab - f1, 9.5), CFrame = CFrame.new(-137, (f1 + slab) / 2, -52.75), Color = concrete })
	-- a sala de baixo virou oficina: os equipamentos subiram para o datacenter (2º andar)
	P({ Name = "Workbench", Size = Vector3.new(12, 0.4, 3), CFrame = CFrame.new(-129, f1 + 3.2, -55.5), Color = Color3.fromRGB(150, 110, 70), Material = Enum.Material.Wood })
	P({ Name = "WorkbenchLegs", Size = Vector3.new(11.5, 3, 0.4), CFrame = CFrame.new(-129, f1 + 1.5, -56.6), Color = metal, Material = Enum.Material.Metal })
	P({ Name = "Pegboard", Size = Vector3.new(12, 4, 0.2), CFrame = CFrame.new(-129, f1 + 6.5, -57.4), Color = Color3.fromRGB(200, 170, 120), Material = Enum.Material.Wood })
	for i = 0, 3 do
		P({ Name = "SpoolOficina", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 1.8, 1.8), CFrame = CFrame.new(-133.5 + i * 3, f1 + 4.3, -55.5), Color = Config.FiberColors[(i % 3) + 1] })
	end
	local oficinaSign = P({ Name = "OficinaSign", Size = Vector3.new(5, 1, 0.1), CFrame = CFrame.new(-129, f1 + 10.6, -48.2), Color = dark })
	textOn(oficinaSign, Enum.NormalId.Back, "OFICINA", Color3.new(1, 1, 1))

	-- almoxarifado (lado leste)
	local shelf = P({ Name = "Shelf", Size = Vector3.new(10, 8, 2.5), CFrame = CFrame.new(-99, f1 + 4, -55.5), Color = Color3.fromRGB(90, 95, 105), Material = Enum.Material.Metal })
	P({ Name = "Shelf2", Size = Vector3.new(2.5, 8, 10), CFrame = CFrame.new(-94.5, f1 + 4, -46), Color = Color3.fromRGB(90, 95, 105), Material = Enum.Material.Metal })
	for i = 0, 3 do
		P({ Name = "OnuBoxStock", Size = Vector3.new(1.6, 1, 1.2), CFrame = CFrame.new(-102.5 + i * 2.2, f1 + 6.5, -54.4), Color = Color3.fromRGB(245, 245, 245) })
		P({ Name = "Spool", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 2.2, 2.2), CFrame = CFrame.new(-102.5 + i * 2.2, f1 + 2.6, -54.4), Color = if i % 2 == 0 then Config.FiberColors[2] else Config.FiberColors[1] })
	end
	local stockSign = P({ Name = "StockSign", Size = Vector3.new(6, 1.2, 0.2), CFrame = CFrame.new(-99, f1 + 9, -56.7), Color = dark })
	textOn(stockSign, Enum.NormalId.Back, "ALMOXARIFADO", Color3.new(1, 1, 1))

	-- luzes internas do térreo
	for _, lx in { -132, -112, -100 } do
		local lamp = P({ Name = "CeilingLamp", Size = Vector3.new(6, 0.2, 2), CFrame = CFrame.new(lx, slab - 1.1, -36), Color = Color3.fromRGB(255, 250, 235), Material = Enum.Material.Neon, CastShadow = false })
		local pl = Instance.new("PointLight")
		pl.Range = 22
		pl.Brightness = 1.1
		pl.Color = Color3.fromRGB(255, 244, 225)
		pl.Parent = lamp
	end

	-- 1º andar: paredes e faixa de janelas
	local h2 = f2top - slab
	P({ Name = "BackWall2", Size = Vector3.new(W, h2, 1), CFrame = CFrame.new(cx, slab + h2 / 2, zb + 0.5), Color = dark })
	P({ Name = "WestWall2", Size = Vector3.new(1, h2, D), CFrame = CFrame.new(x0 + 0.5, slab + h2 / 2, cz), Color = dark })
	P({ Name = "EastWall2", Size = Vector3.new(1, h2, D), CFrame = CFrame.new(x1 - 0.5, slab + h2 / 2, cz), Color = dark })
	P({ Name = "FrontLow2", Size = Vector3.new(W, 3, 1), CFrame = CFrame.new(cx, slab + 1.5, zf - 0.5), Color = dark })
	P({ Name = "FrontHigh2", Size = Vector3.new(W, 3, 1), CFrame = CFrame.new(cx, f2top - 1.5, zf - 0.5), Color = dark })
	P({ Name = "FrontWindow2", Size = Vector3.new(W - 2, h2 - 6, 0.4), CFrame = CFrame.new(cx, slab + h2 / 2, zf - 0.5), Color = Color3.fromRGB(60, 110, 150), Material = Enum.Material.Glass, Transparency = 0.45 })
	P({ Name = "NocCarpet", Size = Vector3.new(x1 - hx1 - 1, 0.1, D - 2), CFrame = CFrame.new((hx1 + x1) / 2, slab + 0.05, cz), Color = Color3.fromRGB(45, 50, 62), Material = Enum.Material.Fabric })

	-- telão do NOC (3 telas na parede dos fundos)
	local screensFolder = folder("Telas", model)
	local function screen(kind: string, size: Vector3, pos: Vector3, lookDir: Vector3): BasePart
		local s = P({ Name = "Tela_" .. kind, Size = size, CFrame = CFrame.lookAt(pos, pos + lookDir), Color = Color3.fromRGB(8, 10, 14), Parent = screensFolder })
		s:SetAttribute("ScreenKind", kind)
		s:SetAttribute("Slot", slot)
		CollectionService:AddTag(s, "NocScreen")
		return s
	end
	local wallZ = zb + 1.2
	P({ Name = "VideoWallFrame", Size = Vector3.new(44, 10, 0.3), CFrame = CFrame.new(-115.5, 22.5, zb + 1.05), Color = Color3.fromRGB(20, 20, 24) })
	screen("Traffic", Vector3.new(12, 8, 0.2), Vector3.new(-130.5, 22.5, wallZ), Vector3.new(0, 0, 1))
	screen("Topology", Vector3.new(16, 9, 0.2), Vector3.new(-115.5, 22.5, wallZ), Vector3.new(0, 0, 1))
	-- mapa geográfico na parede leste
	P({ Name = "MapFrame", Size = Vector3.new(0.3, 9.4, 16.6), CFrame = CFrame.new(x1 - 1.15, 22.5, -40), Color = Color3.fromRGB(20, 20, 24) })
	screen("Map", Vector3.new(16, 8.8, 0.2), Vector3.new(x1 - 1.4, 22.5, -40), Vector3.new(-1, 0, 0))
	screen("Alarms", Vector3.new(12, 8, 0.2), Vector3.new(-100.5, 22.5, wallZ), Vector3.new(0, 0, 1))
	local nocTitle = P({ Name = "NocTitle", Size = Vector3.new(20, 1.6, 0.2), CFrame = CFrame.new(-115.5, 27.8, wallZ), Color = Color3.fromRGB(20, 20, 24) })
	textOn(nocTitle, Enum.NormalId.Back, "CENTRO DE OPERAÇÕES DA REDE", Color3.fromRGB(120, 200, 255))

	-- mesas dos operadores (cada uma com um monitor)
	local deskKinds = { "Onus", "Tickets", "Summary", "Mood" }
	local deskPos = { Vector3.new(-127, 0, -44), Vector3.new(-111, 0, -44), Vector3.new(-127, 0, -33), Vector3.new(-111, 0, -33) }
	for i, d in deskPos do
		local top = slab + 3
		P({ Name = "Desk" .. i, Size = Vector3.new(11, 0.5, 4), CFrame = CFrame.new(d.X, top, d.Z), Color = Color3.fromRGB(62, 66, 76), Material = Enum.Material.Wood })
		P({ Name = "DeskLegs" .. i, Size = Vector3.new(10.5, 2.75, 0.5), CFrame = CFrame.new(d.X, slab + 1.4, d.Z - 1.5), Color = Color3.fromRGB(60, 60, 66) })
		P({ Name = "MonitorStand" .. i, Size = Vector3.new(0.6, 1, 0.6), CFrame = CFrame.new(d.X, top + 0.75, d.Z - 1.2), Color = Color3.fromRGB(40, 40, 44) })
		screen(deskKinds[i], Vector3.new(7, 4, 0.2), Vector3.new(d.X, top + 3.2, d.Z - 1.3), Vector3.new(0, 0, 1))
		local kb = P({ Name = "Keyboard" .. i, Size = Vector3.new(3, 0.15, 1), CFrame = CFrame.new(d.X, top + 0.32, d.Z + 0.5), Color = Color3.fromRGB(35, 35, 40) })
		-- estação de trabalho: acessa os equipamentos pela rede de gerência
		kb:SetAttribute("PcIndex", i)
		kb:SetAttribute("Slot", slot)
		CollectionService:AddTag(kb, "NocPc")
		P({ Name = "Mouse" .. i, Size = Vector3.new(0.4, 0.15, 0.6), CFrame = CFrame.new(d.X + 2.2, top + 0.32, d.Z + 0.5), Color = Color3.fromRGB(35, 35, 40) })
		local tower = P({ Name = "PcTower" .. i, Size = Vector3.new(1.2, 2.6, 2.6), CFrame = CFrame.new(d.X + 4.4, slab + 1.3, d.Z - 0.4), Color = Color3.fromRGB(28, 30, 36), Material = Enum.Material.Metal })
		P({ Name = "PcLed" .. i, Size = Vector3.new(0.15, 0.15, 0.05), CFrame = CFrame.new(d.X + 4.4, slab + 2.3, d.Z + 0.92), Color = Color3.fromRGB(80, 190, 255), Material = Enum.Material.Neon, CastShadow = false, Parent = tower.Parent })
		-- cadeira
		P({ Name = "ChairSeat" .. i, Size = Vector3.new(2.6, 0.5, 2.6), CFrame = CFrame.new(d.X, slab + 2, d.Z + 3.6), Color = Color3.fromRGB(30, 30, 34), Material = Enum.Material.Fabric })
		P({ Name = "ChairBack" .. i, Size = Vector3.new(2.6, 3, 0.4), CFrame = CFrame.new(d.X, slab + 3.7, d.Z + 4.8), Color = Color3.fromRGB(30, 30, 34), Material = Enum.Material.Fabric })
		P({ Name = "ChairPost" .. i, Size = Vector3.new(0.4, 1.8, 0.4), CFrame = CFrame.new(d.X, slab + 0.9, d.Z + 3.6), Color = Color3.fromRGB(90, 90, 95), Material = Enum.Material.Metal })
	end
	-- luz azulada e baixa do NOC
	for _, lx in { -130, -115, -100 } do
		local lamp = P({ Name = "NocLamp", Size = Vector3.new(8, 0.2, 0.6), CFrame = CFrame.new(lx, f2top - 1.2, -38), Color = Color3.fromRGB(110, 170, 255), Material = Enum.Material.Neon, CastShadow = false })
		local pl = Instance.new("PointLight")
		pl.Range = 18
		pl.Brightness = 0.7
		pl.Color = Color3.fromRGB(140, 180, 255)
		pl.Parent = lamp
	end

	-- -----------------------------------------------------------------------
	-- 2º andar: DATACENTER (andar inteiro para os equipamentos)
	-- -----------------------------------------------------------------------
	local f3 = f2top + 1 -- piso do datacenter
	local f4 = f3 + 14 -- teto do datacenter
	local h3 = f4 - f3
	local white = Color3.fromRGB(236, 238, 242)

	-- escada do NOC até o datacenter: sobe da parede dos fundos em direção à rua,
	-- ao lado da primeira escada (x -138.4 a -133)
	local sx0, sx1, sz0, sz1 = -138.4, -133, -52, -24
	local depth2 = (sz1 - sz0) / steps
	local rise2 = (f3 - slab) / steps
	for i = 1, steps do
		local topY = slab + rise2 * i
		local zc = sz0 + depth2 * (i - 0.5)
		P({ Name = "Step2_" .. i, Size = Vector3.new(sx1 - sx0, topY - slab, depth2), CFrame = CFrame.new((sx0 + sx1) / 2, slab + (topY - slab) / 2, zc), Color = Color3.fromRGB(150, 155, 165), Material = Enum.Material.DiamondPlate })
	end
	local stairSign = P({ Name = "StairSign", Size = Vector3.new(5.4, 1, 0.1), CFrame = CFrame.new((sx0 + sx1) / 2, slab + 2.2, sz0 - 0.2) * CFrame.Angles(0, math.rad(180), 0), Color = dark, CanCollide = false })
	textOn(stairSign, Enum.NormalId.Back, "DATACENTER ↑", Color3.fromRGB(80, 190, 255))

	-- laje do datacenter, com o vão da escada (x -139 a -132.6, z -52 a -24)
	local gx0, gx1 = -139, -132.6
	P({ Name = "DcSlabA", Size = Vector3.new(x1 - gx1, 1, D), CFrame = CFrame.new((gx1 + x1) / 2, f3 - 0.5, cz), Color = slabColor, Material = Enum.Material.Concrete })
	P({ Name = "DcSlabB", Size = Vector3.new(gx0 - x0, 1, D), CFrame = CFrame.new((x0 + gx0) / 2, f3 - 0.5, cz), Color = slabColor, Material = Enum.Material.Concrete })
	P({ Name = "DcSlabC", Size = Vector3.new(gx1 - gx0, 1, sz0 - zb), CFrame = CFrame.new((gx0 + gx1) / 2, f3 - 0.5, (zb + sz0) / 2), Color = slabColor, Material = Enum.Material.Concrete })
	P({ Name = "DcSlabD", Size = Vector3.new(gx1 - gx0, 1, zf - sz1), CFrame = CFrame.new((gx0 + gx1) / 2, f3 - 0.5, (sz1 + zf) / 2), Color = slabColor, Material = Enum.Material.Concrete })
	P({ Name = "DcStairRailE", Size = Vector3.new(0.3, 3.5, sz1 - sz0 - 5), CFrame = CFrame.new(gx1 + 0.2, f3 + 1.75, sz0 + (sz1 - sz0 - 5) / 2), Color = glassColor, Material = Enum.Material.Glass, Transparency = 0.5 })
	P({ Name = "DcStairRailW", Size = Vector3.new(0.3, 3.5, sz1 - sz0), CFrame = CFrame.new(gx0 - 0.2, f3 + 1.75, (sz0 + sz1) / 2), Color = glassColor, Material = Enum.Material.Glass, Transparency = 0.5 })

	-- piso elevado (placas cinza com rejunte)
	P({ Name = "DcFloor", Size = Vector3.new(x1 - gx1 - 1, 0.1, D - 1), CFrame = CFrame.new((gx1 + x1) / 2, f3 + 0.05, cz), Color = Color3.fromRGB(196, 200, 206), Material = Enum.Material.SmoothPlastic })
	for gx = gx1 + 4, x1 - 2, 4 do
		P({ Name = "FloorGrid", Size = Vector3.new(0.08, 0.02, D - 1), CFrame = CFrame.new(gx, f3 + 0.11, cz), Color = Color3.fromRGB(150, 155, 162), CanCollide = false, CastShadow = false })
	end
	for gz = zb + 4, zf - 2, 4 do
		P({ Name = "FloorGrid", Size = Vector3.new(x1 - gx1 - 1, 0.02, 0.08), CFrame = CFrame.new((gx1 + x1) / 2, f3 + 0.11, gz), Color = Color3.fromRGB(150, 155, 162), CanCollide = false, CastShadow = false })
	end

	-- paredes claras e fachada de vidro inteira virada para a rua
	P({ Name = "BackWall3", Size = Vector3.new(W, h3, 1), CFrame = CFrame.new(cx, f3 + h3 / 2, zb + 0.5), Color = white, Material = Enum.Material.SmoothPlastic })
	P({ Name = "WestWall3", Size = Vector3.new(1, h3, D), CFrame = CFrame.new(x0 + 0.5, f3 + h3 / 2, cz), Color = white, Material = Enum.Material.SmoothPlastic })
	P({ Name = "EastWall3", Size = Vector3.new(1, h3, D), CFrame = CFrame.new(x1 - 0.5, f3 + h3 / 2, cz), Color = white, Material = Enum.Material.SmoothPlastic })
	P({ Name = "FrontLow3", Size = Vector3.new(W, 1.5, 1), CFrame = CFrame.new(cx, f3 + 0.75, zf - 0.5), Color = dark })
	P({ Name = "FrontHigh3", Size = Vector3.new(W, 1.5, 1), CFrame = CFrame.new(cx, f4 - 0.75, zf - 0.5), Color = dark })
	P({ Name = "FrontWindow3", Size = Vector3.new(W - 2, h3 - 3, 0.4), CFrame = CFrame.new(cx, f3 + h3 / 2, zf - 0.5), Color = Color3.fromRGB(150, 200, 230), Material = Enum.Material.Glass, Transparency = 0.7 })
	for mx = x0 + 1, x1 - 1, 7 do
		P({ Name = "Mullion3", Size = Vector3.new(0.35, h3, 0.6), CFrame = CFrame.new(mx, f3 + h3 / 2, zf - 0.5), Color = metal, Material = Enum.Material.Metal })
	end
	-- bancada na janela, com vista para a rua
	P({ Name = "ViewCounter", Size = Vector3.new(30, 0.4, 2.2), CFrame = CFrame.new(-112, f3 + 3.6, zf - 2), Color = Color3.fromRGB(150, 110, 70), Material = Enum.Material.Wood })
	for _, bx in { -125, -112, -99 } do
		P({ Name = "ViewCounterLeg", Size = Vector3.new(0.4, 3.4, 1.6), CFrame = CFrame.new(bx, f3 + 1.7, zf - 2), Color = metal, Material = Enum.Material.Metal })
	end
	for i = 0, 4 do
		local sxp = -122 + i * 5
		P({ Name = "Stool", Size = Vector3.new(1.6, 0.3, 1.6), CFrame = CFrame.new(sxp, f3 + 2.6, zf - 4.2), Color = Color3.fromRGB(30, 30, 34), Material = Enum.Material.Fabric })
		P({ Name = "StoolPost", Size = Vector3.new(0.3, 2.5, 0.3), CFrame = CFrame.new(sxp, f3 + 1.25, zf - 4.2), Color = metal, Material = Enum.Material.Metal })
	end

	-- fileira de racks na parede dos fundos (frente dos racks virada para +Z)
	local rackZ = -55
	local function rackFrame(name: string, x: number, label: string): BasePart
		local r = P({ Name = name, Size = Vector3.new(4, 10, 3), CFrame = CFrame.new(x, f3 + 5, rackZ), Color = Color3.fromRGB(25, 25, 28), Material = Enum.Material.Metal })
		for _, side in { -1, 1 } do
			P({ Name = name .. "_Post", Size = Vector3.new(0.25, 10, 0.25), CFrame = CFrame.new(x + side * 1.9, f3 + 5, rackZ + 1.55), Color = Color3.fromRGB(60, 62, 70), Material = Enum.Material.Metal })
		end
		local tag = P({ Name = name .. "_Label", Size = Vector3.new(4, 0.8, 0.1), CFrame = CFrame.new(x, f3 + 10.5, rackZ + 1.5), Color = dark })
		textOn(tag, Enum.NormalId.Back, label, Color3.new(1, 1, 1))
		return r
	end
	local dioX, mainX, srvX, spareX, upX = -127, -120, -113, -106, -99.5
	rackFrame("RackDIO", dioX, "RACK 01 · DIO")
	local rack = rackFrame("Rack", mainX, "RACK 02 · REDE")
	rackFrame("RackServidores", srvX, "RACK 03 · SERVIDORES")
	rackFrame("RackReserva", spareX, "RACK 04 · RESERVA")
	-- DIO: painel onde as fibras da OLT encontram as fibras que vão para a rua
	local dio = P({ Name = "DIO", Size = Vector3.new(3.6, 2.2, 0.5), CFrame = CFrame.new(dioX, f3 + 6, rackZ + 1.7), Color = Color3.fromRGB(215, 218, 222), Material = Enum.Material.Metal })
	textOn(dio, Enum.NormalId.Back, "DIO 24F\nP1 A · P2 B · P3 C · P4 D", Color3.fromRGB(40, 40, 50))
	for i = 1, 8 do
		P({ Name = "DioPort", Size = Vector3.new(0.22, 0.22, 0.06), CFrame = CFrame.new(dioX - 1.4 + (i - 1) * 0.4, f3 + 5.2, rackZ + 1.97), Color = if i <= 3 then Color3.fromRGB(40, 180, 90) else Color3.fromRGB(70, 70, 75), CastShadow = false })
	end
	-- servidores decorativos (DNS e sistema do provedor)
	for i = 1, 5 do
		P({ Name = "Server" .. i, Size = Vector3.new(3.6, 0.9, 0.3), CFrame = CFrame.new(srvX, f3 + 1.4 + i * 1.3, rackZ + 1.65), Color = Color3.fromRGB(55, 58, 66), Material = Enum.Material.Metal })
		P({ Name = "ServerLed" .. i, Size = Vector3.new(0.25, 0.25, 0.05), CFrame = CFrame.new(srvX + 1.4, f3 + 1.4 + i * 1.3, rackZ + 1.82), Color = Config.StatusColors.online, Material = Enum.Material.Neon, CastShadow = false })
	end
	-- caixa da operadora: por onde chega o link de internet (upstream)
	local upBox = P({ Name = "CaixaOperadora", Size = Vector3.new(3, 4, 0.8), CFrame = CFrame.new(upX, f3 + 6, zb + 1.4), Color = Color3.fromRGB(180, 40, 40), Material = Enum.Material.Metal })
	textOn(upBox, Enum.NormalId.Back, "OPERADORA\nlink upstream", Color3.new(1, 1, 1))
	-- eletrocalha no alto, por onde passam os cabos
	local trayY, trayZ = f3 + 11.4, rackZ - 0.2
	P({ Name = "Eletrocalha", Size = Vector3.new(36, 0.15, 1.6), CFrame = CFrame.new(-112, trayY - 0.2, trayZ), Color = Color3.fromRGB(150, 155, 160), Material = Enum.Material.DiamondPlate, CanCollide = false })
	for _, side in { -1, 1 } do
		P({ Name = "EletrocalhaBorda", Size = Vector3.new(36, 0.5, 0.1), CFrame = CFrame.new(-112, trayY, trayZ + side * 0.8), Color = Color3.fromRGB(150, 155, 160), Material = Enum.Material.Metal, CanCollide = false })
	end
	-- fibras do tronco: do DIO até a parede leste, descendo por fora até a rua
	World.cable({ Vector3.new(dioX + 1.5, f3 + 6, rackZ + 2.1), Vector3.new(dioX + 1.5, trayY, rackZ + 2.1), Vector3.new(dioX + 1.5, trayY, trayZ), Vector3.new(x1 - 1, trayY, trayZ) }, Color3.fromRGB(240, 200, 40), model, "FibraTronco")
	P({ Name = "EletrodutoExterno", Size = Vector3.new(0.5, trayY - 16, 0.5), CFrame = CFrame.new(x1 + 0.3, (trayY + 16) / 2, trayZ), Color = Color3.fromRGB(90, 92, 98), Material = Enum.Material.Metal })
	local trunkTag = P({ Name = "EtiquetaTronco", Size = Vector3.new(0.4, 0.25, 0.05), CFrame = CFrame.new(x1 - 2, trayY - 0.3, trayZ + 0.85), Color = Color3.fromRGB(240, 200, 40), CanCollide = false, CastShadow = false })
	local function cableTag(target: BasePart, text: string)
		local bb = Instance.new("BillboardGui")
		bb.Name = "Etiqueta"
		bb.Size = UDim2.new(3.2, 0, 0.36, 0)
		bb.StudsOffset = Vector3.new(0, 0.5, 0)
		bb.MaxDistance = 12
		bb.LightInfluence = 0
		bb.Parent = target
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		t.TextColor3 = Color3.fromRGB(20, 20, 25)
		t.Font = Enum.Font.Code
		t.TextScaled = true
		t.Text = text
		t.Parent = bb
	end
	cableTag(trunkTag, "TRONCOS → Rua Principal e Palmeiras")
	local upTag = P({ Name = "EtiquetaOperadora", Size = Vector3.new(0.4, 0.25, 0.05), CFrame = CFrame.new(upX, f3 + 8.4, zb + 1.85), Color = Color3.fromRGB(210, 50, 50), CanCollide = false, CastShadow = false })
	cableTag(upTag, "Link da operadora (upstream)")

	-- legenda das cores e ficha do link, na parede ao lado do DIO
	local legend = P({ Name = "LegendaCabos", Size = Vector3.new(4.4, 3.4, 0.1), CFrame = CFrame.new(-133.5, f3 + 7.2, zb + 1.06), Color = Color3.fromRGB(250, 250, 245) })
	textOn(legend, Enum.NormalId.Back, "CORES DOS CABOS\nAMARELO fibra (OLT, DIO, rua)\nAZUL rede interna (cobre)\nVERMELHO operadora\nEtiqueta em cada ponta", Color3.fromRGB(30, 30, 35))

	-- ar-condicionado de precisão e nobreak (lado oeste, acima da 1ª escada)
	local crac = P({ Name = "ArCondicionado", Size = Vector3.new(6, 9, 3), CFrame = CFrame.new(-143.5, f3 + 4.5, zb + 2.5), Color = Color3.fromRGB(225, 228, 232), Material = Enum.Material.Metal })
	textOn(crac, Enum.NormalId.Back, "AR DE PRECISÃO\n22 °C", Color3.fromRGB(40, 90, 160))
	local ups = P({ Name = "Nobreak", Size = Vector3.new(5, 5, 3), CFrame = CFrame.new(-143.5, f3 + 2.5, -44), Color = Color3.fromRGB(40, 42, 48), Material = Enum.Material.Metal })
	textOn(ups, Enum.NormalId.Right, "NOBREAK 10 kVA", Color3.fromRGB(120, 230, 140))
	for i = 0, 2 do
		P({ Name = "Baterias", Size = Vector3.new(5, 2, 3), CFrame = CFrame.new(-143.5, f3 + 1, -38 + i * 4), Color = Color3.fromRGB(30, 30, 34), Material = Enum.Material.Metal })
	end

	-- painel de monitoramento na parede leste
	P({ Name = "PainelFrame", Size = Vector3.new(0.3, 10.4, 34), CFrame = CFrame.new(x1 - 1.15, f3 + 6.5, -40), Color = Color3.fromRGB(20, 20, 24) })
	screen("Rack", Vector3.new(15, 9.4, 0.2), Vector3.new(x1 - 1.4, f3 + 6.5, -48.5), Vector3.new(-1, 0, 0))
	local dcTopo = screen("Topology", Vector3.new(16, 9.4, 0.2), Vector3.new(x1 - 1.4, f3 + 6.5, -31.5), Vector3.new(-1, 0, 0))
	dcTopo.Name = "Tela_Topology_DC"
	local panelTitle = P({ Name = "PainelTitulo", Size = Vector3.new(0.2, 1.4, 20), CFrame = CFrame.new(x1 - 1.3, f3 + 12.6, -40), Color = Color3.fromRGB(20, 20, 24) })
	textOn(panelTitle, Enum.NormalId.Left, "PAINEL DE MONITORAMENTO", Color3.fromRGB(120, 200, 255))
	local dcTitle = P({ Name = "DatacenterTitle", Size = Vector3.new(14, 1.4, 0.1), CFrame = CFrame.new(-113, f3 + 12.6, zb + 1.06), Color = dark })
	textOn(dcTitle, Enum.NormalId.Back, "DATACENTER", Color3.fromRGB(120, 200, 255))

	-- luz fria do datacenter
	for _, lx in { -125, -112, -99 } do
		for _, lz in { -50, -34 } do
			local lamp = P({ Name = "DcLamp", Size = Vector3.new(7, 0.2, 1), CFrame = CFrame.new(lx, f4 - 1.1, lz), Color = Color3.fromRGB(235, 245, 255), Material = Enum.Material.Neon, CastShadow = false })
			local pl = Instance.new("PointLight")
			pl.Range = 20
			pl.Brightness = 1
			pl.Color = Color3.fromRGB(220, 235, 255)
			pl.Parent = lamp
		end
	end

	-- telhado, platibanda e antena do link de rádio
	P({ Name = "Roof", Size = Vector3.new(W, 1, D), CFrame = CFrame.new(cx, f4 + 0.5, cz), Color = Color3.fromRGB(110, 112, 118), Material = Enum.Material.Concrete })
	P({ Name = "ParapetF", Size = Vector3.new(W, 2, 0.8), CFrame = CFrame.new(cx, f4 + 2, zf - 0.4), Color = dark })
	P({ Name = "ParapetB", Size = Vector3.new(W, 2, 0.8), CFrame = CFrame.new(cx, f4 + 2, zb + 0.4), Color = dark })
	P({ Name = "ParapetW", Size = Vector3.new(0.8, 2, D), CFrame = CFrame.new(x0 + 0.4, f4 + 2, cz), Color = dark })
	P({ Name = "ParapetE", Size = Vector3.new(0.8, 2, D), CFrame = CFrame.new(x1 - 0.4, f4 + 2, cz), Color = dark })
	P({ Name = "AntennaMast", Shape = Enum.PartType.Cylinder, Size = Vector3.new(14, 0.6, 0.6), CFrame = CFrame.new(-100, f4 + 8, -50) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(200, 200, 205), Material = Enum.Material.Metal })
	P({ Name = "AntennaDish", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 4, 4), CFrame = CFrame.new(-100, f4 + 12, -49) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(240, 240, 240), Material = Enum.Material.Metal })
	local beacon = P({ Name = "AntennaBeacon", Shape = Enum.PartType.Ball, Size = Vector3.new(0.8, 0.8, 0.8), CFrame = CFrame.new(-100, f4 + 15.2, -50), Color = Color3.fromRGB(255, 50, 50), Material = Enum.Material.Neon, CastShadow = false })
	CollectionService:AddTag(beacon, "Beacon")
	P({ Name = "AcUnit", Size = Vector3.new(5, 3, 4), CFrame = CFrame.new(-135, f4 + 2.5, -48), Color = Color3.fromRGB(190, 192, 196), Material = Enum.Material.Metal })

	-- letreiro luminoso
	local sign = P({ Name = "Sign", Size = Vector3.new(34, 6, 0.8), CFrame = CFrame.new(cx, f4 + 6.2, zf - 0.2), Color = Color3.fromRGB(16, 20, 30) })
	local signText = textOn(sign, Enum.NormalId.Back, "PRÉDIO DISPONÍVEL", Color3.fromRGB(255, 255, 255))
	signText.Font = Enum.Font.GothamBlack
	local stroke = Instance.new("UIStroke")
	stroke.Color = Config.FiberColors[1]
	stroke.Thickness = 3
	stroke.Parent = signText
	local signGlow = Instance.new("SurfaceLight")
	signGlow.Face = Enum.NormalId.Back
	signGlow.Range = 18
	signGlow.Brightness = 1.5
	signGlow.Color = Config.FiberColors[1]
	signGlow.Parent = sign
	P({ Name = "SignLegL", Size = Vector3.new(0.6, 3.5, 0.6), CFrame = CFrame.new(cx - 14, f4 + 2.5, zf - 0.6), Color = metal, Material = Enum.Material.Metal })
	P({ Name = "SignLegR", Size = Vector3.new(0.6, 3.5, 0.6), CFrame = CFrame.new(cx + 14, f4 + 2.5, zf - 0.6), Color = metal, Material = Enum.Material.Metal })

	-- fitas de LED nas cores da fibra: entre andares, no topo e nas quinas
	local neon = { canopyLed }
	local seg = W / 3
	for i = 1, 3 do
		local color = Config.FiberColors[i]
		table.insert(neon, P({ Name = "LedBand" .. i, Size = Vector3.new(seg, 0.35, 0.3), CFrame = CFrame.new(x0 + seg * (i - 0.5), slab, zf + 0.1), Color = color, Material = Enum.Material.Neon, CastShadow = false }))
		table.insert(neon, P({ Name = "LedBand2_" .. i, Size = Vector3.new(seg, 0.35, 0.3), CFrame = CFrame.new(x0 + seg * (i - 0.5), f3 - 0.5, zf + 0.1), Color = color, Material = Enum.Material.Neon, CastShadow = false }))
		table.insert(neon, P({ Name = "LedRoof" .. i, Size = Vector3.new(seg, 0.35, 0.3), CFrame = CFrame.new(x0 + seg * (i - 0.5), f4 + 3.1, zf + 0.1), Color = color, Material = Enum.Material.Neon, CastShadow = false }))
	end
	for _, qx in { x0 - 0.1, x1 + 0.1 } do
		table.insert(neon, P({ Name = "LedCorner", Size = Vector3.new(0.3, f4 + 3, 0.3), CFrame = CFrame.new(qx, (f4 + 3) / 2, zf + 0.1), Color = Config.FiberColors[1], Material = Enum.Material.Neon, CastShadow = false }))
	end

	-- garagem da equipe, ao lado do prédio (o carro é comprado no terminal de compras)
	local gx0, gx1, gz0, gz1 = -87, -63, -52, -22
	local gcx, gcz = (gx0 + gx1) / 2, (gz0 + gz1) / 2
	local garage = Instance.new("Model")
	garage.Name = "Garagem"
	garage.Parent = model
	local function G(props: { [string]: any })
		props.Parent = garage
		return part(props)
	end
	G({ Name = "GarageFloor", Size = Vector3.new(gx1 - gx0, 0.4, gz1 - gz0), CFrame = CFrame.new(gcx, 0.2, gcz), Color = Color3.fromRGB(110, 112, 118), Material = Enum.Material.Concrete })
	G({ Name = "GarageBack", Size = Vector3.new(gx1 - gx0, 12, 1), CFrame = CFrame.new(gcx, 6, gz0 + 0.5), Color = concrete, Material = Enum.Material.Concrete })
	G({ Name = "GarageWest", Size = Vector3.new(1, 12, gz1 - gz0), CFrame = CFrame.new(gx0 + 0.5, 6, gcz), Color = concrete, Material = Enum.Material.Concrete })
	G({ Name = "GarageEast", Size = Vector3.new(1, 12, gz1 - gz0), CFrame = CFrame.new(gx1 - 0.5, 6, gcz), Color = concrete, Material = Enum.Material.Concrete })
	G({ Name = "GarageRoof", Size = Vector3.new(gx1 - gx0 + 2, 0.8, gz1 - gz0 + 2), CFrame = CFrame.new(gcx, 12.4, gcz), Color = dark, Material = Enum.Material.Metal })
	local header = G({ Name = "GarageHeader", Size = Vector3.new(gx1 - gx0, 2, 0.6), CFrame = CFrame.new(gcx, 11, gz1 - 0.3), Color = dark, Material = Enum.Material.Metal })
	textOn(header, Enum.NormalId.Front, "GARAGEM · EQUIPE DE CAMPO", Color3.fromRGB(255, 170, 60))
	G({ Name = "GarageLed", Size = Vector3.new(gx1 - gx0, 0.25, 0.2), CFrame = CFrame.new(gcx, 9.9, gz1 - 0.1), Color = Color3.fromRGB(255, 140, 30), Material = Enum.Material.Neon, CastShadow = false })
	for _, dx in { -4, 4 } do
		G({ Name = "VagaFaixa", Size = Vector3.new(0.4, 0.05, 16), CFrame = CFrame.new(gcx + dx, 0.43, gcz - 2), Color = Color3.fromRGB(240, 220, 120), CanCollide = false })
	end
	G({ Name = "Driveway", Size = Vector3.new(12, 0.35, 10), CFrame = CFrame.new(gcx, 0.18, gz1 + 5), Color = Color3.fromRGB(120, 120, 126), Material = Enum.Material.Concrete })
	-- quadro de chaves: comprar/recolher o carro e ver quem está com ele
	local keyBoard = G({ Name = "QuadroChaves", Size = Vector3.new(0.3, 2.4, 3.2), CFrame = CFrame.new(gx1 - 1.2, 5, gz1 - 5), Color = Color3.fromRGB(150, 110, 70), Material = Enum.Material.Wood })
	textOn(keyBoard, Enum.NormalId.Left, "CHAVES", Color3.fromRGB(255, 255, 255))
	local garageLight = Instance.new("PointLight")
	garageLight.Range = 22
	garageLight.Brightness = 1
	garageLight.Parent = G({ Name = "GarageLamp", Size = Vector3.new(3, 0.3, 1), CFrame = CFrame.new(gcx, 11.8, gcz), Color = Color3.fromRGB(255, 245, 220), Material = Enum.Material.Neon, CastShadow = false })

	-- ponto de nascimento no saguão
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.2, 6)
	spawn.CFrame = CFrame.new(-120, 0.65, -27)
	spawn.Color = Config.FiberColors[1]
	spawn.Material = Enum.Material.Neon
	spawn.Transparency = 0.6
	spawn.TopSurface = SMOOTH
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Enabled = slot == 1 -- quem entra nasce no prédio 1; depois nasce no prédio do seu provedor
	spawn.CanCollide = false
	spawn.Parent = model
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end

	local isp = {
		model = model,
		spawn = spawn,
		trunkExit = Vector3.new(x1 + 0.3, 16, trayZ),
		entrance = Vector3.new(-120, 0.6, zf + 7),
		reception = Vector3.new(-120, 0.6, -30),
		rackFront = Vector3.new(mainX, f3, rackZ + 1.5),
		floorY = f1,
		dcFloorY = f3,
		dc = {
			trayY = trayY,
			trayZ = trayZ,
			dioPort = Vector3.new(dioX - 1.4, f3 + 5.2, rackZ + 2.05), -- porta P1 (P2 fica 0.4 à direita)
			upstreamPort = Vector3.new(upX, f3 + 4.6, zb + 1.9),
			fichaCFrame = CFrame.lookAt(Vector3.new(-133.5, f3 + 3.6, zb + 1.06), Vector3.new(-133.5, f3 + 3.6, 0)),
		},
		rack = rack,
		shelf = shelf,
		signNeon = neon,
		garage = {
			spot = CFrame.lookAt(Vector3.new(gcx, 0.4, gcz - 2), Vector3.new(gcx, 0.4, gcz + 10)), -- vaga, de frente para a rua
			keyBoard = keyBoard,
			exit = Vector3.new(gcx, 0.6, gz1 + 6), -- saída para a rua
		},
		slot = slot,
		offset = Vector3.zero,
		nameLabels = { signText, logoLabel },
	}
	-- prédio 2: monta igual ao 1 e desloca tudo (modelo e pontos de referência)
	local off = World.IspOffsets[slot] or Vector3.zero
	if off.Magnitude > 0 then
		model.WorldPivot = CFrame.new()
		model:PivotTo(CFrame.new(off))
		local function shift(v: any): any
			if typeof(v) == "Vector3" then
				return v + off
			elseif typeof(v) == "CFrame" then
				return v + off
			end
			return v
		end
		for _, key in { "trunkExit", "entrance", "reception", "rackFront" } do
			isp[key] = shift(isp[key])
		end
		for k, v in isp.dc do
			isp.dc[k] = shift(v)
		end
		for k, v in isp.garage do
			isp.garage[k] = shift(v)
		end
		isp.offset = off
	end
	return isp :: any
end

-- ---------------------------------------------------------------------------

export type WorldData = {
	houses: { House },
	poles: { [string]: Pole },
	boxes: { [string]: BasePart },
	isp: Isp, -- prédio 1 (atalho para isps[1])
	isps: { Isp },
	plazaPoints: { Vector3 },
	sidewalkPoints: { Vector3 },
	palmPoints: { Vector3 },
	cablesFolder: Folder,
	npcFolder: Folder,
	effectsFolder: Folder,
}

function World.build(): WorldData
	local root = workspace:FindFirstChild("VilaAurora")
	if root then
		root:Destroy()
	end
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	root = Instance.new("Folder")
	root.Name = "VilaAurora"
	root.Parent = workspace

	setupLighting()
	local env = folder("Cenario", root)
	buildGround(env)
	local plazaPoints = buildPlaza(env)
	local isps = { buildIsp(root, 1), buildIsp(root, 2) }
	local isp = isps[1]

	local houseFolder = folder("Casas", root)
	local houses = {}
	local xs = { -40, 10, 60, 110 }
	for i, x in xs do
		table.insert(houses, buildHouse(i, Vector3.new(x, 0, -36), Vector3.new(0, 0, 1), -1, houseFolder))
	end
	for i, x in xs do
		table.insert(houses, buildHouse(i + 4, Vector3.new(x, 0, 36), Vector3.new(0, 0, -1), 1, houseFolder))
	end
	-- Rua das Palmeiras: casas 9 a 12 no lado oeste, 13 a 16 no lado leste
	local zs = { -60, -110, -160, -210 }
	for i, z in zs do
		table.insert(houses, buildHouse(8 + i, Vector3.new(World.PalmX - 36, 0, z), Vector3.new(1, 0, 0), 2, houseFolder))
	end
	for i, z in zs do
		table.insert(houses, buildHouse(12 + i, Vector3.new(World.PalmX + 36, 0, z), Vector3.new(-1, 0, 0), 3, houseFolder))
	end
	for _, h in houses do
		h.cto = if h.index <= 4 then "CTO_A" elseif h.index <= 8 then "CTO_B" elseif h.index <= 12 then "CTO_C" else "CTO_D"
	end

	local poleFolder = folder("Postes", root)
	local poles: { [string]: Pole } = {}
	local north = { -85, -60, -15, 35, 85, 135, 185, 235 }
	local south = { -15, 35, 85, 135 }
	for _, x in north do
		poles["N" .. x] = buildPole("PosteN" .. x, x, -16.5, poleFolder)
	end
	for _, x in south do
		poles["S" .. x] = buildPole("PosteS" .. x, x, 16.5, poleFolder)
	end
	for _, z in { -35, -85, -135, -185, -235 } do
		poles["W" .. z] = buildPole("PosteW" .. z, World.PalmX - 16.5, z, poleFolder)
		poles["E" .. z] = buildPole("PosteE" .. z, World.PalmX + 16.5, z, poleFolder)
	end
	local boxes = {
		splitter = buildBox("SplitterPrimario", "Splitter 1:2", poles["N-60"], Color3.fromRGB(60, 60, 65), poleFolder),
		ctoA = buildBox("CTO_A", "CTO A", poles["N35"], Color3.fromRGB(30, 30, 35), poleFolder),
		ctoB = buildBox("CTO_B", "CTO B", poles["S35"], Color3.fromRGB(30, 30, 35), poleFolder),
		splitter2 = buildBox("SplitterPalmeiras", "Splitter 1:2 Palmeiras", poles["W-35"], Color3.fromRGB(60, 60, 65), poleFolder, Vector3.new(0.9, 0, 0)),
		ctoC = buildBox("CTO_C", "CTO C", poles["W-135"], Color3.fromRGB(30, 30, 35), poleFolder, Vector3.new(0.9, 0, 0)),
		ctoD = buildBox("CTO_D", "CTO D", poles["E-135"], Color3.fromRGB(30, 30, 35), poleFolder, Vector3.new(-0.9, 0, 0)),
	}

	local sidewalkPoints = {}
	for x = -100, 140, 30 do
		table.insert(sidewalkPoints, Vector3.new(x, 0.6, -14))
		table.insert(sidewalkPoints, Vector3.new(x + 10, 0.6, 14))
	end
	-- calçadas da Rua das Palmeiras (os moradores de lá passeiam por perto de casa)
	local palmPoints = {}
	for z = -40, -240, -40 do
		table.insert(palmPoints, Vector3.new(World.PalmX - 15, 0.6, z))
		table.insert(palmPoints, Vector3.new(World.PalmX + 15, 0.6, z - 20))
	end

	return {
		houses = houses,
		poles = poles,
		boxes = boxes,
		isp = isp,
		isps = isps,
		plazaPoints = plazaPoints,
		sidewalkPoints = sidewalkPoints,
		palmPoints = palmPoints,
		cablesFolder = folder("Cabos", root),
		npcFolder = folder("Moradores", root),
		effectsFolder = folder("Efeitos", root),
	}
end

return World
