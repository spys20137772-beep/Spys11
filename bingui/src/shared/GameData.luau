-- 빙의 대소동: 공용 데이터 (서버/클라이언트 둘 다 사용)
local GameData = {}

-- 원작 좌표(픽셀) -> 스터드 변환 비율
GameData.K = 64 / 600

---------------------------------------------------------------------
-- 몸 종류
-- Speed: 스터드/초, HP, Life: 빙의했을 때 버티는 시간(초)
---------------------------------------------------------------------
GameData.Bodies = {
	ghost = { Name = "혼이", Speed = 22, HP = 3, R = 1.2, Ability = "도약" },
	mouse = { Name = "쥐", Speed = 19, HP = 20, Life = 28, R = 0.9, Ability = "찍찍", Skill = { "땅굴", 5 } },
	cat = { Name = "고양이", Speed = 23, HP = 40, Life = 32, R = 1.2, Ability = "덮치기", Skill = { "담 넘기", 6 } },
	pigeon = { Name = "비둘기", Speed = 22, HP = 18, Life = 26, R = 1.1, Ability = "똥 폭격", Fly = true, Skill = { "급강하", 3 } },
	citizen = { Name = "시민", Speed = 16, HP = 60, Life = 38, R = 1.4, Ability = "펀치", Human = true, Skill = { "비명", 6 } },
	scientist = { Name = "과학자", Speed = 16, HP = 55, Life = 38, R = 1.4, Ability = "플라스크", Human = true, Key = "lab", Skill = { "투명 물약", 14 } },
	police = { Name = "경찰", Speed = 17.5, HP = 90, Life = 42, R = 1.5, Ability = "권총", Hostile = true, Human = true, Skill = { "수갑", 4 } },
	dog = { Name = "경찰견", Speed = 26, HP = 60, Life = 32, R = 1.3, Ability = "물기", Hostile = true, Skill = { "울부짖기", 8 } },
	hazmat = { Name = "퇴마사", Speed = 16, HP = 110, Life = 42, R = 1.5, Ability = "성수 뿌리기", Hostile = true, Human = true, Skill = { "성수 폭탄", 8 } },
	soldier = { Name = "군인", Speed = 18, HP = 130, Life = 48, R = 1.5, Ability = "소총", Hostile = true, Human = true, Key = "base", Skill = { "공습 요청", 18 } },
	robot = { Name = "보안 로봇", Speed = 16, HP = 220, Life = 55, R = 1.9, Ability = "레이저", Hostile = true, Key = "lab", Skill = { "EMP", 12 } },
	mutant = { Name = "실험체", Speed = 20, HP = 170, Life = 45, R = 1.6, Ability = "촉수 후려치기", Skill = { "분열", 15 } },
	car = { Name = "자동차", Speed = 36, HP = 150, Life = 50, R = 3, Ability = "빵빵", Vehicle = true, Skill = { "니트로", 6 } },
	pcar = { Name = "경찰차", Speed = 39, HP = 200, Life = 55, R = 3, Ability = "사이렌", Vehicle = true, Skill = { "니트로", 6 } },
	tank = { Name = "탱크", Speed = 16, HP = 900, Life = 90, R = 4, Ability = "포격", Vehicle = true, Hostile = true, Skill = { "연막탄", 12 } },
	exorcist = { Name = "대퇴마사", Speed = 15, HP = 1600, Life = 120, R = 2.2, Ability = "부적 난사", Hostile = true, Human = true, Boss = true, Skill = { "퇴마진", 10 } },
}

-- 이 구역에 있어도 의심받지 않는 몸
GameData.Allow = {
	lab = { scientist = true, robot = true, pigeon = true },
	base = { soldier = true, tank = true, pigeon = true },
}

GameData.KillPoints = {
	mutant = 40, mouse = 5, cat = 8, pigeon = 5, citizen = 10, scientist = 12, police = 20, dog = 15,
	hazmat = 25, soldier = 30, robot = 45, car = 30, pcar = 40, tank = 120,
}

