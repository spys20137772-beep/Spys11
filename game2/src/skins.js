// Mochi skins, unlocked by total strawberries collected.
export const SKINS = [
  { id: 'plain', name: '찹쌀떡', need: 0, hi: '#ffffff', lo: '#f6ecdc', line: '#e0cfb5', eye: '#3a2a22', cheek: 'rgba(255,140,160,0.55)' },
  { id: 'mugwort', name: '쑥떡', need: 10, hi: '#d9efc6', lo: '#9fcb83', line: '#7aa862', eye: '#2c3a22', cheek: 'rgba(255,150,150,0.45)' },
  { id: 'berry', name: '딸기찹쌀떡', need: 22, hi: '#ffe6ee', lo: '#ffb7cc', line: '#ee90ac', eye: '#4a2230', cheek: 'rgba(255,90,130,0.55)' },
  { id: 'pumpkin', name: '단호박떡', need: 36, hi: '#fff0c4', lo: '#ffc65c', line: '#e7a43a', eye: '#4a3015', cheek: 'rgba(255,120,90,0.5)' },
  { id: 'sesame', name: '흑임자떡', need: 50, hi: '#6b6b70', lo: '#2f2f35', line: '#1c1c20', eye: '#ffffff', cheek: 'rgba(255,140,170,0.6)' },
  { id: 'rainbow', name: '무지개떡', need: 72, hi: '#fff6c9', lo: '#c7b8ff', line: '#a891f0', eye: '#2f2448', cheek: 'rgba(255,120,170,0.6)', rainbow: true },
];

export const skinById = (id) => SKINS.find((s) => s.id === id) || SKINS[0];

export function medalFor(launches, par) {
  if (!launches || !par) return null;
  if (launches <= par + 1) return 'gold';
  if (launches <= par + 3) return 'silver';
  return 'bronze';
}
export const MEDAL_NAME = { gold: '금메달', silver: '은메달', bronze: '동메달' };
