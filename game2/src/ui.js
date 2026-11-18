// DOM menus and HUD, with keyboard / gamepad navigation.
import { LEVELS, WORLDS } from './levels.js';
import { SKINS, medalFor, MEDAL_NAME } from './skins.js';
import { PARS } from './pars.js';
const medalIcon = (m) => (m ? `<i class="medal ${m}"></i>` : '');

const $ = (s, r = document) => r.querySelector(s);
const isElectron = navigator.userAgent.includes('Electron');
const TOUCH = matchMedia('(pointer: coarse)').matches;
const fmt = (t) => `${Math.floor(t / 60)}:${String(Math.floor(t % 60)).padStart(2, '0')}`;
const BERRY = '<i class="berry"></i>';
const NOBERRY = '<i class="berry off"></i>';

export class UI {
  constructor(app) {
    this.app = app;
    this.root = $('#screens');
    this.hud = $('#hud');
    this.screen = null;
    this.items = [];
    this.focus = 0;
    this.stack = [];
    this.world = 0;
    this.root.addEventListener('click', (e) => { const b = e.target.closest('button'); if (b) b.blur(); window.focus(); });
    this.root.addEventListener('mousemove', (e) => {
      const el = e.target.closest('[data-nav]');
      if (el) { const i = this.items.indexOf(el); if (i >= 0 && i !== this.focus) this.setFocus(i, false); }
    });
    $('#btn-pause').addEventListener('click', (e) => { e.stopPropagation(); app.pause(); });
    $('#btn-restart').addEventListener('click', (e) => { e.stopPropagation(); app.restart(); });
    $('#btn-mute').addEventListener('click', (e) => { e.stopPropagation(); app.sound.init(); app.toggleMute(); });
  }

  show(name, arg) {
    this.screen = name; this.lastArg = arg;
    this.root.classList.remove('hidden');
    this.root.innerHTML = '';
    const el = document.createElement('section');
    el.className = `screen s-${name}`;
    el.innerHTML = this[`html_${name}`](arg);
    this.root.appendChild(el);
    this.bind(el, arg);
    this.items = [...el.querySelectorAll('[data-nav]')];
    const pref = el.querySelector('[data-autofocus]');
    this.setFocus(pref ? this.items.indexOf(pref) : 0, false);
  }
  hide() { this.screen = null; this.root.classList.add('hidden'); this.root.innerHTML = ''; this.items = []; }
  push(name, arg) { this.stack.push([this.screen, this.lastArg, this.focus]); this.show(name, arg); }
  pop() { const [n, a, f] = this.stack.pop() || ['title', undefined, 0]; this.show(n, a); this.setFocus(f || 0, false); }

  setFocus(i, sound = true) {
    if (!this.items.length) return;
    this.focus = (i + this.items.length) % this.items.length;
    this.items.forEach((el, j) => el.classList.toggle('focus', j === this.focus));
    this.items[this.focus].scrollIntoView?.({ block: 'nearest' });
    if (sound) this.app.sound.play('move');
  }

  tick(input) {
    if (!this.screen || !this.items.length) return;
    const cur = this.items[this.focus];
    const grid = this.screen === 'select';
    if (grid && cur.dataset.level !== undefined && (input.act('left') || input.act('right') || input.act('up') || input.act('down'))) {
      const lv = this.items.filter((el) => el.dataset.level !== undefined);
      const i = lv.indexOf(cur), cols = 4;
      let j = i;
      if (input.act('left')) j = i - 1; if (input.act('right')) j = i + 1;
      if (input.act('up')) j = i - cols; if (input.act('down')) j = i + cols;
      if (j >= 0 && j < lv.length) this.setFocus(this.items.indexOf(lv[j]));
      else if (j >= lv.length) this.setFocus(this.items.indexOf(lv[lv.length - 1]) + 1);
      else if (input.act('up')) this.setFocus(0);
      return;
    }
    if (input.act('down') || (this.screen === 'clear' && input.act('right'))) this.setFocus(this.focus + 1);
    else if (input.act('up') || (this.screen === 'clear' && input.act('left'))) this.setFocus(this.focus - 1);
    else if (input.act('left') || input.act('right')) {
      const d = input.act('right') ? 1 : -1;
      if (cur.dataset.range) this.adjustRange(cur, d * 0.1);
      else if (cur.dataset.tab !== undefined) { this.world = (this.world + d + WORLDS.length) % WORLDS.length; this.show('select'); }
    } else if (input.act('ok')) cur.click();
    else if (input.act('back')) { const b = this.root.querySelector('[data-back]'); if (b) b.click(); }
  }

