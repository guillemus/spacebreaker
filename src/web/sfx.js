// STARBREAKER audio: every sound is synthesized with WebAudio, no samples.
(() => {
	'use strict';

	const SFX = {
		SHOOT: 0, HIT: 1, EXPLODE_S: 2, EXPLODE_L: 3, MISSILE: 4, LOCK: 5, AMMO: 6, HULL_HIT: 7,
		SHIELD_HIT: 8, WAVE: 9, CLEAR: 10, BOSS: 11, ENEMY_FIRE: 12, OVERHEAT: 13, GAME_OVER: 14,
		UI: 15, WARP: 16, EMPTY: 17, CHARGE: 18, POP: 19, MEGA: 20,
	};
	// Minimum seconds between two plays of the same sound, keeps dense fights from clipping.
	const THROTTLE = { 1: 0.035, 2: 0.03, 19: 0.03, 12: 0.05, 18: 0.1 };

	let ctx = null;
	let master, sfxBus, musicBus, musicFilter, reverbSend, noiseBuffer;
	let muted = false;
	let intensity = 0.1;
	let smoothIntensity = 0.1;
	const lastPlayed = {};

	function makeNoise(seconds) {
		const len = Math.floor(ctx.sampleRate * seconds);
		const buf = ctx.createBuffer(1, len, ctx.sampleRate);
		const data = buf.getChannelData(0);
		for (let i = 0; i < len; i++) data[i] = Math.random() * 2 - 1;
		return buf;
	}

	function makeImpulse(seconds, decay) {
		const len = Math.floor(ctx.sampleRate * seconds);
		const buf = ctx.createBuffer(2, len, ctx.sampleRate);
		for (let ch = 0; ch < 2; ch++) {
			const data = buf.getChannelData(ch);
			for (let i = 0; i < len; i++) data[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, decay);
		}
		return buf;
	}

	function init() {
		if (ctx) {
			if (ctx.state === 'suspended') ctx.resume();
			return;
		}
		const AC = window.AudioContext || window.webkitAudioContext;
		if (!AC) return;
		ctx = new AC();
		master = ctx.createGain();
		master.gain.value = muted ? 0 : 0.85;
		const comp = ctx.createDynamicsCompressor();
		comp.threshold.value = -16;
		comp.knee.value = 14;
		comp.ratio.value = 5;
		comp.attack.value = 0.002;
		comp.release.value = 0.25;
		master.connect(comp).connect(ctx.destination);

		sfxBus = ctx.createGain();
		sfxBus.gain.value = 0.8;
		sfxBus.connect(master);

		musicFilter = ctx.createBiquadFilter();
		musicFilter.type = 'lowpass';
		musicFilter.frequency.value = 900;
		musicFilter.Q.value = 0.7;
		musicBus = ctx.createGain();
		musicBus.gain.value = 0.3;
		musicBus.connect(musicFilter).connect(master);

		const reverb = ctx.createConvolver();
		reverb.buffer = makeImpulse(2.6, 2.4);
		reverbSend = ctx.createGain();
		reverbSend.gain.value = 0.3;
		reverbSend.connect(reverb).connect(master);

		noiseBuffer = makeNoise(2);
		nextStep = ctx.currentTime + 0.1;
	}
	['pointerdown', 'mousedown', 'keydown', 'touchstart'].forEach(ev => window.addEventListener(ev, init, { passive: true }));

	// ---- building blocks ---------------------------------------------------------------

	function output(pan, wet) {
		const p = ctx.createStereoPanner();
		p.pan.value = Math.max(-1, Math.min(1, pan));
		p.connect(sfxBus);
		if (wet > 0) {
			const send = ctx.createGain();
			send.gain.value = wet;
			p.connect(send).connect(reverbSend);
		}
		return p;
	}

	function envGain(dest, t, vol, attack, dur) {
		const g = ctx.createGain();
		g.gain.setValueAtTime(0.0001, t);
		g.gain.exponentialRampToValueAtTime(Math.max(vol, 0.0002), t + attack);
		g.gain.exponentialRampToValueAtTime(0.0001, t + attack + dur);
		g.connect(dest);
		return g;
	}

	function tone(dest, t, type, f0, f1, dur, vol, attack = 0.003) {
		const o = ctx.createOscillator();
		o.type = type;
		o.frequency.setValueAtTime(Math.max(f0, 1), t);
		o.frequency.exponentialRampToValueAtTime(Math.max(f1, 1), t + attack + dur);
		o.connect(envGain(dest, t, vol, attack, dur));
		o.start(t);
		o.stop(t + attack + dur + 0.05);
		return o;
	}

	function noise(dest, t, filterType, f0, f1, q, dur, vol, attack = 0.003) {
		const src = ctx.createBufferSource();
		src.buffer = noiseBuffer;
		src.loop = true;
		const f = ctx.createBiquadFilter();
		f.type = filterType;
		f.Q.value = q;
		f.frequency.setValueAtTime(f0, t);
		f.frequency.exponentialRampToValueAtTime(Math.max(f1, 10), t + attack + dur);
		src.connect(f).connect(envGain(dest, t, vol, attack, dur));
		src.start(t, Math.random() * 1.5);
		src.stop(t + attack + dur + 0.05);
	}

	const mtof = m => 440 * Math.pow(2, (m - 69) / 12);

	// ---- sound effects -------------------------------------------------------------------

	function play(id, vol, pan, pitch) {
		if (!ctx || ctx.state !== 'running' || vol <= 0.001) return;
		const t = ctx.currentTime;
		const gap = THROTTLE[id];
		if (gap !== undefined) {
			if (lastPlayed[id] !== undefined && t - lastPlayed[id] < gap) return;
			lastPlayed[id] = t;
		}
		const p = pitch;
		switch (id) {
			case SFX.SHOOT: {
				const o = output(pan, 0.08);
				tone(o, t, 'square', 1500 * p, 380 * p, 0.06, 0.05 * vol);
				tone(o, t, 'sawtooth', 820 * p, 140 * p, 0.09, 0.05 * vol);
				noise(o, t, 'highpass', 5000, 3000, 0.7, 0.03, 0.05 * vol);
				break;
			}
			case SFX.HIT: {
				const o = output(pan, 0.05);
				noise(o, t, 'bandpass', 2600 * p, 700 * p, 1.4, 0.06, 0.22 * vol);
				tone(o, t, 'triangle', 340 * p, 120 * p, 0.05, 0.08 * vol);
				break;
			}
			case SFX.EXPLODE_S: {
				const o = output(pan, 0.35);
				noise(o, t, 'lowpass', 2800 * p, 140, 0.8, 0.55, 0.5 * vol);
				tone(o, t, 'sine', 130 * p, 38, 0.35, 0.45 * vol);
				noise(o, t + 0.02, 'highpass', 3500, 1500, 0.5, 0.18, 0.12 * vol);
				break;
			}
			case SFX.EXPLODE_L: {
				const o = output(pan, 0.6);
				noise(o, t, 'lowpass', 2200 * p, 55, 0.9, 1.5, 0.85 * vol, 0.005);
				tone(o, t, 'sine', 95 * p, 24, 1.0, 0.9 * vol);
				tone(o, t, 'sawtooth', 60 * p, 28, 0.6, 0.18 * vol);
				noise(o, t + 0.05, 'highpass', 4000, 1200, 0.6, 0.45, 0.2 * vol);
				break;
			}
			case SFX.MEGA: {
				const o = output(pan, 0.8);
				noise(o, t, 'lowpass', 1800, 40, 0.9, 3.2, 1.0 * vol, 0.01);
				tone(o, t, 'sine', 70, 18, 2.4, 1.0 * vol);
				tone(o, t, 'sawtooth', 45, 20, 1.6, 0.25 * vol);
				noise(o, t + 0.1, 'bandpass', 900, 120, 1.0, 2.0, 0.35 * vol);
				break;
			}
			case SFX.MISSILE: {
				const o = output(pan, 0.3);
				tone(o, t, 'sine', 170, 50, 0.22, 0.35 * vol);
				noise(o, t, 'bandpass', 380, 2800, 2.2, 0.85, 0.4 * vol, 0.02);
				tone(o, t, 'sawtooth', 90, 260, 0.6, 0.07 * vol, 0.03);
				break;
			}
			case SFX.LOCK: {
				const o = output(pan, 0.05);
				tone(o, t, 'square', 1760, 1760, 0.045, 0.045 * vol, 0.002);
				tone(o, t + 0.07, 'square', 2349, 2349, 0.06, 0.045 * vol, 0.002);
				break;
			}
			case SFX.AMMO: {
				const o = output(pan, 0.25);
				[880, 1318, 1760].forEach((f, i) => tone(o, t + i * 0.055, 'triangle', f, f, 0.12, 0.1 * vol, 0.003));
				break;
			}
			case SFX.HULL_HIT: {
				const o = output(pan, 0.3);
				noise(o, t, 'lowpass', 1100, 90, 0.8, 0.45, 0.8 * vol);
				tone(o, t, 'sawtooth', 120, 36, 0.45, 0.35 * vol);
				tone(o, t + 0.02, 'square', 660, 640, 0.12, 0.06 * vol);
				tone(o, t + 0.18, 'square', 660, 640, 0.12, 0.06 * vol);
				break;
			}
			case SFX.SHIELD_HIT: {
				const o = output(pan, 0.4);
				tone(o, t, 'sine', 720, 180, 0.4, 0.32 * vol);
				tone(o, t, 'triangle', 1300, 2600, 0.3, 0.07 * vol);
				noise(o, t, 'bandpass', 3200, 500, 2.0, 0.35, 0.25 * vol);
				break;
			}
			case SFX.WAVE: {
				const o = output(0, 0.5);
				const f = ctx.createBiquadFilter();
				f.type = 'lowpass';
				f.frequency.setValueAtTime(4000, t);
				f.frequency.exponentialRampToValueAtTime(300, t + 1.2);
				f.connect(o);
				[57, 60, 64, 69].forEach(m => {
					tone(f, t, 'sawtooth', mtof(m), mtof(m) * 1.003, 1.1, 0.07 * vol, 0.01);
					tone(f, t, 'sawtooth', mtof(m) * 0.997, mtof(m), 1.1, 0.05 * vol, 0.01);
				});
				tone(o, t, 'sine', 110, 55, 0.8, 0.35 * vol);
				break;
			}
			case SFX.CLEAR: {
				const o = output(0, 0.5);
				[69, 72, 76, 81, 84].forEach((m, i) => tone(o, t + i * 0.09, 'triangle', mtof(m), mtof(m), 0.35, 0.11 * vol, 0.004));
				tone(o, t + 0.45, 'sine', mtof(93), mtof(93), 0.8, 0.06 * vol, 0.01);
				break;
			}
			case SFX.BOSS: {
				const o = output(0, 0.4);
				for (let i = 0; i < 4; i++) {
					const f = i % 2 === 0 ? 440 : 330;
					tone(o, t + i * 0.34, 'square', f, f * 0.98, 0.3, 0.07 * vol, 0.01);
					tone(o, t + i * 0.34, 'sawtooth', f / 2, f / 2, 0.3, 0.06 * vol, 0.01);
				}
				tone(o, t, 'sine', 55, 40, 1.6, 0.4 * vol, 0.05);
				break;
			}
			case SFX.ENEMY_FIRE: {
				const o = output(pan, 0.2);
				tone(o, t, 'sawtooth', 480 * p, 1100 * p, 0.16, 0.08 * vol);
				tone(o, t, 'square', 240 * p, 90 * p, 0.2, 0.06 * vol);
				break;
			}
			case SFX.OVERHEAT: {
				const o = output(0, 0.2);
				noise(o, t, 'highpass', 7000, 1800, 0.5, 0.9, 0.22 * vol, 0.01);
				tone(o, t, 'square', 220, 200, 0.12, 0.06 * vol);
				tone(o, t + 0.15, 'square', 165, 150, 0.16, 0.06 * vol);
				break;
			}
			case SFX.GAME_OVER: {
				const o = output(0, 0.7);
				tone(o, t, 'sawtooth', 330, 30, 2.4, 0.2 * vol, 0.02);
				tone(o, t, 'sawtooth', 332, 31, 2.4, 0.15 * vol, 0.02);
				noise(o, t, 'lowpass', 1500, 60, 0.7, 2.5, 0.4 * vol, 0.02);
				break;
			}
			case SFX.UI: {
				const o = output(pan, 0.1);
				tone(o, t, 'sine', 990 * p, 990 * p, 0.06, 0.1 * vol, 0.002);
				tone(o, t + 0.05, 'sine', 1480 * p, 1480 * p, 0.09, 0.08 * vol, 0.002);
				break;
			}
			case SFX.WARP: {
				const o = output(pan, 0.5);
				tone(o, t, 'sine', 60, 1400, 0.7, 0.14 * vol, 0.05);
				noise(o, t, 'bandpass', 200, 5000, 3.0, 0.7, 0.2 * vol, 0.05);
				break;
			}
			case SFX.EMPTY: {
				const o = output(pan, 0);
				tone(o, t, 'square', 180, 150, 0.04, 0.06 * vol, 0.001);
				tone(o, t + 0.07, 'square', 150, 120, 0.05, 0.05 * vol, 0.001);
				break;
			}
			case SFX.CHARGE: {
				const o = output(pan, 0.15);
				tone(o, t, 'sawtooth', 160 * p, 900 * p, 0.75, 0.035 * vol, 0.05);
				break;
			}
			case SFX.POP: {
				const o = output(pan, 0.2);
				tone(o, t, 'sine', 900 * p, 200 * p, 0.09, 0.15 * vol);
				noise(o, t, 'highpass', 3000, 1500, 0.8, 0.06, 0.1 * vol);
				break;
			}
		}
	}

	// ---- music: a small synthwave sequencer driven by game intensity ------------------------

	const BPM = 104;
	const STEP = 60 / BPM / 4;
	const CHORDS = [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]];
	const BASS = [33, 29, 36, 31];
	let nextStep = 0;
	let stepIndex = 0;

	function kick(t, vol) {
		tone(musicBus, t, 'sine', 150, 42, 0.22, 0.9 * vol, 0.002);
		noise(musicBus, t, 'lowpass', 1200, 200, 0.7, 0.03, 0.15 * vol, 0.001);
	}
	function hat(t, vol) {
		noise(musicBus, t, 'highpass', 8000, 7000, 0.8, 0.035, 0.12 * vol, 0.001);
	}
	function snare(t, vol) {
		noise(musicBus, t, 'bandpass', 1800, 900, 0.9, 0.18, 0.35 * vol, 0.002);
		tone(musicBus, t, 'triangle', 230, 170, 0.1, 0.18 * vol, 0.002);
	}
	function bass(t, midi, vol) {
		const f = ctx.createBiquadFilter();
		f.type = 'lowpass';
		f.Q.value = 6;
		f.frequency.setValueAtTime(300 + smoothIntensity * 1600, t);
		f.frequency.exponentialRampToValueAtTime(140, t + STEP * 1.8);
		f.connect(musicBus);
		tone(f, t, 'sawtooth', mtof(midi), mtof(midi), STEP * 1.6, 0.35 * vol, 0.004);
		tone(f, t, 'square', mtof(midi) * 0.5, mtof(midi) * 0.5, STEP * 1.6, 0.2 * vol, 0.004);
	}
	function pad(t, chord, dur, vol) {
		chord.forEach(m => {
			[-6, 6].forEach(cents => {
				const o = ctx.createOscillator();
				o.type = 'sawtooth';
				o.frequency.value = mtof(m);
				o.detune.value = cents;
				const g = ctx.createGain();
				g.gain.setValueAtTime(0.0001, t);
				g.gain.exponentialRampToValueAtTime(0.03 * vol, t + dur * 0.35);
				g.gain.exponentialRampToValueAtTime(0.0001, t + dur * 1.05);
				o.connect(g).connect(musicBus);
				o.start(t);
				o.stop(t + dur * 1.1);
			});
		});
	}
	function arp(t, midi, vol) {
		tone(musicBus, t, 'square', mtof(midi), mtof(midi), STEP * 0.8, 0.05 * vol, 0.002);
	}

	function scheduleStep(i, t) {
		const s = i % 16;
		const bar = Math.floor(i / 16) % 4;
		const I = smoothIntensity;
		if (s === 0) pad(t, CHORDS[bar], STEP * 16, 0.6 + I * 0.4);
		if (s % 2 === 0 && I > 0.08) bass(t, BASS[bar] + (s % 8 === 6 ? 12 : 0), Math.min(1, 0.4 + I));
		if (I > 0.25 && s % 4 === 0) kick(t, Math.min(1, I + 0.2));
		else if (I > 0.08 && s === 0) kick(t, 0.5);
		if (I > 0.4 && s % 4 === 2) hat(t, I);
		if (I > 0.7 && s % 2 === 1) hat(t, I * 0.5);
		if (I > 0.55 && (s === 4 || s === 12)) snare(t, I);
		if (I > 0.75) {
			const chord = CHORDS[bar];
			arp(t, chord[s % 3] + 12 + (Math.floor(s / 3) % 2) * 12, I - 0.5);
		}
	}

	function scheduler() {
		if (!ctx || ctx.state !== 'running') return;
		smoothIntensity += (intensity - smoothIntensity) * 0.08;
		musicFilter.frequency.setTargetAtTime(700 + smoothIntensity * 5200, ctx.currentTime, 0.4);
		if (nextStep < ctx.currentTime) nextStep = ctx.currentTime + 0.05;
		while (nextStep < ctx.currentTime + 0.15) {
			scheduleStep(stepIndex, nextStep);
			nextStep += STEP;
			stepIndex = (stepIndex + 1) % 64;
		}
	}
	setInterval(scheduler, 25);

	window.SB = {
		sfx: (id, vol, pan, pitch) => play(id, vol, pan, pitch),
		music: value => { intensity = Math.max(0, Math.min(1, value)); },
		setMuted: value => {
			muted = value;
			if (master) master.gain.setTargetAtTime(muted ? 0 : 0.85, ctx.currentTime, 0.05);
		},
	};
})();
