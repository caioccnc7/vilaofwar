-- Aparência dos NPCs: cada morador tem cabelo, chapéu, óculos, barba, roupa e
-- sapato próprios; os técnicos usam uniforme (capacete, colete refletivo, cinto de
-- ferramentas, luvas e botas). Tudo feito com peças soldadas no boneco R15, sem
-- depender de itens do catálogo.

local Players = game:GetService("Players")

local Looks = {}

local SKIN = {
	light = Color3.fromRGB(255, 213, 170),
	fair = Color3.fromRGB(234, 192, 134),
	tan = Color3.fromRGB(224, 172, 105),
	brown = Color3.fromRGB(198, 134, 66),
	medium = Color3.fromRGB(160, 102, 60),
	dark = Color3.fromRGB(141, 85, 36),
	deep = Color3.fromRGB(105, 64, 40),
}
local HAIR = {
	black = Color3.fromRGB(30, 26, 24),
	brown = Color3.fromRGB(92, 58, 34),
	auburn = Color3.fromRGB(140, 60, 30),
	blond = Color3.fromRGB(222, 188, 110),
	grey = Color3.fromRGB(170, 170, 172),
	white = Color3.fromRGB(232, 232, 228),
}

-- Um perfil por casa (1 a 16), na ordem dos nomes do ResidentService.
-- hair: short, long, bun, ponytail, curly, bald, bob, spiky, mohawk, pigtails
-- hat: cap, capBack, straw, fedora · extra: glasses, sunglasses, mustache, beard, headphones
-- sleeves: "short" (braço de pele) ou "long"
local Profiles = {
	{ skin = "fair", hair = "bun", hairColor = "grey", shirt = Color3.fromRGB(220, 110, 150), pants = Color3.fromRGB(110, 70, 120), shoes = Color3.fromRGB(90, 60, 50), glasses = true, height = 0.92, sleeves = "short", collar = true },
	{ skin = "brown", hair = "bald", hairColor = "grey", hat = "straw", shirt = Color3.fromRGB(245, 245, 240), pants = Color3.fromRGB(110, 85, 60), shoes = Color3.fromRGB(70, 45, 30), mustache = true, height = 0.96, sleeves = "short", collar = true },
	{ skin = "tan", hair = "long", hairColor = "brown", shirt = Color3.fromRGB(40, 160, 150), pants = Color3.fromRGB(40, 50, 90), shoes = Color3.fromRGB(240, 240, 240), height = 1.0, sleeves = "short" },
	{ skin = "light", hair = "short", hairColor = "black", hat = "capBack", hatColor = Color3.fromRGB(200, 40, 40), shirt = Color3.fromRGB(120, 125, 135), pants = Color3.fromRGB(30, 30, 35), shoes = Color3.fromRGB(240, 240, 240), height = 1.04, sleeves = "long" },
	{ skin = "medium", hair = "ponytail", hairColor = "auburn", shirt = Color3.fromRGB(250, 200, 50), pants = Color3.fromRGB(70, 90, 140), shoes = Color3.fromRGB(200, 60, 60), height = 0.98, sleeves = "short" },
	{ skin = "deep", hair = "curly", hairColor = "black", headphones = true, shirt = Color3.fromRGB(40, 100, 200), pants = Color3.fromRGB(50, 50, 55), shoes = Color3.fromRGB(240, 240, 240), height = 1.05, sleeves = "short" },
	{ skin = "fair", hair = "pigtails", hairColor = "blond", shirt = Color3.fromRGB(240, 130, 180), pants = Color3.fromRGB(80, 120, 190), shoes = Color3.fromRGB(250, 250, 250), height = 0.9, sleeves = "short" },
	{ skin = "light", hair = "short", hairColor = "white", hat = "cap", hatColor = Color3.fromRGB(40, 90, 60), shirt = Color3.fromRGB(70, 130, 80), pants = Color3.fromRGB(90, 80, 70), shoes = Color3.fromRGB(60, 40, 30), glasses = true, mustache = true, height = 0.95, sleeves = "long", collar = true },
	{ skin = "dark", hair = "curly", hairColor = "grey", shirt = Color3.fromRGB(200, 50, 60), pants = Color3.fromRGB(60, 50, 60), shoes = Color3.fromRGB(80, 50, 40), glasses = true, height = 0.92, sleeves = "short", collar = true },
	{ skin = "tan", hair = "short", hairColor = "brown", beard = true, shirt = Color3.fromRGB(240, 130, 50), pants = Color3.fromRGB(50, 60, 80), shoes = Color3.fromRGB(90, 70, 50), height = 1.06, width = 1.08, sleeves = "short" },
	{ skin = "light", hair = "long", hairColor = "blond", sunglasses = true, shirt = Color3.fromRGB(250, 250, 250), pants = Color3.fromRGB(70, 110, 170), shoes = Color3.fromRGB(220, 170, 140), height = 1.0, sleeves = "short" },
	{ skin = "medium", hair = "bald", hairColor = "white", hat = "fedora", hatColor = Color3.fromRGB(60, 50, 45), beard = true, beardColor = "white", shirt = Color3.fromRGB(40, 50, 90), pants = Color3.fromRGB(70, 70, 75), shoes = Color3.fromRGB(30, 30, 30), height = 0.97, width = 1.05, sleeves = "long", collar = true },
	{ skin = "brown", hair = "bob", hairColor = "black", shirt = Color3.fromRGB(150, 80, 190), pants = Color3.fromRGB(40, 40, 45), shoes = Color3.fromRGB(160, 40, 60), height = 0.99, sleeves = "short" },
	{ skin = "fair", hair = "spiky", hairColor = "blond", hat = "cap", hatColor = Color3.fromRGB(40, 90, 200), shirt = Color3.fromRGB(60, 170, 90), pants = Color3.fromRGB(90, 110, 140), shoes = Color3.fromRGB(240, 240, 240), height = 1.03, sleeves = "short" },
	{ skin = "deep", hair = "bun", hairColor = "white", shirt = Color3.fromRGB(240, 150, 60), pants = Color3.fromRGB(120, 70, 50), shoes = Color3.fromRGB(70, 50, 40), glasses = true, height = 0.9, sleeves = "short", collar = true },
	{ skin = "tan", hair = "mohawk", hairColor = "black", headphones = true, shirt = Color3.fromRGB(35, 35, 40), pants = Color3.fromRGB(60, 60, 65), shoes = Color3.fromRGB(200, 40, 40), height = 1.04, sleeves = "short" },
}

