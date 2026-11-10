-- Relógio da cidade (um só para todos) e o caixa de cada provedor: dinheiro,
-- estoque, crédito, SLA, prazo de implantação, manifestação e falência.
--
-- Game.day / Game.hour / Game.clockText() são da cidade. Game.newProvider(P) cria o
-- "game" de um provedor; ele enxerga o relógio pela metatable (g.day, g.clockText()).

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local Providers = require(script.Parent.Providers)

local Game = {}

Game.day = 1
Game.hour = Config.DayStartHour

local stateFolder: Folder
local net: any
local residents: any

function Game.init(netService: any, residentService: any)
	net = netService
	residents = residentService
	stateFolder = ReplicatedStorage:FindFirstChild("GameState") :: Folder
	if not stateFolder then
		stateFolder = Instance.new("Folder")
		stateFolder.Name = "GameState"
		stateFolder.Parent = ReplicatedStorage
	end
	stateFolder:SetAttribute("Day", Game.day)
	stateFolder:SetAttribute("Hour", Game.hour)
	stateFolder:SetAttribute("GraceDays", Config.Opening.GraceDays)
end

function Game.clockText(): string
	local h = math.floor(Game.hour)
	local m = math.floor((Game.hour - h) * 60)
	return string.format("%02d:%02d", h, m)
end

-- ---------------------------------------------------------------------------
-- Caixa de um provedor
-- ---------------------------------------------------------------------------

