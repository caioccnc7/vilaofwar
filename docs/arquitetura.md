# Arquitetura

O jogo roda quase todo no servidor. O mapa é gerado por código (`WorldBuilder`), a rede é um grafo em Luau puro (`NetworkGraph`) e os clientes só desenham o que o servidor manda.

## Mapa das pastas no Roblox

| Pasta em `src/` | Vai para | Tipo |
| --- | --- | --- |
| `shared/` | `ReplicatedStorage.Shared` | ModuleScripts usados pelos dois lados |
| `server/` | `ServerScriptService.Server` | Scripts e módulos do servidor |
| `server/Cli/` | `ServerScriptService.Server.Cli` | Consoles (roteador, OLT, Ubuntu) |
| `client/` | `StarterPlayer.StarterPlayerScripts.Client` | LocalScripts |

Convenção de nomes:
- `Nome.server.luau` vira `Script`.
- `Nome.client.luau` vira `LocalScript`.
- O resto vira `ModuleScript`.

## Fluxo do servidor

`Main.server.luau` é o ponto de entrada:

1. `World.build()` monta a cidade, as 16 casas, os postes e os **dois prédios** (o segundo é uma cópia deslocada em +290 no eixo X).
2. `Providers.init()`, `Game.init()`, `Net.init()`, `Residents.init()`, `Director.init()` e `RackModule.start()` sobem os serviços globais.
3. `Providers.start(world)` passa a ouvir a entrada e a saída de jogadores e o menu Provedor.
4. Laço de 1 segundo:
   - `rack.apply()` de cada provedor aplica a configuração dos equipamentos ao grafo.
   - `Net.tick()` propaga o sinal e calcula tráfego, alarmes e a escolha dos moradores.
   - `Residents.tick()` atualiza humor, falas e cancelamentos.
   - `Director.tick()` sorteia incidentes.
   - `game.tick()` de cada provedor cuida de SLA, reputação e fase.
   - `Game.tick()` avança o relógio e fecha o dia.
   - O servidor envia `NocUpdate` a cada jogador, só com os dados do provedor dele.

## Serviços globais e serviços por provedor

| Global (um por servidor) | Por provedor (criado ao abrir) |
| --- | --- |
| `WorldBuilder` (mapa) | `Game.newProvider(P)`: caixa, estoque, crédito, SLA, fase |
| `NetworkService` (rua, casas, grafo) | `RackModule.new(P, world, net)`: rack, loja, ficha do link, PCs do NOC |
| `ResidentService` (moradores) | `ErpModule.new(P, world, net)`: ordens de serviço, atendente, computador da recepção, tela do ERP |
| | `TechModule.new(P, world, net)`: técnicos pela fila do ERP (cria o `CarModule.new`) |
| `IncidentDirector` | |
| `GameService` (relógio da cidade) | |
| `Providers` (cadastro) | |

O provedor `P` é uma tabela `{ id, slot, name, price, owner, partners, isp, folder, game, rack, tech }`. `slot` é o prédio (1 ou 2).

- `Providers.onOpen` (no Main) cria `P.game`, `P.rack`, `P.erp` e `P.tech` (o ERP antes da equipe, porque os técnicos leem a fila dele).
- O extrato (receitas e despesas por categoria) e a movimentação do estoque ficam no `game` do provedor: `g.record`, `g.ledger`, `g.daily`, `g.moves`. `spend`/`earn` recebem a categoria.
- `Providers.onClose` desliga as casas do provedor e chama `destroy()` no rack e na equipe. O rack cria tudo numa pasta `RackDoProvedor` dentro do prédio, então fechar não deixa lixo.

Os Remotes do console, da loja e do rack são únicos para o jogo inteiro. `RackModule.start()` encaminha cada pedido para o rack de `Providers.of(player)`.

## Grafo da rede (`shared/NetworkGraph.luau`)