-- ---------------------------------------------------------------------------
-- Montagem
-- ---------------------------------------------------------------------------

local function makeRig(skin: Color3, height: number?, width: number?): Model?
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = skin
	desc.LeftArmColor = skin
	desc.RightArmColor = skin
	desc.TorsoColor = skin
	desc.LeftLegColor = skin
	desc.RightLegColor = skin
	desc.HeightScale = height or 1
	desc.WidthScale = width or 1
	desc.DepthScale = width or 1
	desc.HeadScale = 1
	local ok, m = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if ok and m then
		-- as cores passam a ser das peças (BodyColors pintaria tudo de volta)
		local bc = m:FindFirstChildOfClass("BodyColors")
		if bc then
			bc:Destroy()
		end
		return m
	end
	return nil
end

-- peça decorativa soldada numa parte do corpo (offset relativo à parte)
local function deco(model: Model, attach: BasePart, props: { [string]: any }, offset: CFrame): BasePart
	local p = Instance.new(props.Class or "Part") :: BasePart
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	-- a forma vem antes do tamanho (bola força tamanho igual nos três eixos)
	if props.Shape then
		(p :: any).Shape = props.Shape
	end
	for k, v in props do
		if k ~= "Class" and k ~= "Shape" then
			(p :: any)[k] = v
		end
	end
	p.CFrame = attach.CFrame * offset
	p.Parent = model
	local w = Instance.new("WeldConstraint")
	w.Part0 = attach
	w.Part1 = p
	w.Parent = p
	return p
end

local function paint(model: Model, names: { string }, color: Color3, material: Enum.Material?)
	for _, n in names do
		local p = model:FindFirstChild(n)
		if p and p:IsA("BasePart") then
			p.Color = color
			if material then
				p.Material = material
			end
		end
	end
end

local ARMS_UP = { "LeftUpperArm", "RightUpperArm" }
local ARMS_LOW = { "LeftLowerArm", "RightLowerArm" }
local HANDS = { "LeftHand", "RightHand" }
local LEGS = { "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" }
local FEET = { "LeftFoot", "RightFoot" }

