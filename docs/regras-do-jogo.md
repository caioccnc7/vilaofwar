# Regras do jogo

Estas regras foram combinadas com o Caio (dono do projeto). Os números ficam em `src/shared/Config.luau`, então dá para balancear sem mexer no resto do código.

## Relógio

- O expediente vai das 8h às 20h. Cada hora de jogo dura 60 segundos, então um dia de jogo leva 12 minutos.
- O relógio é um só para a cidade inteira. No fechamento de cada dia, cada provedor recebe o seu resumo.

## Mundo aberto e provedores

- A cidade começa **sem prédios de provedor**. Há **5 lotes** fixos no mapa (`Shared/CityMap`), cada um com uma placa "Construir".
- Cada jogador pode ser dono de **um** provedor. O servidor aceita mais de 5 jogadores: quem fica sem lote entra como **sócio**.
- Construir custa **R$ 2.500** (`Config.Lots.BuildCost`), pagos da carteira do dono. O resto da carteira vira o caixa do provedor.
- Cada jogador chega com **R$ 12.000 próprios**, guardados no atributo `Wallet`.
- Pelo menu **Provedor** (tecla P), o jogador pode:
  - **Construir o prédio:** escolhe um lote livre e um nome. Vira o dono, e o dinheiro dele vira o caixa do provedor.
  - **Entrar como sócio:** passa a trabalhar num provedor que já existe e pode **aportar** o próprio dinheiro no caixa.
  - **Renomear** o provedor. O nome aparece na fachada.
  - **Mudar o preço** da mensalidade, de R$ 10 a R$ 120 por dia.
- Só a equipe do provedor usa o terminal de compras, o rack, os PCs do NOC e o carro do prédio dele.
- **Dono sai do jogo:** o sócio que entrou por último vira dono e fica com o caixa.
- **Ninguém sobra:** o provedor fecha, as casas dele ficam livres, o prédio é desmontado e o lote volta a ficar livre.

## Rede neutra

- Postes, splitters, CTOs e drops são de todos. Cada provedor liga a **própria OLT** na mesma rua, por troncos próprios.
- Um rompimento no cabo da rua derruba os clientes dos dois provedores. Qualquer equipe pode consertar.

## Disputa pelos moradores

- Quem já tem contrato fica com o provedor dele e **mantém o preço do contrato até cancelar**.
- A disputa é só por quem **nunca contratou ou cancelou**:
  - Cada morador tem um preço máximo, sorteado entre R$ 35 e R$ 75.
  - Ele escolhe o provedor **mais barato** que caiba nesse preço. No empate, vence quem tem mais estrelas de reputação.
  - Só dá para instalar internet na casa que escolheu o seu provedor.

## Começo sem internet

- O provedor abre com o rack vazio, sem link, sem ferramentas e sem estoque.
- É preciso contratar o link da operadora (R$ 800 de ativação e R$ 1 por Mbps por dia). Depois comprar e configurar o roteador e a OLT e ligar as casas.
- O capital inicial cobre tudo isso para as 16 casas (cerca de R$ 9.650) e ainda sobra uma reserva.

## Prazo, manifestação e falência (por provedor)

- **Prazo de implantação:** 3 dias de jogo contando o dia em que o provedor abriu. Nesse período, quem escolheu o provedor e ainda está sem internet só passa na frente do prédio para perguntar quando a internet chega.
- Depois do prazo, a paciência dessas pessoas cai aos poucos.
- **Moradores (%):** média do humor dos moradores do provedor, ou seja, os clientes e quem escolheu ele.
- **Manifestação:** depois do prazo, se a média ficar abaixo de 5%, os moradores protestam com cartazes na frente do prédio. A manifestação acaba quando a média passa de 10%.
- **Falência:** se a média chegar a 0%, o provedor fecha e as casas dele ficam livres. A equipe recebe de novo R$ 12.000 para recomeçar.

## Clientes

- O morador que escolheu um provedor vai ao balcão da recepção pedir a internet. O pedido vira uma **OS de instalação** no ERP. Sem essa OS, ninguém instala a casa.
- Se o morador escolher outro provedor (preço), a OS é cancelada e ele pede no outro.
- O cliente sem internet há 45 s liga para o provedor: vira uma **OS de reparo**. Ela fecha sozinha quando a internet volta.
- Uma ONU só queima depois de **5 dias de jogo** de uso, contados da instalação ou da última troca (`Config.Onu.MinAgeDays`).
- O cliente só cancela depois de **1 dia inteiro** de expediente sem internet (12 horas de jogo seguidas).
- Cada cliente paga, por dia, o preço do contrato dele. A instalação rende R$ 100.
- Há multa de SLA de R$ 5 por cliente por hora sem internet.

