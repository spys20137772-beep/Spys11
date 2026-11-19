-- 게임 전체 설정. 가격, 아이템, 게임패스 ID 등은 전부 여기서 바꾸면 됨.
local Config = {}

---------------------------------------------------------------------
-- 기본 설정
---------------------------------------------------------------------
Config.PLOT_COUNT = 6 -- 부지 개수 (= 서버 최대 인원 권장값)
Config.PLOT_SPACING = 130 -- 부지 사이 간격
Config.ROAD_HALF_WIDTH = 30 -- 가운데 도로 절반 폭

Config.START_CASH = 0
Config.CONVEYOR_SPEED = 8 -- 기본 컨베이어 속도
Config.MAX_ORES_PER_PLOT = 150 -- 렉 방지: 부지당 최대 광석 수
Config.ORE_LIFETIME = 30 -- 광석이 안 팔리면 이 시간(초) 뒤 삭제

---------------------------------------------------------------------
-- 환생
---------------------------------------------------------------------
Config.REBIRTH_BASE_COST = 150000
Config.REBIRTH_COST_GROWTH = 2.5 -- 환생할 때마다 비용 x2.5
Config.REBIRTH_BONUS = 0.5 -- 환생 1회당 수입 +50%

function Config.GetRebirthCost(rebirths: number): number
	return math.floor(Config.REBIRTH_BASE_COST * Config.REBIRTH_COST_GROWTH ^ rebirths)
end

function Config.GetMultiplier(rebirths: number, has2x: boolean?): number
	local m = 1 + rebirths * Config.REBIRTH_BONUS
	if has2x then
		m *= 2
	end
	return m
end

---------------------------------------------------------------------
-- 저장
---------------------------------------------------------------------
Config.DATASTORE_NAME = "TycoonData_v1"
Config.AUTOSAVE_INTERVAL = 60

---------------------------------------------------------------------
-- 결제 (Creator Dashboard에서 만든 ID를 넣기. 0이면 비활성화)
---------------------------------------------------------------------
Config.GAMEPASS_2X_CASH = 0 -- "수입 2배" 게임패스 ID

Config.CASH_PRODUCTS = { -- 개발자 상품 (돈 구매)
	{ Id = 0, Cash = 5000, Label = "💵 $5K 받기" },
	{ Id = 0, Cash = 50000, Label = "💰 $50K 받기" },
	{ Id = 0, Cash = 500000, Label = "🏦 $500K 받기" },
}

---------------------------------------------------------------------
-- 아이템 목록
-- 순서 = 버튼 위치 순서. Requires = 먼저 사야 버튼이 나타나는 아이템.
--
-- Type 종류:
--   Dropper       : X(컨베이어 위 위치), Value(광석 가치), Interval(초)
--   Upgrader      : X, Multiplier(광석 가치 배수)
--   ConveyorBoost : Speed
--   Walls / Lamps / Floor / Trees / Fountain : 장식
---------------------------------------------------------------------
Config.Items = {
	{
		Id = "Dropper1", Name = "기본 드로퍼", Price = 0, Type = "Dropper",
		X = -36, Value = 3, Interval = 2,
		Color = Color3.fromRGB(150, 150, 155), OreColor = Color3.fromRGB(110, 110, 110), OreMaterial = Enum.Material.Slate,
	},
	{
		Id = "Dropper2", Name = "구리 드로퍼", Price = 40, Type = "Dropper", Requires = "Dropper1",
		X = -26, Value = 5, Interval = 2,
		Color = Color3.fromRGB(196, 112, 60), OreColor = Color3.fromRGB(205, 127, 50), OreMaterial = Enum.Material.Metal,
	},
	{
		Id = "Upgrader1", Name = "세척기 (x1.5)", Price = 120, Type = "Upgrader", Requires = "Dropper2",
		X = 20, Multiplier = 1.5,
		Color = Color3.fromRGB(80, 200, 255),
	},
	{
		Id = "Walls", Name = "벽 세우기", Price = 200, Type = "Walls", Requires = "Dropper2",
		Color = Color3.fromRGB(230, 220, 200),
	},
	{
		Id = "Dropper3", Name = "철 드로퍼", Price = 350, Type = "Dropper", Requires = "Upgrader1",
		X = -16, Value = 10, Interval = 2,
		Color = Color3.fromRGB(90, 100, 115), OreColor = Color3.fromRGB(160, 170, 180), OreMaterial = Enum.Material.DiamondPlate,
	},
	{
		Id = "Boost", Name = "고속 컨베이어", Price = 500, Type = "ConveyorBoost", Requires = "Dropper3",
		Speed = 14,
		Color = Color3.fromRGB(0, 255, 200),
	},
	{
		Id = "Dropper4", Name = "은 드로퍼", Price = 900, Type = "Dropper", Requires = "Dropper3",
		X = -6, Value = 20, Interval = 1.8,
		Color = Color3.fromRGB(200, 205, 215), OreColor = Color3.fromRGB(225, 230, 240), OreMaterial = Enum.Material.Foil,
	},
	{
		Id = "Lamps", Name = "가로등", Price = 1200, Type = "Lamps", Requires = "Walls",
		Color = Color3.fromRGB(255, 220, 140),
	},
	{
		Id = "Upgrader2", Name = "정제기 (x2)", Price = 2000, Type = "Upgrader", Requires = "Dropper4",
		X = 25, Multiplier = 2,
		Color = Color3.fromRGB(255, 90, 200),
	},
	{
		Id = "Dropper5", Name = "황금 드로퍼", Price = 4500, Type = "Dropper", Requires = "Upgrader2",
		X = 4, Value = 50, Interval = 1.5,
		Color = Color3.fromRGB(255, 200, 40), OreColor = Color3.fromRGB(255, 215, 0), OreMaterial = Enum.Material.Neon,
	},
	{
		Id = "Floor", Name = "고급 바닥", Price = 3000, Type = "Floor", Requires = "Lamps",
		Color = Color3.fromRGB(235, 235, 240),
	},
	{
		Id = "Trees", Name = "정원수", Price = 6000, Type = "Trees", Requires = "Floor",
		Color = Color3.fromRGB(60, 160, 70),
	},
	{
		Id = "Dropper6", Name = "다이아 드로퍼", Price = 15000, Type = "Dropper", Requires = "Dropper5",
		X = 14, Value = 120, Interval = 1.2,
		Color = Color3.fromRGB(80, 220, 255), OreColor = Color3.fromRGB(120, 240, 255), OreMaterial = Enum.Material.Glass,
	},
	{
		Id = "Fountain", Name = "분수대", Price = 25000, Type = "Fountain", Requires = "Trees",
		Color = Color3.fromRGB(80, 170, 255),
	},
	{
		Id = "Upgrader3", Name = "퀀텀 업그레이더 (x3)", Price = 40000, Type = "Upgrader", Requires = "Dropper6",
		X = 30, Multiplier = 3,
		Color = Color3.fromRGB(170, 80, 255),
	},
}

return Config