local function dressBody(m: Model, shirt: Color3, pants: Color3, shoes: Color3, longSleeves: boolean, skin: Color3)
	paint(m, { "UpperTorso" }, shirt, Enum.Material.SmoothPlastic)
	paint(m, { "LowerTorso" }, pants, Enum.Material.SmoothPlastic)
	paint(m, ARMS_UP, shirt, Enum.Material.SmoothPlastic)
	paint(m, ARMS_LOW, if longSleeves then shirt else skin, if longSleeves then Enum.Material.SmoothPlastic else nil)
	paint(m, HANDS, skin)
	paint(m, LEGS, pants, Enum.Material.SmoothPlastic)
	paint(m, FEET, shoes)
	-- sola mais escura e um pouco maior: parece calçado
	for _, n in FEET do
		local foot = m:FindFirstChild(n) :: BasePart?
		if foot then
			local s = foot.Size
			deco(m, foot, { Name = "Sola", Size = Vector3.new(s.X * 1.08, s.Y * 0.28, s.Z * 1.12), Color = Color3.fromRGB(35, 32, 30) }, CFrame.new(0, -s.Y * 0.38, -s.Z * 0.04))
		end
	end
end

local function hair(m: Model, head: BasePart, style: string, color: Color3)
	local u = head.Size.Y
	local w = head.Size.X
	local function H(name: string, size: Vector3, off: CFrame, shape: Enum.PartType?)
		return deco(m, head, { Name = name, Size = size, Color = color, Material = Enum.Material.SmoothPlastic, Shape = shape or Enum.PartType.Block }, off)
	end
	local function cap() -- camada de cima e de trás, base de quase todo penteado
		H("CabeloTopo", Vector3.new(w * 1.06, u * 0.3, u * 1.06), CFrame.new(0, u * 0.42, u * 0.03))
		H("CabeloNuca", Vector3.new(w * 1.06, u * 0.62, u * 0.22), CFrame.new(0, u * 0.12, u * 0.46))
	end
	if style == "short" then
		cap()
	elseif style == "long" then
		cap()
		H("CabeloLongo", Vector3.new(w * 1.04, u * 1.25, u * 0.26), CFrame.new(0, -u * 0.25, u * 0.5))
		for _, sx in { -1, 1 } do
			H("CabeloLado", Vector3.new(u * 0.14, u * 0.9, u * 0.5), CFrame.new(sx * w * 0.5, -u * 0.05, u * 0.2))
		end
	elseif style == "bun" then
		cap()
		H("Coque", Vector3.new(u * 0.5, u * 0.5, u * 0.5), CFrame.new(0, u * 0.55, u * 0.42), Enum.PartType.Ball)
	elseif style == "ponytail" then
		cap()
		H("RaboDeCavalo", Vector3.new(u * 0.28, u * 0.85, u * 0.28), CFrame.new(0, -u * 0.05, u * 0.66) * CFrame.Angles(math.rad(-18), 0, 0))
		H("Prendedor", Vector3.new(u * 0.32, u * 0.1, u * 0.32), CFrame.new(0, u * 0.32, u * 0.6))
	elseif style == "curly" then
		for _, p in { Vector3.new(0, 0.5, 0), Vector3.new(-0.32, 0.42, 0.1), Vector3.new(0.32, 0.42, 0.1), Vector3.new(0, 0.42, 0.35), Vector3.new(-0.28, 0.3, 0.35), Vector3.new(0.28, 0.3, 0.35), Vector3.new(-0.2, 0.48, -0.25), Vector3.new(0.2, 0.48, -0.25) } do
			H("Cacho", Vector3.new(u * 0.48, u * 0.48, u * 0.48), CFrame.new(p * u), Enum.PartType.Ball)
		end
	elseif style == "bald" then
		for _, sx in { -1, 1 } do
			H("CabeloLado", Vector3.new(u * 0.1, u * 0.28, u * 0.75), CFrame.new(sx * w * 0.52, u * 0.08, u * 0.12))
		end
		H("CabeloNuca", Vector3.new(w * 1.02, u * 0.28, u * 0.12), CFrame.new(0, u * 0.08, u * 0.52))
	elseif style == "bob" then
		cap()
		for _, sx in { -1, 1 } do
			H("CabeloLado", Vector3.new(u * 0.16, u * 0.72, u * 0.85), CFrame.new(sx * w * 0.52, u * 0.02, u * 0.1))
		end
		H("Franja", Vector3.new(w * 0.95, u * 0.16, u * 0.12), CFrame.new(0, u * 0.36, -u * 0.48))
	elseif style == "spiky" then
		cap()
		for i = -1, 1 do
			deco(m, head, { Name = "Espeto", Class = "WedgePart", Size = Vector3.new(u * 0.3, u * 0.35, u * 0.5), Color = color }, CFrame.new(i * u * 0.3, u * 0.7, -u * 0.1))
		end
	elseif style == "mohawk" then
		H("CabeloNuca", Vector3.new(w * 1.02, u * 0.3, u * 0.14), CFrame.new(0, u * 0.05, u * 0.5))
		H("Moicano", Vector3.new(u * 0.2, u * 0.38, u * 1.05), CFrame.new(0, u * 0.66, u * 0.02))
	elseif style == "pigtails" then
		cap()
		for _, sx in { -1, 1 } do
			H("Chiquinha", Vector3.new(u * 0.4, u * 0.4, u * 0.4), CFrame.new(sx * w * 0.62, u * 0.25, u * 0.25), Enum.PartType.Ball)
		end
	end
