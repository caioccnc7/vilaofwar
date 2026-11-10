-- Ferramentas comuns dos consoles: árvore de palavras-chave, abreviação de comandos
-- ("disp ont autof all"), completar com TAB e ajuda com "?".
--
-- Um nó da árvore:
--   { kw = { { w = "display", d = "Display information", n = <nó> }, ... },
--     arg = { name = "<portid>", d = "Port ID", n = <nó>, num = true }?,
--     cr = true? }   -- cr: o comando pode terminar aqui (<cr>)

local Complete = {}

export type Entry = { w: string, d: string?, n: any }

-- separa por espaço, respeitando "texto entre aspas"
function Complete.tokens(line: string): { string }
	local out = {}
	local i, n = 1, #line
	while i <= n do
		local c = string.sub(line, i, i)
		if c == " " or c == "\t" then
			i += 1
		elseif c == "\"" then
			local close = string.find(line, "\"", i + 1, true) or (n + 1)
			table.insert(out, string.sub(line, i, close))
			i = close + 1
		else
			local j = i
			while j <= n do
				local cj = string.sub(line, j, j)
				if cj == " " or cj == "\t" then
					break
				end
				j += 1
			end
			table.insert(out, string.sub(line, i, j - 1))
			i = j
		end
	end
	return out
end

-- coluna (1 = primeiro caractere) onde começa o token número idx
function Complete.column(line: string, idx: number): number
	local pos, count = 1, 0
	local n = #line
	while pos <= n do
		local c = string.sub(line, pos, pos)
		if c ~= " " then
			count += 1
			if count == idx then
				return pos
			end
			if c == "\"" then
				pos = (string.find(line, "\"", pos + 1, true) or n) + 1
			else
				pos = (string.find(line, " ", pos, true) or (n + 1))
			end
		else
			pos += 1
		end
	end
	return n + 1
end

function Complete.startsWith(s: string, prefix: string): boolean
	return string.sub(s, 1, #prefix) == prefix
end

-- palavra-chave exata ou abreviação sem ambiguidade
-- retorna (entrada, "ok" | "ambiguous" | "none")
function Complete.findKw(node: any, tok: string): (Entry?, string)
	if not node or not node.kw then
		return nil, "none"
	end
	local low = string.lower(tok)
	local hits = {}
	for _, e in node.kw do
		if e.w == low then
			return e, "ok"
		end
		if Complete.startsWith(e.w, low) then
			table.insert(hits, e)
		end
	end
	if #hits == 1 then
		return hits[1], "ok"
	elseif #hits > 1 then
		return nil, "ambiguous"
	end
	return nil, "none"
end

local function argAccepts(arg: any, tok: string): boolean
	if arg.num then
		return tonumber(tok) ~= nil
	end
	if arg.pattern then
		return string.match(tok, arg.pattern) ~= nil
	end
	return true
end

-- Percorre os tokens. Retorna o nó final, os tokens com as palavras-chave por
-- extenso e, em caso de erro, o índice do token errado e o tipo do erro.
function Complete.walk(root: any, tokens: { string }): (any, { string }, number?, string?)
	local node = root
	local full = {}
	for i, t in tokens do
		local e, how = Complete.findKw(node, t)
		if e then
			table.insert(full, e.w)
			node = e.n or { cr = true }
		elseif how == "ambiguous" and not (node.arg and argAccepts(node.arg, t)) then
			return nil, full, i, "ambiguous"
		elseif node and node.arg and argAccepts(node.arg, t) then
			table.insert(full, t)
			node = node.arg.n or { cr = true }
		elseif node and node.arg then
			return nil, full, i, "param"
		else
			return nil, full, i, if how == "ambiguous" then "ambiguous" else "unknown"
		end
	end
	return node, full, nil, nil
end

-- candidatos para a palavra que está sendo digitada
function Complete.candidates(node: any, partial: string): ({ Entry }, any)
	local list = {}
	if not node then
		return list, nil
	end
	local low = string.lower(partial)
	for _, e in node.kw or {} do
		if Complete.startsWith(e.w, low) then
			table.insert(list, e)
		end
	end
	local arg = nil
	if node.arg and (partial == "" or argAccepts(node.arg, partial)) then
		arg = node.arg
	end
	return list, arg
end

function Complete.commonPrefix(words: { string }): string
	if #words == 0 then
		return ""
	end
	local p = words[1]
	for i = 2, #words do
		local w = words[i]
		local k = 0
		while k < #p and k < #w and string.sub(p, k + 1, k + 1) == string.sub(w, k + 1, k + 1) do
			k += 1
		end
		p = string.sub(p, 1, k)
	end
	return p
end

-- linha sem a palavra parcial do fim
function Complete.base(line: string, partial: string): string
	return string.sub(line, 1, #line - #partial)
end

-- palavras em colunas, como o bash e o RouterOS mostram no TAB
function Complete.columns(words: { string }, width: number?): string
	local w = 0
	for _, s in words do
		w = math.max(w, #s)
	end
	w += 2
	local perLine = math.max(1, math.floor((width or 78) / w))
	local out, row = {}, {}
	for i, s in words do
		table.insert(row, s .. string.rep(" ", w - #s))
		if #row == perLine or i == #words then
			table.insert(out, (string.gsub(table.concat(row), "%s+$", "")))
			row = {}
		end
	end
	return table.concat(out, "\n")
end

-- Decide o que o TAB faz com uma lista de palavras possíveis:
-- uma só completa; várias com começo comum maior completa até onde dá; senão mostra a lista.
-- retorna (nova linha ou nil, lista para mostrar ou nil)
function Complete.decide(line: string, partial: string, words: { string }, addSpace: boolean?): (string?, { string }?)
	if #words == 0 then
		return nil, nil
	end
	local base = Complete.base(line, partial)
	if #words == 1 then
		return base .. words[1] .. (if addSpace == false then "" else " "), nil
	end
	local cp = Complete.commonPrefix(words)
	if #cp > #partial then
		return base .. cp, nil
	end
	return nil, words
end

return Complete
