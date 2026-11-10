--!strict
-- Configurações gerais do jogo. Mexa aqui para balancear.

local Config = {}

Config.GameName = "Fibra da Vila"
Config.CityName = "Vila Aurora"

-- Relógio: o expediente vai das 8h às 20h. Cada hora de jogo dura HourSeconds segundos reais.
Config.DayStartHour = 8
Config.DayEndHour = 20
Config.HourSeconds = 60 -- 12 horas de jogo = 12 minutos reais

-- Economia (R$)
-- A vila começa SEM internet e SEM prédios de provedor. Do dinheiro inicial, R$ 2.500
-- pagam a obra do prédio (Config.Lots) e o resto (R$ 9.500) monta o rack, o link, as
-- ferramentas e os insumos das primeiras casas. O crédito do governo ajuda a crescer.
Config.StartMoney = 12000
Config.DailyFeePerCustomer = 40 -- preço inicial da mensalidade (rateada por dia) de um provedor novo
-- Preço que o provedor pode cobrar (por dia de jogo). Cada morador aceita pagar até um
-- valor sorteado entre WillingMin e WillingMax; acima disso ele não contrata ninguém.
Config.Price = {
	Min = 10,
	Max = 120,
	WillingMin = 35,
	WillingMax = 75,
}
Config.InstallFee = 100 -- taxa de instalação cobrada do cliente

-- Lotes de provedor (Shared/CityMap): a cidade começa sem prédios de provedor. Quem
-- abre um provedor escolhe um lote livre e paga a obra com o próprio dinheiro; o que
-- sobra vira o caixa. Máximo de 5 provedores por servidor, 1 por jogador (dono).
Config.Lots = {
	BuildCost = 2500, -- obra do prédio (térreo, NOC, datacenter e garagem)
}

-- Jardim das Acácias (bairro nobre): os moradores aceitam pagar mais caro
Config.Nobre = {
	WillingMin = 70,
	WillingMax = 120,
}

-- Licitações dos prédios públicos (regras no LicitacaoService). Preços por dia.
Config.Bids = {
	FirstDay = 2, -- os primeiros editais abrem no dia 2
	OpenHours = 3, -- horas de jogo para mandar proposta
	ContractDays = 5, -- duração do contrato
	InstallDays = 1, -- prazo para ligar e ativar o prédio depois de ganhar
	MinClients = 3, -- atestado de capacidade técnica: clientes online na hora do resultado
	FloorFraction = 0.5, -- proposta mínima = metade do valor de referência
	RetryHours = 2, -- licitação sem vencedor abre de novo depois disso
	Fine = 1500, -- multa por não instalar no prazo ou estourar o SLA
	SlaMult = 5, -- multa por hora sem internet: 5x a de uma casa
	Orgs = {
		{ key = "prefeitura", name = "Prefeitura", ref = 300, slaHours = 4, demand = 4 },
		{ key = "escola", name = "Escola Municipal", ref = 200, slaHours = 6, demand = 5 },
		{ key = "policia", name = "Delegacia de Polícia", ref = 250, slaHours = 3, demand = 3 },
		{ key = "hospital", name = "Hospital Municipal", ref = 400, slaHours = 2, demand = 4 },
	},
}

-- Ferramentas do provedor: compradas uma vez, todos da equipe pegam no almoxarifado
Config.ToolPrices = {
	PowerMeter = 300,
	Fusion = 1200,
	Notebook = 1500,
}

-- Insumos: comprados em pacotes no terminal de compras e gastos a cada serviço
Config.Supplies = {
	onu = { name = "ONU", pack = 4, price = 600, info = "Caixa com 4 ONUs. Gasta 1 por instalação ou troca." },
	drop = { name = "Fibra drop", pack = 4, price = 200, info = "Bobina para 4 instalações. Gasta 1 por cliente novo." },
	emenda = { name = "Tubete de emenda", pack = 10, price = 150, info = "Pacote com 10. Gasta 1 por emenda de fibra rompida." },
	conector = { name = "Conector SC/APC", pack = 10, price = 100, info = "Pacote com 10. Gasta 1 ao refazer o conector de uma casa." },
}
Config.SupplyOrder = { "onu", "drop", "emenda", "conector" }