  adjustRange(el, d) {
    const o = this.app.save.data.options, k = el.dataset.range;
    o[k] = Math.round(Math.min(1, Math.max(0, o[k] + d)) * 10) / 10;
    el.querySelector('.val').textContent = `${Math.round(o[k] * 100)}%`;
    el.querySelector('.fill').style.width = `${o[k] * 100}%`;
    this.app.applyOptions(); this.app.sound.play('click');
  }

  // ------------------------------------------------------------ screens
  html_title() {
    const s = this.app.save;
    const any = Object.keys(s.data.levels).length > 0;
    return `
      <div class="logo">
        <div class="mochi-big"><span></span></div>
        <div class="logo-kr">찰떡 점프</div>
        <div class="logo-en">CHALTTEOK JUMP</div>
      </div>
      <div class="menu">
        <button data-nav data-act="continue">${any ? '이어하기' : '시작하기'}</button>
        <button data-nav data-act="select">스테이지 선택</button>
        <button data-nav data-act="skins">꾸미기</button>
        <button data-nav data-act="options">설정</button>
        <button data-nav data-act="credits">만든 사람</button>
        ${isElectron ? '<button data-nav data-act="quit">게임 종료</button>' : ''}
      </div>
      <div class="records">딸기 ${s.totalBerries()} / ${LEVELS.length * 3} · 클리어 ${Object.values(s.data.levels).filter((l) => l.done).length} / ${LEVELS.length} · 금메달 ${LEVELS.filter((l) => medalFor(s.level(l.id).best, PARS[l.id]) === 'gold').length}</div>
      <div class="hint">${TOUCH ? '화면을 당겼다 놓으면 찰떡이 날아가요' : '마우스로 당겼다 놓기 · 방향키로 조준하고 Space · R 다시 시작 · Esc 일시정지'}</div>`;
  }

  html_select() {
    const s = this.app.save, wi = this.world, W = WORLDS[wi];
    const tabs = WORLDS.map((w, i) => {
      const lv = LEVELS.filter((l) => l.world === w.id);
      const got = lv.reduce((n, l) => n + s.level(l.id).berries.filter(Boolean).length, 0);
      return `<button data-nav data-tab="${i}" class="tab t-${w.theme} ${i === wi ? 'on' : ''}">${w.name}<small>${BERRY} ${got}/${lv.length * 3}</small></button>`;
    }).join('');
    const cells = LEVELS.map((l, i) => ({ l, i })).filter(({ l }) => l.world === W.id).map(({ l, i }) => {
      const rec = s.level(l.id), open = this.app.unlocked(i);
      const b = rec.berries.map((x) => (x ? BERRY : NOBERRY)).join('');
      return `<button data-nav data-level="${i}" class="cell t-${W.theme} ${open ? '' : 'locked'} ${rec.done ? 'done' : ''}" ${this.app.nextLevel() === i ? 'data-autofocus' : ''}>
        ${rec.done ? medalIcon(medalFor(rec.best, PARS[l.id])) : ''}<b>${open ? l.id.split('-')[1] : '🔒'}</b><span class="nm">${open ? l.name : '잠김'}</span><span class="bs">${open ? b : ''}</span></button>`;
    }).join('');
    return `
      <h2>스테이지 선택</h2>
      <div class="tabs">${tabs}</div>
      <div class="grid">${cells}</div>
      <div class="menu"><button data-nav data-back>뒤로</button></div>`;
  }

