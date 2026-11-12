# Testes

## Comandos de teste no Studio

Durante o Play, abra o Command Bar, troque para o lado do **servidor** e use o `BindableFunction` `FibraTeste`. O Command Bar não enxerga o `_G` dos scripts, por isso o atalho é um objeto.

```lua
local F = game.ServerStorage.FibraTeste
F:Invoke("abrir", "Nome")        -- o 1º jogador abre um provedor
F:Invoke("alvo", 2)              -- os próximos comandos valem para o prédio 2
F:Invoke("escolhas")             -- casa=provedor escolhido/preço máximo (* = cliente)
F:Invoke("link")                 -- contrata o link de graça
F:Invoke("kit")                  -- ferramentas + 1 pacote de cada insumo
F:Invoke("dinheiro", 5000)
F:Invoke("tecnico")              -- contrata um técnico de graça
F:Invoke("carro")                -- compra o carro de graça
F:Invoke("equipe")               -- resumo da equipe e do carro
F:Invoke("hora", 18)             -- pula o relógio
F:Invoke("prazo")                -- pula para depois do prazo do provedor alvo
F:Invoke("humor", 4)             -- humor de todos (4 = manifestação, 0.2 = falência)
F:Invoke("semnet", 3)            -- casa 3 a 10 s de cancelar
F:Invoke("romper", "TRONCO2")    -- rompe um cabo específico
F:Invoke("incidente", "cut")     -- também: onu, dirty, dns, hw (onu só com ONU de 5+ dias)
F:Invoke("atendente")            -- contrata a atendente de graça
F:Invoke("pedido", 3)            -- o morador da casa 3 pede instalação (abre OS)
F:Invoke("os")                   -- resumo das OS do ERP
F:Invoke("envelhecer", 5)        -- ONUs instaladas ficam 5 dias mais velhas
F:Invoke("lote", 4)              -- o 1º jogador constrói o provedor no lote 4
F:Invoke("sinal", 3)             -- caminho óptico da casa 3 até a OLT do alvo (mostra SN e porta PON)
F:Invoke("licitacao")            -- abre todas as licitações agora
F:Invoke("atestado", 0)          -- muda quantos clientes online o atestado pede (só nesta sessão)
F:Invoke("proposta", 180)        -- o provedor alvo propõe R$ 180 em todas as abertas
F:Invoke("resultado")            -- fecha as licitações abertas e escolhe o vencedor
F:Invoke("licitacoes")           -- resumo das licitações
F:Invoke("ir", 25)               -- leva o 1º jogador até a casa (ou prédio público) N
```

## Roteiro manual (1 jogador)

1. Ao entrar, o menu Provedor abre e o HUD mostra "Você: R$ 12000".
2. Abra um provedor com nome. Confira:
   - o nome na fachada;
   - o caixa de R$ 12000;
   - a barra amarela do prazo.
3. Pelo menu P, mude o nome e o preço. Com `escolhas`, veja os moradores trocando de escolha quando o preço passa do máximo deles.
4. `prazo` e depois `humor 4`: aparecem a faixa vermelha e os cartazes na frente do prédio.
5. `humor 0.2`: aparece a tela de falência, o prédio volta a "PRÉDIO DISPONÍVEL" e a carteira volta a R$ 12000.
6. Abra outro provedor no prédio 2. O rack, a loja e os PCs devem funcionar lá.

## Roteiro do ERP (1 jogador)

1. `abrir`, `link`, `kit`. Em até ~1 min, moradores vão ao balcão e abrem OS de instalação (alarme "ERP" no NOC).
2. Tecla O: a aba Ordens mostra as OS "aguardando agendamento". Agende uma: sem técnico ela fica com a equipe.
3. Caixa de uma casa sem OS: o botão Instalar fica bloqueado com o aviso do ERP. Na casa com OS, instale: a OS vira "concluída".
4. `tecnico` e `atendente`: a atendente aparece atrás do balcão, agenda as OS pendentes e o técnico vai instalar sozinho (fila dele na aba Equipe).
5. `romper DIST_A` com clientes na CTO A: depois de 45 s as casas ligam (OS de reparo), o técnico emenda e as outras OS fecham sozinhas.
6. `incidente onu` logo após instalar não faz nada. `envelhecer 5` e `incidente onu` queima uma ONU. O mesmo vale para `incidente hw` (roteador e OLT).
7. Aba Receitas e despesas: compras, instalações e (depois de `hora 19.9`) mensalidades, link e salários. Aba Estoque: movimentação com a OS de cada uso.