end

local function hat(m: Model, head: BasePart, kind: string, color: Color3)
	local u = head.Size.Y
	local w = head.Size.X
	if kind == "cap" or kind == "capBack" then
		local dir = if kind == "cap" then -1 else 1
		deco(m, head, { Name = "Bone", Size = Vector3.new(w * 1.1, u * 0.32, u * 1.1), Color = color, Material = Enum.Material.SmoothPlastic }, CFrame.new(0, u * 0.5, 0))
		deco(m, head, { Name = "Aba", Size = Vector3.new(w * 0.9, u * 0.05, u * 0.5), Color = color, Material = Enum.Material.SmoothPlastic }, CFrame.new(0, u * 0.36, dir * u * 0.72))
		deco(m, head, { Name = "Botao", Shape = Enum.PartType.Ball, Size = Vector3.new(u * 0.12, u * 0.12, u * 0.12), Color = color }, CFrame.new(0, u * 0.68, 0))
	elseif kind == "straw" then
		local straw = Color3.fromRGB(225, 195, 120)
		deco(m, head, { Name = "AbaPalha", Shape = Enum.PartType.Cylinder, Size = Vector3.new(u * 0.06, u * 2.0, u * 2.0), Color = straw, Material = Enum.Material.SmoothPlastic }, CFrame.new(0, u * 0.4, 0) * CFrame.Angles(0, 0, math.rad(90)))
		deco(m, head, { Name = "CopaPalha", Shape = Enum.PartType.Cylinder, Size = Vector3.new(u * 0.45, u * 1.05, u * 1.05), Color = straw, Material = Enum.Material.SmoothPlastic }, CFrame.new(0, u * 0.62, 0) * CFrame.Angles(0, 0, math.rad(90)))
		deco(m, head, { Name = "Fita", Shape = Enum.PartType.Cylinder, Size = Vector3.new(u * 0.1, u * 1.07, u * 1.07), Color = Color3.fromRGB(120, 40, 30) }, CFrame.new(0, u * 0.48, 0) * CFrame.Angles(0, 0, math.rad(90)))
	elseif kind == "fedora" then
		deco(m, head, { Name = "AbaChapeu", Shape = Enum.PartType.Cylinder, Size = Vector3.new(u * 0.05, u * 1.55, u * 1.55), Color = color }, CFrame.new(0, u * 0.42, 0) * CFrame.Angles(0, 0, math.rad(90)))
		deco(m, head, { Name = "CopaChapeu", Shape = Enum.PartType.Cylinder, Size = Vector3.new(u * 0.5, u * 1.0, u * 1.0), Color = color }, CFrame.new(0, u * 0.66, 0) * CFrame.Angles(0, 0, math.rad(90)))
		deco(m, head, { Name = "Fita", Shape = Enum.PartType.Cylinder, Size = Vector3.new(u * 0.1, u * 1.02, u * 1.02), Color = Color3.fromRGB(25, 25, 25) }, CFrame.new(0, u * 0.48, 0) * CFrame.Angles(0, 0, math.rad(90)))
	end
end

