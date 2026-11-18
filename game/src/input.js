// Keyboard + gamepad input.
const PAD = { a: 0, b: 1, x: 2, y: 3, select: 8, start: 9, up: 12, down: 13, left: 14, right: 15 };

export class Input {
  constructor() {
    this.keys = new Set();
    this.pressed = new Set();
    this.padPressed = new Set();
    this.padPrev = {};
    this.pad = null;
    this.padMove = null; // test hook: {x,y}
    this.botMove = null; // test hook: function returning {x,y}
    addEventListener('keydown', (e) => {
      if (!this.keys.has(e.code)) this.pressed.add(e.code);
      this.keys.add(e.code);
      if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Space', 'Enter'].includes(e.code)) e.preventDefault();
    });
    addEventListener('keyup', (e) => this.keys.delete(e.code));
    addEventListener('blur', () => this.keys.clear());
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

  endFrame() { this.pressed.clear(); this.padPressed.clear(); }

  move() {
    if (this.botMove) return this.botMove();
    let x = 0, y = 0;
    const k = this.keys;
    if (k.has('KeyA') || k.has('ArrowLeft')) x -= 1;
    if (k.has('KeyD') || k.has('ArrowRight')) x += 1;
    if (k.has('KeyW') || k.has('ArrowUp')) y -= 1;
    if (k.has('KeyS') || k.has('ArrowDown')) y += 1;
    if (this.pad) {
      const ax = this.pad.axes[0] || 0, ay = this.pad.axes[1] || 0;
      if (Math.hypot(ax, ay) > 0.2) { x += ax; y += ay; }
      const b = this.pad.buttons;
      if (b[14]?.pressed) x -= 1;
      if (b[15]?.pressed) x += 1;
      if (b[12]?.pressed) y -= 1;
      if (b[13]?.pressed) y += 1;
    }
    const l = Math.hypot(x, y);
    if (l > 1) { x /= l; y /= l; }
    return { x, y };
  }

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
    }
    return false;
  }

  any() { return this.pressed.size > 0 || this.padPressed.size > 0; }
}
