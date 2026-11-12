-- Cria os RemoteEvents usados entre servidor e clientes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local folder = ReplicatedStorage:FindFirstChild("Remotes")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
end

local function event(name: string): RemoteEvent
	local e = folder:FindFirstChild(name)
	if not e then
		e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = folder
	end
	return e :: RemoteEvent
end

Remotes.NocUpdate = event("NocUpdate") -- servidor -> clientes: estado da rede a cada segundo
Remotes.Notify = event("Notify") -- servidor -> cliente: aviso curto no HUD
Remotes.Dialog = event("Dialog") -- servidor -> cliente: caixa de diálogo de um morador
Remotes.DaySummary = event("DaySummary") -- servidor -> clientes: fechamento do dia
Remotes.Bankrupt = event("Bankrupt") -- servidor -> clientes: o provedor faliu (fim de jogo)
Remotes.ProviderAction = event("ProviderAction") -- cliente -> servidor: abrir, entrar, aportar, renomear, preço
Remotes.ProviderMenu = event("ProviderMenu") -- servidor -> cliente: abre o menu de provedores
Remotes.ConsoleOpen = event("ConsoleOpen") -- servidor -> cliente: abre o console de um equipamento
Remotes.ShopOpen = event("ShopOpen") -- servidor -> cliente: abre a loja
Remotes.ShopBuy = event("ShopBuy") -- cliente -> servidor: compra um item
Remotes.RackMenu = event("RackMenu") -- servidor -> cliente: abre/atualiza o menu de ações de um equipamento (nil fecha)
Remotes.RackAction = event("RackAction") -- cliente -> servidor: ação escolhida no menu do equipamento
Remotes.HouseMenu = event("HouseMenu") -- servidor -> cliente: abre/atualiza o menu da caixa da casa (nil fecha)
Remotes.HouseAction = event("HouseAction") -- cliente -> servidor: ação escolhida no menu da caixa da casa
Remotes.ErpOpen = event("ErpOpen") -- servidor -> cliente: abre/atualiza a tela do ERP (nil fecha)
Remotes.ErpAction = event("ErpAction") -- cliente -> servidor: abrir, agendar, comprar, contratar...
Remotes.BidAction = event("BidAction") -- cliente -> servidor: proposta (ou retirada) numa licitação
Remotes.BidOpen = event("BidOpen") -- servidor -> cliente: abre a tela das licitações (mural da Prefeitura)

Remotes.GuerraAction = event("GuerraAction") -- cliente -> servidor: atacar, parar, comprar equipamento, anti-DDoS, RTBH, Robux

local guerraState = folder:FindFirstChild("GuerraState")
if not guerraState then
	guerraState = Instance.new("RemoteFunction")
	guerraState.Name = "GuerraState"
	guerraState.Parent = folder
end
Remotes.GuerraState = guerraState :: RemoteFunction -- cliente -> servidor: dados da tela Guerra (ataque, defesa e loja)

local fn = folder:FindFirstChild("ConsoleCommand")
if not fn then
	fn = Instance.new("RemoteFunction")
	fn.Name = "ConsoleCommand"
	fn.Parent = folder
end
Remotes.ConsoleCommand = fn :: RemoteFunction -- cliente -> servidor: uma linha digitada no console

local comp = folder:FindFirstChild("ConsoleComplete")
if not comp then
	comp = Instance.new("RemoteFunction")
	comp.Name = "ConsoleComplete"
	comp.Parent = folder
end
Remotes.ConsoleComplete = comp :: RemoteFunction -- cliente -> servidor: TAB no console (completa a linha)

local bidState = folder:FindFirstChild("BidState")
if not bidState then
	bidState = Instance.new("RemoteFunction")
	bidState.Name = "BidState"
	bidState.Parent = folder
end
Remotes.BidState = bidState :: RemoteFunction -- cliente -> servidor: lista das licitações (com a proposta do seu provedor)

function Remotes.notify(player: Player?, text: string, kind: string?)
	if player then
		Remotes.Notify:FireClient(player, text, kind or "info")
	else
		Remotes.Notify:FireAllClients(text, kind or "info")
	end
end

return Remotes