function Game.newProvider(P: any): any
	local g = setmetatable({}, { __index = Game })
	g.P = P
	g.money = 0
	g.reputation = 3.5
	g.linkContracted = false
	g.phase = "implantacao" -- implantacao | operacao | protesto | falencia
	g.bankrupt = false
	g.openedDay = Game.day
	g.onPhase = nil :: ((string, string) -> ())?
	g.owned = {} -- [toolKey] = true
	g.stock = {} -- [supplyKey] = unidades
	for _, k in Config.SupplyOrder do
		g.stock[k] = 0
	end
	g.dailyCosts = {} :: { () -> number }
	g.debt = 0
	local loansToday = 0
	local stats = {
		revenue = 0,
		costs = 0,
		penalties = 0,
		cancellations = 0,
		installs = 0,
		repairs = 0,
		upSeconds = 0,
		customerSeconds = 0,
	}
	local penaltyAcc = 0
	local folder = P.folder

	-- ERP: extrato (receitas e despesas) e movimentação do estoque
	g.ledger = {} :: { any } -- lançamentos, mais novo primeiro
	g.daily = {} :: { [number]: any } -- [dia] = { receita = { [categoria] = R$ }, despesa = {...} }
	g.moves = {} :: { any } -- entradas e saídas do estoque, mais novo primeiro
	g.usedToday = {} :: { [string]: number }
	local lowWarned = {} :: { [string]: boolean }

	local function dayTotals(day: number): any
		local d = g.daily[day]
		if not d then
			d = { receita = {}, despesa = {} }
			g.daily[day] = d
			g.daily[day - 3] = nil -- guarda só os últimos dias
		end
		return d
	end

	-- Registra um lançamento no extrato do ERP. kind: "receita" ou "despesa".
	-- line = false soma no total do dia sem criar linha no extrato.
	function g.record(kind: string, category: string, desc: string, amount: number, line: boolean?)
		amount = math.floor(amount + 0.5)
		if amount <= 0 then
			return
		end
		local d = dayTotals(Game.day)
		d[kind][category] = (d[kind][category] or 0) + amount
		if line ~= false then
			table.insert(g.ledger, 1, { day = Game.day, time = Game.clockText(), kind = kind, category = category, desc = desc, amount = amount })
			if #g.ledger > Config.Erp.LedgerSize then
				table.remove(g.ledger)
			end
		end
	end

	local function move(kind: string, delta: number, reason: string)
		table.insert(g.moves, 1, { day = Game.day, time = Game.clockText(), kind = kind, delta = delta, reason = reason, after = g.stock[kind] or 0 })
		if #g.moves > 30 then
			table.remove(g.moves)
		end
	end

	local function publish()
		folder:SetAttribute("Money", math.floor(g.money))
		folder:SetAttribute("Reputation", g.reputation)
		folder:SetAttribute("Debt", math.floor(g.debt))
		folder:SetAttribute("Phase", g.phase)
		folder:SetAttribute("OpenedDay", g.openedDay)
		folder:SetAttribute("LinkOn", g.linkContracted)
		for k, v in g.stock do
			folder:SetAttribute("Stock_" .. k, v)
		end
		for _, k in Config.ToolOrder do
			folder:SetAttribute("Owns_" .. k, g.owned[k] == true)
		end
	end
	g.publish = publish

	-- aviso para um jogador ou, sem jogador, para toda a equipe do provedor
	function g.notify(player: Player?, text: string, kind: string?)
		Providers.notify(P, player, text, kind)
	end

	function g.spend(amount: number, reason: string, player: Player?, category: string?): boolean
		if g.money < amount then
			g.notify(player, string.format("Caixa sem dinheiro para %s (R$ %d).", reason, amount), "error")
			return false
		end
		g.money -= amount
		stats.costs += amount
		g.record("despesa", category or "Compras", reason, amount)
		publish()
		g.notify(player, string.format("-R$ %d · %s", amount, reason), "money")
		return true
	end

	function g.earn(amount: number, reason: string, player: Player?, category: string?)
		g.money += amount
		stats.revenue += amount
		g.record("receita", category or "Serviços", reason, amount)
		publish()
		g.notify(player, string.format("+R$ %d · %s", amount, reason), "money")
	end

	function g.addStock(kind: string, units: number, reason: string?)
		g.stock[kind] = (g.stock[kind] or 0) + units
		if (g.stock[kind] or 0) >= (Config.Erp.MinStock[kind] or 0) then
			lowWarned[kind] = nil
		end
		move(kind, units, reason or "Entrada")
		publish()
	end

	function g.useStock(needs: { [string]: number }, player: Player?, reason: string?): boolean
		for kind, n in needs do
			if (g.stock[kind] or 0) < n then
				local s = Config.Supplies[kind]
				g.notify(player, string.format("Sem %s no estoque. Compre no terminal de compras do almoxarifado.", if s then s.name else kind), "error")
				return false
			end
		end
		for kind, n in needs do
			g.stock[kind] -= n
			g.usedToday[kind] = (g.usedToday[kind] or 0) + n
			move(kind, -n, reason or "Uso")
			-- estoque abaixo do mínimo: o ERP avisa uma vez
			local min = Config.Erp.MinStock[kind] or 0
			if g.stock[kind] < min and not lowWarned[kind] then
				lowWarned[kind] = true
				local s = Config.Supplies[kind]
				net.addAlarm(P.slot, "Estoque", string.format("%s abaixo do mínimo: %d em estoque (mínimo %d). Compre pelo ERP ou no terminal", if s then s.name else kind, g.stock[kind], min), "warning")
			end
		end
		publish()
		return true
	end

	function g.loanStatus()
		local L = Config.GovLoan
		local reason = nil
		if loansToday >= L.PerDay then
			reason = "Você já pediu crédito hoje. Tente amanhã."
		elseif g.debt + L.Amount * (1 + L.Interest) > L.MaxDebt then
			reason = string.format("Dívida alta demais (R$ %d). Pague parte antes de pedir mais.", math.floor(g.debt))
		end
		return {
			name = L.Name,
			amount = L.Amount,
			repay = math.floor(L.Amount * (1 + L.Interest)),
			daily = L.DailyPayment,
			debt = math.floor(g.debt),
			maxDebt = L.MaxDebt,
			canRequest = reason == nil,
			reason = reason or "",
		}
	end

	function g.requestLoan(player: Player?): boolean
		local st = g.loanStatus()
		if not st.canRequest then
			g.notify(player, st.reason, "error")
			return false
		end
		loansToday += 1
		g.debt += st.repay
		g.money += st.amount
		g.record("receita", "Empréstimo", Config.GovLoan.Name .. " (devolve R$ " .. st.repay .. ")", st.amount)
		publish()
		g.notify(nil, string.format("Crédito do governo liberado: +R$ %d. Devolve R$ %d em parcelas de R$ %d por dia.", st.amount, st.repay, st.daily), "money")
		return true
	end

	function g.count(kind: string)
		if stats[kind] ~= nil then
			stats[kind] += 1
		end
	end

	function g.sla(): number
		if stats.customerSeconds <= 0 then
			return 100
		end
		return stats.upSeconds / stats.customerSeconds * 100
	end

	-- O prazo de implantação deste provedor já acabou? (conta do dia em que ele abriu)
	function g.pastDeadline(): boolean
		return Game.day > g.openedDay + Config.Opening.GraceDays - 1
	end

	function g.deadlineDay(): number
		return g.openedDay + Config.Opening.GraceDays - 1
	end

	local function setPhase(p: string)
		if p == g.phase then
			return
		end
		local old = g.phase
		g.phase = p
		publish()
		if g.onPhase then
			task.spawn(g.onPhase, p, old)
		end
	end

	local function goBankrupt()
		if g.bankrupt then
			return
		end
		g.bankrupt = true
		setPhase("falencia")
		for _, pl in Providers.members(P) do
			Remotes.Bankrupt:FireClient(pl, {
				name = P.name,
				day = Game.day,
				money = math.floor(g.money),
				debt = math.floor(g.debt),
				customers = net.activeCount(P.slot),
				houses = #net.houses,
			})
		end
	end
	g.goBankrupt = goBankrupt

	-- fechamento do dia deste provedor
	function g.endDay()
		local active = net.activeCount(P.slot)
		local fees = net.feesOf(P.slot) -- cada cliente paga o preço do próprio contrato
		local upstreamCost = net.slot(P.slot).upstreamMbps * Config.UpstreamCostPerMbpsDay
		g.money += fees - upstreamCost
		stats.revenue += fees
		stats.costs += upstreamCost
		g.record("receita", "Mensalidades", string.format("Mensalidades do dia (%d clientes)", active), fees)
		g.record("despesa", "Link da operadora", string.format("Link de %d Mbps", net.slot(P.slot).upstreamMbps), upstreamCost)
		local loanPayment = math.min(g.debt, Config.GovLoan.DailyPayment)
		g.money -= loanPayment
		g.debt -= loanPayment
		g.record("despesa", "Empréstimo", "Parcela do " .. Config.GovLoan.Name, loanPayment)
		loansToday = 0
		local staffCost = 0
		for _, fn in g.dailyCosts do
			local amount, category, desc = fn()
			staffCost += amount
			g.record("despesa", category or "Equipe", desc or category or "Custo diário", amount)
		end
		g.money -= staffCost
		stats.costs += staffCost
		if stats.penalties >= 1 then
			-- as multas já saíram do caixa durante o dia; aqui só vira uma linha no extrato
			table.insert(g.ledger, 1, { day = Game.day, time = Game.clockText(), kind = "despesa", category = "Multas de SLA", desc = "Multas de SLA do dia", amount = math.floor(stats.penalties) })
		end
		table.clear(g.usedToday)
		local summary = {
			provider = P.name,
			day = Game.day,
			customers = active,
			fees = fees,
			revenue = stats.revenue,
			costs = stats.costs,
			penalties = math.floor(stats.penalties),
			upstreamCost = upstreamCost,
			loanPayment = loanPayment,
			staffCost = staffCost,
			debt = math.floor(g.debt),
			sla = g.sla(),
			mood = residents.averageMood(P.slot) or 50,
			cancellations = stats.cancellations,
			installs = stats.installs,
			repairs = stats.repairs,
			money = math.floor(g.money),
			reputation = g.reputation,
		}
		for _, pl in Providers.members(P) do
			Remotes.DaySummary:FireClient(pl, summary)
		end
		for k in stats do
			stats[k] = 0
		end
		publish()
	end

	-- avisos do prazo, chamados quando o dia da cidade vira
	function g.newDay()
		local last = g.deadlineDay()
		if Game.day == last then
			g.notify(nil, string.format("Último dia do prazo de implantação do %s! No fim do dia %d a vila espera ter internet.", P.name, last), "alarm")
		elseif Game.day == last + 1 then
			g.notify(nil, "O prazo de implantação acabou. Quem escolheu o seu provedor e continua sem internet vai ficar impaciente.", "alarm")
		end
	end

	-- uma vez por segundo
	function g.tick(dt: number)
		if g.bankrupt then
			return
		end
		for _, h in net.houses do
			if h.contract ~= "active" or h.slot ~= P.slot then
				continue
			end
			stats.customerSeconds += dt
			if h.status == "online" or h.status == "slow" then
				stats.upSeconds += dt
			elseif h.status == "unstable" then
				stats.upSeconds += dt * 0.5
			else
				local p = Config.SlaPenaltyPerHour * (h.house.slaMult or 1) * dt / Config.HourSeconds -- prédio público multa mais
				stats.penalties += p
				penaltyAcc += p
			end
		end
		if penaltyAcc >= 1 then
			local whole = math.floor(penaltyAcc)
			penaltyAcc -= whole
			g.money -= whole
			stats.costs += whole
			g.record("despesa", "Multas de SLA", "", whole, false)
		end

		-- satisfação de quem é cliente ou escolheu este provedor
		local avg = residents.averageMood(P.slot)
		if avg then
			g.reputation = math.clamp(avg / 20, 0, 5)
		end
		folder:SetAttribute("Mood", avg or -1)

		local O = Config.Opening
		if not g.pastDeadline() then
			setPhase("implantacao")
		elseif avg == nil then
			setPhase("operacao")
		elseif avg < O.BankruptAt then
			goBankrupt()
			return
		elseif avg < O.ProtestBelow then
			setPhase("protesto")
		elseif g.phase ~= "protesto" or avg >= O.ProtestEndAbove then
			setPhase("operacao")
		end
		publish()
	end

	function g.summary()
		return {
			clock = Game.clockText(),
			day = Game.day,
			money = math.floor(g.money),
			reputation = g.reputation,
			sla = g.sla(),
			penalties = math.floor(stats.penalties),
			debt = math.floor(g.debt),
			stock = g.stock,
			name = P.name,
			price = P.price,
		}
	end

	publish()
	return g
end

-- ---------------------------------------------------------------------------
-- Relógio da cidade
-- ---------------------------------------------------------------------------

-- Chamado uma vez por segundo pelo Main. Devolve true quando o dia acabou.
function Game.tick(dt: number): boolean
	Game.hour += dt / Config.HourSeconds
	Lighting.ClockTime = Game.hour
	local ended = false
	if Game.hour >= Config.DayEndHour then
		for _, P in Providers.list() do
			P.game.endDay()
		end
		Game.day += 1
		Game.hour = Config.DayStartHour
		for _, P in Providers.list() do
			P.game.newDay()
		end
		ended = true
	end
	stateFolder:SetAttribute("Day", Game.day)
	stateFolder:SetAttribute("Hour", Game.hour)
	return ended
end

-- Chamado pelo FibraTeste ("hora", "prazo")
function Game.publishClock()
	stateFolder:SetAttribute("Day", Game.day)
	stateFolder:SetAttribute("Hour", Game.hour)
end

return Game
