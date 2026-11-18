// Pre-rendered sprites drawn with canvas paths (no image assets).
const SS = 2; // supersample

function make(size, draw) {
  const c = document.createElement('canvas');
  c.width = c.height = Math.ceil(size * SS);
  const g = c.getContext('2d');
  g.scale(SS, SS);
  g.translate(size / 2, size / 2);
  draw(g, size);
  return { img: c, size };
}

function whiteOf(spr) {
  const c = document.createElement('canvas');
  c.width = spr.img.width; c.height = spr.img.height;
  const g = c.getContext('2d');
  g.drawImage(spr.img, 0, 0);
  g.globalCompositeOperation = 'source-atop';
  g.fillStyle = '#ffffff';
  g.fillRect(0, 0, c.width, c.height);
  return { img: c, size: spr.size };
}

function eyes(g, x, y, gap, r, color = '#fff') {
  g.fillStyle = color;
  g.beginPath(); g.arc(x - gap, y, r, 0, Math.PI * 2); g.arc(x + gap, y, r, 0, Math.PI * 2); g.fill();
}

export function glow(size, inner, outer) {
  return make(size, (g, s) => {
    const gr = g.createRadialGradient(0, 0, 0, 0, 0, s / 2);
    gr.addColorStop(0, inner);
    gr.addColorStop(0.35, outer);
    gr.addColorStop(1, 'rgba(0,0,0,0)');
    g.fillStyle = gr;
    g.beginPath(); g.arc(0, 0, s / 2, 0, Math.PI * 2); g.fill();
  });
}

