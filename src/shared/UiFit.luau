-- Ajuda as janelas a caberem em qualquer tela (celular, tablet, PC).
-- UiFit.scale(frame, w, h) põe um UIScale no frame para que a janela, desenhada com
-- w × h pixels, caiba na área útil da ScreenGui (já sem a barra do Roblox).
-- Só diminui, nunca aumenta. h = nil considera só a largura.

local UserInputService = game:GetService("UserInputService")

local UiFit = {}

-- celular ou tablet sem teclado físico
UiFit.touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local function guiOf(frame: Instance): ScreenGui?
	return frame:FindFirstAncestorOfClass("ScreenGui")
end

function UiFit.scale(frame: GuiObject, w: number, h: number?, margin: number?): UIScale
	local m = margin or 16
	local s = frame:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	s.Parent = frame
	local gui = guiOf(frame)
	if not gui then
		return s
	end
	local function update()
		local v = gui.AbsoluteSize
		if v.X < 2 or v.Y < 2 then
			return
		end
		local k = (v.X - m * 2) / w
		if h then
			k = math.min(k, (v.Y - m * 2) / h)
		end
		s.Scale = math.clamp(k, 0.4, 1)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	update()
	return s
end

-- tela pequena (celular deitado tem por volta de 360 a 430 de altura útil)
function UiFit.isSmall(gui: ScreenGui): boolean
	local v = gui.AbsoluteSize
	return v.Y < 520 or v.X < 900
end

-- roda fn(small) agora e sempre que a tela mudar de tamanho
function UiFit.onResize(gui: ScreenGui, fn: (boolean) -> ())
	local last: boolean? = nil
	local function update()
		local v = gui.AbsoluteSize
		if v.X < 2 then
			return
		end
		local small = UiFit.isSmall(gui)
		if small ~= last then
			last = small
			fn(small)
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	update()
end

-- botão "X" vermelho no canto superior direito de uma janela
function UiFit.closeX(parent: GuiObject, onClick: () -> (), size: number?): TextButton
	local n = size or 36
	local b = Instance.new("TextButton")
	b.Name = "FecharX"
	b.AnchorPoint = Vector2.new(1, 0)
	b.Position = UDim2.new(1, -8, 0, 8)
	b.Size = UDim2.fromOffset(n, n)
	b.BackgroundColor3 = Color3.fromRGB(190, 55, 55)
	b.Font = Enum.Font.GothamBlack
	b.TextSize = math.floor(n * 0.55)
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = "X"
	b.ZIndex = 20
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = b
	b.Parent = parent
	b.Activated:Connect(onClick)
	return b
end

return UiFit
