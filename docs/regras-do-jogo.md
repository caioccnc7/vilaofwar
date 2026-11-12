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
- Roteador e OLT só queimam depois de **5 dias de jogo** no rack, contados do dia em que foram instalados (`Config.Equip.MinAgeDays`).
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

## Guerra dos provedores: ataque DDoS

Combinado com o Caio em 12/11/2026. Os números ficam em `Config.Ddos`.

- **Quem ataca:** só o dono do provedor, pela tela Guerra (tecla K, aba Ataque). Provedor no prazo de implantação (3 dias) não ataca nem é atacado.
- **Força:** cada cliente online de quem ataca vira um bot (mínimo 3). Prédio público não entra.
- **Tipos:**
  - **SYN flood:** 20 mil pacotes/s por bot contra um roteador que aguenta 150 mil sem proteção. Carga ≥ 100%: clientes da vítima fora do ar; ≥ 50%: instáveis; ≥ 25%: lentos.
  - **Volumétrico (amplificação DNS):** 5 Mbps por bot vezes a amplificação (4x da internet + 4x por roteador da cidade com DNS aberto na WAN). Sem o Amplificador de tráfego, o ataque não passa de 95% do link da vítima (lento e instável). Acima de 1,5x o link, os clientes caem.
- **Duração:** de 1 a 8 horas de jogo. O teto é 8h porque o cliente cancela com 12h seguidas sem internet.
- **Custo para quem ataca:** os bots ficam com internet lenta durante o ataque (o humor cai), a botnet fica 12h em recarga e o ataque pode ser denunciado. Servidor C2 dobra a força.
- **Refletores:** cada roteador com DNS aberto na WAN gasta 30 Mbps do próprio link durante um ataque volumétrico de outro provedor.
- **Fim do ataque:** acaba o tempo, o atacante para, a vítima pede blackhole, os bots ficam sem internet, ou a vítima segura tudo por 30 minutos de jogo (a botnet desiste). Depois, a vítima fica 12h protegida.
- **Defesas e quanto deixam passar** (multiplicam entre si):
  - `tcp-syncookies=yes`: 50% do SYN flood.
  - Limite de conexões (`connection-limit` com `tcp-flags=syn`, ou a cadeia `detect-ddos` com `dst-limit`): 30%.
  - Lista negra com drop na tabela raw (automática pela `detect-ddos` ou com o bloco do atacante numa address-list): 30%.
  - Firewall dedicado (R$ 30.000): 10% do SYN flood.
  - Filtro `udp src-port=53` na raw: tira a instabilidade do volumétrico, mas não esvazia o link.
  - Appliance de scrubbing (R$ 60.000): 20% do volumétrico.
  - Anti-DDoS da operadora (R$ 400 de ativação + R$ 400 por dia): 5% de qualquer ataque, e manda o relatório da origem.
  - Blackhole (RTBH): grátis, encerra o ataque na hora, mas o IP da vítima fica 1h fora do ar.
- **Armadilhas reais:** regra que descarta `src-port=53` sem exceção para os DNS do roteador deixa todos os clientes Sem DNS. Regra que fecha `dst-port=53` sem `in-interface=ether1` fecha o DNS para os clientes.
- **Rastreio:** no SYN flood, o `whois` no PC do NOC de um IP visto no `/tool torch` registra a prova. No volumétrico, o torch mostra só refletores; a origem vem no relatório da operadora (anti-DDoS ou blackhole).
- **Denúncia:** balcão de ocorrências na frente da Delegacia (casa 27), em até 24h de jogo. O atacante paga R$ 3.000 de multa e perde 1 estrela; a vítima recebe R$ 1.500.
- **Reputação:** quem segura o ataque (prejudicado menos de 25% do tempo) ganha +0,3 estrela. O ajuste volta a zero aos poucos (0,25 por dia).
- **Equipamentos de guerra** (R$ do jogo, defesa mais barata que ataque): Firewall MikroTik CCR2216 R$ 30.000, Appliance Huawei AntiDDoS8000 R$ 60.000, Servidor C2 R$ 45.000, Amplificador de tráfego R$ 80.000. Ficam com o provedor enquanto ele existir.

## Loja com Robux

Combinado com o Caio em 12/11/2026. Os valores e IDs ficam em `Config.Robux`.

- **Pacotes de dinheiro do jogo** (Developer Products, podem ser comprados várias vezes): 49 Robux = R$ 10.000, 149 = R$ 35.000, 399 = R$ 100.000, 999 = R$ 300.000.
- O dinheiro vai para o caixa do provedor de quem comprou. Sem provedor, vai para a carteira do jogador. Vale para a partida (o jogo não guarda progresso).
- **Passe VIP** (Game Pass, 199 Robux): só visual. Fachada dourada no prédio enquanto alguém com o passe estiver na equipe, e uniforme VIP. Não dá vantagem.
- Muito difícil sem Robux, mas não impossível: um provedor bem tocado lucra algo como R$ 1.000 a R$ 2.500 por dia de jogo.
- Enquanto o ID do produto for 0 no `Config`, o item aparece como "Em breve" e não vende.