-- Crédito do governo (programa de inclusão digital para pequenos provedores)
Config.GovLoan = {
	Name = "Programa Conecta Vila",
	Amount = 2000, -- valor de cada pedido
	Interest = 0.10, -- juros fixos: devolve 10% a mais
	DailyPayment = 300, -- parcela descontada no fechamento de cada dia
	MaxDebt = 6600, -- não libera crédito novo se a dívida passar disso
	PerDay = 1, -- pedidos por dia
}

-- Técnico de rua (NPC contratado). Caro de propósito: só compensa com uma boa
-- gestão (rede grande, muitos clientes, estoque sempre abastecido).
Config.Tech = {
	Name = "Técnico Bento",
	HireFee = 300, -- exame, uniforme e EPI no dia da contratação
	DailySalary = 180, -- pago no fechamento de cada dia em que estiver contratado
	SeverancePerDay = 90, -- rescisão: este valor vezes os dias trabalhados
	SeveranceMin = 180, -- rescisão mínima, mesmo com poucos dias
	WorkStartHour = 8, -- começa a trabalhar
	WorkEndHour = 18, -- depois disso vai para casa descansar
	RepairSeconds = 8, -- tempo de serviço no local
	InstallSeconds = 12, -- tempo para instalar o drop e a ONU numa casa nova
	WalkSpeed = 15,
	Max = 8, -- tamanho máximo da equipe (limite para o servidor não pesar)
	-- nomes da equipe, na ordem de contratação
	Names = { "Técnico Bento", "Técnica Rita", "Técnico Joca", "Técnica Lúcia", "Técnico Davi", "Técnica Nara", "Técnico Caetano", "Técnica Irene" },
	CarMinDistance = 90, -- abaixo disso o técnico vai a pé mesmo com o carro na garagem
}

-- Atendente do escritório (NPC contratado). Fica no balcão da recepção, registra os
-- pedidos de instalação e os chamados de reparo e agenda tudo no ERP para os técnicos.
Config.Attendant = {
	Name = "Atendente Sofia",
	HireFee = 200, -- uniforme e treinamento no ERP
	DailySalary = 120, -- pago no fechamento de cada dia em que estiver contratada
	SeverancePerDay = 60, -- rescisão: este valor vezes os dias trabalhados
	SeveranceMin = 120,
	WorkStartHour = 8,
	WorkEndHour = 18,
	ScheduleSeconds = 6, -- tempo para registrar e agendar cada ordem de serviço
	ActivateSeconds = 8, -- tempo para ativar na OLT um cliente já instalado (ont add + service-port)
}

-- ERP do provedor: ordens de serviço, agenda dos técnicos, receitas, despesas e estoque
Config.Erp = {
	MinStock = { onu = 2, drop = 2, emenda = 2, conector = 2 }, -- abaixo disso o ERP avisa
	RequestEvery = { 10, 70 }, -- segundos até o morador ir pedir instalação depois de escolher o provedor
	KeepClosed = 12, -- ordens concluídas ou canceladas que ficam na lista
	LedgerSize = 40, -- lançamentos guardados no extrato
}

-- ONU: só pode queimar depois de alguns dias de uso (conta da instalação ou da última troca)
Config.Onu = {
	MinAgeDays = 5,
}

-- Carro da equipe: comprado uma vez no terminal de compras (aba Equipe).
-- O chefe dirige quando quiser; o técnico só usa se o carro estiver na garagem.
Config.Car = {
	Name = "Furgão da equipe",
	Price = 3500,
	DailyCost = 40, -- combustível e seguro, pago no fechamento de cada dia
	MaxSpeed = 60, -- velocidade máxima com o jogador dirigindo (studs/s)
	ReverseSpeed = 18,
	Accel = 28,
	TurnRate = 1.7, -- giro em rad/s na velocidade máxima
	TechSpeed = 45, -- velocidade quando o técnico dirige
}

