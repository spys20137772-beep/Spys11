// DOM menus, HUD and keyboard/gamepad menu navigation.
import { META, metaCost, WEAPONS, PASSIVES } from './content.js';

const $ = (sel, root = document) => root.querySelector(sel);
const fmt = (t) => `${String(Math.floor(t / 60)).padStart(2, '0')}:${String(Math.floor(t % 60)).padStart(2, '0')}`;
const isElectron = navigator.userAgent.includes('Electron');
const TOUCH = matchMedia('(pointer: coarse)').matches;

export class UI {
  constructor(app) {
    this.app = app;
    this.root = $('#screens');
    this.hud = $('#hud');
    this.screen = null;
    this.focus = 0;
    this.items = [];
    this.stack = [];
    this.hudCache = {};
    // mouse: hovering moves focus; buttons never take DOM focus
    // keep keyboard focus on the page (matters when embedded in an iframe), but never on a button,
    // so Enter/Space are handled once by our own navigation
    this.root.addEventListener('click', (e) => { const b = e.target.closest('button'); if (b) b.blur(); window.focus(); });
    this.root.addEventListener('mousemove', (e) => {
      const el = e.target.closest('[data-nav]');
      if (el) { const i = this.items.indexOf(el); if (i >= 0 && i !== this.focus) this.setFocus(i, false); }
    });
  }

  // ------------------------------------------------------------ screens
  show(name, arg) {
    this.screen = name;
    this.lastArg = arg;
    this.root.innerHTML = '';
    this.root.classList.remove('hidden');
    const el = document.createElement('section');
    el.className = `screen s-${name}`;
    el.innerHTML = this[`html_${name}`](arg);
    this.root.appendChild(el);
    this.bind(el, name, arg);
    this.items = [...el.querySelectorAll('[data-nav]')];
    this.setFocus(0, false);
  }

  hide() {
    this.screen = null;
    this.root.classList.add('hidden');
    this.root.innerHTML = '';
    this.items = [];
  }

  push(name, arg) { this.stack.push([this.screen, this.lastArg, this.focus]); this.show(name, arg); }
  pop() {
    const [n, a, f] = this.stack.pop() || ['title', undefined, 0];
    this.show(n, a);
    this.setFocus(f || 0, false);
  }

  setFocus(i, sound = true) {
    if (!this.items.length) return;
    this.focus = (i + this.items.length) % this.items.length;
    this.items.forEach((el, j) => el.classList.toggle('focus', j === this.focus));
    if (sound) this.app.sound.play('move');
  }

  // Called every frame with input while a screen is open.
  tick(input) {
    if (!this.screen || !this.items.length) return;
    const cur = this.items[this.focus];
    const horiz = this.screen === 'levelup';
    if (input.act('down') || (horiz && input.act('right'))) this.setFocus(this.focus + 1);
    else if (input.act('up') || (horiz && input.act('left'))) this.setFocus(this.focus - 1);
    else if (!horiz && (input.act('left') || input.act('right'))) {
      if (cur.dataset.range) this.adjustRange(cur, input.act('right') ? 0.1 : -0.1);
    } else if (input.act('ok')) {
      cur.click();
    } else if (input.act('back')) {
      const back = this.root.querySelector('[data-back]');
      if (back) back.click();
    }
  }

  adjustRange(el, d) {
    const key = el.dataset.range;
    const o = this.app.save.data.options;
    o[key] = Math.round(Math.min(1, Math.max(0, o[key] + d)) * 10) / 10;
    el.querySelector('.val').textContent = `${Math.round(o[key] * 100)}%`;
    el.querySelector('.fill').style.width = `${o[key] * 100}%`;
    this.app.applyOptions();
    this.app.sound.play('click');
  }

  // ------------------------------------------------------------ html
  html_title() {
    const d = this.app.save.data;
    return `
      <div class="logo">
        <div class="logo-kr">등불지기</div>
        <div class="logo-en">LANTERNBOUND</div>
      </div>
      <div class="menu">
        <button data-nav data-act="play">시작하기</button>
        <button data-nav data-act="shop">강화 상점 <span class="badge">🪙 ${d.gold}</span></button>
        <button data-nav data-act="options">설정</button>
        <button data-nav data-act="credits">만든 사람</button>
        ${isElectron ? '<button data-nav data-act="quit">게임 종료</button>' : ''}
      </div>
      <div class="records">
        최고 기록 ${fmt(d.best.time)} · 처치 ${d.best.kills} · 클리어 ${d.wins}회
      </div>
      <div class="hint">${TOUCH ? '화면을 누른 채 끌면 그 방향으로 이동합니다' : '이동 WASD / 방향키 / 게임패드 / 마우스 끌기 · 선택 Enter · 일시정지 Esc'}</div>`;
  }

