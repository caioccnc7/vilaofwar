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
F:Invoke("incidente", "cut")     -- também: onu, dirty, dns, hw
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

## Roteiro com 2 jogadores (ainda pendente)

No Studio, use Teste > Servidor e clientes com 2 jogadores, ou entre com duas contas.

1. Jogador A abre o prédio 1 e jogador B entra como sócio. B aporta dinheiro e o caixa sobe.
2. A sai do jogo: B vira dono e fica com o caixa.
3. Com A e B em provedores diferentes, preços diferentes mudam a escolha dos moradores. As casas do outro aparecem roxas no NOC e não dá para instalar nelas.
4. O rompimento de um cabo da rua derruba clientes dos dois provedores.