local function faceExtras(m: Model, head: BasePart, prof: any)
	local u = head.Size.Y
	local front = -head.Size.Z * 0.5
	if prof.glasses or prof.sunglasses then
		local frame = Color3.fromRGB(30, 30, 35)
		local lens = if prof.sunglasses then Color3.fromRGB(20, 20, 25) else Color3.fromRGB(190, 220, 240)
		for _, sx in { -1, 1 } do
			deco(m, head, { Name = "Aro", Size = Vector3.new(u * 0.3, u * 0.2, u * 0.04), Color = frame }, CFrame.new(sx * u * 0.2, u * 0.08, front - u * 0.03))
			deco(m, head, { Name = "Lente", Size = Vector3.new(u * 0.24, u * 0.14, u * 0.02), Color = lens, Material = Enum.Material.Glass, Transparency = if prof.sunglasses then 0.05 else 0.45 }, CFrame.new(sx * u * 0.2, u * 0.08, front - u * 0.055))
			deco(m, head, { Name = "Haste", Size = Vector3.new(u * 0.03, u * 0.03, u * 0.55), Color = frame }, CFrame.new(sx * head.Size.X * 0.51, u * 0.1, front + u * 0.25))
		end
		deco(m, head, { Name = "Ponte", Size = Vector3.new(u * 0.1, u * 0.03, u * 0.03), Color = frame }, CFrame.new(0, u * 0.12, front - u * 0.03))
	end
	local beardColor = HAIR[prof.beardColor or prof.hairColor] or HAIR.black
	if prof.mustache then
		deco(m, head, { Name = "Bigode", Size = Vector3.new(u * 0.42, u * 0.08, u * 0.06), Color = beardColor, Material = Enum.Material.SmoothPlastic }, CFrame.new(0, -u * 0.13, front - u * 0.02))
	end
	if prof.beard then
		deco(m, head, { Name = "Barba", Size = Vector3.new(head.Size.X * 0.9, u * 0.3, u * 0.5), Color = beardColor, Material = Enum.Material.SmoothPlastic }, CFrame.new(0, -u * 0.38, front + u * 0.2))
		deco(m, head, { Name = "Bigode", Size = Vector3.new(u * 0.45, u * 0.08, u * 0.06), Color = beardColor, Material = Enum.Material.SmoothPlastic }, CFrame.new(0, -u * 0.13, front - u * 0.02))
	end
	if prof.headphones then
		local c = Color3.fromRGB(25, 25, 30)
		deco(m, head, { Name = "Arco", Size = Vector3.new(head.Size.X * 1.1, u * 0.08, u * 0.18), Color = c }, CFrame.new(0, u * 0.62, 0))
		for _, sx in { -1, 1 } do
			deco(m, head, { Name = "Concha", Shape = Enum.PartType.Cylinder, Size = Vector3.new(u * 0.16, u * 0.42, u * 0.42), Color = c }, CFrame.new(sx * head.Size.X * 0.55, u * 0.02, 0))
			deco(m, head, { Name = "ConchaCor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(u * 0.04, u * 0.3, u * 0.3), Color = Color3.fromRGB(230, 60, 60), Material = Enum.Material.Neon }, CFrame.new(sx * head.Size.X * 0.64, u * 0.02, 0))
		end
	end
end

local function torsoExtras(m: Model, prof: any)
	local torso = m:FindFirstChild("UpperTorso") :: BasePart?
	local lower = m:FindFirstChild("LowerTorso") :: BasePart?
	if torso and prof.collar then
		local s = torso.Size
		for _, sx in { -1, 1 } do
			deco(m, torso, { Name = "Gola", Class = "WedgePart", Size = Vector3.new(s.X * 0.18, s.Y * 0.18, s.Z * 0.12), Color = prof.shirt:Lerp(Color3.new(1, 1, 1), 0.35), Material = Enum.Material.SmoothPlastic }, CFrame.new(sx * s.X * 0.12, s.Y * 0.4, -s.Z * 0.5) * CFrame.Angles(0, math.rad(180), 0))
		end
		for i = 0, 2 do
			deco(m, torso, { Name = "Botao", Shape = Enum.PartType.Ball, Size = Vector3.new(s.Y * 0.06, s.Y * 0.06, s.Y * 0.06), Color = Color3.fromRGB(240, 240, 235) }, CFrame.new(0, s.Y * (0.22 - i * 0.22), -s.Z * 0.52))
		end
	end
	if lower then
		local s = lower.Size
		deco(m, lower, { Name = "Cinto", Size = Vector3.new(s.X * 1.04, s.Y * 0.22, s.Z * 1.08), Color = Color3.fromRGB(50, 35, 25), Material = Enum.Material.Leather }, CFrame.new(0, s.Y * 0.32, 0))
		deco(m, lower, { Name = "Fivela", Size = Vector3.new(s.X * 0.16, s.Y * 0.18, s.Z * 0.06), Color = Color3.fromRGB(200, 180, 110), Material = Enum.Material.Metal }, CFrame.new(0, s.Y * 0.32, -s.Z * 0.56))
	end
end

function Looks.resident(index: number): Model?
	local prof = Profiles[(index - 1) % #Profiles + 1]
	local skin = SKIN[prof.skin] or SKIN.tan
	local m = makeRig(skin, prof.height, prof.width)
	if not m then
		return nil
	end
	dressBody(m, prof.shirt, prof.pants, prof.shoes, prof.sleeves == "long", skin)
	local head = m:FindFirstChild("Head") :: BasePart?
	if head then
		hair(m, head, prof.hair, HAIR[prof.hairColor] or HAIR.black)
		if prof.hat then
			hat(m, head, prof.hat, prof.hatColor or Color3.fromRGB(60, 60, 60))
		end
		faceExtras(m, head, prof)
	end
	torsoExtras(m, prof)
	return m
end

-- ---------------------------------------------------------------------------
-- Uniforme do técnico
-- ---------------------------------------------------------------------------

local TechSkins = { SKIN.brown, SKIN.light, SKIN.dark, SKIN.fair, SKIN.deep, SKIN.tan, SKIN.medium, SKIN.light }
-- embaixo do capacete só aparece cabelo comprido (rabo de cavalo, coque); "none" = nada
local TechHair = { "none", "ponytail", "none", "bun", "none", "none", "none", "ponytail" }
local TechHairColor = { HAIR.black, HAIR.brown, HAIR.black, HAIR.auburn, HAIR.black, HAIR.black, HAIR.brown, HAIR.blond }

function Looks.technician(slot: number): Model?
	local skin = TechSkins[(slot - 1) % #TechSkins + 1]
	local m = makeRig(skin, 1.02, 1.04)
	if not m then
		return nil
	end
	local navy = Color3.fromRGB(30, 45, 80)
	dressBody(m, navy, navy, Color3.fromRGB(35, 30, 28), true, skin)
	-- luvas
	paint(m, HANDS, Color3.fromRGB(70, 70, 75), Enum.Material.SmoothPlastic)
	-- botas: cano alto até a canela
	for _, n in { "LeftLowerLeg", "RightLowerLeg" } do
		local leg = m:FindFirstChild(n) :: BasePart?
		if leg then
			local s = leg.Size
			deco(m, leg, { Name = "CanoBota", Size = Vector3.new(s.X * 1.1, s.Y * 0.35, s.Z * 1.1), Color = Color3.fromRGB(35, 30, 28), Material = Enum.Material.Leather }, CFrame.new(0, -s.Y * 0.33, 0))
		end
	end
	local orange = Color3.fromRGB(255, 125, 25)
	local reflective = Color3.fromRGB(225, 230, 235)
	local torso = m:FindFirstChild("UpperTorso") :: BasePart?
	if torso then
		local s = torso.Size
		-- colete laranja com faixas refletivas
		local vest = deco(m, torso, { Name = "Colete", Size = Vector3.new(s.X * 1.04, s.Y * 0.9, s.Z * 1.1), Color = orange, Material = Enum.Material.SmoothPlastic }, CFrame.new(0, -s.Y * 0.04, 0))
		for _, y in { 0.05, -0.25 } do
			deco(m, torso, { Name = "Refletivo", Size = Vector3.new(s.X * 1.06, s.Y * 0.08, s.Z * 1.12), Color = reflective, Material = Enum.Material.Neon }, CFrame.new(0, s.Y * y, 0))
		end
		for _, sx in { -1, 1 } do
			deco(m, torso, { Name = "RefletivoOmbro", Size = Vector3.new(s.X * 0.1, s.Y * 0.08, s.Z * 1.12), Color = reflective, Material = Enum.Material.Neon }, CFrame.new(sx * s.X * 0.25, s.Y * 0.28, 0) * CFrame.Angles(0, 0, math.rad(90)))
		end
		-- crachá e rádio
		local badge = deco(m, torso, { Name = "Cracha", Size = Vector3.new(s.X * 0.18, s.Y * 0.2, s.Z * 0.04), Color = Color3.fromRGB(250, 250, 250) }, CFrame.new(-s.X * 0.22, s.Y * 0.2, -s.Z * 0.58))
		local _ = badge
		deco(m, torso, { Name = "Radio", Size = Vector3.new(s.X * 0.12, s.Y * 0.28, s.Z * 0.12), Color = Color3.fromRGB(30, 30, 30) }, CFrame.new(s.X * 0.28, s.Y * 0.15, -s.Z * 0.6))
		deco(m, torso, { Name = "Antena", Size = Vector3.new(s.X * 0.03, s.Y * 0.22, s.X * 0.03), Color = Color3.fromRGB(30, 30, 30) }, CFrame.new(s.X * 0.31, s.Y * 0.42, -s.Z * 0.6))
		-- costas do colete com o nome do provedor
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Back
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 50
		gui.Parent = vest
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(0.9, 0.3)
		t.Position = UDim2.fromScale(0.05, 0.12)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.GothamBlack
		t.TextScaled = true
		t.TextColor3 = Color3.fromRGB(20, 30, 60)
		t.Text = "FIBRA DA VILA"
		t.Parent = gui
	end
	local lower = m:FindFirstChild("LowerTorso") :: BasePart?
	if lower then
		local s = lower.Size
		-- cinto de ferramentas com bolsas, alicate e bobina de fibra
		deco(m, lower, { Name = "CintoFerramentas", Size = Vector3.new(s.X * 1.08, s.Y * 0.3, s.Z * 1.14), Color = Color3.fromRGB(110, 75, 40), Material = Enum.Material.Leather }, CFrame.new(0, s.Y * 0.25, 0))
		for _, sx in { -1, 1 } do
			deco(m, lower, { Name = "Bolsa", Size = Vector3.new(s.X * 0.28, s.Y * 0.6, s.Z * 0.35), Color = Color3.fromRGB(95, 65, 35), Material = Enum.Material.Leather }, CFrame.new(sx * s.X * 0.48, -s.Y * 0.05, -s.Z * 0.2))
		end
		deco(m, lower, { Name = "Alicate", Size = Vector3.new(s.X * 0.05, s.Y * 0.5, s.X * 0.05), Color = Color3.fromRGB(220, 40, 40) }, CFrame.new(-s.X * 0.42, s.Y * 0.35, -s.Z * 0.3))
		deco(m, lower, { Name = "BobinaFibra", Shape = Enum.PartType.Cylinder, Size = Vector3.new(s.X * 0.12, s.Y * 0.55, s.Y * 0.55), Color = Color3.fromRGB(240, 200, 40) }, CFrame.new(s.X * 0.6, 0, s.Z * 0.15))
	end
	local head = m:FindFirstChild("Head") :: BasePart?
	if head then
		local u = head.Size.Y
		local w = head.Size.X
		hair(m, head, TechHair[(slot - 1) % #TechHair + 1], TechHairColor[(slot - 1) % #TechHairColor + 1])
		-- capacete com aba, faixa refletiva e jugular
		local yellow = Color3.fromRGB(250, 200, 30)
		local shell = deco(m, head, { Name = "Capacete", Size = Vector3.new(w * 1.2, u * 0.8, u * 1.25), Color = yellow }, CFrame.new(0, u * 0.5, 0.02 * u))
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = shell
		deco(m, head, { Name = "AbaCapacete", Size = Vector3.new(w * 1.0, u * 0.06, u * 0.35), Color = yellow }, CFrame.new(0, u * 0.36, -u * 0.68))
		deco(m, head, { Name = "Crista", Size = Vector3.new(u * 0.14, u * 0.12, u * 1.1), Color = yellow }, CFrame.new(0, u * 0.82, 0))
		deco(m, head, { Name = "FaixaCapacete", Size = Vector3.new(w * 1.24, u * 0.07, u * 0.08), Color = reflective, Material = Enum.Material.Neon }, CFrame.new(0, u * 0.5, -u * 0.6))
		for _, sx in { -1, 1 } do
			deco(m, head, { Name = "Jugular", Size = Vector3.new(u * 0.04, u * 0.7, u * 0.06), Color = Color3.fromRGB(40, 40, 40) }, CFrame.new(sx * w * 0.5, -u * 0.05, -u * 0.05))
		end
	end
	return m
end

return Looks