const DRAW = {
  wisp(g) {
    g.fillStyle = '#8b5cf6';
    g.beginPath();
    g.arc(0, -2, 11, Math.PI, 0);
    g.lineTo(11, 8); g.lineTo(6, 4); g.lineTo(2, 10); g.lineTo(-3, 4); g.lineTo(-7, 10); g.lineTo(-11, 6);
    g.closePath(); g.fill();
    g.fillStyle = 'rgba(255,255,255,0.18)';
    g.beginPath(); g.arc(-4, -6, 4, 0, Math.PI * 2); g.fill();
    eyes(g, 0, -2, 4, 2.2);
  },
  bat(g) {
    g.fillStyle = '#b4233c';
    g.beginPath();
    g.moveTo(0, -3); g.lineTo(-13, -7); g.lineTo(-9, 1); g.lineTo(-14, 4); g.lineTo(-4, 4);
    g.lineTo(0, 7); g.lineTo(4, 4); g.lineTo(14, 4); g.lineTo(9, 1); g.lineTo(13, -7); g.closePath(); g.fill();
    g.fillStyle = '#5c0f1f';
    g.beginPath(); g.arc(0, 0, 5, 0, Math.PI * 2); g.fill();
    eyes(g, 0, -1, 2, 1.3, '#ffd166');
  },
  splitter(g) {
    g.fillStyle = '#f97316';
    g.beginPath(); g.ellipse(0, 2, 16, 13, 0, 0, Math.PI * 2); g.fill();
    g.fillStyle = 'rgba(255,255,255,0.22)';
    g.beginPath(); g.ellipse(-6, -4, 5, 3, -0.5, 0, Math.PI * 2); g.fill();
    g.strokeStyle = '#7c2d12'; g.lineWidth = 2;
    g.beginPath(); g.moveTo(0, -11); g.lineTo(-3, -3); g.lineTo(2, 3); g.lineTo(-1, 12); g.stroke();
    eyes(g, 0, 2, 6, 2.4, '#1c0a02');
  },
  splitling(g) {
    g.fillStyle = '#fb923c';
    g.beginPath(); g.ellipse(0, 1, 9, 8, 0, 0, Math.PI * 2); g.fill();
    eyes(g, 0, 1, 3.5, 1.6, '#1c0a02');
  },
  brute(g) {
    g.fillStyle = '#4b5563';
    g.beginPath(); g.roundRect(-19, -16, 38, 34, 10); g.fill();
    g.fillStyle = '#9ca3af';
    g.beginPath(); g.moveTo(-17, -12); g.lineTo(-22, -24); g.lineTo(-9, -15); g.fill();
    g.beginPath(); g.moveTo(17, -12); g.lineTo(22, -24); g.lineTo(9, -15); g.fill();
    g.fillStyle = '#374151';
    g.beginPath(); g.roundRect(-12, 4, 24, 8, 3); g.fill();
    eyes(g, 0, -4, 7, 3, '#fde047');
  },
  spitter(g) {
    g.fillStyle = '#0f766e';
    for (let i = 0; i < 6; i++) {
      const a = (i / 6) * Math.PI * 2;
      g.beginPath(); g.ellipse(Math.cos(a) * 8, Math.sin(a) * 8, 7, 4, a, 0, Math.PI * 2); g.fill();
    }
    g.fillStyle = '#2dd4bf';
    g.beginPath(); g.arc(0, 0, 8, 0, Math.PI * 2); g.fill();
    g.fillStyle = '#042f2e';
    g.beginPath(); g.arc(0, 0, 3.5, 0, Math.PI * 2); g.fill();
  },
  charger(g) {
    g.fillStyle = '#3b82f6';
    g.beginPath(); g.moveTo(15, 0); g.lineTo(-10, -13); g.lineTo(-5, 0); g.lineTo(-10, 13); g.closePath(); g.fill();
    g.fillStyle = '#1e3a8a';
    g.beginPath(); g.moveTo(9, 0); g.lineTo(-4, -6); g.lineTo(-4, 6); g.closePath(); g.fill();
    g.fillStyle = '#fef08a';
    g.beginPath(); g.arc(3, 0, 2.3, 0, Math.PI * 2); g.fill();
  },
  boss(g) {
    const gr = g.createRadialGradient(0, 0, 10, 0, 0, 48);
    gr.addColorStop(0, '#3b0764'); gr.addColorStop(1, '#1e0533');
    g.fillStyle = gr;
    g.beginPath();
    g.arc(0, 0, 44, Math.PI, 0);
    for (let i = 0; i <= 8; i++) {
      const x = 44 - i * 11; g.lineTo(x, 40 + (i % 2 ? -10 : 0));
    }
    g.closePath(); g.fill();
    g.fillStyle = '#fbbf24';
    g.beginPath();
    g.moveTo(-24, -34); g.lineTo(-18, -54); g.lineTo(-8, -40); g.lineTo(0, -58); g.lineTo(8, -40); g.lineTo(18, -54); g.lineTo(24, -34);
    g.closePath(); g.fill();
    g.fillStyle = '#f472b6';
    g.shadowColor = '#f472b6'; g.shadowBlur = 12;
    g.beginPath(); g.ellipse(-14, -6, 7, 4, 0.2, 0, Math.PI * 2); g.ellipse(14, -6, 7, 4, -0.2, 0, Math.PI * 2); g.fill();
    g.shadowBlur = 0;
    g.strokeStyle = '#a855f7'; g.lineWidth = 3;
    g.beginPath(); g.arc(0, 14, 12, 0.15 * Math.PI, 0.85 * Math.PI); g.stroke();
  },
};

const SIZES = { wisp: 30, bat: 32, splitter: 40, splitling: 24, brute: 54, spitter: 36, charger: 36, boss: 124 };

export function buildSprites() {
  const S = { enemy: {}, enemyWhite: {} };
  for (const k in DRAW) {
    S.enemy[k] = make(SIZES[k], DRAW[k]);
    S.enemyWhite[k] = whiteOf(S.enemy[k]);
  }
  S.glowEmber = glow(34, 'rgba(255,240,200,1)', 'rgba(255,140,40,0.75)');
  S.glowSpark = glow(22, 'rgba(255,255,220,1)', 'rgba(255,210,80,0.7)');
  S.glowOrb = glow(46, 'rgba(255,250,220,1)', 'rgba(255,180,60,0.6)');
  S.glowEnemy = glow(26, 'rgba(255,230,255,1)', 'rgba(236,72,153,0.75)');
  S.glowFire = glow(64, 'rgba(255,200,90,0.85)', 'rgba(255,90,30,0.4)');
  S.glowGem = [
    glow(20, 'rgba(200,240,255,1)', 'rgba(56,189,248,0.6)'),
    glow(24, 'rgba(210,255,220,1)', 'rgba(74,222,128,0.6)'),
    glow(30, 'rgba(255,220,230,1)', 'rgba(244,63,94,0.6)'),
  ];
  S.lantern = glow(260, 'rgba(255,220,150,0.22)', 'rgba(255,170,60,0.08)');
  return S;
}

export { SS };