  html_options() {
    const o = this.app.save.data.options;
    const range = (k, l) => `<button data-nav data-range="${k}" class="opt"><span>${l}</span><span class="slider"><span class="fill" style="width:${o[k] * 100}%"></span></span><span class="val">${Math.round(o[k] * 100)}%</span></button>`;
    const tog = (k, l) => `<button data-nav data-toggle="${k}" class="opt"><span>${l}</span><span class="tog ${o[k] ? 'on' : ''}">${o[k] ? '켜짐' : '꺼짐'}</span></button>`;
    return `
      <h2>설정</h2>
      <div class="opts">
        ${range('master', '전체 볼륨')}${range('music', '배경음악')}${range('sfx', '효과음')}
        ${tog('preview', '궤적 미리보기')}${tog('shake', '화면 흔들림')}${tog('fullscreen', '전체 화면')}
      </div>
      <div class="sub">볼륨은 ← → 로도 조절할 수 있어요</div>
      <div class="menu"><button data-nav data-back>뒤로</button></div>`;
  }

  html_skins() {
    const s = this.app.save, have = s.totalBerries(), cur = s.data.options.skin;
    const cards = SKINS.map((k) => {
      const open = have >= k.need;
      return `<button data-nav data-skin="${k.id}" class="skin ${open ? '' : 'locked'} ${cur === k.id ? 'on' : ''}" ${cur === k.id ? 'data-autofocus' : ''}>
        <span class="mochi-mini ${k.rainbow ? 'rainbow' : ''}" style="--hi:${k.hi};--lo:${k.lo};--line:${k.line};--eye:${k.eye}"></span>
        <b>${k.name}</b><small>${open ? (cur === k.id ? '사용 중' : '고르기') : `딸기 ${k.need}개`}</small></button>`;
    }).join('');
    return `
      <h2>꾸미기</h2>
      <div class="sub">딸기를 모으면 새 찰떡이 열려요 · 지금 ${BERRY} ${have}개</div>
      <div class="skins">${cards}</div>
      <div class="menu"><button data-nav data-back>뒤로</button></div>`;
  }

  updateMute() {
    const m = this.app.save.data.options.muted;
    $('#btn-mute').textContent = m ? '🔇' : '🔊';
  }

  html_credits() {
    return `
      <h2>만든 사람</h2>
      <div class="credits">
        <p><b>찰떡 점프</b></p>
        <p>기획 · 프로그래밍 · 그래픽 · 사운드 · 레벨 디자인<br>Claude와 함께 만든 게임</p>
        <p>그림은 모두 코드로 그렸고, 소리는 실시간으로 합성합니다.<br>24개 스테이지는 모두 자동 풀이 프로그램으로 클리어 가능함을 확인했습니다.</p>
      </div>
      <div class="menu"><button data-nav data-back>뒤로</button></div>`;
  }

  html_pause() {
    const play = this.app.play;
    return `
      <h2>일시정지</h2>
      <div class="sub">${play.def.id} ${play.def.name}</div>
      <div class="menu">
        <button data-nav data-act="resume" data-back>계속하기</button>
        <button data-nav data-act="restart">다시 시작</button>
        <button data-nav data-act="select">스테이지 선택</button>
        <button data-nav data-act="options">설정</button>
      </div>`;
  }

  html_clear(r) {
    const b = r.got.map((x) => (x ? BERRY : NOBERRY)).join('');
    return `
      <h2 class="pop">클리어!</h2>
      <div class="sub">${r.id} ${r.name}</div>
      <div class="bigberries">${b}</div>
      <div class="medalrow">${medalIcon(r.medal)}<span><b>${MEDAL_NAME[r.medal]}</b>${r.medal === 'gold' ? ' 최고예요!' : ` · 금메달은 점프 ${r.par + 1}번 이하`}</span></div>
      <div class="result">
        <div><small>점프</small><b>${r.launches}</b>${r.newBest && !r.firstClear ? '<em>최고 기록!</em>' : ''}</div>
        <div><small>시간</small><b>${fmt(r.time)}</b></div>
        <div><small>넘어짐</small><b>${r.deaths}</b></div>
      </div>
      <div class="menu row">
        <button data-nav data-act="next" data-autofocus>${r.last ? '엔딩 보기' : '다음 스테이지'}</button>
        <button data-nav data-act="restart">다시 하기</button>
        <button data-nav data-act="select">스테이지 선택</button>
      </div>`;
  }