-- Cancelamento: o cliente só cancela depois de 1 dia inteiro de expediente sem internet
Config.CancelAfterSeconds = (Config.DayEndHour - Config.DayStartHour) * Config.HourSeconds
Config.SlaPenaltyPerHour = 5 -- multa por cliente, por hora de jogo sem internet
Config.UpstreamCostPerMbpsDay = 1 -- só cobra depois que o link é contratado
Config.UpstreamUpgradeMbps = 100
Config.UpstreamUpgradeCost = 600
Config.StartUpstreamMbps = 100 -- velocidade do primeiro contrato do link

-- Link da operadora: o provedor começa sem. Contrata no terminal de compras.
Config.Link = {
	Name = "Link da operadora",
	InstallFee = 800, -- taxa de ativação, paga uma vez
}

-- Começo do jogo: prazo de implantação.
-- Estimativa para quem joga pela primeira vez (1 dia de jogo = 12 min reais):
--   leitura rápida da wiki ~10 min, compras e montagem do rack ~5 min,
--   configurar o roteador ~8 min, instalar e autorizar as primeiras casas ~13 min.
--   Total ~36 min = 3 dias de jogo.
-- Durante o prazo, quem não tem internet só pergunta quando ela chega. Depois do
-- prazo, quem continua sem internet fica impaciente e o humor cai.
Config.Opening = {
	GraceDays = 3, -- o prazo acaba no fechamento do dia 3
	ProtestBelow = 5, -- moradores abaixo de 5%: manifestação na frente do provedor
	ProtestEndAbove = 10, -- a manifestação acaba quando passar de 10%
	BankruptAt = 0.5, -- moradores em 0%: falência
	VisitEvery = { 100, 220 }, -- segundos entre as visitas de quem espera internet ao provedor
}

-- Sinal óptico (GPON)
Config.OltTxDbm = 3.0
Config.SignalUnstableDbm = -27.0 -- abaixo disso a conexão fica instável
Config.SignalDownDbm = -30.0 -- abaixo disso a ONU cai

-- Incidentes
Config.IncidentMinSeconds = 70
Config.IncidentMaxSeconds = 150
Config.MaxActiveIncidents = 2

-- Humor dos moradores (0 a 100), variação por segundo
Config.Mood = {
	Start = 75,
	online = 0.3,
	slow = -0.15,
	nodns = -0.6,
	unstable = -0.5,
	offline = -0.8,
	NoContractDrift = 0, -- quem não tem contrato não muda de humor durante o prazo
	-- depois do prazo, quem espera internet perde humor: WaitBase + WaitScale * humor/75
	-- por segundo (cai mais rápido no começo e mais devagar perto de zero).
	-- Sem nenhuma casa ligada: de 75% a 5% em ~2 dias, de 5% a 0% em ~4 horas de jogo.
	WaitBase = 0.02,
	WaitScale = 0.06,
}
Config.TicketAfterSeconds = 45
Config.CancelWarnFraction = 0.5 -- alarme quando o cliente passa metade do prazo sem internet -- tempo offline até o morador abrir chamado

-- Cores por status
Config.StatusColors = {
	online = Color3.fromRGB(46, 204, 113),
	slow = Color3.fromRGB(241, 196, 15),
	nodns = Color3.fromRGB(155, 89, 182),
	unstable = Color3.fromRGB(230, 126, 34),
	offline = Color3.fromRGB(231, 76, 60),
	nocontract = Color3.fromRGB(127, 140, 141),
}

Config.StatusLabels = {
	online = "Online",
	slow = "Lenta",
	nodns = "Sem DNS",
	unstable = "Instável",
	offline = "Offline",
	nocontract = "Sem contrato",
}

-- Cores dos cabos de fibra, usadas nos LEDs do prédio
Config.FiberColors = {
	Color3.fromRGB(0, 140, 255),
	Color3.fromRGB(255, 140, 0),
	Color3.fromRGB(0, 200, 90),
}

Config.ToolNames = {
	PowerMeter = "Power Meter",
	Fusion = "Máquina de Fusão",
	Notebook = "Notebook TI",
}
Config.ToolOrder = { "PowerMeter", "Fusion", "Notebook" }

return Config
