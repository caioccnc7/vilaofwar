-- Quiosque da wiki na recepção do provedor. Ao apertar E, abre a wiki na tela do jogador.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end
local wikiOpen = remotes:FindFirstChild("WikiOpen") or Instance.new("RemoteEvent")
wikiOpen.Name = "WikiOpen"
wikiOpen.Parent = remotes

-- espera o mapa ser montado pelo WorldBuilder
local counter: BasePart? = nil
for _ = 1, 60 do
	counter = workspace:FindFirstChild("ReceptionCounter", true) :: BasePart?
	if counter then
		break
	end
	task.wait(1)
end
if not counter then
	warn("[Wiki] balcão da recepção não encontrado; quiosque não criado")
	return
end

local floorY = counter.Position.Y - counter.Size.Y / 2
local base = Vector3.new(counter.Position.X + 10, floorY, counter.Position.Z + 2)

local model = Instance.new("Model")
model.Name = "QuiosqueWiki"

local function part(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = model
	return p
end

part({ Name = "Pe", Size = Vector3.new(1.6, 3.6, 1.2), CFrame = CFrame.new(base + Vector3.new(0, 1.8, 0)), Color = Color3.fromRGB(30, 34, 42), Material = Enum.Material.Metal })
local screen = part({
	Name = "Tela",
	Size = Vector3.new(3, 2, 0.2),
	-- tela inclinada virada para a entrada do prédio (+Z)
	CFrame = CFrame.new(base + Vector3.new(0, 4.3, 0.2)) * CFrame.Angles(math.rad(-20), 0, 0),
	Color = Color3.fromRGB(8, 12, 20),
	Material = Enum.Material.SmoothPlastic,
})

local sg = Instance.new("SurfaceGui")
sg.Face = Enum.NormalId.Back
sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
sg.PixelsPerStud = 60
sg.LightInfluence = 0
sg.Parent = screen
local label = Instance.new("TextLabel")
label.Size = UDim2.fromScale(1, 1)
label.BackgroundColor3 = Color3.fromRGB(8, 12, 20)
label.TextColor3 = Color3.fromRGB(80, 190, 255)
label.Font = Enum.Font.GothamBlack
label.TextScaled = true
label.Text = "WIKI DO PROVEDOR\nguia de como jogar\n(aperte E)"
label.Parent = sg
local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0.08, 0)
padding.PaddingRight = UDim.new(0.08, 0)
padding.PaddingTop = UDim.new(0.1, 0)
padding.PaddingBottom = UDim.new(0.1, 0)
padding.Parent = label

local light = Instance.new("PointLight")
light.Color = Color3.fromRGB(80, 190, 255)
light.Range = 8
light.Brightness = 0.8
light.Parent = screen

local prompt = Instance.new("ProximityPrompt")
prompt.ActionText = "Abrir wiki"
prompt.ObjectText = "Wiki do provedor"
prompt.KeyboardKeyCode = Enum.KeyCode.E
prompt.MaxActivationDistance = 9
prompt.RequiresLineOfSight = false
prompt.Parent = screen
prompt.Triggered:Connect(function(player)
	wikiOpen:FireClient(player, "primeiro-dia")
end)

model.Parent = counter.Parent
