// All game data: weapons, passives, enemies, meta upgrades, timeline.

export const MAX_WEAPONS = 6;
export const MAX_PASSIVES = 6;
export const RUN_LENGTH = 600; // boss arrives at 10:00

// ---------------------------------------------------------------- weapons
// stats(l) returns the numbers for level l (1..max). desc[i] is shown when
// picking level i+1.
export const WEAPONS = {
  ember: {
    name: '불씨탄', icon: '🔥', max: 5,
    desc: ['가장 가까운 적에게 불씨를 쏩니다.', '발사 수 +1', '피해 +5', '발사 수 +1', '관통 +2, 피해 +5'],
    stats: (l) => ({
      cd: 0.95,
      dmg: 10 + (l >= 3 ? 5 : 0) + (l >= 5 ? 5 : 0),
      count: 1 + (l >= 2 ? 1 : 0) + (l >= 4 ? 1 : 0),
      pierce: l >= 5 ? 2 : 0,
      speed: 430,
    }),
  },
  orbit: {
    name: '수호 등불', icon: '🏮', max: 5,
    desc: ['등불이 주위를 돌며 닿는 적을 태웁니다.', '등불 +1', '피해 +6', '등불 +1, 반경 증가', '등불 +1, 피해 +6'],
    stats: (l) => ({
      count: 2 + (l >= 2 ? 1 : 0) + (l >= 4 ? 1 : 0) + (l >= 5 ? 1 : 0),
      dmg: 9 + (l >= 3 ? 6 : 0) + (l >= 5 ? 6 : 0),
      radius: 72 + (l >= 4 ? 18 : 0),
      spin: 3.2,
    }),
  },
  aura: {
    name: '열기장', icon: '🌕', max: 5,
    desc: ['주변의 적에게 계속 열기 피해를 줍니다.', '범위 +20%', '피해 +3', '범위 +20%, 주기 단축', '피해 +4'],
    stats: (l) => ({
      radius: 70 * (1 + (l >= 2 ? 0.2 : 0) + (l >= 4 ? 0.2 : 0)),
      dmg: 5 + (l >= 3 ? 3 : 0) + (l >= 5 ? 4 : 0),
      tick: l >= 4 ? 0.38 : 0.5,
    }),
  },
  sparks: {
    name: '불꽃 산탄', icon: '✨', max: 5,
    desc: ['바라보는 방향으로 불꽃을 흩뿌립니다.', '불꽃 +2', '피해 +4', '불꽃 +2, 사거리 증가', '피해 +5, 재사용 단축'],
    stats: (l) => ({
      cd: l >= 5 ? 1.15 : 1.5,
      count: 5 + (l >= 2 ? 2 : 0) + (l >= 4 ? 2 : 0),
      dmg: 8 + (l >= 3 ? 4 : 0) + (l >= 5 ? 5 : 0),
      life: l >= 4 ? 0.45 : 0.34,
      speed: 560,
    }),
  },
  chain: {
    name: '연쇄 번개', icon: '⚡', max: 5,
    desc: ['번개가 적을 따라 튀어 다닙니다.', '연쇄 +2', '피해 +8', '연쇄 +2, 재사용 단축', '피해 +10'],
    stats: (l) => ({
      cd: l >= 4 ? 1.6 : 2.1,
      chains: 3 + (l >= 2 ? 2 : 0) + (l >= 4 ? 2 : 0),
      dmg: 18 + (l >= 3 ? 8 : 0) + (l >= 5 ? 10 : 0),
    }),
  },
  trail: {
    name: '불길 자국', icon: '👣', max: 5,
    desc: ['지나간 자리에 불길을 남깁니다.', '지속 시간 증가', '피해 +3', '불길 크기 증가', '피해 +4, 지속 시간 증가'],
    stats: (l) => ({
      dur: 2.4 + (l >= 2 ? 0.8 : 0) + (l >= 5 ? 0.8 : 0),
      dmg: 5 + (l >= 3 ? 3 : 0) + (l >= 5 ? 4 : 0),
      radius: 26 + (l >= 4 ? 10 : 0),
    }),
  },
  meteor: {
    name: '유성', icon: '☄️', max: 5,
    desc: ['적 무리 위로 유성을 떨어뜨립니다.', '유성 +1', '피해 +20', '유성 +1, 폭발 범위 증가', '유성 +1, 재사용 단축'],
    stats: (l) => ({
      cd: l >= 5 ? 2.3 : 3.0,
      count: 1 + (l >= 2 ? 1 : 0) + (l >= 4 ? 1 : 0) + (l >= 5 ? 1 : 0),
      dmg: 38 + (l >= 3 ? 20 : 0),
      radius: 70 + (l >= 4 ? 20 : 0),
    }),
  },
  sickle: {
    name: '회귀 낫', icon: '🌙', max: 5,
    desc: ['던지면 되돌아오는 낫. 모든 적을 관통합니다.', '낫 +1', '피해 +8', '낫 +1, 크기 증가', '피해 +10'],
    stats: (l) => ({
      cd: 1.8,
      count: 1 + (l >= 2 ? 1 : 0) + (l >= 4 ? 1 : 0),
      dmg: 15 + (l >= 3 ? 8 : 0) + (l >= 5 ? 10 : 0),
      size: 16 + (l >= 4 ? 6 : 0),
    }),
  },
};