## Equipe e carro

- Dá para contratar até 8 técnicos NPC:
  - R$ 300 na contratação e R$ 180 por dia de salário.
  - Rescisão de R$ 90 por dia trabalhado, com mínimo de R$ 180.
- Os técnicos só trabalham com OS agendada no ERP (fila no celular). Instalam casas novas e atendem reparos: procuram o defeito no caminho até a OLT (rompimento, ONU, conector). Se a rua está boa, encerram a OS com o diagnóstico e avisam no NOC.
- A fila de cada técnico: OS em execução, depois reparos, depois instalações, da mais antiga para a mais nova. Cada OS agendada vai para o técnico com menos serviço; sem técnico, fica com a equipe (jogadores).
- Atendente do escritório (`Config.Attendant`): R$ 200 na contratação, R$ 120 por dia, rescisão de R$ 60 por dia trabalhado (mínimo R$ 120). Das 8h às 18h registra e agenda cada OS em uns 6 s. Sem atendente, o jogador agenda pelo ERP.
- O carro da equipe custa R$ 3.500 e mais R$ 40 por dia. O jogador dirige. O técnico só usa o carro quando ele está na garagem.

## ERP

- Abre com a tecla O, o botão ERP ou o computador do balcão da recepção.
- Abas: Ordens de serviço, Equipe, Receitas e despesas, Estoque.
- Receitas e despesas por categoria (hoje e ontem) e extrato com os últimos 40 lançamentos.
- Estoque com mínimo por insumo (`Config.Erp.MinStock`, alarme no NOC abaixo dele), compra de pacote pelo ERP e movimentação (quem usou e em qual OS).
- Ativação na OLT: a OLT conta como configurada quando está ativa no rack e já tem pelo menos um service-port (primeiro cliente feito à mão no terminal). A partir daí, casas instaladas sem `ont add` ou sem `service-port` aparecem na seção Ativação na OLT; o botão Ativar ou a atendente (`Config.Attendant.ActivateSeconds` por casa, antes de agendar OS) fazem o `ont add` (ou `ont modify` se a ONU foi trocada, achando a ONT pelo desc `casa<N>`) e o `service-port` com VLAN 100, gemport 1.
- Casa sem internet só por causa da OLT (não autorizada ou sem service-port) não vira OS de reparo.

## Crédito do governo

- O programa Conecta Vila libera R$ 2.000 por pedido, uma vez por dia, com 10% de juros.
- A parcela é de R$ 300 por dia, e a dívida máxima é de R$ 6.600.

## Bairro nobre

- Jardim das Acácias: mansões 17 a 24 (CTOs E e F, splitter das Acácias). Os moradores aceitam pagar de R$ 70 a R$ 120 por dia (`Config.Nobre`).

## Licitações dos prédios públicos

Prefeitura (casa 25), Escola (26), Delegacia (27) e Hospital (28), na CTO G. Valores em `Config.Bids`; código em `server/LicitacaoService.luau`; tela em `client/Licitacoes.client.luau` (tecla L).

- O primeiro edital abre no **dia 2**. Fica aberto **3 horas** de jogo.
- Só o **dono** do provedor manda proposta (preço por dia), entre o piso (50% da referência) e a referência.
- **Menor preço vence.** Empate: maior reputação, depois quem mandou primeiro.
- **Atestado:** o provedor precisa ter **3 clientes online** quando o edital fecha, senão a proposta é desclassificada.
- Contrato de **5 dias**. O vencedor tem **1 dia** para instalar e ativar (OS aberta no ERP).
- SLA (horas seguidas sem internet): Prefeitura 4h, Escola 6h, Delegacia 3h, Hospital 2h. Estourou: multa de **R$ 1.500** e rescisão. Não instalou no prazo: mesma multa.
- Edital sem vencedor reabre em 2 horas. No fim do contrato abre um edital novo (renovação).

| Órgão | Referência (R$/dia) | SLA |
|---|---|---|
| Prefeitura | 300 | 4h |
| Escola | 200 | 6h |
| Delegacia | 250 | 3h |
| Hospital | 400 | 2h |