  html_shop() {
    const d = this.app.save.data;
    const rows = Object.entries(META).map(([id, m]) => {
      const lvl = d.meta[id] || 0, maxed = lvl >= m.max, cost = metaCost(id, lvl);
      const pips = Array.from({ length: m.max }, (_, i) => `<i class="${i < lvl ? 'on' : ''}"></i>`).join('');
      return `<button data-nav data-buy="${id}" class="shop-row ${maxed ? 'maxed' : cost > d.gold ? 'poor' : ''}">
        <span class="ic">${m.icon}</span>
        <span class="info"><b>${m.name}</b><small>${m.desc}</small><span class="pips">${pips}</span></span>
        <span class="cost">${maxed ? '최대' : `🪙 ${cost}`}</span>
      </button>`;
    }).join('');
    return `
      <h2>강화 상점</h2>
      <div class="sub">보유 금화 <b class="gold">🪙 ${d.gold}</b> · 금화는 매 판이 끝나면 쌓입니다</div>
      <div class="shop">${rows}</div>
      <div class="menu row">
        <button data-nav data-act="refund">초기화 (금화 환불)</button>
        <button data-nav data-back>뒤로</button>
      </div>`;
  }

  html_options() {
    const o = this.app.save.data.options;
    const range = (key, label) => `
      <button data-nav data-range="${key}" class="opt">
        <span>${label}</span>
        <span class="slider"><span class="fill" style="width:${o[key] * 100}%"></span></span>
        <span class="val">${Math.round(o[key] * 100)}%</span>
      </button>`;
    const toggle = (key, label) => `
      <button data-nav data-toggle="${key}" class="opt">
        <span>${label}</span><span class="tog ${o[key] ? 'on' : ''}">${o[key] ? '켜짐' : '꺼짐'}</span>
      </button>`;
    return `
      <h2>설정</h2>
      <div class="opts">
        ${range('master', '전체 볼륨')}
        ${range('music', '배경음악')}
        ${range('sfx', '효과음')}
        ${toggle('fullscreen', '전체 화면')}
        ${toggle('shake', '화면 흔들림')}
        ${toggle('dmgNums', '피해 숫자 표시')}
      </div>
      <div class="sub">볼륨은 ← → 로 조절합니다</div>
      <div class="menu"><button data-nav data-back>뒤로</button></div>`;
  }

  html_credits() {
    return `
      <h2>만든 사람</h2>
      <div class="credits">
        <p><b>등불지기 (Lanternbound)</b></p>
        <p>기획 · 프로그래밍 · 그래픽 · 사운드<br>Claude와 함께 만든 게임</p>
        <p>모든 그림은 코드로 그렸고, 모든 소리는 실시간으로 합성됩니다.<br>외부 이미지나 음원을 쓰지 않았습니다.</p>
        <p class="dim">어두운 숲에 등불을 지키는 마지막 사람이 남았습니다.<br>10분을 버티고 공허의 왕을 쓰러뜨리세요.</p>
      </div>
      <div class="menu"><button data-nav data-back>뒤로</button></div>`;
  }

  html_levelup(arg) {
    const cards = arg.choices.map((c, i) => `
      <button data-nav data-pick="${i}" class="card ${c.isNew ? 'new' : ''}">
        <span class="tag">${c.tag}</span>
        <span class="ic">${c.icon}</span>
        <b>${c.name}</b>
        <small>${c.text}</small>
      </button>`).join('');
    return `
      <h2>${arg.chest ? '보물 상자!' : '레벨 업!'}</h2>
      <div class="sub">${arg.chest ? '상자에서 강화 하나를 고르세요' : '강화 하나를 고르세요'}</div>
      <div class="cards">${cards}</div>`;
  }

  html_pause() {
    const g = this.app.game;
    const ws = g.weapons.map((w) => `<span>${WEAPONS[w.id].icon} ${WEAPONS[w.id].name} <b>Lv${w.lvl}</b></span>`).join('');
    const ps = Object.entries(g.passives).map(([id, l]) => `<span>${PASSIVES[id].icon} ${PASSIVES[id].name} <b>Lv${l}</b></span>`).join('');
    return `
      <h2>일시정지</h2>
      <div class="loadout">${ws}${ps}</div>
      <div class="menu">
        <button data-nav data-act="resume" data-back>계속하기</button>
        <button data-nav data-act="options">설정</button>
        <button data-nav data-act="giveup">포기하고 타이틀로</button>
      </div>`;
  }

