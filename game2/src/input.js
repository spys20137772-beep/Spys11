// Input: pull-to-launch with mouse/touch, keyboard aiming, gamepad aiming, menu navigation.
const PAD = { a: 0, b: 1, x: 2, y: 3, start: 9, up: 12, down: 13, left: 14, right: 15 };

export class Input {
  constructor() {
    this.keys = new Set();
    this.pressed = new Set();
    this.padPressed = new Set();
    this.padPrev = {};
    this.pad = null;
    this.drag = null;         // {id, ox, oy, x, y} in CSS px
    this.released = null;     // {dx, dy} pull vector on release (consumed by game)
    this.enabled = () => false;
    addEventListener('keydown', (e) => {
      if (!this.keys.has(e.code)) this.pressed.add(e.code);
      this.keys.add(e.code);
      if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Space', 'Enter'].includes(e.code)) e.preventDefault();
    });
    addEventListener('keyup', (e) => this.keys.delete(e.code));
    addEventListener('blur', () => { this.keys.clear(); this.drag = null; });
  }

  attach(el) {
    el.addEventListener('pointerdown', (e) => {
      window.focus();
      if (!this.enabled() || this.drag) return;
      this.drag = { id: e.pointerId, ox: e.clientX, oy: e.clientY, x: e.clientX, y: e.clientY };
      try { el.setPointerCapture(e.pointerId); } catch { /* ignore */ }
      e.preventDefault();
    });
    el.addEventListener('pointermove', (e) => {
      if (this.drag && this.drag.id === e.pointerId) { this.drag.x = e.clientX; this.drag.y = e.clientY; }
    });
    const end = (e, cancel) => {
      const d = this.drag;
      if (!d || d.id !== e.pointerId) return;
      this.drag = null;
      if (!cancel) this.released = { dx: d.x - d.ox, dy: d.y - d.oy };
    };
    el.addEventListener('pointerup', (e) => end(e, false));
    el.addEventListener('pointercancel', (e) => end(e, true));
  }

  poll() {
    this.pad = null;
    const pads = navigator.getGamepads ? navigator.getGamepads() : [];
    for (const p of pads) if (p && p.connected) { this.pad = p; break; }
    if (!this.pad) return;
    const b = this.pad.buttons;
    for (const [name, i] of Object.entries(PAD)) {
      const now = !!(b[i] && b[i].pressed);
      if (now && !this.padPrev[name]) this.padPressed.add(name);
      this.padPrev[name] = now;
    }
    const ax = this.pad.axes[0] || 0, ay = this.pad.axes[1] || 0;
    const dirs = { su: ay < -0.6, sd: ay > 0.6, sl: ax < -0.6, sr: ax > 0.6 };
    for (const [n, v] of Object.entries(dirs)) {
      if (v && !this.padPrev[n]) this.padPressed.add(n);
      this.padPrev[n] = v;
    }
  }

  // Gamepad left stick as an aim vector (launch direction), or null.
  padAim() {
    if (!this.pad) return null;
    const x = this.pad.axes[0] || 0, y = this.pad.axes[1] || 0, m = Math.hypot(x, y);
    return m > 0.3 ? { x: x / m, y: y / m, k: Math.min(1, (m - 0.3) / 0.65) } : null;
  }

  endFrame() { this.pressed.clear(); this.padPressed.clear(); }

  act(name) {
    const k = this.pressed, p = this.padPressed;
    switch (name) {
      case 'up': return k.has('ArrowUp') || k.has('KeyW') || p.has('up') || p.has('su');
      case 'down': return k.has('ArrowDown') || k.has('KeyS') || p.has('down') || p.has('sd');
      case 'left': return k.has('ArrowLeft') || k.has('KeyA') || p.has('left') || p.has('sl');
      case 'right': return k.has('ArrowRight') || k.has('KeyD') || p.has('right') || p.has('sr');
      case 'ok': return k.has('Enter') || k.has('Space') || p.has('a');
      case 'back': return k.has('Escape') || k.has('Backspace') || p.has('b');
      case 'pause': return k.has('Escape') || k.has('KeyP') || p.has('start');
      case 'restart': return k.has('KeyR') || p.has('y');
      case 'launch': return k.has('Space') || k.has('Enter') || p.has('a');
    }
    return false;
  }

  held(code) { return this.keys.has(code); }
}
