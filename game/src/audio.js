// Synthesized sound effects and a small step sequencer for music.
// No audio files: everything is made with WebAudio oscillators and noise.

const mtof = (m) => 440 * Math.pow(2, (m - 69) / 12);

const TRACKS = {
  menu:   { bpm: 76,  prog: [[57, 'm'], [53, ''], [48, ''], [55, '']], bass: 'whole', arp: 'bell', drums: false, lead: 'sine', pad: true },
  battle: { bpm: 120, prog: [[57, 'm'], [53, ''], [48, ''], [55, '']], bass: 'eighth', arp: 'fast', drums: true, lead: 'triangle', pad: false },
  boss:   { bpm: 140, prog: [[50, 'm'], [46, ''], [43, 'm'], [45, '']], bass: 'sixteenth', arp: 'fast', drums: true, lead: 'sawtooth', pad: false },
};

export class Sound {
  constructor() {
    this.ctx = null;
    this.vol = { master: 0.8, music: 0.6, sfx: 0.8 };
    this.last = {};
    this.track = null;
    this.wanted = null;
    this.step = 0;
    this.nextTime = 0;
    this.played = 0; // count of sfx played (used by tests)
  }

  // Must be called from a user gesture.
  init() {
    if (this.ctx) { if (this.ctx.state === 'suspended') this.ctx.resume(); return; }
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    const ctx = this.ctx = new AC();
    this.master = ctx.createGain();
    this.musicG = ctx.createGain();
    this.sfxG = ctx.createGain();
    const comp = ctx.createDynamicsCompressor();
    this.musicG.connect(this.master);
    this.sfxG.connect(this.master);
    this.master.connect(comp).connect(ctx.destination);
    const len = ctx.sampleRate;
    this.noiseBuf = ctx.createBuffer(1, len, ctx.sampleRate);
    const d = this.noiseBuf.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    this.applyVol();
    setInterval(() => this.schedule(), 25);
    if (this.wanted) this.music(this.wanted);
  }

  setVolumes(v) { Object.assign(this.vol, v); this.applyVol(); }
  applyVol() {
    if (!this.ctx) return;
    this.master.gain.value = this.vol.master;
    this.musicG.gain.value = this.vol.music * 0.45;
    this.sfxG.gain.value = this.vol.sfx * 0.55;
  }

