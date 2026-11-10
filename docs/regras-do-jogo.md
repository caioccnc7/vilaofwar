# Regras do jogo

Estas regras foram combinadas com o Caio (dono do projeto). Os números ficam em `src/shared/Config.luau`, então dá para balancear sem mexer no resto do código.

## Relógio

- O expediente vai das 8h às 20h. Cada hora de jogo dura 60 segundos, então um dia de jogo leva 12 minutos.
- O relógio é um só para a cidade inteira. No fechamento de cada dia, cada provedor recebe o seu resumo.

## Mundo aberto e provedores

- A cidade tem **dois prédios** iguais. Cada um pode ter **um provedor** aberto. O servidor aceita no máximo dois provedores.
- Cada jogador chega com **R$ 12.000 próprios**, guardados no atributo `Wallet`.
- Pelo menu **Provedor** (tecla P), o jogador pode:
  - **Abrir provedor:** escolhe um prédio livre e um nome. Vira o dono, e o dinheiro dele vira o caixa do provedor.
  - **Entrar como sócio:** passa a trabalhar num provedor que já existe e pode **aportar** o próprio dinheiro no caixa.
  - **Renomear** o provedor. O nome aparece na fachada.
  - **Mudar o preço** da mensalidade, de R$ 10 a R$ 120 por dia.
- Só a equipe do provedor usa o terminal de compras, o rack, os PCs do NOC e o carro do prédio dele.
- **Dono sai do jogo:** o sócio que entrou por último vira dono e fica com o caixa.
- **Ninguém sobra:** o provedor fecha, as casas dele ficam livres e o prédio volta a ficar disponível.

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

- O cliente só cancela depois de **1 dia inteiro** de expediente sem internet (12 horas de jogo seguidas).
- Cada cliente paga, por dia, o preço do contrato dele. A instalação rende R$ 100.
- Há multa de SLA de R$ 5 por cliente por hora sem internet.

## Equipe e carro

- Dá para contratar até 8 técnicos NPC:
  - R$ 300 na contratação e R$ 180 por dia de salário.
  - Rescisão de R$ 90 por dia trabalhado, com mínimo de R$ 180.
- Os técnicos fazem sozinhos os reparos da rua, de dia, usando o estoque.
- O carro da equipe custa R$ 3.500 e mais R$ 40 por dia. O jogador dirige. O técnico só usa o carro quando ele está na garagem.

## Crédito do governo

- O programa Conecta Vila libera R$ 2.000 por pedido, uma vez por dia, com 10% de juros.
- A parcela é de R$ 300 por dia, e a dívida máxima é de R$ 6.600.
