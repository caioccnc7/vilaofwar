# Changelog

Tudo o que entrou no jogo, do mais novo para o mais antigo. É o mesmo conteúdo da página **Novidades** da wiki do jogo (`src/shared/Wiki.luau`).

## 10/11/2026 · OLT passo a passo

- Página da OLT refeita como passo a passo numerado, do autofind até o cliente navegando, com uma lista de erros comuns e o que fazer em cada um.
- Botões usar da wiki preenchem o SN, a porta e o ONTID reais que apareceram no console (antes vinha um SN de exemplo).
- OLT mais clara: autofind vazio diz o motivo, o ont add recusa SN de exemplo, avisa quando o SN não é de nenhuma casa e mostra o service-port pronto para o próximo passo. Consultas gerais (service-port, current-configuration, by-sn) também valem dentro da placa GPON.
- Roteador e OLT só queimam depois de 5 dias no rack (antes podia acontecer no dia 2).

## 10/11/2026 · cidade ampliada

- Cidade muito maior, ocupando todo o terreno: Avenida Central, Avenida Sul, Rua da Serra e Rua do Rio, parque com lago, campo de futebol e a Praça da Chegada, onde todo mundo nasce.
- Jardim das Acácias, o bairro nobre: 8 mansões com piscina e jardim (casas 17 a 24, CTOs E e F). Moradores chiques (terno, vestido, pérolas), exigentes, que aceitam pagar R$ 70 a R$ 120 por dia.
- Lotes de provedor: a cidade começa sem prédios de provedor. São 5 lotes; quem abre um provedor escolhe o lote e o prédio é construído na hora (obra de R$ 2.500). Cada jogador só pode ser dono de 1. Os outros entram como sócios.
- Centro Cívico: Prefeitura, Escola Municipal, Delegacia de Polícia e Hospital Municipal (casas 25 a 28, CTO G).
- Licitações (tecla L, botão Licitações ou mural da Prefeitura): os donos de provedor disputam os prédios públicos com proposta de preço. Menor preço vence; atestado de 3 clientes online, contrato de 5 dias, 1 dia para instalar, SLA por órgão e multa de R$ 1.500.
- Montanhas, morros e mata de pinheiros em volta da cidade.
- Rede: 4 splitters na rua (Principal, Palmeiras, Acácias e Centro Cívico) e 7 CTOs. Cada prédio novo puxa um tronco até cada splitter pela linha de postes.

## 10/11/2026

- OLT: consultas (display ont autofind, display ont info 0 1 <porta> all, display service-port...) funcionam em qualquer modo. Comando digitado no modo errado agora explica em que modo ele roda e o caminho até lá. Wiki com o prompt real (MA5800-X7).
- Ativação pelo ERP: com a OLT configurada (primeiro cliente ativado à mão), as casas instaladas aparecem em Ativação na OLT. O botão Ativar ou a atendente fazem o ont add e o service-port.
- ERP do provedor (tecla O, botão ERP ou computador da recepção): ordens de serviço, agenda e fila de cada técnico, receitas e despesas com extrato, e estoque com mínimo e movimentação.
- Instalações pedidas pelos moradores: quem escolheu o seu provedor vai ao balcão da recepção pedir a internet. Sem OS de instalação, não dá para instalar.
- Chamados viram OS de reparo. Os técnicos só trabalham com OS agendada: instalam casas novas e procuram o defeito na rua; se a rua está boa, avisam que o problema é no rack ou na OLT.
- Atendente do escritório contratável (R$ 120 por dia): registra e agenda as OS sozinha no expediente.
- ONU só queima depois de 5 dias de uso, contados da instalação ou da última troca.
- Caixa da casa organizada: um aviso só (Opções, E) abre um painel com o estado da casa e as ações por tecla: medir sinal (E), refazer conector (F), trocar ONU (R) ou instalar internet (E). Os avisos não ficam mais um em cima do outro.
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
