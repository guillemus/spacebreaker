// Emscripten JS library: functions the Odin game imports from "env".
addToLibrary({
	js_sfx: function (id, vol, pan, pitch) {
		if (window.SB) window.SB.sfx(id, vol, pan, pitch);
	},
	js_music: function (intensity) {
		if (window.SB) window.SB.music(intensity);
	},
	js_set_muted: function (muted) {
		if (window.SB) window.SB.setMuted(muted !== 0);
	},
	js_get_best: function () {
		try {
			return parseInt(localStorage.getItem('starbreaker_best') || '0', 10) | 0;
		} catch (e) {
			return 0;
		}
	},
	js_get_start_wave: function () {
		const w = parseInt(new URLSearchParams(window.location.search).get('wave') || '1', 10);
		return Number.isFinite(w) && w >= 1 ? Math.min(w, 99) : 1;
	},
	js_set_best: function (value) {
		try {
			localStorage.setItem('starbreaker_best', String(value));
		} catch (e) {}
	},
});