  html_result(r) {
    const ws = r.weapons.map((w) => `<span>${w.icon} ${w.name} <b>Lv${w.lvl}</b></span>`).join('');
    return `
      <h2 class="${r.win ? 'win' : 'lose'}">${r.win ? '공허의 왕을 쓰러뜨렸습니다!' : '등불이 꺼졌습니다'}</h2>
      ${r.newBest ? '<div class="sub gold">새 최고 기록!</div>' : ''}
      <div class="result">
        <div><small>버틴 시간</small><b>${fmt(r.time)}</b></div>
        <div><small>레벨</small><b>${r.level}</b></div>
        <div><small>처치</small><b>${r.kills}</b></div>
        <div><small>얻은 금화</small><b class="gold">🪙 ${r.gold}</b></div>
      </div>
      <div class="loadout">${ws}</div>
      <div class="menu row">
        <button data-nav data-act="play">다시 하기</button>
        <button data-nav data-act="shop">강화 상점</button>
        <button data-nav data-act="title">타이틀로</button>
      </div>`;
  }

  // ------------------------------------------------------------ events
  bind(el, name, arg) {
    const app = this.app;
    el.addEventListener('click', (e) => {
      const b = e.target.closest('button');
      if (!b) return;
      app.sound.init();
      if (b.dataset.pick !== undefined) { app.pick(arg.choices[+b.dataset.pick]); return; }
      if (b.dataset.range) { this.setFocus(this.items.indexOf(b), false); return; }
      if (b.dataset.toggle) {
        const o = app.save.data.options, k = b.dataset.toggle;
        o[k] = !o[k];
        const t = b.querySelector('.tog'); t.classList.toggle('on', o[k]); t.textContent = o[k] ? '켜짐' : '꺼짐';
        app.applyOptions(k);
        app.sound.play('click');
        return;
      }
      if (b.dataset.buy) {
        const id = b.dataset.buy, d = app.save.data, lvl = d.meta[id] || 0, cost = metaCost(id, lvl);
        if (lvl < META[id].max && d.gold >= cost) {
          d.gold -= cost; d.meta[id] = lvl + 1; app.save.write(); app.sound.play('coin');
          const f = this.focus; this.show('shop'); this.setFocus(f, false);
        } else app.sound.play('hurt');
        return;
      }
      app.sound.play('click');
      const act = b.dataset.act;
      if (b.hasAttribute('data-back') && !act) { app.save.write(); this.pop(); return; }
      switch (act) {
        case 'play': app.startRun(); break;
        case 'shop': this.push('shop'); break;
        case 'options': this.push('options'); break;
        case 'credits': this.push('credits'); break;
        case 'quit': window.close(); break;
        case 'resume': app.resume(); break;
        case 'giveup': app.toTitle(); break;
        case 'title': app.toTitle(); break;
        case 'refund': {
          const d = app.save.data;
          let back = 0;
          for (const id in META) for (let l = 0; l < (d.meta[id] || 0); l++) back += metaCost(id, l);
          d.gold += back; for (const id in META) d.meta[id] = 0; app.save.write();
          this.show('shop');
          break;
        }
      }
    });
  }

  // ------------------------------------------------------------ HUD
  showHud(on) { this.hud.classList.toggle('hidden', !on); }

  updateHud(g) {
    const c = this.hudCache;
    const set = (id, v, fn) => { if (c[id] !== v) { c[id] = v; fn(v); } };
    set('xp', Math.round(g.xp / g.xpNext * 1000), (v) => { $('#xpfill').style.width = `${v / 10}%`; });
    set('lv', g.level, (v) => { $('#lv').textContent = `Lv ${v}`; });
    set('time', Math.floor(g.time), (v) => { $('#timer').textContent = fmt(v); });
    set('kills', g.kills, (v) => { $('#kills').textContent = `💀 ${v}`; });
    set('gold', g.goldRun, (v) => { $('#gold').textContent = `🪙 ${v}`; });
    const slots = g.weapons.map((w) => `${w.id}${w.lvl}`).join() + '|' + Object.entries(g.passives).map(([k, v]) => k + v).join();
    set('slots', slots, () => {
      $('#slots').innerHTML =
        g.weapons.map((w) => `<span class="slot">${WEAPONS[w.id].icon}<i>${w.lvl}</i></span>`).join('') +
        '<span class="sep"></span>' +
        Object.entries(g.passives).map(([id, l]) => `<span class="slot p">${PASSIVES[id].icon}<i>${l}</i></span>`).join('');
    });
    const boss = g.boss && !g.boss.dead ? Math.round(g.boss.hp / g.boss.maxHp * 1000) : -1;
    set('boss', boss, (v) => {
      $('#bossbar').classList.toggle('hidden', v < 0);
      if (v >= 0) $('#bossfill').style.width = `${v / 10}%`;
    });
    const banner = g.banner ? g.banner.text : '';
    set('banner', banner, (v) => {
      const b = $('#banner'); b.textContent = v; b.classList.toggle('show', !!v);
    });
  }
}
