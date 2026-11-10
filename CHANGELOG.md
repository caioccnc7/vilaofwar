# Changelog

Tudo o que entrou no jogo, do mais novo para o mais antigo. É o mesmo conteúdo da página **Novidades** da wiki do jogo (`src/shared/Wiki.luau`).

## 10/11/2026

- Wiki junto com o console: F1 ou o botão Wiki do console abre a wiki num painel ao lado, na página do equipamento em uso. Clique num comando da wiki para mandá-lo à linha do console.
- Mundo aberto: cada jogador chega com R$ 12000 e escolhe (tecla P) abrir o seu provedor ou entrar como sócio de outro, aportando o próprio dinheiro.
- Segundo prédio na cidade, igual ao primeiro. Até dois provedores por servidor, com caixa, rack, NOC, equipe e carro próprios. A rua é compartilhada (rede neutra).
- Nome do provedor e preço da internet editáveis. Quem já é cliente mantém o preço do contrato até cancelar.
- Concorrência: quem não tem contrato ou cancelou escolhe o provedor mais barato (empate: reputação). Cada morador tem um preço máximo.
- Se o dono sai do jogo, o último sócio vira dono e fica com o caixa. Sem ninguém, o provedor fecha. Prazo, manifestação e falência agora são de cada provedor.
- Começo novo: a vila começa sem internet, com o rack vazio e R$ 12000 em caixa. Contrate o link da operadora, compre e configure os equipamentos e ligue as casas até o fim do dia 3.
- Quem não tem internet passa na frente do provedor perguntando quando ela chega. Depois do prazo, a paciência acaba aos poucos.
- Manifestação na frente do provedor quando os moradores ficam abaixo de 5% depois do prazo, e falência em 0%.
- Terminais mais realistas: TAB completa comandos ou lista as opções em todos os consoles; roteador e OLT aceitam abreviações e ? de ajuda; a OLT avisa comando incompleto; roteador ganhou /log, /ip arp, /system clock e /tool traceroute.
- PCs do NOC e Notebook TI agora rodam Ubuntu: ls, cd, cat, ip a, ping com nomes do /etc/hosts, tracepath, nslookup, dig e ssh admin@borda-vila. O cabo de console abre com screen /dev/ttyUSB0 115200.
- Jogo ajustado para celular: terminal de compras, console, wiki, menu do rack, tablet e resumo do dia cabem na tela e têm um X para fechar. Botões de Wiki e Tablet na tela para quem joga sem teclado.
- Visual novo dos moradores: cada um tem cabelo, chapéu, óculos, barba, roupa e sapato próprios.
- Técnicos de uniforme: capacete com jugular, colete laranja refletivo, cinto de ferramentas, rádio, luvas e botas.
- Roteador e OLT do rack mais realistas: orelhas de fixação, portas RJ45 e SFP+, placas GPON com LED por porta e ventoinhas.
- Caixas da rua (CTO e splitter) com tampa, etiqueta, aviso de laser, prensa-cabos e cintas no poste. ONU das casas com antenas e etiqueta.
- Cidade maior: Rua das Palmeiras com 8 casas novas (9 a 16), tronco de fibra próprio, splitter e CTOs C e D.
- Equipe de técnicos: contrate quantos quiser (até 8), cada um com salário e rescisão próprios. Eles dividem os serviços.
- Carro da equipe: o chefe dirige e o técnico usa quando o carro está na garagem. Garagem ao lado do prédio.
- NOC mostra as duas ruas, a equipe e o carro no mapa. Tablet e telas em duas colunas para as 16 casas.
- Técnico de rua contratável: faz os reparos da rua de dia, recebe salário diário e tem rescisão ao ser demitido.
- Menu de ações do equipamento: um aviso só (Opções, E) abre um painel com o estado e as ações organizadas por tecla.
- Datacenter no 2º andar: andar inteiro para os equipamentos, com vista para a rua e painel de monitoramento.
- Cabos coloridos (vermelho, azul, amarelo) com etiqueta que só aparece de perto.
- Notebook do TI: terminal portátil com cabo de console direto no equipamento.
- Ferramentas e insumos agora são comprados. Estoque de ONU, fibra drop, tubetes e conectores.
- Terminal de compras com abas: Equipamentos, Ferramentas, Insumos e Financeiro.
- Capital inicial de R$ 12000, suficiente para o kit inicial.
- Crédito do governo para o dono do provedor.
- Cliente só cancela depois de 1 dia inteiro sem internet.
- Wiki do provedor dentro do jogo: tecla J, botão Wiki e quiosque na recepção.

## 09/11/2026

- Sala de rack realista: comprar, instalar, ligar, cabear e configurar equipamentos.
- Console com comandos reais: roteador MikroTik RouterOS e OLT Huawei MA5800.
- NOC com telão de topologia ao vivo e mapa da rua na parede.
- PCs do NOC com acesso remoto por SSH e Telnet.
- Manual de cada equipamento (tecla H no rack).
- Alarmes iguais agrupados num só.
- Novos problemas: DNS do upstream cai e equipamento queima.

## Infraestrutura do projeto

- 10/11/2026: código e documentação publicados no GitHub.
