-- Sala de rack: equipamentos físicos (roteador e OLT) com energia, cabos, console e configuração.
-- Equipamento novo chega numa caixa, é instalado num slot vazio, ligado, cabeado e configurado
-- pelo console. A rede do jogo só funciona com o que estiver configurado de verdade.
--
-- Cada provedor tem o seu rack: RackModule.new(P, world, net) cria tudo no prédio dele.
-- Os Remotes são um só para o jogo inteiro e vão para o rack do provedor do jogador.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config)
local World = require(script.Parent.WorldBuilder)
local Remotes = require(script.Parent.Remotes)
local RouterCli = require(script.Parent.Cli.RouterCli)
local OltCli = require(script.Parent.Cli.OltCli)
local Docs = require(script.Parent.Cli.Docs)
local Shell = require(script.Parent.Cli.LinuxShell)
local Providers = require(script.Parent.Providers)
local NetworkGraph = require(ReplicatedStorage.Shared.NetworkGraph)

local RackModule = {}


function RackModule.new(P: any, worldData: any, netService: any): any
	local Rack = {}
	Rack.devices = {} -- lista de equipamentos instalados
	Rack.deadDns = {} -- servidores DNS externos fora do ar

	local net: any = netService
	local game_: any = P.game
	local world: any = worldData
	local isp = worldData.isps[P.slot]
	-- tudo o que o rack cria fica nesta pasta (some quando o provedor fecha)
	local runtime = Instance.new("Folder")
	runtime.Name = "RackDoProvedor"
	runtime.Parent = isp.model
	local extraPrompts = {} -- prompts nas peças fixas do prédio (PCs do NOC)
	local conns = {}

	-- só a equipe deste provedor mexe no prédio dele
	local function own(player: Player): boolean
		if Providers.of(player) == P then
			return true
		end
		Remotes.notify(player, "Este prédio é do " .. P.name .. ". Use o seu provedor (menu Provedor, tecla P).", "error")
		return false
	end
	local slots = {}
	local sessions = {} -- [player][deviceId] = sessão do console
	local pcSessions = {} -- [player][pcIndex] = { remote = dev?, session = {} }
	local pcs = {} -- [pcIndex] = BasePart (teclado da mesa do NOC)
	local seenAt = {} -- SN -> horário em que apareceu no autofind
	local nextId = 1
	local lastRouterProblem = ""
	local lastDay = 1
	local shopTerminal: BasePart
	local techService: any = nil -- TechService (técnico de rua), ligado pelo Main
	local boxSpot: Vector3

	local SLOT_COUNT = 5
	local BOOT = { router = 20, olt = 30 }
	local NB = 100 -- id do terminal do notebook (os PCs do NOC usam 1 a 4)
	local SERIAL_RANGE = 10 -- alcance do cabo de console do notebook

	local RED = Color3.fromRGB(210, 50, 50) -- link da operadora
	local BLUE = Color3.fromRGB(40, 120, 230) -- rede interna (cobre)
	local YELLOW = Color3.fromRGB(240, 200, 40) -- fibra óptica

	Rack.Catalog = {
		{ id = "router", kind = "router", name = "Roteador " .. RouterCli.Brand .. " " .. RouterCli.Model, price = 900, info = "Roteador de borda. Vem zerado de fábrica." },
		{ id = "olt", kind = "olt", name = "OLT " .. OltCli.Brand .. " " .. OltCli.Model, price = 1800, info = "8 portas PON. Vem sem nenhuma ONU cadastrada." },
		{ id = "link", kind = "link", name = "+" .. Config.UpstreamUpgradeMbps .. " Mbps de link do upstream", price = Config.UpstreamUpgradeCost, info = "Mais banda para o horário de pico." },
		{ id = "tool_PowerMeter", kind = "tool", tool = "PowerMeter", name = Config.ToolNames.PowerMeter, price = Config.ToolPrices.PowerMeter, info = "Mede o sinal óptico (dBm) nas casas e nas caixas da rua." },
		{ id = "tool_Fusion", kind = "tool", tool = "Fusion", name = Config.ToolNames.Fusion, price = Config.ToolPrices.Fusion, info = "Emenda fibra rompida, refaz conectores e instala clientes." },
		{ id = "tool_Notebook", kind = "tool", tool = "Notebook", name = Config.ToolNames.Notebook, price = Config.ToolPrices.Notebook, info = "Terminal portátil: ssh, telnet e cabo de console direto no equipamento." },
	}
	for _, key in Config.SupplyOrder do
		local sp = Config.Supplies[key]
		table.insert(Rack.Catalog, { id = "sup_" .. key, kind = "supply", supply = key, units = sp.pack, name = sp.name .. " (" .. sp.pack .. " un.)", price = sp.price, info = sp.info })
	end

	local FICHA = table.concat({
		"FICHA DO LINK · FIBRA DA VILA · DATACENTER (2º andar)",
		"",
		"Rack 01 = DIO (fibras) · Rack 02 = rede (roteador e OLT) · Rack 03 = servidores · Rack 04 = reserva",
		"Cabos: VERMELHO operadora · AZUL rede interna · AMARELO fibra. Chegue perto para ler a etiqueta.",
		"Cabo de console: Notebook TI perto do equipamento, screen /dev/ttyUSB0 115200 (ou console).",
		"TAB completa os comandos em todos os terminais. ? mostra as opções no roteador e na OLT.",
		"",
		"Upstream (ether1): IP 100.64.10.2/30, gateway 100.64.10.1",
		"DNS do upstream: 200.200.200.53   DNS públicos: 8.8.8.8, 1.1.1.1",
		"Rede dos clientes (ether2): 10.100.0.1/22, NAT masquerade saindo pela ether1",
		"OLT: placa GPON 0/1. Porta 0 = CTO A (1-4), 1 = CTO B (5-8), 2 = CTO C (9-12), 3 = CTO D (13-16)",
		"Perfis: ont-lineprofile-id 10, ont-srvprofile-id 10, VLAN 100, gemport 1",
		"Gerência (PCs do NOC, Ubuntu): ssh admin@borda-vila (10.100.0.1), telnet olt-vila (10.100.0.2)",
		"Manual completo: aperte H em cada equipamento ou 'man' no PC do NOC",
		"",
		"ROTEADOR NOVO",
		"  /system identity set name=BORDA-VILA",
		"  /ip address add address=100.64.10.2/30 interface=ether1",
		"  /ip address add address=10.100.0.1/22 interface=ether2",
		"  /ip route add gateway=100.64.10.1",
		"  /ip firewall nat add chain=srcnat action=masquerade out-interface=ether1",
		"  /ip dns set servers=200.200.200.53,8.8.8.8 allow-remote-requests=yes",
		"  /ping 8.8.8.8   e   /ping google.com",
		"",
		"ONU NOVA NA OLT",
		"  enable",
		"  config",
		"  display ont autofind all",
		"  interface gpon 0/1",
		"  ont add 0 sn-auth <SN> omci ont-lineprofile-id 10 ont-srvprofile-id 10 desc \"casa1\"",
		"  quit",
		"  service-port vlan 100 gpon 0/1/0 ont <ID> gemport 1 multi-service user-vlan 100 tag-transform translate",
		"",
		"ONU TROCADA: interface gpon 0/1  ->  ont modify <porta> <ID> sn <SN-novo>",
	}, "\n")

	-- A ficha mostra no topo se o link já foi contratado.
	local function fichaText(): string
		if game_ and game_.linkContracted then
			return string.format("LINK ATIVO: %d Mbps contratados com a operadora (cabo vermelho na ether1).\n\n", net.slot(P.slot).upstreamMbps) .. FICHA
		end
		return "LINK NÃO CONTRATADO! O cabo vermelho da operadora ainda não tem sinal.\nContrate o link no terminal de compras (almoxarifado, térreo) antes de configurar o roteador.\n\n" .. FICHA
	end

	-- ---------------------------------------------------------------------------
	-- Visual dos equipamentos
	-- ---------------------------------------------------------------------------

	local function slotCFrame(i: number): CFrame
		local f = isp.rackFront
		return CFrame.new(f.X, isp.dcFloorY + 1.4 + (i - 1) * 1.75, f.Z + 0.3)
	end

	local function prompt(parent: Instance, action: string, object: string, key: Enum.KeyCode, hold: number?, row: number?): ProximityPrompt
		local p = Instance.new("ProximityPrompt")
		-- Vários prompts na mesma peça ficam empilhados um sobre o outro; o
		-- deslocamento em linhas deixa todas as opções visíveis.
		p.UIOffset = Vector2.new(0, (row or 0) * 72)
		p.ActionText = action
		p.ObjectText = object
		p.KeyboardKeyCode = key
		p.HoldDuration = hold or 0
		p.MaxActivationDistance = 9
		p.RequiresLineOfSight = false
		p.Parent = parent
		return p
	end

	local function deviceLabel(dev: any): string
		if dev.kind == "router" then
			return dev.cfg.identity
		end
		return dev.cfg.sysname
	end

	local function isActive(dev: any): boolean
		return dev.powered and dev.cabled and not dev.failed and os.clock() >= dev.bootUntil
	end

	local function activeOf(kind: string): any
		for _, dev in Rack.devices do
			if dev.kind == kind and isActive(dev) then
				return dev
			end
		end
		return nil
	end
	Rack.activeOf = activeOf

	local function uptime(dev: any): string
		local s = math.max(0, math.floor(os.clock() - dev.bootUntil))
		return string.format("%dh%02dm%02ds", s // 3600, (s // 60) % 60, s % 60)
	end

	-- Etiqueta presa no cabo. Só aparece de perto (MaxDistance), para o rack não
	-- virar uma poluição de texto quando você olha de longe.
	local function cableTag(dev: any, pos: Vector3, text: string, color: Color3)
		local t = World.part({ Name = "Etiqueta", Size = Vector3.new(0.28, 0.16, 0.04), CFrame = CFrame.new(pos), Color = Color3.new(1, 1, 1), CanCollide = false, CastShadow = false, Parent = dev.model })
		table.insert(dev.parts.cables, t)
		local bb = Instance.new("BillboardGui")
		-- tamanho em studs: a etiqueta fica do tamanho de uma etiqueta de verdade e
		-- não cobre as vizinhas quando você chega perto
		bb.Size = UDim2.new(2.8, 0, 0.32, 0)
		bb.MaxDistance = 10
		bb.LightInfluence = 0
		bb.Parent = t
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = Color3.fromRGB(250, 250, 250)
		frame.BorderSizePixel = 0
		frame.Parent = bb
		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(0, 6, 1, 0)
		stripe.BackgroundColor3 = color
		stripe.BorderSizePixel = 0
		stripe.Parent = frame
		local label = Instance.new("TextLabel")
		label.Position = UDim2.fromOffset(9, 0)
		label.Size = UDim2.new(1, -11, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Code
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Color3.fromRGB(20, 20, 25)
		label.Text = text
		label.Parent = frame
	end

	local function cableLine(dev: any, points: { Vector3 }, color: Color3, startTag: string, endTag: string?, lift: number)
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			local len = (b - a).Magnitude
			if len > 0.01 then
				local seg = World.part({ Name = "Cabo", Size = Vector3.new(0.1, 0.1, len), CFrame = CFrame.lookAt((a + b) / 2, b), Color = color, CanCollide = false, CastShadow = false, Parent = dev.model })
				table.insert(dev.parts.cables, seg)
			end
		end
		-- etiquetas empilhadas pela altura (lift) para não ficarem uma em cima da outra
		cableTag(dev, points[3] + Vector3.new(0, 0.35 + lift, 0.05), startTag, color)
		if endTag then
			cableTag(dev, points[#points] + Vector3.new(0, 0.5 + lift, 0.15), endTag, color)
		end
	end

	-- Cada cabo sai da porta, vai para a lateral do rack, sobe até a eletrocalha e
	-- desce no destino (caixa da operadora ou DIO). Roteador e OLT se ligam pela
	-- lateral esquerda do rack, sem passar pela eletrocalha.
	local function drawCables(dev: any)
		for _, c in dev.parts.cables do
			c:Destroy()
		end
		dev.parts.cables = {}
		if not dev.cabled then
			return
		end
		local dc = isp.dc
		local cf = dev.parts.body.CFrame
		local rx = isp.rackFront.X
		local frontZ = cf.Position.Z + 0.55
		local floor = isp.dcFloorY
		local function portPos(i: number): Vector3
			local x = 0.35 + (i - 1) * (if dev.kind == "olt" then 0.17 else 0.3)
			return (cf * CFrame.new(x, -0.25, 0.32)).Position
		end
		local function viaTray(from: Vector3, laneX: number, to: Vector3, lane: number): { Vector3 }
			local up = dc.trayY - 0.3 - lane * 0.08
			local tz = dc.trayZ + lane * 0.12
			return {
				from,
				Vector3.new(from.X, from.Y, frontZ + lane * 0.05),
				Vector3.new(laneX, from.Y, frontZ + lane * 0.05),
				Vector3.new(laneX, up, frontZ + lane * 0.05),
				Vector3.new(laneX, up, tz),
				Vector3.new(to.X, up, tz),
				Vector3.new(to.X, up, to.Z + 0.25),
				Vector3.new(to.X, to.Y, to.Z + 0.25),
				to,
			}
		end
		local function toSide(from: Vector3, lane: number): { Vector3 }
			local laneX = rx - 2.15 - lane * 0.1
			local bottom = floor + 0.8
			return {
				from,
				Vector3.new(from.X, from.Y, frontZ),
				Vector3.new(laneX, from.Y, frontZ),
				Vector3.new(laneX, bottom, frontZ),
				Vector3.new(rx - 1.2, bottom, frontZ),
			}
		end
		if dev.kind == "router" then
			cableLine(dev, viaTray(portPos(1), rx + 2.15, dc.upstreamPort, 0), RED, "ether1 → OPERADORA (internet)", "← " .. deviceLabel(dev) .. " ether1", 0)
			cableLine(dev, toSide(portPos(2), 0), BLUE, "ether2 → OLT uplink", nil, 0)
		else
			cableLine(dev, toSide(portPos(8), 1), BLUE, "uplink → roteador ether2", nil, 0)
			for pon = 0, 1 do
				local target = dc.dioPort + Vector3.new(pon * 0.4, 0, 0)
				local cto = if pon == 0 then "CTO A" else "CTO B"
				cableLine(dev, viaTray(portPos(pon + 1), rx - 2.35 - pon * 0.12, target, pon + 1), YELLOW, "PON 0/1/" .. pon .. " → DIO P" .. (pon + 1) .. " → " .. cto, "DIO P" .. (pon + 1) .. " ← PON 0/1/" .. pon .. " (" .. cto .. ")", 0.4 + pon * 0.4)
			end
		end
	end

	-- Menu de ações: cada equipamento tem UM prompt ("Opções", tecla E). Ele abre
	-- um painel na tela com o estado do equipamento e as ações com suas teclas.
	local MENU_RANGE = 12
	local menuViewers = {} -- [player] = dev com o menu aberto
	local menuData: (dev: any) -> any -- definida mais abaixo, depois de deviceState

	local function refreshPrompts(dev: any)
		dev.prompts.menu.ObjectText = deviceLabel(dev)
		for player, d in menuViewers do
			if d == dev and player.Parent then
				Remotes.RackMenu:FireClient(player, menuData(dev))
			end
		end
	end

	local function buildDevice(dev: any)
		local model = Instance.new("Model")
		model.Name = dev.kind .. "_" .. dev.id
		model.Parent = runtime
		dev.model = model
		local cf = slotCFrame(dev.slot)
		local isOlt = dev.kind == "olt"
		-- frente do rack aponta para +Z. As portas onde chegam os cabos ficam sempre na
		-- linha de baixo (y = -0.25), em x = 0.35 + (i - 1) * passo (ver drawCables).
		local body = World.part({ Name = "Body", Size = Vector3.new(3.5, 1.4, 0.6), CFrame = cf, Color = if isOlt then Color3.fromRGB(214, 216, 220) else Color3.fromRGB(42, 44, 50), Material = Enum.Material.Metal, Parent = model })
		local function P(name: string, size: Vector3, x: number, y: number, z: number, color: Color3, props: { [string]: any }?): BasePart
			local t: { [string]: any } = { Name = name, Size = size, CFrame = cf * CFrame.new(x, y, z), Color = color, CastShadow = false, Parent = model }
			if props then
				for k, v in props do
					t[k] = v
				end
			end
			return World.part(t)
		end
		local function label(part: BasePart, text: string, color: Color3, font: Enum.Font?, align: Enum.TextXAlignment?)
			local g = Instance.new("SurfaceGui")
			g.Face = Enum.NormalId.Back
			g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			g.PixelsPerStud = 80
			g.LightInfluence = 0.2
			g.Parent = part
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Size = UDim2.fromScale(1, 1)
			t.Font = font or Enum.Font.GothamBold
			t.TextScaled = true
			t.TextXAlignment = align or Enum.TextXAlignment.Left
			t.TextColor3 = color
			t.Text = text
			t.Parent = g
		end
		local metal = if isOlt then Color3.fromRGB(214, 216, 220) else Color3.fromRGB(42, 44, 50)
		local screw = Color3.fromRGB(175, 178, 184)
		-- orelhas de fixação no rack, com parafusos
		for _, sx in { -1, 1 } do
			P("Orelha", Vector3.new(0.22, 1.4, 0.06), sx * 1.86, 0, 0.27, metal, { Material = Enum.Material.Metal })
			for _, sy in { -0.45, 0.45 } do
				P("Parafuso", Vector3.new(0.04, 0.1, 0.1), sx * 1.86, sy, 0.31, screw, { Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal, CFrame = cf * CFrame.new(sx * 1.86, sy, 0.31) * CFrame.Angles(0, math.rad(90), 0) })
			end
		end
		local ledPwr, ledSt
		local ports = {}
		local function led(x: number, y: number): BasePart
			return P("Led", Vector3.new(0.07, 0.05, 0.03), x, y, 0.335, Color3.fromRGB(30, 30, 30), { Material = Enum.Material.Neon })
		end

		if not isOlt then
			-- ===== MikroTik CCR: painel preto, 16 portas RJ45 + 2 SFP+ =====
			P("Painel", Vector3.new(3.48, 1.3, 0.04), 0, 0, 0.31, Color3.fromRGB(26, 27, 31), { Material = Enum.Material.Metal })
			local brandPlate = P("Marca", Vector3.new(1.3, 0.34, 0.01), -1.0, 0.4, 0.332, Color3.fromRGB(26, 27, 31))
			label(brandPlate, RouterCli.Brand:upper(), Color3.fromRGB(240, 240, 245), Enum.Font.GothamBlack)
			local modelPlate = P("Modelo", Vector3.new(1.3, 0.2, 0.01), -1.0, 0.13, 0.332, Color3.fromRGB(26, 27, 31))
			label(modelPlate, RouterCli.Model .. " · RouterOS", Color3.fromRGB(150, 155, 165), Enum.Font.Gotham)
			-- grade de ventilação
			for i = 0, 5 do
				P("Grade", Vector3.new(1.2, 0.035, 0.02), -1.0, -0.12 - i * 0.075, 0.334, Color3.fromRGB(10, 10, 12))
			end
			ledPwr = led(-0.25, 0.45)
			ledSt = led(-0.25, 0.3)
			local pwrTxt = P("TxtLed", Vector3.new(0.3, 0.1, 0.01), -0.25, 0.18, 0.332, Color3.fromRGB(26, 27, 31))
			label(pwrTxt, "PWR  USR", Color3.fromRGB(150, 155, 165), Enum.Font.Code, Enum.TextXAlignment.Center)
			-- duas fileiras de RJ45 (a de baixo recebe os cabos: ether1 a ether4)
			for row = 0, 1 do
				local y = if row == 0 then -0.25 else 0.18
				for i = 1, 4 do
					local x = 0.35 + (i - 1) * 0.3
					P("RJ45", Vector3.new(0.22, 0.18, 0.04), x, y, 0.33, Color3.fromRGB(12, 12, 14))
					P("RJ45Contato", Vector3.new(0.14, 0.04, 0.01), x, y + 0.04, 0.352, Color3.fromRGB(200, 170, 80), { Material = Enum.Material.Metal })
					local l = led(x - 0.07, y + 0.12)
					if row == 0 then
						table.insert(ports, l)
					end
				end
			end
			-- SFP+ prateadas
			for _, y in { -0.25, 0.18 } do
				P("SFP", Vector3.new(0.3, 0.14, 0.04), 1.55, y, 0.33, Color3.fromRGB(185, 188, 194), { Material = Enum.Material.Metal })
				P("SFPBoca", Vector3.new(0.22, 0.08, 0.01), 1.55, y, 0.352, Color3.fromRGB(20, 20, 22))
			end
			local portsTxt = P("TxtPortas", Vector3.new(1.2, 0.08, 0.01), 0.8, 0.43, 0.332, Color3.fromRGB(26, 27, 31))
			label(portsTxt, "ETHER 1-8 · SFP+ 1-2", Color3.fromRGB(150, 155, 165), Enum.Font.Code)
		else
			-- ===== Huawei MA5800: chassi cinza, bandeja de ventoinhas e placas =====
			-- bandeja de ventoinhas à esquerda
			P("Ventoinhas", Vector3.new(0.62, 1.3, 0.04), -1.42, 0, 0.31, Color3.fromRGB(70, 72, 78), { Material = Enum.Material.Metal })
			for _, fy in { 0.3, -0.3 } do
				P("Ventoinha", Vector3.new(0.03, 0.48, 0.48), -1.42, fy, 0.33, Color3.fromRGB(30, 30, 34), { Shape = Enum.PartType.Cylinder, CFrame = cf * CFrame.new(-1.42, fy, 0.33) * CFrame.Angles(0, math.rad(90), 0) })
				P("Grade", Vector3.new(0.5, 0.03, 0.01), -1.42, fy, 0.35, Color3.fromRGB(120, 122, 128))
				P("Grade", Vector3.new(0.03, 0.5, 0.01), -1.42, fy, 0.35, Color3.fromRGB(120, 122, 128))
			end
			-- placas (de cima para baixo): controle, linha GPON, linha GPON (cabos), energia
			local boards = {
				{ y = 0.46, name = "MPLA", color = Color3.fromRGB(196, 198, 202) },
				{ y = 0.12, name = "GPHF", color = Color3.fromRGB(190, 192, 196) },
				{ y = -0.24, name = "GPHF", color = Color3.fromRGB(190, 192, 196) },
				{ y = -0.53, name = "PILA", color = Color3.fromRGB(176, 178, 182) },
			}
			for bi, bd in boards do
				local h = if bi == 4 then 0.2 else 0.3
				P("Placa", Vector3.new(2.6, h, 0.04), 0.32, bd.y, 0.31, bd.color, { Material = Enum.Material.Metal })
				-- alavancas de extração nas pontas
				for _, ex in { -0.92, 1.56 } do
					P("Alavanca", Vector3.new(0.08, h - 0.04, 0.05), ex, bd.y, 0.335, Color3.fromRGB(40, 40, 44))
				end
				local tag = P("TxtPlaca", Vector3.new(0.3, 0.1, 0.01), -0.7, bd.y + (if bi == 4 then 0 else 0.07), 0.332, bd.color)
				label(tag, bd.name, Color3.fromRGB(60, 62, 70), Enum.Font.Code)
			end
			-- placa de controle: LEDs de estado e a marca
			ledPwr = led(-0.7, 0.4)
			ledSt = led(-0.55, 0.4)
			local brandPlate = P("Marca", Vector3.new(0.9, 0.16, 0.01), 0.15, 0.46, 0.332, Color3.fromRGB(196, 198, 202))
			label(brandPlate, OltCli.Brand:upper(), Color3.fromRGB(200, 25, 35), Enum.Font.GothamBlack)
			local modelPlate = P("Modelo", Vector3.new(0.9, 0.12, 0.01), 1.05, 0.46, 0.332, Color3.fromRGB(196, 198, 202))
			label(modelPlate, OltCli.Model, Color3.fromRGB(70, 72, 80), Enum.Font.Gotham)
			-- 8 portas PON em cada placa GPHF; a de baixo recebe as fibras
			for bi = 2, 3 do
				local y = boards[bi].y
				for i = 1, 8 do
					local x = 0.35 + (i - 1) * 0.17
					P("PON", Vector3.new(0.12, 0.1, 0.04), x, y - 0.02, 0.33, Color3.fromRGB(175, 178, 184), { Material = Enum.Material.Metal })
					P("PONBoca", Vector3.new(0.08, 0.05, 0.01), x, y - 0.02, 0.352, Color3.fromRGB(20, 20, 22))
					local l = led(x, y + 0.09)
					if bi == 3 then
						table.insert(ports, l)
					end
				end
			end
			-- fonte: chave e tomada
			P("Chave", Vector3.new(0.12, 0.1, 0.05), 1.2, -0.53, 0.335, Color3.fromRGB(30, 30, 32))
		end
		dev.parts = { body = body, ledPwr = ledPwr, ledSt = ledSt, ports = ports, cables = {} }

		local menu = prompt(body, "Opções", deviceLabel(dev), Enum.KeyCode.E)
		-- só o prompt mais perto aparece, mesmo com vários equipamentos no rack
		menu.Exclusivity = Enum.ProximityPromptExclusivity.OneGlobally
		menu.MaxActivationDistance = 7
		dev.prompts = { menu = menu }
		menu.Triggered:Connect(function(player)
			menuViewers[player] = dev
			Remotes.RackMenu:FireClient(player, menuData(dev))
		end)
		refreshPrompts(dev)
		drawCables(dev)
	end

	local function doPower(player: Player, dev: any)
		dev.powered = not dev.powered
		if dev.powered then
			dev.bootUntil = os.clock() + BOOT[dev.kind]
			Remotes.notify(player, deviceLabel(dev) .. " ligando. Leva uns " .. BOOT[dev.kind] .. " segundos para subir.", "info")
		else
			Remotes.notify(player, deviceLabel(dev) .. " desligado.", "info")
		end
	end

	local function doCables(player: Player, dev: any)
		if not dev.cabled then
			for _, other in Rack.devices do
				if other ~= dev and other.kind == dev.kind and other.cabled then
					Remotes.notify(player, "Os cabos já estão no outro " .. (if dev.kind == "olt" then "OLT" else "roteador") .. " (" .. deviceLabel(other) .. "). Desconecte lá primeiro.", "error")
					return
				end
			end
		end
		dev.cabled = not dev.cabled
		drawCables(dev)
		if dev.cabled then
			local what = if dev.kind == "olt" then "uplink azul no roteador e fibras amarelas no DIO (CTO A e B)" else "vermelho da operadora na ether1 e azul da OLT na ether2"
			Remotes.notify(player, "Cabos conectados: " .. what .. ". Chegue perto para ler as etiquetas.", "success")
		else
			Remotes.notify(player, "Cabos de " .. deviceLabel(dev) .. " desconectados.", "info")
		end
	end

	function Rack.addDevice(kind: string, slot: number, production: boolean): any
		local dev = {
			id = nextId,
			kind = kind,
			slot = slot,
			powered = production,
			cabled = production,
			failed = false,
			bootUntil = if production then os.clock() - 3600 * 3 else 0,
			cfg = if kind == "router" then (if production then RouterCli.productionConfig() else RouterCli.factoryConfig()) else OltCli.factoryConfig(),
		}
		nextId += 1
		table.insert(Rack.devices, dev)
		slots[slot].device = dev
		slots[slot].part:SetAttribute("Free", false)
		slots[slot].part.Transparency = 1
		buildDevice(dev)
		return dev
	end

	function Rack.removeDevice(dev: any)
		for i, d in Rack.devices do
			if d == dev then
				table.remove(Rack.devices, i)
				break
			end
		end
		local s = slots[dev.slot]
		s.device = nil
		s.part:SetAttribute("Free", true)
		s.part.Transparency = 0.8
		dev.model:Destroy()
		for _, perPlayer in sessions do
			perPlayer[dev.id] = nil
		end
	end

	-- ---------------------------------------------------------------------------
	-- Console
	-- ---------------------------------------------------------------------------

	local function sessionFor(player: Player, dev: any)
		sessions[player] = sessions[player] or {}
		local s = sessions[player][dev.id]
		if not s then
			s = { path = {}, mode = "user" }
			sessions[player][dev.id] = s
		end
		return s
	end

	local function routerIfaces(dev: any)
		local olt = nil
		for _, d in Rack.devices do
			if d.kind == "olt" and d.powered and d.cabled and not d.failed then
				olt = d
			end
		end
		-- ether1 só tem link depois que o provedor contrata a operadora
		return { ether1 = dev.cabled and game_.linkContracted == true, ether2 = dev.cabled and olt ~= nil, ether3 = false, ether4 = false }
	end

	local function ontState(port: number, sn: string)
		for _, h in net.houses do
			if h.sn == sn and h.slot == P.slot and h.contract == "active" and h.onuId and net.ponPortOf(h) == port then
				local dead = { los = true, onu = true, lowsignal = true, power = true, olt = true, unauth = true }
				if h.signal and not dead[h.reason] then
					return { run = "online", rx = h.signal }
				end
				return { run = "offline" }
			end
		end
		return { run = "offline" }
	end

	local function autofind(olt: any, port: number?)
		local list = {}
		for _, h in net.houses do
			if h.contract == "active" and h.onuId and h.sn then
				local p = net.ponPortOf(h)
				local node = net.graph.nodes[h.onuId]
				local dbm = net.graph:signalAt(h.onuId, P.slot)
				if (port == nil or port == p) and node and node.state == "ok" and dbm and dbm >= Config.SignalDownDbm and not OltCli.findOnt(olt.cfg, p, h.sn) then
					seenAt[h.sn] = seenAt[h.sn] or ("2026-11-0" .. game_.day .. " " .. game_.clockText() .. ":00")
					table.insert(list, { port = p, sn = h.sn, time = seenAt[h.sn] })
				end
			end
		end
		table.sort(list, function(a, b)
			return a.port < b.port
		end)
		return list
	end

	local function gameDate(): string
		return string.format("2026-11-%02d", math.clamp(game_.day, 1, 30))
	end

	-- tabela ARP e log do roteador, montados a partir do estado do rack
	local function routerExtras(dev: any): (any, any)
		local ifaces = routerIfaces(dev)
		local ev = RouterCli.evaluate(dev.cfg, ifaces, Rack.deadDns)
		local arp = {}
		if ev.wanOk then
			table.insert(arp, { ip = RouterCli.Upstream.gateway, mac = "00:1A:2B:3C:4D:01", iface = "ether1" })
		end
		if ev.lanOk then
			for _, d in Rack.devices do
				if d.kind == "olt" and isActive(d) then
					table.insert(arp, { ip = Rack.OltMgmtIp, mac = "00:E0:FC:12:34:56", iface = "ether2" })
				end
			end
			for i = 1, 4 do
				table.insert(arp, { ip = "10.100.0." .. (50 + i), mac = string.format("3C:52:82:1A:0B:%02X", 0x50 + i), iface = "ether2" })
			end
		end
		local t = gameDate() .. " "
		local log = {
			t .. "08:00:02 system,info router rebooted",
			t .. "08:00:04 interface,info ether1 link " .. (if ifaces.ether1 then "up (speed 1G, full duplex)" else "down"),
			t .. "08:00:04 interface,info ether2 link " .. (if ifaces.ether2 then "up (speed 1G, full duplex)" else "down"),
		}
		for _, problem in ev.problems do
			table.insert(log, t .. game_.clockText() .. ":00 system,warning " .. problem)
		end
		table.insert(log, t .. game_.clockText() .. ":00 system,info,account user admin logged in via local")
		return arp, log
	end

	local function runLine(dev: any, session: any, line: string): string
		if dev.kind == "router" then
			local arp, log = routerExtras(dev)
			return RouterCli.run(dev.cfg, session, line, {
				ifaces = routerIfaces(dev),
				deadDns = Rack.deadDns,
				uptime = uptime(dev),
				time = game_.clockText() .. ":00",
				date = gameDate(),
				dateTime = gameDate() .. " " .. game_.clockText() .. ":00",
				arp = arp,
				log = log,
				reboot = function()
					dev.bootUntil = os.clock() + BOOT.router
				end,
			})
		end
		return OltCli.run(dev.cfg, session, line, {
			autofind = function(port)
				return autofind(dev, port)
			end,
			ontState = ontState,
			uptime = uptime(dev),
		})
	end

	local function promptOf(dev: any, session: any): string
		if dev.kind == "router" then
			return RouterCli.prompt(dev.cfg, session)
		end
		return OltCli.prompt(dev.cfg, session)
	end

	function Rack.openConsole(player: Player, dev: any)
		if not dev.powered then
			Remotes.notify(player, "O equipamento está desligado.", "error")
			return
		end
		if dev.failed then
			Remotes.notify(player, "O console não responde e o LED está vermelho. Esse equipamento queimou: compre outro e substitua.", "error")
			return
		end
		local session = sessionFor(player, dev)
		local banner = if dev.kind == "router" then RouterCli.banner(dev.cfg) else OltCli.banner(dev.cfg)
		local title = (if dev.kind == "router" then "Console · " .. RouterCli.Model else "Console · " .. OltCli.Model) .. " · slot " .. dev.slot
		Remotes.ConsoleOpen:FireClient(player, { id = dev.id, title = title, banner = banner, prompt = promptOf(dev, session) })
	end

	function Rack.openManual(player: Player, kind: string)
		local doc = if kind == "router" then Docs.Router elseif kind == "olt" then Docs.Olt else Docs.Pc
		local title = if kind == "router" then "Manual · MikroTik RouterOS" elseif kind == "olt" then "Manual · Huawei MA5800" else "Manual · PC do NOC"
		Remotes.ConsoleOpen:FireClient(player, { id = 0, title = title, banner = doc, prompt = "" })
	end

	-- ---------------------------------------------------------------------------
	-- Rede de gerência: os PCs do NOC acessam os equipamentos por SSH/Telnet
	-- ---------------------------------------------------------------------------

	Rack.OltMgmtIp = "10.100.0.2"

	local function stripPrefix(a: string): string
		return (string.match(a, "^([^/]+)") or a)
	end

	-- IP de gerência de um equipamento, ou nil se ele não tem IP na rede interna.
	local function mgmtIpOf(dev: any): string?
		if dev.kind == "router" then
			for _, a in dev.cfg.addresses do
				if a.interface == "ether2" then
					return stripPrefix(a.address)
				end
			end
			return nil
		end
		return Rack.OltMgmtIp
	end

	-- Responde na rede de gerência: ligado, cabeado, inicializado e com IP.
	local function reachableAt(ip: string): any
		for _, d in Rack.devices do
			if isActive(d) and mgmtIpOf(d) == ip then
				return d
			end
		end
		return nil
	end

	local function hostsText(): string
		local out = { "  IP              EQUIPAMENTO                                ACESSO", "  --------------  -----------------------------------------  ------------------" }
		local listed = {}
		for _, d in Rack.devices do
			local ip = mgmtIpOf(d)
			if ip and not listed[ip] then
				listed[ip] = true
				local name = if d.kind == "router" then "MikroTik " .. RouterCli.Model else "Huawei " .. OltCli.Model
				local how = if d.kind == "router" then "ssh admin@" .. ip else "telnet " .. ip
				local state = if isActive(d) then "" else "  (sem resposta)"
				table.insert(out, string.format("  %-15s %-42s %s%s", ip, deviceLabel(d) .. " · " .. name, how, state))
			end
		end
		if #out == 2 then
			table.insert(out, "  nenhum equipamento com IP na rede interna")
		end
		return table.concat(out, "\n")
	end

	-- /etc/hosts dos PCs (fixo, como num computador de verdade)
	local HOSTS = {
		{ ip = "10.100.0.1", names = { "borda-vila", "roteador" }, info = "MikroTik " .. RouterCli.Model .. " (ssh)", mac = "48:a9:8a:3c:1e:02" },
		{ ip = "10.100.0.2", names = { "olt-vila", "olt" }, info = "Huawei " .. OltCli.Model .. " (telnet)", mac = "00:e0:fc:12:34:56" },
	}

	-- o que um PC da rede de gerência enxerga da internet (passa pelo roteador 10.100.0.1)
	local function netState(): any
		local router = nil
		for _, d in Rack.devices do
			if d.kind == "router" and isActive(d) then
				router = d
			end
		end
		if not router then
			return { gw = false, routeOk = false, natOk = false, dnsOk = false, deadDns = Rack.deadDns }
		end
		local ev = RouterCli.evaluate(router.cfg, routerIfaces(router), Rack.deadDns)
		local gw = ev.lanOk and mgmtIpOf(router) == "10.100.0.1"
		return { gw = gw, routeOk = ev.routeOk, natOk = ev.natOk, dnsOk = gw and ev.dnsOk, deadDns = Rack.deadDns }
	end

	local WEEKDAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }

	local function pcEnv(idx: number): any
		local isNb = idx == NB
		local day = math.clamp(game_.day, 1, 30)
		local clock = game_.clockText() .. ":00"
		return {
			isNotebook = isNb,
			idx = idx,
			user = if isNb then "ti" else "noc",
			host = if isNb then "notebook-ti" else "noc-pc" .. idx,
			iface = if isNb then "wlp2s0" else "enp3s0",
			myIp = if isNb then "10.100.0.100" else "10.100.0." .. (50 + idx),
			hosts = HOSTS,
			ficha = fichaText(),
			man = { routeros = Docs.Router, ma5800 = Docs.Olt },
			time = clock,
			dateLong = string.format("%s Nov %2d %s -03 2026", WEEKDAYS[(day % 7) + 1], day, clock),
			deviceAt = function(ip: string): string?
				local d = reachableAt(ip)
				return d and d.kind
			end,
			isPc = function(ip: string): boolean
				local last = tonumber(string.match(ip, "^10%.100%.0%.(%d+)$") or "")
				return last ~= nil and ((last >= 51 and last <= 54) or last == 100)
			end,
			net = netState,
		}
	end

	local function shellOf(st: any, idx: number): any
		if not st.shell then
			st.shell = Shell.newSession(pcEnv(idx))
		end
		return st.shell
	end

	local function pcPrompt(idx: number, st: any?): string
		local env = pcEnv(idx)
		return Shell.prompt(if st then shellOf(st, idx) else Shell.newSession(env), env)
	end

	local function hasNotebook(player: Player): boolean
		local name = Config.ToolNames.Notebook
		local char = player.Character
		local bp = player:FindFirstChildOfClass("Backpack")
		return (char ~= nil and char:FindFirstChild(name) ~= nil) or (bp ~= nil and bp:FindFirstChild(name) ~= nil)
	end

	local function rootOf(player: Player): BasePart?
		local char = player.Character
		return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	end

	-- Equipamento mais perto do jogador, ao alcance do cabo de console.
	local function nearestDevice(player: Player): any
		local root = rootOf(player)
		if not root then
			return nil
		end
		local best, bestD = nil, SERIAL_RANGE
		for _, d in Rack.devices do
			local dist = (d.parts.body.Position - root.Position).Magnitude
			if dist <= bestD then
				best, bestD = d, dist
			end
		end
		return best
	end

	function Rack.openNotebook(player: Player)
		pcSessions[player] = pcSessions[player] or {}
		local st = { remote = nil, session = nil, serial = false }
		pcSessions[player][NB] = st
		local banner = Shell.banner(pcEnv(NB)) .. "Wi-Fi da gerência conectado (10.100.0.0/22). Cabo USB-serial em /dev/ttyUSB0.\n"
		Remotes.ConsoleOpen:FireClient(player, { id = -NB, title = "Notebook TI · Ubuntu", banner = banner, prompt = pcPrompt(NB, st) })
	end

	function Rack.openPc(player: Player, idx: number)
		pcSessions[player] = pcSessions[player] or {}
		local st = { remote = nil, session = nil }
		pcSessions[player][idx] = st
		local banner = Shell.banner(pcEnv(idx))
		Remotes.ConsoleOpen:FireClient(player, { id = -idx, title = "PC do NOC · estação " .. idx .. " · Ubuntu", banner = banner, prompt = pcPrompt(idx, st) })
	end

	-- liga o PC/notebook num equipamento (ssh, telnet ou cabo de console)
	local function connectTo(player: Player, idx: number, st: any, conn: any, prefix: string): any
		if conn.kind == "serial" then
			local dev = nearestDevice(player)
			if not dev then
				return { output = prefix .. "\n[screen is terminating]\n(nada responde no cabo: chegue a até 3 m de um equipamento do rack 02, no datacenter)", prompt = pcPrompt(idx, st) }
			end
			local label = deviceLabel(dev)
			if not dev.powered then
				return { output = "\n[screen is terminating]\n(" .. label .. " está desligado: ligue a energia (R) e espere inicializar)", prompt = pcPrompt(idx, st) }
			end
			if dev.failed then
				return { output = "\n[screen is terminating]\n(sem resposta e LED vermelho: " .. label .. " queimou, compre outro e substitua)", prompt = pcPrompt(idx, st) }
			end
			if os.clock() < dev.bootUntil then
				return { output = string.format("\n[screen is terminating]\n(%s ainda está inicializando: %ds)", label, math.ceil(dev.bootUntil - os.clock())), prompt = pcPrompt(idx, st) }
			end
			st.remote = dev
			st.serial = true
			st.session = { path = {}, mode = "user" }
			local banner = if dev.kind == "router" then RouterCli.banner(dev.cfg) else OltCli.banner(dev.cfg)
			local hello = string.format("(cabo de console em %s, slot %d · 115200 8N1)\n", label, dev.slot)
			if dev.kind == "router" then
				hello ..= dev.cfg.identity .. " Login: admin\nPassword: \n"
			else
				hello ..= ">>User name:admin\n>>User password:\n"
			end
			return { output = hello .. banner, prompt = promptOf(dev, st.session) }
		end
		local dev = reachableAt(conn.ip)
		if not dev then
			return { output = prefix .. "Connection closed by " .. conn.ip, prompt = pcPrompt(idx, st) }
		end
		st.remote = dev
		st.serial = false
		st.session = { path = {}, mode = "user" }
		local banner = if dev.kind == "router" then RouterCli.banner(dev.cfg) else OltCli.banner(dev.cfg)
		return { output = prefix .. banner, prompt = promptOf(dev, st.session) }
	end

	local function onPcCommand(player: Player, idx: number, line: string)
		local isNb = idx == NB
		local pc = pcs[idx]
		local st = pcSessions[player] and pcSessions[player][idx]
		if (not isNb and not pc) or not st then
			return { output = "% Sessão encerrada.", prompt = "", closed = true }
		end
		local root = rootOf(player)
		if isNb then
			if not root or not hasNotebook(player) then
				return { output = "% O notebook foi guardado.", prompt = "", closed = true }
			end
		elseif not root or (root.Position - pc.Position).Magnitude > 14 then
			return { output = "% Você saiu da mesa.", prompt = "", closed = true }
		end
		line = string.gsub(line, "^%s+", "")
		line = string.gsub(line, "%s+$", "")

		-- sessão remota aberta num equipamento
		local dev = st.remote
		if dev then
			local function back(msg: string)
				local serial = st.serial
				st.remote = nil
				st.session = nil
				st.serial = false
				if serial then
					return { output = msg .. "\n[screen is terminating]", prompt = pcPrompt(idx, st) }
				end
				return { output = msg .. "\nConnection to " .. (mgmtIpOf(dev) or "?") .. " closed.", prompt = pcPrompt(idx, st) }
			end
			if st.serial then
				-- cabo de console: não depende de IP nem de cabo de rede, só de energia
				if not table.find(Rack.devices, dev) or not dev.powered or dev.failed then
					return back("% Sem resposta na porta console")
				end
				if (dev.parts.body.Position - root.Position).Magnitude > SERIAL_RANGE + 4 then
					return back("% O cabo de console soltou: você se afastou do equipamento")
				end
				if os.clock() < dev.bootUntil then
					return { output = string.format("Inicializando... (%ds)", math.ceil(dev.bootUntil - os.clock())), prompt = "" }
				end
			elseif not table.find(Rack.devices, dev) or not isActive(dev) then
				return back("Connection reset by peer")
			end
			if dev.kind == "router" and line == "exit" then
				return back("interrupted")
			end
			if dev.kind == "olt" and st.session.mode == "user" and (line == "quit" or line == "exit") then
				return back("  Check whether system data has been changed. Please save data before logout.\n  Configuration console exit, please retry to log on")
			end
			local ok, out = pcall(runLine, dev, st.session, line)
			if not ok then
				warn("[PC] " .. tostring(out))
				out = "% Erro interno do console"
			end
			refreshPrompts(dev)
			if dev.kind == "router" and out == "interrupted" then
				return back(out)
			end
			if not st.serial and not isActive(dev) then
				-- /system reboot pela sessão remota derruba a conexão
				return back(out)
			end
			return { output = out, prompt = promptOf(dev, st.session) }
		end

		-- bash do Ubuntu
		local env = pcEnv(idx)
		local sh = shellOf(st, idx)
		local ok, res = pcall(Shell.run, sh, env, line)
		if not ok then
			warn("[Shell] " .. tostring(res))
			return { output = "bash: erro interno", prompt = Shell.prompt(sh, env) }
		end
		if res.closed then
			return { output = res.output, prompt = "", closed = true }
		end
		if res.connect then
			return connectTo(player, idx, st, res.connect, res.output)
		end
		return { output = res.output, prompt = Shell.prompt(sh, env) }
	end

	local function onRackCommand(player: Player, deviceId: any, line: string)
		local dev = nil
		for _, d in Rack.devices do
			if d.id == deviceId then
				dev = d
			end
		end
		if not dev then
			return { output = "% Conexão perdida: o equipamento não está mais no rack.", prompt = "", closed = true }
		end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or (root.Position - dev.parts.body.Position).Magnitude > 14 then
			return { output = "% Conexão perdida: você se afastou do rack (o cabo de console é curto).", prompt = "", closed = true }
		end
		if not dev.powered or dev.failed then
			return { output = "% Sem resposta do equipamento.", prompt = "", closed = true }
		end
		if os.clock() < dev.bootUntil then
			local left = math.ceil(dev.bootUntil - os.clock())
			return { output = string.format("Inicializando... (%ds)", left), prompt = "" }
		end
		local session = sessionFor(player, dev)
		local ok, out = pcall(runLine, dev, session, line)
		if not ok then
			warn("[Console] " .. tostring(out))
			out = "% Erro interno do console"
		end
		-- o nome (sysname/identity) pode ter mudado pelo comando
		refreshPrompts(dev)
		if dev.kind == "router" and out == "interrupted" then
			session.path = {}
			return { output = out, prompt = "", closed = true }
		end
		if dev.kind == "olt" and session.mode == "user" and string.find(out, "Configuration console exit", 1, true) then
			return { output = out, prompt = "", closed = true }
		end
		return { output = out, prompt = promptOf(dev, session) }
	end

	-- TAB: completa a linha ou devolve a lista de opções
	local function completeFor(dev: any, session: any, line: string): any
		if dev.kind == "router" then
			return RouterCli.complete(dev.cfg, session, line)
		end
		return OltCli.complete(dev.cfg, session, line)
	end

	local function onComplete(player: Player, deviceId: any, line: any)
		if typeof(line) ~= "string" or #line > 300 or typeof(deviceId) ~= "number" then
			return {}
		end
		line = string.gsub(line, "[\r\n\t]", "")
		local ok, res = pcall(function()
			if deviceId < 0 then
				local idx = -deviceId
				local st = pcSessions[player] and pcSessions[player][idx]
				if not st then
					return {}
				end
				if st.remote then
					if os.clock() < st.remote.bootUntil then
						return {}
					end
					return completeFor(st.remote, st.session, line)
				end
				return Shell.complete(shellOf(st, idx), pcEnv(idx), line)
			end
			for _, d in Rack.devices do
				if d.id == deviceId and d.powered and not d.failed and os.clock() >= d.bootUntil then
					return completeFor(d, sessionFor(player, d), line)
				end
			end
			return {}
		end)
		if not ok then
			warn("[TAB] " .. tostring(res))
			return {}
		end
		return res
	end

	local function onCommand(player: Player, deviceId: any, line: any)
		if typeof(line) ~= "string" or #line > 300 or typeof(deviceId) ~= "number" then
			return { output = "", prompt = "" }
		end
		if deviceId < 0 then
			return onPcCommand(player, -deviceId, line)
		end
		return onRackCommand(player, deviceId, line)
	end

	-- ---------------------------------------------------------------------------
	-- Loja e caixas
	-- ---------------------------------------------------------------------------

	local function makeBoxTool(item: any): Tool
		local tool = Instance.new("Tool")
		tool.Name = "Caixa: " .. (if item.kind == "olt" then "OLT" else "Roteador")
		tool.ToolTip = item.name
		tool.CanBeDropped = false
		tool:SetAttribute("EquipmentKind", item.kind)
		tool.GripPos = Vector3.new(0, 0, 1)
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(2.4, 1.2, 1.6)
		handle.Color = Color3.fromRGB(180, 140, 90)
		handle.Material = Enum.Material.Cardboard
		handle.CanCollide = false
		handle.Massless = true
		handle.Parent = tool
		return tool
	end

	local function spawnBox(item: any)
		local offset = Vector3.new(math.random(-20, 20) / 10, 0, math.random(-20, 20) / 10)
		local box = World.part({ Name = "CaixaEquipamento", Size = Vector3.new(2.4, 1.2, 1.6), CFrame = CFrame.new(boxSpot + offset + Vector3.new(0, 0.6, 0)), Color = Color3.fromRGB(180, 140, 90), Material = Enum.Material.Cardboard, Parent = runtime })
		World.textOn(box, Enum.NormalId.Top, if item.kind == "olt" then "OLT" else "ROTEADOR", Color3.fromRGB(60, 40, 20))
		local p = prompt(box, "Pegar caixa", item.name, Enum.KeyCode.E, 0.5)
		p.Triggered:Connect(function(player)
			if not own(player) then
				return
			end
			local backpack = player:FindFirstChildOfClass("Backpack")
			if not backpack then
				return
			end
			makeBoxTool(item).Parent = backpack
			box:Destroy()
			Remotes.notify(player, "Caixa na mochila. Equipe ela e leve até um slot vazio do rack.", "info")
		end)
	end

	-- Antes do primeiro contrato, o item de link é a contratação (taxa de ativação).
	local function linkOffer(): (string, number, string)
		return string.format("Contratar link da operadora (%d Mbps)", Config.StartUpstreamMbps),
			Config.Link.InstallFee,
			string.format("Ativa o cabo vermelho da ether1. Taxa de ativação única + R$ %d por dia (R$ %d por Mbps).", Config.StartUpstreamMbps * Config.UpstreamCostPerMbpsDay, Config.UpstreamCostPerMbpsDay)
	end

	-- Tudo o que a tela da loja mostra: catálogo, o que já é do provedor, estoque e crédito.
	local function shopPayload()
		local items = {}
		for _, it in Rack.Catalog do
			local name, price, info = it.name, it.price, it.info
			if it.kind == "link" and not game_.linkContracted then
				name, price, info = linkOffer()
			end
			table.insert(items, {
				id = it.id,
				kind = it.kind,
				name = name,
				price = price,
				info = info,
				owned = it.tool ~= nil and game_.owned[it.tool] == true,
				stock = if it.supply then game_.stock[it.supply] else nil,
			})
		end
		return { items = items, money = math.floor(game_.money), loan = game_.loanStatus(), tech = if techService then techService.status() else nil }
	end

	local function onBuy(player: Player, itemId: any)
		local root = rootOf(player)
		if not root or (root.Position - shopTerminal.Position).Magnitude > 16 then
			return
		end
		-- equipe e carro: "tech_hire", "tech_fire:<id>", "car_buy", "car_recall"
		if techService and typeof(itemId) == "string" and (string.sub(itemId, 1, 5) == "tech_" or string.sub(itemId, 1, 4) == "car_") then
			if itemId == "tech_hire" then
				techService.hire(player)
			elseif string.sub(itemId, 1, 10) == "tech_fire:" then
				techService.fire(player, tonumber(string.sub(itemId, 11)))
			elseif itemId == "car_buy" then
				techService.Car.buy(player)
			elseif itemId == "car_recall" then
				techService.Car.recall(player)
			end
			Remotes.ShopOpen:FireClient(player, shopPayload())
			return
		end
		if itemId == "loan" then
			game_.requestLoan(player)
			Remotes.ShopOpen:FireClient(player, shopPayload())
			return
		end
		for _, item in Rack.Catalog do
			if item.id == itemId then
				if item.tool and game_.owned[item.tool] then
					Remotes.notify(player, "O provedor já tem " .. item.name .. ". Pegue na prateleira do almoxarifado.", "info")
					return
				end
				if item.kind == "link" and not game_.linkContracted then
					local name, price = linkOffer()
					if not game_.spend(price, name, player) then
						return
					end
					game_.linkContracted = true
					game_.publish()
					net.slot(P.slot).upstreamMbps = Config.StartUpstreamMbps
					net.addAlarm(P.slot, "Upstream", string.format("Link da operadora ativado: %d Mbps na ether1", net.slot(P.slot).upstreamMbps), "ok")
					game_.notify(nil, "Link contratado! O cabo vermelho da operadora já tem sinal. Agora configure o roteador (veja a ficha do link no datacenter).", "success")
					Remotes.ShopOpen:FireClient(player, shopPayload())
					return
				end
				if not game_.spend(item.price, item.name, player) then
					return
				end
				if item.kind == "link" then
					net.slot(P.slot).upstreamMbps += Config.UpstreamUpgradeMbps
					net.addAlarm(P.slot, "Upstream", "Link ampliado para " .. net.slot(P.slot).upstreamMbps .. " Mbps", "ok")
				elseif item.kind == "tool" then
					net.grantTool(P, item.tool)
					game_.notify(nil, item.name .. " comprado. Já está no inventário de toda a equipe.", "success")
				elseif item.kind == "supply" then
					game_.addStock(item.supply, item.units)
					Remotes.notify(player, string.format("Estoque: +%d %s (agora %d).", item.units, Config.Supplies[item.supply].name, game_.stock[item.supply]), "success")
				else
					spawnBox(item)
					Remotes.notify(player, "Pedido entregue: a caixa está no chão do almoxarifado. Leve até um slot vazio do rack 02, no datacenter (2º andar).", "success")
				end
				Remotes.ShopOpen:FireClient(player, shopPayload())
				return
			end
		end
	end

	local function buildShopAndSlots()
		local f1 = isp.floorY
		-- terminal de compras no almoxarifado
		World.part({ Name = "ShopDesk", Size = Vector3.new(4, 3, 2), CFrame = CFrame.new(Vector3.new(-106, f1 + 1.5, -50) + isp.offset), Color = Color3.fromRGB(90, 95, 105), Material = Enum.Material.Metal, Parent = runtime })
		shopTerminal = World.part({ Name = "ShopTerminal", Size = Vector3.new(2.4, 1.6, 0.2), CFrame = CFrame.lookAt(Vector3.new(-106, f1 + 4, -50.5) + isp.offset, Vector3.new(-106, f1 + 4, -40) + isp.offset), Color = Color3.fromRGB(15, 18, 25), Parent = runtime })
		World.textOn(shopTerminal, Enum.NormalId.Front, "COMPRAS", Color3.fromRGB(80, 190, 255))
		local p = prompt(shopTerminal, "Abrir terminal", "Compras e financeiro", Enum.KeyCode.E)
		p.Triggered:Connect(function(player)
			if own(player) then
				Remotes.ShopOpen:FireClient(player, shopPayload())
			end
		end)
		boxSpot = Vector3.new(-101, f1, -47) + isp.offset

		-- ficha do link na parede ao lado do rack
		local ficha = World.part({ Name = "FichaDoLink", Size = Vector3.new(2.4, 3, 0.1), CFrame = isp.dc.fichaCFrame, Color = Color3.fromRGB(255, 250, 220), Parent = runtime })
		World.textOn(ficha, Enum.NormalId.Front, "FICHA DO LINK\n(aperte E)", Color3.fromRGB(40, 40, 40))
		local fp = prompt(ficha, "Ler ficha", "Ficha do link", Enum.KeyCode.E)
		fp.Triggered:Connect(function(player)
			Remotes.ConsoleOpen:FireClient(player, { id = 0, title = "Ficha do link (colada na parede)", banner = fichaText(), prompt = "" })
		end)

		-- slots do rack principal
		for i = 1, SLOT_COUNT do
			local part = World.part({ Name = "Slot" .. i, Size = Vector3.new(3.6, 1.4, 0.1), CFrame = slotCFrame(i), Color = Color3.fromRGB(90, 200, 255), Material = Enum.Material.Neon, Transparency = 0.8, CanCollide = false, CastShadow = false, Parent = runtime })
			-- o cliente só mostra este prompt para quem está segurando uma caixa
			-- (ver RackMenu no Console.client) e só se o slot estiver livre
			part:SetAttribute("Free", true)
			CollectionService:AddTag(part, "RackSlot")
			local sp = prompt(part, "Instalar equipamento", "Slot " .. i .. " vazio", Enum.KeyCode.Q, 2)
			sp.Exclusivity = Enum.ProximityPromptExclusivity.OneGlobally
			slots[i] = { part = part, prompt = sp, device = nil }
			sp.Triggered:Connect(function(player)
				if slots[i].device or not own(player) then
					return
				end
				local char = player.Character
				local tool = char and char:FindFirstChildOfClass("Tool")
				local kind = tool and tool:GetAttribute("EquipmentKind")
				if not kind then
					Remotes.notify(player, "Equipe a caixa do equipamento (compre no terminal de compras do almoxarifado, no térreo).", "error")
					return
				end
				tool:Destroy()
				Rack.addDevice(kind, i, false)
				Remotes.notify(player, "Instalado no slot " .. i .. ". Agora aperte E em Opções: ligar energia (R), conectar cabos (F) e configurar pelo console (E).", "success")
			end)
		end
	end

	-- ---------------------------------------------------------------------------
	-- A rede depende do rack
	-- ---------------------------------------------------------------------------

	local function ledColor(dev: any, configured: boolean): (Color3, Color3)
		local off = Color3.fromRGB(30, 30, 30)
		if not dev.powered then
			return off, off
		end
		local pwr = Color3.fromRGB(60, 220, 90)
		if dev.failed then
			return Color3.fromRGB(230, 50, 40), Color3.fromRGB(230, 50, 40)
		end
		if os.clock() < dev.bootUntil then
			return pwr, if math.floor(os.clock() * 2) % 2 == 0 then Color3.fromRGB(255, 150, 30) else off
		end
		if not dev.cabled or not configured then
			return pwr, Color3.fromRGB(255, 150, 30)
		end
		return pwr, Color3.fromRGB(60, 220, 90)
	end

	function Rack.apply()
		-- dia novo: o DNS do upstream volta
		if game_.day ~= lastDay then
			lastDay = game_.day
			Rack.deadDns = {}
		end

		local graph = net.graph
		local router = activeOf("router")
		local olt = activeOf("olt")
		local ev = nil
		if router then
			ev = RouterCli.evaluate(router.cfg, routerIfaces(router), Rack.deadDns)
		end
		local routed = ev ~= nil and ev.routeOk and ev.lanOk and ev.natOk
		graph.nodes[net.coreId(P.slot, "router")].state = if routed then "ok" else "failed"
		graph.nodes[net.coreId(P.slot, "dns")].state = if ev and ev.dnsOk then "ok" else "failed"
		graph.nodes[net.coreId(P.slot, "olt")].state = if olt then "ok" else "failed"
		graph.nodes[net.coreId(P.slot, "upstream")].state = if game_.linkContracted then "ok" else "failed"

		-- alarme quando a configuração do roteador muda de situação
		local problem = ""
		if not router then
			problem = "nenhum roteador ativo no rack"
		elseif not game_.linkContracted then
			problem = "link da operadora não contratado (terminal de compras)"
		elseif ev and #ev.problems > 0 then
			problem = ev.problems[1]
		end
		if problem ~= lastRouterProblem then
			if problem ~= "" then
				net.addAlarm(P.slot, "Roteador", problem, "critical")
			elseif lastRouterProblem ~= "" then
				net.addAlarm(P.slot, "Roteador", "Configuração ok, tráfego normal", "ok")
			end
			lastRouterProblem = problem
		end

		-- autorização das ONUs na OLT
		for _, h in net.houses do
			if h.onuId and h.slot == P.slot and graph.nodes[h.onuId] then
				local node = graph.nodes[h.onuId]
				if olt then
					local port = net.ponPortOf(h)
					local id = OltCli.findOnt(olt.cfg, port, h.sn)
					node.authorized = id ~= nil
					node.service = id ~= nil and OltCli.hasService(olt.cfg, port, id)
				else
					node.authorized = nil
					node.service = nil
				end
			end
		end

		-- LEDs
		for _, dev in Rack.devices do
			local configured = true
			if dev.kind == "router" then
				local e = RouterCli.evaluate(dev.cfg, routerIfaces(dev), Rack.deadDns)
				configured = e.routeOk and e.lanOk and e.natOk
			end
			local p, s = ledColor(dev, configured)
			dev.parts.ledPwr.Color = p
			dev.parts.ledSt.Color = s
			for i, port in dev.parts.ports do
				local lit = dev.powered and dev.cabled and not dev.failed and i <= (if dev.kind == "olt" then 2 else 2)
				port.Color = if lit and math.random() < 0.8 then Color3.fromRGB(60, 220, 90) else Color3.fromRGB(20, 20, 22)
				port.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
			end
		end
	end

	-- ---------------------------------------------------------------------------
	-- Topologia para o telão do NOC
	-- ---------------------------------------------------------------------------

	local function deviceState(dev: any, configured: boolean): string
		if dev.failed then
			return "fail"
		elseif not dev.powered then
			return "off"
		elseif not dev.cabled then
			return "nocable"
		elseif os.clock() < dev.bootUntil then
			return "boot"
		elseif not configured then
			return "config"
		end
		return "ok"
	end

	-- Equipamento que está fazendo o papel (o cabeado, se houver; senão qualquer um).
	local function mainOf(kind: string): any
		local any_ = nil
		for _, d in Rack.devices do
			if d.kind == kind then
				if d.cabled then
					return d
				end
				any_ = any_ or d
			end
		end
		return any_
	end

	local function edgeStateOf(nodeId: string): string
		local n = net.graph.nodes[nodeId]
		local pe = n and NetworkGraph.parentEdgeOf(n, P.slot)
		if not pe then
			return "none"
		end
		local e = net.graph.edges[pe]
		return if e then e.state else "none"
	end

	function Rack.topology()
		local graph = net.graph
		local router = mainOf("router")
		local olt = mainOf("olt")
		local ev = nil
		local r = nil
		if router then
			ev = RouterCli.evaluate(router.cfg, routerIfaces(router), Rack.deadDns)
			local configured = ev.routeOk and ev.lanOk and ev.natOk
			r = {
				label = deviceLabel(router),
				model = RouterCli.Model,
				ip = mgmtIpOf(router) or "sem IP",
				state = deviceState(router, configured),
				problem = if ev.problems[1] then ev.problems[1] else "",
			}
		end
		local o = nil
		if olt then
			local total, online = 0, 0
			for _, h in net.houses do
				if h.contract == "active" and h.slot == P.slot and h.onuId then
					total += 1
					if h.status ~= "offline" then
						online += 1
					end
				end
			end
			o = {
				label = deviceLabel(olt),
				model = OltCli.Model,
				ip = Rack.OltMgmtIp,
				state = deviceState(olt, true),
				onts = #olt.cfg.onts,
				online = online,
				total = total,
			}
		end
		local routerUp = router ~= nil and isActive(router)
		local ctos = {}
		local splitters = {}
		local splByCto = {}
		for _, splId in { "SPL", "SPL2" } do
			local sn = graph.nodes[splId]
			local entry = { id = splId, label = if sn then sn.label else splId, state = edgeStateOf(splId), ctos = {} }
			table.insert(splitters, entry)
			splByCto[splId] = entry
		end
		for _, id in net.CtoOrder do
			local node = graph.nodes[id]
			local houses = {}
			for index, h in net.houses do
				if h.house.cto == id then
					local rival = h.contract == "active" and h.slot ~= P.slot
					if rival then
						table.insert(houses, { index = index, status = "nocontract", contract = "rival", reason = "", sn = "" })
					else
						table.insert(houses, { index = index, status = h.status, signal = h.signal, contract = h.contract, reason = h.reason, sn = h.sn })
					end
				end
			end
			table.sort(houses, function(a, b)
				return a.index < b.index
			end)
			local cto = { id = id, label = node and node.label or id, port = net.PonPort[id], edge = edgeStateOf(id), houses = houses }
			table.insert(ctos, cto)
			local sp = splByCto[net.CtoSplitter[id]]
			if sp then
				table.insert(sp.ctos, cto)
			end
		end
		return {
			internet = routerUp and ev ~= nil and ev.wanOk and ev.routeOk,
			dns = routerUp and ev ~= nil and ev.dnsOk,
			uplink = net.slot(P.slot).upstreamMbps,
			router = r,
			olt = o,
			trunk = edgeStateOf("SPL"),
			splitter = graph.nodes.SPL and graph.nodes.SPL.label or "Splitter",
			ctos = ctos,
			splitters = splitters,
		}
	end

	local StateText = {
		ok = "Funcionando",
		boot = "Inicializando",
		config = "Ligado, falta configurar",
		nocable = "Ligado, sem cabos",
		off = "Desligado",
		fail = "Queimado (LED vermelho)",
	}

	menuData = function(dev: any)
		local configured = true
		if dev.kind == "router" then
			local e = RouterCli.evaluate(dev.cfg, routerIfaces(dev), Rack.deadDns)
			configured = e.routeOk and e.lanOk and e.natOk
		end
		local st = deviceState(dev, configured)
		return {
			id = dev.id,
			label = deviceLabel(dev),
			model = if dev.kind == "router" then "MikroTik " .. RouterCli.Model else "Huawei " .. OltCli.Model,
			slot = dev.slot,
			state = st,
			stateText = StateText[st] or st,
			ip = mgmtIpOf(dev) or "sem IP",
			powered = dev.powered,
			cabled = dev.cabled,
			failed = dev.failed,
			pos = dev.parts.body.Position,
		}
	end

	local function onRackAction(player: Player, deviceId: any, action: any)
		if typeof(deviceId) ~= "number" or typeof(action) ~= "string" then
			return
		end
		if action == "close" then
			menuViewers[player] = nil
			return
		end
		local dev = nil
		for _, d in Rack.devices do
			if d.id == deviceId then
				dev = d
			end
		end
		local root = rootOf(player)
		if not dev or not root or (root.Position - dev.parts.body.Position).Magnitude > MENU_RANGE then
			menuViewers[player] = nil
			Remotes.RackMenu:FireClient(player, nil)
			return
		end
		if action == "console" then
			menuViewers[player] = nil
			Rack.openConsole(player, dev)
			return
		elseif action == "manual" then
			menuViewers[player] = nil
			Rack.openManual(player, dev.kind)
			return
		elseif action == "power" then
			doPower(player, dev)
		elseif action == "cables" then
			doCables(player, dev)
		elseif action == "remove" then
			if dev.powered then
				Remotes.notify(player, "Desligue o equipamento antes de tirar do rack.", "error")
			else
				menuViewers[player] = nil
				Rack.removeDevice(dev)
				Remotes.notify(player, "Equipamento retirado do rack.", "info")
				Remotes.RackMenu:FireClient(player, nil)
				return
			end
		end
		refreshPrompts(dev)
	end

	-- Painel do datacenter: equipamentos do rack e os cabos principais.
	function Rack.status()
		local devs = {}
		for _, d in Rack.devices do
			local configured = true
			if d.kind == "router" then
				local e = RouterCli.evaluate(d.cfg, routerIfaces(d), Rack.deadDns)
				configured = e.routeOk and e.lanOk and e.natOk
			end
			table.insert(devs, {
				slot = d.slot,
				kind = d.kind,
				label = deviceLabel(d),
				model = if d.kind == "router" then RouterCli.Model else OltCli.Model,
				state = deviceState(d, configured),
				ip = mgmtIpOf(d) or "sem IP",
				uptime = if isActive(d) then uptime(d) else "-",
			})
		end
		table.sort(devs, function(a, b)
			return a.slot > b.slot
		end)
		local router, olt = mainOf("router"), mainOf("olt")
		local rUp = router ~= nil and router.cabled and isActive(router)
		local oUp = olt ~= nil and olt.cabled and isActive(olt)
		local function fiber(distId: string): string
			if not oUp then
				return "down"
			end
			local trunk, dist = edgeStateOf(net.CtoSplitter[distId] or "SPL"), edgeStateOf(distId)
			if trunk == "broken" or dist == "broken" then
				return "broken"
			elseif trunk == "dirty" or dist == "dirty" then
				return "dirty"
			end
			return "ok"
		end
		local links = {
			{ name = "ether1 → Operadora", color = "red", state = if rUp then "ok" else "down" },
			{ name = "ether2 → OLT uplink", color = "blue", state = if rUp and oUp then "ok" else "down" },
			{ name = "PON 0/1/0 → DIO P1 → CTO A", color = "yellow", state = fiber("CTO_A") },
			{ name = "PON 0/1/1 → DIO P2 → CTO B", color = "yellow", state = fiber("CTO_B") },
			{ name = "PON 0/1/2 → DIO P3 → CTO C (Palmeiras)", color = "yellow", state = fiber("CTO_C") },
			{ name = "PON 0/1/3 → DIO P4 → CTO D (Palmeiras)", color = "yellow", state = fiber("CTO_D") },
		}
		return { devices = devs, links = links, slots = SLOT_COUNT, free = SLOT_COUNT - #Rack.devices }
	end

	-- ---------------------------------------------------------------------------
	-- Incidentes do rack
	-- ---------------------------------------------------------------------------

	function Rack.canKillDns(): boolean
		local router = activeOf("router")
		if not router or not game_.linkContracted then
			return false
		end
		local up = RouterCli.Upstream.upstreamDns
		return table.find(router.cfg.dns.servers, up) ~= nil and not Rack.deadDns[up]
	end

	function Rack.killUpstreamDns()
		Rack.deadDns[RouterCli.Upstream.upstreamDns] = true
	end

	function Rack.canFailHardware(): boolean
		return game_.day >= 2 and (activeOf("router") ~= nil or activeOf("olt") ~= nil)
	end

	function Rack.failHardware()
		local options = {}
		for _, d in Rack.devices do
			if isActive(d) then
				table.insert(options, d)
			end
		end
		if #options == 0 then
			return
		end
		local dev = options[math.random(1, #options)]
		dev.failed = true
		net.addAlarm(P.slot, if dev.kind == "olt" then "OLT" else "Roteador", deviceLabel(dev) .. " parou de responder", "critical")
	end

	-- ---------------------------------------------------------------------------

	function Rack.setTech(t: any)
		techService = t
	end

	-- Ganchos para o despacho global dos Remotes (ver RackModule.start)
	Rack._onCommand = onCommand
	Rack._onComplete = onComplete
	Rack._onBuy = onBuy
	Rack._onRackAction = onRackAction

	-- Provedor fechou: tira tudo do prédio
	function Rack.destroy()
		for _, c in conns do
			c:Disconnect()
		end
		for _, pp in extraPrompts do
			pp:Destroy()
		end
		for player in menuViewers do
			Remotes.RackMenu:FireClient(player, nil)
		end
		table.clear(menuViewers)
		table.clear(sessions)
		table.clear(pcSessions)
		Rack.devices = {}
		runtime:Destroy()
	end

	-- ---------------------------------------------------------------------------
	-- Montagem (o rack começa vazio: a equipe compra, instala e configura)
	-- ---------------------------------------------------------------------------

	buildShopAndSlots()

	-- estações do NOC deste prédio
	for _, part in CollectionService:GetTagged("NocPc") do
		if part:GetAttribute("Slot") ~= P.slot then
			continue
		end
		local idx = part:GetAttribute("PcIndex") :: number
		pcs[idx] = part
		local pp = prompt(part, "Usar computador", "Estação " .. idx, Enum.KeyCode.E)
		pp.MaxActivationDistance = 8
		table.insert(extraPrompts, pp)
		pp.Triggered:Connect(function(player)
			if own(player) then
				Rack.openPc(player, idx)
			end
		end)
	end

	table.insert(
		conns,
		Players.PlayerRemoving:Connect(function(player)
			menuViewers[player] = nil
			pcSessions[player] = nil
			sessions[player] = nil
		end)
	)

	return Rack
end

-- ---------------------------------------------------------------------------
-- Remotes: um só para o jogo inteiro, cada pedido vai para o rack do provedor do jogador
-- ---------------------------------------------------------------------------

local function rackOf(player: Player): any
	local P = Providers.of(player)
	return P and P.rack
end

function RackModule.start()
	Remotes.ConsoleCommand.OnServerInvoke = function(player, deviceId, line)
		local rack = rackOf(player)
		if not rack then
			return { output = "% Você não faz parte de nenhum provedor.", prompt = "", closed = true }
		end
		return rack._onCommand(player, deviceId, line)
	end
	Remotes.ConsoleComplete.OnServerInvoke = function(player, deviceId, line)
		local rack = rackOf(player)
		return if rack then rack._onComplete(player, deviceId, line) else {}
	end
	Remotes.ShopBuy.OnServerEvent:Connect(function(player, itemId)
		local rack = rackOf(player)
		if rack then
			rack._onBuy(player, itemId)
		end
	end)
	Remotes.RackAction.OnServerEvent:Connect(function(player, deviceId, action)
		local rack = rackOf(player)
		if rack then
			rack._onRackAction(player, deviceId, action)
		end
	end)

	-- Notebook TI: clicar com ele na mão abre o terminal
	local hooked = setmetatable({}, { __mode = "k" })
	local function hookNotebook(tool: Instance)
		if hooked[tool] or not tool:IsA("Tool") then
			return
		end
		hooked[tool] = true
		tool.Activated:Connect(function()
			local player = Players:GetPlayerFromCharacter(tool.Parent)
			local rack = player and rackOf(player)
			if rack then
				rack.openNotebook(player)
			end
		end)
	end
	CollectionService:GetInstanceAddedSignal("NotebookTI"):Connect(hookNotebook)
	for _, t in CollectionService:GetTagged("NotebookTI") do
		hookNotebook(t)
	end
end

return RackModule