- **Nós:** upstream, roteador, DNS, OLT, splitter, CTO, ONU.
- **Arestas:** núcleo, tronco, distribuição, drop.
- Cada nó e aresta tem estado (`ok`, `failed`, `broken`, `dirty`).
- `computeOnus()` percorre cada ONU até a OLT do provedor dela e calcula o sinal em dBm e o motivo da queda.
- **Rede neutra:**
  - Os nós do núcleo têm `provider` (1 ou 2). Os ids do prédio 2 têm sufixo: `ROUTER_2`, `OLT_2` etc. (`Net.coreId`).
  - Os splitters guardam `parentBy[slot]`, que é o tronco de cada provedor (`TRONCO`/`TRONCO2` do prédio 1 e `TRONCO_P2`/`TRONCO2_P2` do prédio 2).
  - Funções como `traceToOlt`, `signalAt`, `parentOf` e `onusBelow` recebem o provedor.

## Estado para os clientes

- **`ReplicatedStorage.GameState`:** `Day`, `Hour` e `GraceDays` (relógio da cidade).
- **`GameState.P1` / `GameState.P2`:**
  - Dados do provedor: `Open`, `Name`, `Price`, `Owner`, `Partners`.
  - Caixa: `Money`, `Reputation`, `Debt`.
  - Fase: `Phase`, `OpenedDay`, `LinkOn`, `Mood`.
  - Itens: `Stock_*`, `Owns_*`.
- **Atributos do jogador:**
  - `Slot`: o prédio do provedor dele, ou nil.
  - `Wallet`: o dinheiro próprio dele.
- **`NocUpdate`:** foto da rede vista pelo provedor do jogador. As casas do concorrente aparecem com contrato `rival`.

## Remotes (`server/Remotes.luau`)

| Remote | Direção | Uso |
| --- | --- | --- |
| `NocUpdate` | servidor → cliente | estado da rede a cada segundo |
| `Notify` | servidor → cliente | avisos no HUD |
| `Dialog` | servidor → cliente | conversa com morador |
| `DaySummary` | servidor → cliente | fechamento do dia |
| `Bankrupt` | servidor → cliente | tela de falência |
| `ProviderMenu` / `ProviderAction` | ambos | menu Provedor (abrir, entrar, aportar, renomear, preço) |
| `ShopOpen` / `ShopBuy` | ambos | terminal de compras |
| `RackMenu` / `RackAction` | ambos | menu Opções do equipamento |
| `ConsoleOpen`, `ConsoleCommand`, `ConsoleComplete` | ambos | consoles (linha digitada e TAB) |
| `WikiOpen` | servidor → cliente | quiosque da wiki |
| `ErpOpen` / `ErpAction` | ambos | tela do ERP (abrir, agendar, cancelar, abrir OS, comprar, contratar) |

## Onde mexer

| Arquivo | O que tem |
| --- | --- |
| `shared/Config.luau` | Preços, tempos, limites de sinal, regras de prazo e preço |
| `shared/Wiki.luau` | Páginas da wiki do jogo e o changelog |
| `shared/Dialogs.luau` | Falas dos moradores |
| `server/Providers.luau` | Abrir, sócio, aporte, nome, preço, herança e fechamento |
| `server/GameService.luau` | Relógio e caixa de cada provedor |
| `server/NetworkService.luau` | Grafo da rua, casas, ferramentas, reparos, escolha pelo preço |
| `server/RackService.luau` | Rack, loja, ficha, PCs do NOC e consoles |
| `server/Cli/*.luau` | Comandos do roteador, da OLT e do Ubuntu |
| `server/ResidentService.luau` | Moradores: humor, falas, visitas e manifestação |
| `server/TechService.luau` / `CarService.luau` | Equipe de rua e carro |
| `server/WorldBuilder.luau` | Cidade e prédios |
| `client/Hud.client.luau` | HUD, menu Provedor, tablet, resumo do dia, falência |
| `client/NocScreens.client.luau` | Telas do NOC |
| `client/Console.client.luau` | Console e terminal de compras |
