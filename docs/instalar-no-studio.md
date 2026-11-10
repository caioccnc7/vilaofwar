# Como levar o código para o Studio

O jogo oficial é a experiência **Provedor de Internet**, com edição ao vivo (Team Create). O código de `src/` entra nela importando três modelos.

> Regra do projeto: trabalhar só no Studio aberto. Não sobrescrever nem fechar e reabrir o place. Salvar e publicar ficam com o dono do projeto.

## 1. Gerar os modelos

```bash
python3 tools/gen_models.py v2
```

Isso cria `modelos/v2_Shared.rbxmx`, `modelos/v2_Server.rbxmx` e `modelos/v2_Client.rbxmx`.

## 2. Fazer backup no Studio

No Command Bar (Exibir > Barra de comandos), no modo de edição:

```lua
local b = Instance.new("Folder") b.Name = "Backup_antes_v2" b.Parent = game.ServerStorage
for _, x in { game.ReplicatedStorage.Shared, game.ServerScriptService.Server, game.StarterPlayer.StarterPlayerScripts.Client } do
	x:Clone().Parent = b
end
```

## 3. Importar

1. Limpe a seleção (`game.Selection:Set({})`). Se algo estiver selecionado, o modelo importado entra dentro dele.
2. Vá em Arquivo > Importar modelo do Roblox e escolha os três arquivos `.rbxmx`. Eles aparecem no Workspace.

## 4. Trocar as pastas

```lua
local CH = game:GetService("ChangeHistoryService")
CH:SetWaypoint("antes v2")
local function swap(new, parent)
	local old = parent:FindFirstChild(new.Name)
	if old then old:Destroy() end
	new.Parent = parent
end
swap(workspace:FindFirstChild("Shared", true), game.ReplicatedStorage)
swap(workspace:FindFirstChild("Server", true), game.ServerScriptService)
swap(workspace:FindFirstChild("Client", true), game.StarterPlayer.StarterPlayerScripts)
CH:SetWaypoint("v2")
```

## 5. Conferir

Compare o tamanho de cada script com o arquivo (`wc -c src/...`):

```lua
for _, f in { game.ReplicatedStorage.Shared, game.ServerScriptService.Server, game.StarterPlayer.StarterPlayerScripts.Client } do
	for _, s in f:GetDescendants() do
		if s:IsA("LuaSourceContainer") then print(s.Name, #s.Source) end
	end
end
```

Depois aperte Play e veja se a janela Saída mostra algum erro. Se der problema, volte com Ctrl+Z ou recoloque as pastas do backup.

## Alternativa: Rojo

O `default.project.json` mapeia `src/` para as mesmas pastas, então `rojo serve` também funciona. Num place com edição ao vivo, combine antes com quem está editando.