  html_ending() {
    const s = this.app.save;
    return `
      <div class="mochi-big happy"><span></span></div>
      <h2>모든 하늘을 건넜어요!</h2>
      <div class="credits">
        <p>찰떡이는 부엌을 빠져나와 정원을 지나<br>밤하늘 끝의 별에 닿았습니다.</p>
        <p class="big">${BERRY} ${s.totalBerries()} / ${LEVELS.length * 3}</p>
        <p class="dim">${s.totalBerries() < LEVELS.length * 3 ? '아직 못 모은 딸기가 있어요. 다시 도전해 보세요!' : '딸기를 전부 모았어요. 완벽해요!'}</p>
        <p class="dim">플레이해 주셔서 고마워요.</p>
      </div>
      <div class="menu row">
        <button data-nav data-act="select">스테이지 선택</button>
        <button data-nav data-act="title">타이틀로</button>
      </div>`;
  }

  // ------------------------------------------------------------ events
  bind(el, arg) {
    const app = this.app;
    el.addEventListener('click', (e) => {
      const b = e.target.closest('button');
      if (!b) return;
      app.sound.init();
      if (b.dataset.tab !== undefined) { this.world = +b.dataset.tab; app.sound.play('click'); this.show('select'); this.setFocus(this.world, false); return; }
      if (b.dataset.level !== undefined) {
        const i = +b.dataset.level;
        if (!app.unlocked(i)) { app.sound.play('die'); return; }
        app.sound.play('click'); app.startLevel(i); return;
      }
      if (b.dataset.range) { this.setFocus(this.items.indexOf(b), false); return; }
      if (b.dataset.skin) {
        const k = SKINS.find((x) => x.id === b.dataset.skin);
        if (app.save.totalBerries() < k.need) { app.sound.play('die'); return; }
        app.save.data.options.skin = k.id; app.save.write(); app.applySkinCss(); app.sound.play('berry');
        const f = this.focus; this.show('skins'); this.setFocus(f, false);
        return;
      }
      if (b.dataset.toggle) {
        const o = app.save.data.options, k = b.dataset.toggle;
        o[k] = !o[k];
        const t = b.querySelector('.tog'); t.classList.toggle('on', o[k]); t.textContent = o[k] ? '켜짐' : '꺼짐';
        app.applyOptions(k); app.sound.play('click');
        return;
      }
      app.sound.play('click');
      const act = b.dataset.act;
      if (b.hasAttribute('data-back') && !act) { app.save.write(); this.pop(); return; }
      switch (act) {
        case 'continue': app.startLevel(app.nextLevel()); break;
        case 'select': this.world = WORLDS.findIndex((w) => w.id === LEVELS[Math.min(app.nextLevel(), LEVELS.length - 1)].world); if (app.play) app.toSelect(); else this.push('select'); break;
        case 'options': this.push('options'); break;
        case 'credits': this.push('credits'); break;
        case 'skins': this.push('skins'); break;
        case 'quit': window.close(); break;
        case 'resume': app.resume(); break;
        case 'restart': app.restart(); break;
        case 'next': app.next(); break;
        case 'title': app.toTitle(); break;
      }
    });
  }

  // ------------------------------------------------------------ HUD
  showHud(on) { this.hud.classList.toggle('hidden', !on); }

  updateHud(play) {
    const w = play.world;
    const key = `${play.def.id}|${w.got.join()}|${w.launches}`;
    if (this.hudKey !== key) {
      this.hudKey = key;
      $('#lvname').textContent = `${play.def.id} ${play.def.name}`;
      $('#hudberries').innerHTML = w.got.map((g) => (g ? BERRY : NOBERRY)).join('');
      $('#launches').textContent = `점프 ${w.launches} / 금 ${play.par + 1}`;
    }
  }

  tip(text) {
    const t = $('#tip');
    t.textContent = text || '';
    t.classList.toggle('show', !!text);
    clearTimeout(this.tipTimer);
    if (text) this.tipTimer = setTimeout(() => t.classList.remove('show'), 4200);
  }
}