// ---------------------------------------------------------------- passives
export const PASSIVES = {
  vigor:  { name: '생명의 불씨', icon: '❤️', max: 5, desc: '최대 체력 +20%' },
  swift:  { name: '질주', icon: '👟', max: 5, desc: '이동 속도 +10%' },
  might:  { name: '화력', icon: '💪', max: 5, desc: '모든 피해 +10%' },
  haste:  { name: '가속', icon: '⏳', max: 5, desc: '무기 재사용 시간 -8%' },
  reach:  { name: '확산', icon: '🌀', max: 5, desc: '공격 범위 +10%' },
  magnet: { name: '끌림', icon: '🧲', max: 5, desc: '경험치 획득 범위 +30%' },
  armor:  { name: '갑주', icon: '🛡️', max: 5, desc: '받는 피해 -1' },
  regen:  { name: '재생', icon: '🌿', max: 5, desc: '초당 체력 회복 +0.4' },
  multi:  { name: '증폭', icon: '➕', max: 2, desc: '모든 무기 발사 수 +1' },
};

// ---------------------------------------------------------------- meta shop
export const META = {
  hp:     { name: '단단한 몸', icon: '❤️', max: 5, base: 120, desc: '시작 최대 체력 +10%' },
  might:  { name: '타오르는 의지', icon: '💪', max: 5, base: 150, desc: '모든 피해 +5%' },
  speed:  { name: '가벼운 발', icon: '👟', max: 3, base: 140, desc: '이동 속도 +5%' },
  magnet: { name: '이끄는 빛', icon: '🧲', max: 3, base: 100, desc: '경험치 획득 범위 +20%' },
  greed:  { name: '탐욕', icon: '🪙', max: 5, base: 120, desc: '얻는 금화 +10%' },
  revive: { name: '두 번째 등불', icon: '🕯️', max: 1, base: 900, desc: '쓰러져도 한 번 부활' },
};
export const metaCost = (id, lvl) => Math.round(META[id].base * (1 + lvl * 0.8));

// ---------------------------------------------------------------- enemies
// ai: chase | zig | ranged | charge | boss
export const ENEMIES = {
  wisp:      { name: '떠돌이 혼', hp: 12, speed: 72, r: 11, dmg: 8, xp: 1, ai: 'chase', kbRes: 0 },
  bat:       { name: '그늘 박쥐', hp: 8, speed: 128, r: 9, dmg: 6, xp: 1, ai: 'zig', kbRes: 0 },
  splitter:  { name: '갈래 점액', hp: 40, speed: 62, r: 16, dmg: 10, xp: 2, ai: 'chase', kbRes: 0.2, splits: 'splitling' },
  splitling: { name: '작은 점액', hp: 10, speed: 96, r: 9, dmg: 6, xp: 1, ai: 'chase', kbRes: 0 },
  brute:     { name: '바위 거인', hp: 75, speed: 46, r: 21, dmg: 16, xp: 5, ai: 'chase', kbRes: 0.7 },
  spitter:   { name: '독침 꽃', hp: 26, speed: 62, r: 13, dmg: 8, xp: 3, ai: 'ranged', kbRes: 0.1 },
  charger:   { name: '돌진 투구', hp: 45, speed: 58, r: 14, dmg: 14, xp: 3, ai: 'charge', kbRes: 0.4 },
  boss:      { name: '공허의 왕', hp: 3800, speed: 58, r: 46, dmg: 28, xp: 0, ai: 'boss', kbRes: 1 },
};

// Spawn weights by minute.
export function spawnWeights(min) {
  return [
    ['wisp', Math.max(3, 10 - min * 0.8)],
    ['bat', min >= 1 ? 6 : 0],
    ['splitter', min >= 2 ? 4 : 0],
    ['brute', min >= 3 ? 3 + min * 0.2 : 0],
    ['spitter', min >= 4 ? 3 : 0],
    ['charger', min >= 5 ? 3 + min * 0.2 : 0],
  ];
}

// Scripted moments in a run.
export const TIMELINE = [
  { t: 120, kind: 'ring', enemy: 'bat', n: 26, msg: '박쥐 떼가 둘러쌉니다!' },
  { t: 180, kind: 'elite', enemy: 'brute', msg: '강한 적이 나타났습니다' },
  { t: 270, kind: 'ring', enemy: 'wisp', n: 40, msg: '혼들이 몰려옵니다!' },
  { t: 360, kind: 'elite', enemy: 'charger', msg: '강한 적이 나타났습니다' },
  { t: 420, kind: 'ring', enemy: 'bat', n: 44, msg: '박쥐 떼가 둘러쌉니다!' },
  { t: 510, kind: 'elite', enemy: 'splitter', msg: '강한 적이 나타났습니다' },
  { t: 540, kind: 'ring', enemy: 'charger', n: 24, msg: '마지막 파도!' },
  { t: RUN_LENGTH, kind: 'boss', enemy: 'boss', msg: '공허의 왕이 깨어났습니다' },
];

export const xpFor = (level) => Math.floor(5 + level * 7 + level * level * 0.55);