---------------------------------------------------------------------
-- 경계 단계
---------------------------------------------------------------------
GameData.Stars = { 25, 70, 150, 280, 450 }
GameData.StarSub = {
	"경찰이 출동했다!",
	"경찰견과 경찰차까지!",
	"퇴마사가 온다! 영혼 상태 조심!",
	"군대 투입!",
	"로봇과 탱크까지!! 도시 비상사태!",
}
GameData.Responders = {
	[0] = {},
	{ { "police", 2 } },
	{ { "police", 4 }, { "dog", 2 }, { "pcar", 1 } },
	{ { "police", 4 }, { "dog", 2 }, { "pcar", 2 }, { "hazmat", 3 } },
	{ { "police", 3 }, { "dog", 2 }, { "pcar", 2 }, { "hazmat", 3 }, { "soldier", 4 } },
	{ { "police", 3 }, { "pcar", 2 }, { "hazmat", 4 }, { "soldier", 5 }, { "robot", 2 }, { "tank", 1 } },
}

function GameData.StarsFor(heat: number): number
	local s = 0
	for _, t in ipairs(GameData.Stars) do
		if heat >= t then
			s += 1
		end
	end
	return s
end

---------------------------------------------------------------------
-- 진화 (업그레이드)
---------------------------------------------------------------------
GameData.Upgrades = {
	{ Id = "life", Name = "깊은 빙의", Desc = "빙의한 몸이 버티는 시간 +25%", Max = 5, Icon = "💫" },
	{ Id = "dry", Name = "질긴 영혼", Desc = "영혼 상태 유지 시간 +2초", Max = 5, Icon = "🕯️" },
	{ Id = "jump", Name = "영혼 가속", Desc = "순간이동·도약 거리 +20%", Max = 5, Icon = "💨" },
	{ Id = "power", Name = "완전 장악", Desc = "빙의한 몸 공격력 +20%", Max = 5, Icon = "💪" },
	{ Id = "sneak", Name = "투명 영혼", Desc = "경계 상승 -12%", Max = 5, Icon = "🥸" },
	{ Id = "hp", Name = "영혼 보호막", Desc = "영혼 체력 +1", Max = 3, Icon = "🛡️" },
	{ Id = "boom", Name = "폭발 빙의", Desc = "몸을 떠날 때 그 몸이 펑! 터져요", Max = 3, Icon = "💥" },
	{ Id = "fear", Name = "공포의 강림", Desc = "빙의하는 순간 주변 사람이 기절해요", Max = 3, Icon = "😱" },
	{ Id = "polter", Name = "폴터가이스트", Desc = "영혼 상태 능력: 주변을 전부 날려버려요", Max = 3, Icon = "🌀" },
}

function GameData.UpgradeCost(level: number): number
	return math.floor(40 * 1.7 ^ level + 0.5)
end

function GameData.SoulRange(jumpLevel: number): number
	return 35 * (1 + 0.2 * jumpLevel)
end