  tone(freq, dur, type = 'square', vol = 0.2, slideTo = null, delay = 0, dest = this.sfxG) {
    const ctx = this.ctx, t = ctx.currentTime + delay;
    const o = ctx.createOscillator(), g = ctx.createGain();
    o.type = type;
    o.frequency.setValueAtTime(freq, t);
    if (slideTo) o.frequency.exponentialRampToValueAtTime(slideTo, t + dur);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(vol, t + 0.008);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g).connect(dest);
    o.start(t); o.stop(t + dur + 0.05);
  }

  noise(dur, vol, freq = 2000, type = 'bandpass', delay = 0, dest = this.sfxG, at = null) {
    const ctx = this.ctx, t = at ?? ctx.currentTime + delay;
    const s = ctx.createBufferSource(); s.buffer = this.noiseBuf;
    const f = ctx.createBiquadFilter(); f.type = type; f.frequency.value = freq;
    const g = ctx.createGain();
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    s.connect(f).connect(g).connect(dest);
    s.start(t, Math.random() * 0.5); s.stop(t + dur + 0.05);
  }

  play(name) {
    if (!this.ctx) return;
    const now = performance.now();
    const gap = { hit: 45, gem: 30, shoot: 60, kill: 40, spark: 60, zap: 60, coin: 30, explode: 70 }[name] || 0;
    if (gap && now - (this.last[name] || 0) < gap) return;
    this.last[name] = now;
    this.played++;
    switch (name) {
      case 'click': this.tone(880, 0.06, 'triangle', 0.15); break;
      case 'move': this.tone(660, 0.04, 'triangle', 0.08); break;
      case 'shoot': this.tone(720, 0.09, 'square', 0.05, 360); break;
      case 'spark': this.noise(0.08, 0.12, 5000, 'highpass'); break;
      case 'hit': this.noise(0.05, 0.12, 1800); this.tone(180, 0.05, 'square', 0.04, 90); break;
      case 'kill': this.tone(300, 0.1, 'triangle', 0.07, 120); break;
      case 'gem': this.tone(1200 + Math.random() * 300, 0.06, 'sine', 0.06, 1800); break;
      case 'coin': this.tone(1500, 0.06, 'square', 0.05); this.tone(2000, 0.08, 'square', 0.05, null, 0.05); break;
      case 'zap': this.noise(0.15, 0.16, 3500, 'highpass'); this.tone(1400, 0.12, 'sawtooth', 0.05, 400); break;
      case 'explode': this.noise(0.4, 0.35, 400, 'lowpass'); this.tone(120, 0.3, 'sine', 0.25, 40); break;
      case 'hurt': this.tone(220, 0.18, 'sawtooth', 0.12, 80); this.noise(0.12, 0.15, 800); break;
      case 'heal': [660, 880, 1100].forEach((f, i) => this.tone(f, 0.12, 'sine', 0.1, null, i * 0.06)); break;
      case 'levelup': [523, 659, 784, 1046].forEach((f, i) => this.tone(f, 0.18, 'triangle', 0.14, null, i * 0.07)); break;
      case 'chest': [392, 523, 659, 784, 1046, 1318].forEach((f, i) => this.tone(f, 0.2, 'square', 0.07, null, i * 0.06)); break;
      case 'boss': this.tone(110, 1.2, 'sawtooth', 0.2, 55); this.noise(1.0, 0.2, 300, 'lowpass'); break;
      case 'victory': [523, 659, 784, 1046, 784, 1046, 1318].forEach((f, i) => this.tone(f, 0.3, 'triangle', 0.14, null, i * 0.12)); break;
      case 'defeat': [392, 349, 311, 262].forEach((f, i) => this.tone(f, 0.45, 'triangle', 0.14, null, i * 0.22)); break;
    }
  }

  // ---------------------------------------------------------------- music
  music(name) {
    this.wanted = name;
    if (!this.ctx) return;
    if (this.track === name) return;
    this.track = name;
    this.step = 0;
    this.nextTime = this.ctx.currentTime + 0.1;
  }

  schedule() {
    if (!this.ctx || !this.track) return;
    const tr = TRACKS[this.track];
    const stepDur = 60 / tr.bpm / 4;
    while (this.nextTime < this.ctx.currentTime + 0.15) {
      this.playStep(tr, this.step, this.nextTime, stepDur);
      this.step++;
      this.nextTime += stepDur;
    }
  }

  voice(freq, t, dur, type, vol) {
    const ctx = this.ctx;
    const o = ctx.createOscillator(), g = ctx.createGain();
    o.type = type; o.frequency.value = freq;
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(vol, t + Math.min(0.02, dur * 0.2));
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g).connect(this.musicG);
    o.start(t); o.stop(t + dur + 0.05);
  }

  playStep(tr, step, t, sd) {
    const s = step % 16, bar = Math.floor(step / 16);
    const [root, q] = tr.prog[bar % tr.prog.length];
    const chord = [root, root + (q === 'm' ? 3 : 4), root + 7];
    // bass
    if (tr.bass === 'whole' && s === 0) this.voice(mtof(root - 12), t, sd * 16, 'sine', 0.22);
    if (tr.bass === 'eighth' && s % 2 === 0) this.voice(mtof(root - 12 + (s === 10 ? 7 : 0)), t, sd * 1.8, 'triangle', 0.3);
    if (tr.bass === 'sixteenth') this.voice(mtof(root - 12 + (s % 4 === 3 ? 12 : 0)), t, sd * 0.9, 'sawtooth', 0.12);
    // pad
    if (tr.pad && s === 0) for (const n of chord) this.voice(mtof(n), t, sd * 16, 'sine', 0.05);
    // arp
    if (tr.arp === 'bell' && s % 4 === 0) this.voice(mtof(chord[(s / 4 + bar) % 3] + 24), t, sd * 6, 'sine', 0.06);
    if (tr.arp === 'fast') {
      const n = chord[s % 3] + (s % 6 < 3 ? 12 : 24);
      this.voice(mtof(n), t, sd * 0.9, tr.lead, tr.lead === 'sawtooth' ? 0.03 : 0.05);
    }
    // drums
    if (tr.drums) {
      if (s % 4 === 0) {
        const ctx = this.ctx, o = ctx.createOscillator(), g = ctx.createGain();
        o.frequency.setValueAtTime(140, t); o.frequency.exponentialRampToValueAtTime(40, t + 0.12);
        g.gain.setValueAtTime(0.5, t); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.15);
        o.connect(g).connect(this.musicG); o.start(t); o.stop(t + 0.2);
      }
      if (s % 2 === 1) this.noise(0.04, 0.06, 8000, 'highpass', 0, this.musicG, t);
      if (s === 4 || s === 12) this.noise(0.14, 0.18, 1500, 'bandpass', 0, this.musicG, t);
    }
  }
}
