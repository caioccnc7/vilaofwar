-- Falas dos moradores. Cada situação tem várias opções para não repetir.
-- Os moradores são o termômetro do provedor: o que eles falam mostra como a rede está.

local Dialogs = {}

Dialogs.Bubble = {
	online_happy = {
		"A internet tá voando hoje!",
		"Baixei o jogo novo em dez minutos!",
		"Melhor provedor da Vila Aurora.",
		"Chamada de vídeo sem travar nenhuma vez.",
		"Até o Wi-Fi do quintal tá bom.",
	},
	online_neutral = {
		"Hoje tá funcionando, ainda bem.",
		"Tá ok... por enquanto.",
		"Vamos ver se dura até a noite.",
	},
	online_grumpy = {
		"Voltou, mas eu ainda tô de olho.",
		"Ontem foi um sufoco, hein.",
		"Se cair de novo eu cancelo.",
	},
	slow = {
		"O vídeo tá travando de novo...",
		"Tá lento demais pra hora do jogo.",
		"Todo mundo em casa e a internet arrastando.",
		"Contratei 300 mega e parece 3.",
	},
	nodns = {
		"O Wi-Fi conecta mas nenhum site abre, que estranho.",
		"Tá conectado, mas o navegador diz que não achou o site.",
		"O WhatsApp até manda, mas nada carrega.",
	},
	unstable = {
		"Cai e volta, cai e volta, o dia todo.",
		"A luz da ONU fica piscando vermelho às vezes.",
		"Toda hora a chamada corta no meio.",
	},
	offline = {
		"Tô sem internet desde agora há pouco!",
		"Caiu tudo aqui em casa.",
		"Alguém sabe se caiu pra todo mundo?",
		"Nem sinal de internet!",
	},
	offline_onu = {
		"A luz da caixinha apagou, nem acende mais.",
		"Deu um estalo na caixinha da internet e apagou.",
	},
	offline_long = {
		"Vou cancelar e contratar outro provedor.",
		"Já liguei três vezes e nada!",
		"Vou lá no provedor reclamar pessoalmente.",
	},
	nocontract = {
		"Quando vão instalar minha internet?",
		"Queria tanto ter fibra aqui em casa...",
		"Meus vizinhos têm internet e eu não.",
	},
	cancelled = {
		"Cancelei. Se melhorar, quem sabe eu volto.",
	},
	-- sem internet, dentro do prazo de implantação: curiosos, sem reclamar
	waiting = {
		"Dizem que vai chegar fibra aqui na vila!",
		"Já tô até escolhendo o plano.",
		"Vi o pessoal do provedor passando com ferramenta.",
		"Será que minha casa entra na primeira leva?",
	},
	-- sem internet, depois do prazo: impacientes
	waiting_late = {
		"Já passou do prazo e nada de internet!",
		"Prometeram fibra e até agora nada.",
		"Tô usando o 4G da vizinha, que vergonha.",
		"Se não instalarem logo, vou na frente do provedor.",
	},
	-- na frente do provedor, perguntando
	visit = {
		"Bom dia! Quando chega a internet lá em casa?",
		"Oi! Já tem previsão pra minha rua?",
		"Passei só pra saber quando vão instalar a fibra.",
		"Quero ser o primeiro cliente! Quando começa?",
	},
	visit_late = {
		"E aí, cadê minha internet? O prazo já acabou!",
		"Vim de novo perguntar da instalação. Nada ainda?",
		"Até quando eu vou ficar sem internet?",
	},
	-- manifestação na frente do provedor
	protest = {
		"Queremos internet! Queremos internet!",
		"Cadê a fibra? Cadê a fibra?",
		"Prometeu, tem que cumprir!",
		"Internet já!",
		"Vila Aurora quer conexão!",
	},
}

-- Cartazes da manifestação (um por morador)
Dialogs.Signs = {
	"QUEREMOS INTERNET!",
	"CADÊ A FIBRA?",
	"INTERNET JÁ!",
	"PROMETEU, CUMPRA!",
	"VILA SEM SINAL",
	"CHEGA DE ESPERAR",
}

-- Fala longa quando o jogador conversa (ProximityPrompt).
Dialogs.Talk = {
	online = "Por aqui tá tudo funcionando. Obrigado pelo serviço!",
	slow = "Tá conectando, mas tá muito lento, principalmente agora. Parece que todo mundo usa ao mesmo tempo.",
	nodns = "O celular mostra o Wi-Fi conectado, mas nenhum site abre. Esquisito, né?",
	unstable = "A internet cai e volta sozinha. A luz da ONU às vezes fica vermelha. Será que é o cabo?",
	offline = "Tô sem internet. A luz da ONU tá acesa, mas a de sinal tá vermelha.",
	offline_onu = "A caixinha da internet apagou de vez, nem a luz de energia acende.",
	nocontract = "Ainda não tenho internet. Instala pra mim? Pago a taxa de instalação na hora!",
	cancelled = "Cancelei o plano. Se vocês instalarem de novo, eu dou mais uma chance.",
	waiting = "Ainda não tenho internet, mas soube que o provedor tá montando a rede. Quando ficar pronto, instala lá em casa? Pago a taxa de instalação na hora!",
	waiting_late = "O prazo pra internet chegar já passou e eu continuo sem. Cada dia que passa minha paciência diminui. Instala logo, por favor!",
	protest = "Estamos aqui na frente porque a vila tá sem internet! Só saio daqui quando a internet chegar!",
}

Dialogs.NeighborHint = "E olha, o vizinho também falou que caiu na mesma hora."
Dialogs.AloneHint = "Os vizinhos disseram que lá tá funcionando, só aqui que não."

function Dialogs.pick(list: { string }): string
	return list[math.random(1, #list)]
end

return Dialogs
