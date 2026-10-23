// Page-side helpers for scripts/e2e/cdp.py, evaluated in the Flutter web page
// once semantics are on. A node's label is its aria-label, else its text.
// Adapted from ~/src/tutor/scripts/e2e_page.js.
({
  label: (e) => (e.getAttribute('aria-label') || e.textContent || '').trim(),

  nodes: () => [...document.querySelectorAll('flt-semantics, [role], [aria-label]')],

  // Semantics are off until the hidden placeholder is clicked.
  enableSemantics() {
    const p = document.querySelector('flt-semantics-placeholder');
    if (p) p.click();
    return document.querySelectorAll('flt-semantics').length;
  },

  // The node labelled `label` (else the first whose label starts with it, else
  // contains it). A container can carry its only child's label: a button
  // wins, then the smallest box. Returns the centre of its on-screen part.
  find(label) {
    const area = (e) => {
      const r = e.getBoundingClientRect();
      return r.width * r.height;
    };
    const off = (e) => (e.getAttribute('aria-disabled') === 'true' ? 2e12 : 0);
    const clickable = (e) =>
      ['button', 'checkbox', 'link', 'tab'].includes(e.getAttribute('role'));
    const rank = (e) => off(e) + (clickable(e) ? 0 : 1e12) + area(e);
    const sized = (e) => area(e) > 0;
    const best = (list) => list.filter(sized).sort((a, b) => rank(a) - rank(b))[0];
    const all = this.nodes();
    const hit = best(all.filter((e) => this.label(e) === label))
      || best(all.filter((e) => this.label(e).startsWith(label)))
      || best(all.filter((e) => this.label(e).includes(label)));
    if (!hit) return null;
    const r = hit.getBoundingClientRect();
    const top = Math.max(r.top, 0), bottom = Math.min(r.bottom, innerHeight);
    const left = Math.max(r.left, 0), right = Math.min(r.right, innerWidth);
    const visible = bottom - top >= 4 && right - left >= 4;
    return {
      x: visible ? (left + right) / 2 : r.x + r.width / 2,
      y: visible ? (top + bottom) / 2 : r.y + r.height / 2,
      visible,
      below: r.top >= innerHeight,
      disabled: hit.getAttribute('aria-disabled') === 'true',
      checked: hit.getAttribute('aria-checked') || hit.getAttribute('aria-selected'),
      text: this.label(hit),
    };
  },

  // Labels of selected role chips (`<name> (<count>)`), e.g. to deselect.
  selectedChips() {
    const on = (e) => [e.getAttribute('aria-checked'), e.getAttribute('aria-selected')]
      .includes('true');
    return [...new Set(this.nodes().filter(on).map((e) => this.label(e))
      .filter((t) => /^.+ \(\d+\)$/.test(t)))];
  },

  // Every non-empty label on the page, one per line.
  text() {
    return [...new Set(this.nodes().map((e) => this.label(e)).filter((t) => t))].join('\n');
  },

  // The stored script imported from file `source`, read straight from
  // IndexedDB (lib/storage/idb_store.dart: db `sufler`, store `json`).
  async script(source) {
    const db = await new Promise((ok, bad) => {
      const r = indexedDB.open('sufler');
      r.onsuccess = () => ok(r.result);
      r.onerror = () => bad(r.error);
    });
    const all = await new Promise((ok, bad) => {
      const r = db.transaction('json').objectStore('json').getAll();
      r.onsuccess = () => ok(r.result);
      r.onerror = () => bad(r.error);
    });
    db.close();
    const scripts = all.map((s) => JSON.parse(s)).filter((s) => s && s.lines);
    return scripts.find((s) => s.source === source) || null;
  },
})
