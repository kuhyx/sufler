// Injected before the app boots (Page.addScriptToEvaluateOnNewDocument) so
// the E2E driver can see audio start: wraps speechSynthesis.speak (flutter_tts
// on web) and HTMLMediaElement.play (audioplayers on web) and logs each call
// and its outcome (for media, the clip's duration) into window.__suflerAudio.
// Also logs each `/api/` request (fetch or XHR: path, status, start/end,
// bytes) into window.__suflerNet, and for a rendered clip (`render_line`) its
// duration, so a later call can read a request an earlier one started.
// Observes only; never alters. Registered again by each boot(): the first
// copy per document wins.
(() => {
  if (window.__suflerAudio) return;
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
  // Each element gets a number, so repeated play() calls on one element (a
  // no-op while it plays) can be told apart from two clips sounding at once.
  const ids = new WeakMap();
  let elements = 0;
  HTMLMediaElement.prototype.play = function () {
    if (!ids.has(this)) ids.set(this, ++elements);
    const entry = {
      kind: 'media', t: now(), el: ids.get(this), paused: this.paused,
      src: String(this.src).slice(0, 40),
    };
    log.push(entry);
    const p = play.call(this);
    p.then(() => { entry.playing = now(); entry.duration = this.duration; },
      (e) => { entry.error = String(e); });
    this.addEventListener('ended', () => { entry.ended = now(); }, { once: true });
    return p;
  };
  const net = (window.__suflerNet = []);
  const api = (url) => {
    const at = String(url).indexOf('/api/');
    return at < 0 ? null : String(url).slice(at);
  };
  // The size, and for a clip its duration, of a finished response body.
  const body = (entry, blob) => {
    entry.bytes = blob.size;
    if (!entry.path.includes('render_line') || !blob.size) return;
    const a = new Audio();
    a.preload = 'metadata';
    a.onloadedmetadata = () => { entry.clipSeconds = a.duration; };
    a.src = URL.createObjectURL(blob);
  };
  const fetch0 = window.fetch;
  window.fetch = function (input, init) {
    const path = api(input && input.url ? input.url : input);
    const p = fetch0.call(this, input, init);
    if (!path) return p;
    const entry = { path, t: now(), via: 'fetch' };
    net.push(entry);
    p.then((r) => {
      entry.status = r.status;
      r.clone().blob().then((b) => { entry.done = now(); body(entry, b); },
        (e) => { entry.error = String(e); });
    }, (e) => { entry.error = String(e); entry.done = now(); });
    return p;
  };
  const open = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (method, url, ...rest) {
    this.__suflerPath = api(url);
    return open.call(this, method, url, ...rest);
  };
  const send = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function (...args) {
    if (this.__suflerPath) {
      const entry = { path: this.__suflerPath, t: now(), via: 'xhr' };
      net.push(entry);
      this.addEventListener('loadend', () => {
        entry.status = this.status;
        entry.done = now();
        const r = this.response;
        if (r instanceof Blob) body(entry, r);
        else if (r instanceof ArrayBuffer) body(entry, new Blob([r]));
        else if (['', 'text'].includes(this.responseType)) entry.bytes = this.responseText.length;
      });
    }
    return send.apply(this, args);
  };
})();
