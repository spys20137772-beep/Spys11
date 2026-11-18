// Synthesized sound effects and a small step sequencer for music.
// No audio files: everything is made with WebAudio oscillators and noise.

const mtof = (m) => 440 * Math.pow(2, (m - 69) / 12);

const TRACKS = {
  menu:    { bpm: 90,  prog: [[60, ''], [57, 'm'], [53, ''], [55, '']], bass: 'whole', arp: 'bell', drums: false, lead: 'sine', pad: true },
  kitchen: { bpm: 112, prog: [[60, ''], [57, 'm'], [53, ''], [55, '']], bass: 'eighth', arp: 'fast', drums: true, lead: 'triangle', pad: false },
  garden:  { bpm: 100, prog: [[53, ''], [50, 'm'], [46, ''], [48, '']], bass: 'eighth', arp: 'bell', drums: true, lead: 'sine', pad: true },
  night:   { bpm: 80,  prog: [[57, 'm'], [53, ''], [48, ''], [55, '']], bass: 'whole', arp: 'bell', drums: false, lead: 'sine', pad: true },
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
    const gap = { stick: 40, clink: 50, crumble: 60, boing: 60 }[name] || 0;
    if (gap && now - (this.last[name] || 0) < gap) return;
    this.last[name] = now;
    this.played++;
    switch (name) {
      case 'click': this.tone(880, 0.06, 'triangle', 0.15); break;
      case 'move': this.tone(660, 0.04, 'triangle', 0.08); break;
      case 'launch': this.noise(0.18, 0.12, 1200, 'bandpass'); this.tone(300, 0.16, 'sine', 0.12, 700); break;
      case 'stick': this.tone(140, 0.09, 'sine', 0.22, 70); this.noise(0.07, 0.1, 600, 'lowpass'); break;
      case 'boing': this.tone(220, 0.28, 'sine', 0.22, 880); this.tone(330, 0.2, 'triangle', 0.06, 990, 0.02); break;
      case 'clink': this.tone(1760, 0.08, 'triangle', 0.08); this.tone(2640, 0.06, 'sine', 0.05, null, 0.01); break;
      case 'break': this.noise(0.25, 0.3, 900, 'bandpass'); this.tone(110, 0.15, 'square', 0.08, 60); break;
      case 'crumble': this.noise(0.2, 0.18, 2500, 'bandpass'); break;
      case 'berry': [1046, 1318, 1568, 2093].forEach((f, i) => this.tone(f, 0.14, 'sine', 0.1, null, i * 0.05)); break;
      case 'flag': [784, 1046].forEach((f, i) => this.tone(f, 0.18, 'triangle', 0.12, null, i * 0.09)); break;
      case 'die': this.tone(600, 0.25, 'square', 0.08, 120); this.noise(0.2, 0.15, 1500); break;
      case 'goal': [523, 659, 784, 1046, 1318].forEach((f, i) => this.tone(f, 0.26, 'triangle', 0.13, null, i * 0.08)); break;
      case 'ending': [523, 659, 784, 1046, 784, 1046, 1318, 1568].forEach((f, i) => this.tone(f, 0.35, 'triangle', 0.13, null, i * 0.13)); break;
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
