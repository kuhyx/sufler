// Injected before the app boots (Page.addScriptToEvaluateOnNewDocument) so
// the E2E driver can see audio start: wraps speechSynthesis.speak (flutter_tts
// on web) and HTMLMediaElement.play (audioplayers on web) and logs each call
// and its outcome into window.__suflerAudio. Observes only; never alters.
(() => {
  const log = (window.__suflerAudio = []);
  const now = () => Math.round(performance.now());
  const synth = window.speechSynthesis;
  if (synth) {
    const speak = synth.speak.bind(synth);
    synth.speak = (u) => {
      const voices = synth.getVoices();
      const entry = {
        kind: 'speech', t: now(), chars: (u.text || '').length, lang: u.lang,
        voices: voices.length, plVoices: voices.filter((v) => /^pl/i.test(v.lang)).length,
      };
      log.push(entry);
      u.addEventListener('start', () => { entry.started = now(); });
      u.addEventListener('end', () => { entry.ended = now(); });
      u.addEventListener('error', (e) => { entry.error = e.error || 'error'; });
      return speak(u);
    };
  }
  const play = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function () {
    const entry = { kind: 'media', t: now(), src: String(this.src).slice(0, 40) };
    log.push(entry);
    const p = play.call(this);
    p.then(() => { entry.playing = now(); }, (e) => { entry.error = String(e); });
    this.addEventListener('ended', () => { entry.ended = now(); }, { once: true });
    return p;
  };
})();