---------------------------------------------------------------------
-- 미션 (순서대로 진행)
---------------------------------------------------------------------
GameData.Missions = {
	{ Id = "infect_mouse", Text = "쥐한테 빙의하기", Reward = 20, Tip = "쥐 쪽을 보고 B(E키)를 누르면 순간이동 빙의!" },
	{ Id = "cat_stall", Text = "고양이로 시장 가판대 털기", Reward = 30, Tip = "고양이 [덮치기]로 시장 가판대를 들이받아요." },
	{ Id = "fridge", Text = "냉장고 털어서 몸 회복하기", Reward = 30, Tip = "집 안으로 들어가서 냉장고 앞에서 상호작용!" },
	{ Id = "poop", Text = "비둘기 똥 5번 명중", N = 5, Reward = 40, Tip = "비둘기는 공원과 시장에 많아요." },
	{ Id = "fountain", Text = "사람 몸으로 분수에 퐁당!", Reward = 40, Tip = "시민을 조종해서 공원 분수로 걸어 들어가요." },
	{ Id = "infect_police", Text = "경찰 몸 빼앗기", Reward = 50, Tip = "경찰서 근처엔 냄새를 맡는 경찰견이 있어요!" },
	{ Id = "ppc", Text = "경찰서 컴퓨터로 수배 기록 지우기", Reward = 60, Tip = "사람 몸으로 경찰서 안 컴퓨터를 써요. 경계가 0이 돼요!" },
	{ Id = "stars2", Text = "경계 2단계 찍기", Reward = 50, Tip = "마구 깽판을 쳐요!" },
	{ Id = "house", Text = "건물 한 채 무너뜨리기", Reward = 60, Tip = "자동차로 들이받거나 총으로 쏴요. 초록 통도 잘 터져요!" },
	{ Id = "gate_lab", Text = "과학자로 연구소 문 열기", Reward = 80, Tip = "영혼은 벽을 통과해요! 담 안의 과학자에게 빙의해요." },
	{ Id = "specimen", Text = "실험체 풀어주기", Reward = 90, Tip = "연구소 안 초록 수조를 깨요. 실험체는 아무나 공격해요!" },
	{ Id = "infect_robot", Text = "보안 로봇 탈취하기", Reward = 100, Tip = "로봇은 연구소를 지켜요. 과학자 몸이면 의심받지 않아요." },
	{ Id = "gate_base", Text = "군인으로 군사기지 문 열기", Reward = 120, Tip = "군사기지는 도시 구석! 담을 통과해서 군인을 노려요." },
	{ Id = "infect_tank", Text = "탱크 탈취하기!", Reward = 200, Tip = "탱크에 영혼을 쏴서 빙의! 포격 조심." },
	{ Id = "tank5", Text = "탱크로 건물 5채 부수기", N = 5, Reward = 250, Tip = "포격하거나 그냥 밀고 들어가요!" },
	{ Id = "boss", Text = "대퇴마사 처치 또는 빙의", Reward = 400, Tip = "경계 5단계를 25초 넘게 버티면 등장! 약해지면 빙의할 수 있어요." },
	{ Id = "s5", Text = "경계 5단계에서 60초 버티기", N = 60, Reward = 300, Tip = "도시 전체가 너를 쫓는다!" },
}

---------------------------------------------------------------------
-- 도시
---------------------------------------------------------------------
GameData.BS = 64 -- 블록 간격 (스터드)
GameData.RW = 16 -- 도로 폭
GameData.NB = 9 -- 9x9 블록
GameData.WS = GameData.BS * GameData.NB + GameData.RW
GameData.DAYLEN = 300 -- 하루 길이(초)

GameData.ZoneMap = {
	{ "home", "home", "park", "home", "mart", "home", "lab", "lab", "home" },
	{ "home", "school", "park", "cafe", "home", "police", "lab", "lab", "home" },
	{ "market", "market", "park", "home", "home", "home", "home", "gas", "home" },
	{ "home", "home", "home", "police", "hosp", "home", "park", "home", "home" },
	{ "cafe", "home", "bank", "home", "park", "home", "home", "mart", "home" },
	{ "home", "park", "home", "market", "home", "school", "home", "base", "base" },
	{ "home", "park", "market", "home", "gas", "home", "home", "base", "base" },
	{ "home", "home", "home", "home", "park", "cafe", "home", "home", "home" },
	{ "mart", "home", "hosp", "home", "home", "home", "bank", "home", "park" },
}

GameData.ZoneKo = {
	home = "주택가", park = "공원", market = "시장", police = "경찰서", lab = "연구소", base = "군사기지",
	school = "학교", cafe = "카페 거리", mart = "마트", hosp = "병원", bank = "은행", gas = "주유소",
}

GameData.BuildingName = {
	house = "주택", police = "경찰서", lab = "연구소", base = "군 병영", school = "학교",
	cafe = "카페", mart = "마트", hosp = "병원", bank = "은행", gas = "주유소",
}
GameData.BuildingHP = { house = 320, police = 950, lab = 750, base = 750, school = 1200, cafe = 600, mart = 700, hosp = 1000, bank = 900, gas = 420 }
GameData.BuildingPoints = { house = 50, police = 120, lab = 120, base = 100, school = 140, cafe = 70, mart = 90, hosp = 130, bank = 130, gas = 80 }

return GameData