## Roteiro da OLT e da ativação pelo ERP

1. Console da OLT no modo `MA5800-X7>`: `display ont autofind all` e `display service-port all` respondem (sem `enable`).
2. Ainda no `>`: `ont add 0 sn-auth X` responde que o comando é do modo placa GPON e mostra `enable, config, interface gpon 0/1`. No `(config-if-gpon-0/1)#`, `service-port ...` manda dar `quit`.
3. Instale uma casa: o ERP mostra a seção Ativação na OLT com o botão Ativar cinza e o aviso de OLT não configurada.
4. Ative essa casa à mão (ont add + service-port). Instale outra: Ativar fica azul e funciona; `display current-configuration` mostra a ONT `casa<N>` e o service-port novo.
5. Com a atendente contratada no expediente, a próxima casa instalada é ativada sozinha e a OS de instalação ganha a nota "Ativada na OLT por ...".

## Roteiro da cidade ampliada e das licitações

1. `lote 3`, `rack`, `kit`, `instalar 25` e `sinal 25`: o caminho tem que passar por `CTO_G`, `SPL4` e `TRONCO3_SPL4`.
2. `atestado 0`, `licitacao`, `proposta 210`, `resultado`, `licitacoes`: Prefeitura, Delegacia e Hospital ficam com o provedor; a Escola recusa (R$ 210 passa da referência de R$ 200). `os` mostra as OS de instalação.
3. Tecla L: a tela mostra os contratos, o prazo de instalação e o próximo edital.
4. O `olt` do debug não tem autofind (lista vazia). Para o primeiro `ont add`, pegue o SN com `sinal N`.

Testado em 10/11/2026 com 1 jogador. Falta testar com 2+ jogadores e no simulador de celular.

## Roteiro do DDoS e da loja (1 jogador, dois provedores)

Os comandos de teste valem para o alvo (`alvo N`). `rival N` abre um provedor sem dono no lote N, para ter dois provedores com um jogador só.

1. `rival 2`, `alvo 2`, `rack`. Depois `lote 1`, `rack` e `kit` (o alvo passa a ser o prédio 1).
2. `ddos "2 syn 3 10"`: o prédio 1 ataca o 2 com 10 bots de teste por 3h. `ataques` mostra kpps, carga e efeito (carga 1,33 = fora do ar). Alarme "CPU do roteador alta" no NOC do prédio 2.
3. `alvo 2` e `roteador "/tool torch interface=ether1"`: linhas tcp vindas de 45.170.81.x. `roteador "/ip settings set tcp-syncookies=yes"` e `ataques`: a carga cai pela metade.
4. `roteador "/ip firewall filter add chain=input protocol=tcp tcp-flags=syn connection-limit=100,32 action=drop"`: carga cai para 0,2 e o efeito some. Em 30 min de jogo a botnet desiste.
5. `ddos "1 dns 2 10"` (prédio 2 ataca o 1). Com o DNS aberto, o efeito é "unstable". A regra raw com `src-port=53` sem exceção derruba o DNS (casas "Sem DNS"); com `src-address-list=!dns-confiaveis` e a lista certa, o DNS volta e o efeito vira "slow".
6. `guerra "amp"` no prédio 2 e de novo `ddos "1 dns 2 30"`: acima de 1,5x o link, as casas caem. Tecla K > Defesa > Pedir blackhole: o ataque para, chega o relatório com a origem e as casas ficam 1h fora.
7. Denúncia: vá até a Delegacia (`ir 27`) e aperte E no balcão de ocorrências. O atacante paga a multa e perde reputação.
8. Loja: `robux "reforco"` põe R$ 10.000 no caixa. `vip` liga o Passe VIP (fachada dourada em até 5 s e colete no personagem depois de renascer).
9. Tecla K: confira as três abas, os ✔/✘ das defesas e o botão Loja. Repita no Device Simulator (iPhone XR).

Com IDs reais em `Config.Robux`, teste a compra de verdade no Studio (o Roblox simula a compra sem cobrar).

## Roteiro com 2 jogadores (ainda pendente)

No Studio, use Teste > Servidor e clientes com 2 jogadores, ou entre com duas contas.

1. Jogador A abre o prédio 1 e jogador B entra como sócio. B aporta dinheiro e o caixa sobe.
2. A sai do jogo: B vira dono e fica com o caixa.
3. Com A e B em provedores diferentes, preços diferentes mudam a escolha dos moradores. As casas do outro aparecem roxas no NOC e não dá para instalar nelas.
4. O rompimento de um cabo da rua derruba clientes dos dois provedores.
