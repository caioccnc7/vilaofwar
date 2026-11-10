-- Planta da Vila Aurora: ruas, lotes de provedor, prédios públicos e bairros.
-- Só dados (sem peças): o servidor monta o mapa a partir daqui (WorldBuilder) e o
-- NOC desenha o mapa da rede com as mesmas ruas.
--
-- Eixos: X cresce para o leste, Z cresce para o sul. Toda rua tem 24 studs de
-- largura (12 para cada lado do eixo) e calçada de 6 studs.

local CityMap = {}

-- Área da cidade (o "quadrado" verde). Fora dela ficam as montanhas.
CityMap.Bounds = { minX = -390, maxX = 620, minZ = -430, maxZ = 470 }

CityMap.RoadHalf = 12

-- axis "x": rua leste-oeste no z = at, de x = from até x = to
-- axis "z": rua norte-sul no x = at, de z = from até z = to
CityMap.Roads = {
	{ name = "Rua Principal", axis = "x", at = 0, from = -300, to = 540 },
	{ name = "Avenida Central", axis = "x", at = -300, from = -300, to = 540 },
	{ name = "Avenida Sul", axis = "x", at = 200, from = -300, to = 540 },
	{ name = "Alameda das Acácias", axis = "x", at = 330, from = -300, to = 260 },
	{ name = "Rua das Palmeiras", axis = "z", at = 300, from = -300, to = 0 },
	{ name = "Rua da Serra", axis = "z", at = -300, from = -300, to = 330 },
	{ name = "Rua do Rio", axis = "z", at = 540, from = -300, to = 200 },
}

-- Lotes onde um provedor pode construir o prédio. O prédio é sempre igual e de
-- frente para uma rua leste-oeste (lado norte da rua); "offset" é o deslocamento
-- em relação ao lote 1. Terreno do prédio + garagem: x -150..-61, z -60..-17.
CityMap.Lots = {
	{ id = 1, offset = { 0, -0 }, street = "Rua Principal", place = "perto da praça" },
	{ id = 2, offset = { 290, 0 }, street = "Rua Principal", place = "perto da Rua das Palmeiras" },
	{ id = 3, offset = { 0, -300 }, street = "Avenida Central", place = "lado oeste" },
	{ id = 4, offset = { 450, -300 }, street = "Avenida Central", place = "lado leste" },
	{ id = 5, offset = { 450, 200 }, street = "Avenida Sul", place = "perto do Jardim das Acácias" },
}
CityMap.LotRect = { x0 = -150, x1 = -61, z0 = -60, z1 = -17 }
CityMap.IspRect = { x0 = -148, x1 = -92, z0 = -58, z1 = -22 } -- só o prédio

-- Prédios públicos (clientes das licitações), na calçada sul da Avenida Central,
-- de frente para a avenida. x = centro, w = largura, d = profundidade.
CityMap.Civic = {
	{ key = "prefeitura", x = -40, w = 58, d = 34 },
	{ key = "escola", x = 62, w = 52, d = 30 },
	{ key = "policia", x = 142, w = 40, d = 28 },
	{ key = "hospital", x = 222, w = 54, d = 34 },
}
CityMap.CivicFrontZ = -272 -- frente dos prédios públicos (a calçada da avenida vai até -282)

-- Jardim das Acácias (bairro nobre): mansões dos dois lados da Alameda
CityMap.MansionXs = { -200, -80, 40, 160 }
CityMap.MansionNorthZ = 280 -- centro das mansões do lado norte (frente para o sul)
CityMap.MansionSouthZ = 380 -- centro das mansões do lado sul (frente para o norte)

-- Áreas verdes e pontos de interesse (usados pelo mapa do NOC e pelos passeios)
CityMap.Park = { x0 = -55, x1 = 245, z0 = -222, z1 = -72 } -- Parque da Vila, atrás dos prédios públicos
CityMap.Field = { x = -180, z = 120 } -- campo de futebol
CityMap.CitySpawn = { x = -230, z = 40 } -- ponto de chegada de quem entra no jogo (Praça da Chegada)

return CityMap
