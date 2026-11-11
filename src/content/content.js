/* Skyward+ — content script. Reads the gradebook, injects the launcher + overlay. */
(function () {
  const SP = globalThis.SkywardPlus;
  const S = SP.storage;
  const isTop = window.top === window.self;
  let shadow = null, overlayOpen = false, mounted = null;

  /* ---------- capture ---------- */
  async function captureNow(doc = document) {
    try {
      const { courses, debug } = SP.parse.scrapePage(doc, location.href);
      if (!courses.length) return { courses: 0, assignments: 0, debug };
      const res = await S.ingest(courses, { source: 'scrape' });
      return {
        courses: courses.length,
        assignments: courses.reduce((s, c) => s + c.assignments.length, 0),
        added: res.added, updated: res.updated, debug,
      };
    } catch (e) {
      return { error: e.message };
    }
  }
  SP.captureNow = captureNow;

  /* ---------- overlay ---------- */
  const HOST_CSS = `
    :host { all: initial; }
    .sp-launcher {
      position: fixed; right: 18px; bottom: 18px; z-index: 2147483000;
      display: flex; align-items: center; gap: 8px; padding: 10px 15px;
      border: 0; border-radius: 999px; cursor: pointer;
      font: 600 13px/1 Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
      color: #fff; background: linear-gradient(140deg, #5b9dff, #8a6bff);
      box-shadow: 0 8px 26px rgba(40,80,180,.38); transition: transform .14s ease, box-shadow .14s ease;
    }
    .sp-launcher:hover { transform: translateY(-1px); box-shadow: 0 12px 32px rgba(40,80,180,.5); }
    .sp-launcher b { font-weight: 800; }
    .sp-launcher .count {
      background: rgba(255,255,255,.22); border-radius: 999px; padding: 2px 7px; font-size: 11px; font-weight: 700;
    }
    .sp-overlay {
      position: fixed; inset: 0; z-index: 2147483001; display: none;
      background: rgba(6,8,12,.62); backdrop-filter: blur(3px);
      animation: sp-fade .16s ease;
    }
    .sp-overlay[data-open="true"] { display: block; }
    .sp-panel {
      position: absolute; inset: 22px; border-radius: 16px; overflow: hidden;
      box-shadow: 0 30px 90px rgba(0,0,0,.5); border: 1px solid #242a35;
      display: flex; flex-direction: column; background: #0a0c10;
      animation: sp-rise .18s cubic-bezier(.2,.8,.3,1);
    }
    @media (max-width: 720px) { .sp-panel { inset: 0; border-radius: 0; border: 0; } }
    @keyframes sp-fade { from { opacity: 0 } }
    @keyframes sp-rise { from { opacity: 0; transform: translateY(10px) scale(.995) } }
  `;

  async function ensureShadow() {
    if (shadow) return shadow;
    const host = document.createElement('div');
    host.id = 'skyward-plus-root';
    host.style.cssText = 'all:initial;position:static';
    (document.body || document.documentElement).appendChild(host);
    shadow = host.attachShadow({ mode: 'open' });

    const base = document.createElement('style');
    base.textContent = HOST_CSS;
    shadow.appendChild(base);

    const appCss = document.createElement('style');
    try {
      appCss.textContent = await fetch(chrome.runtime.getURL('src/ui/app.css')).then((r) => r.text());
    } catch { /* CSS still loads via the <link> fallback below */ }
    shadow.appendChild(appCss);
    return shadow;
  }

  async function openOverlay() {
    const sh = await ensureShadow();
    let overlay = sh.querySelector('.sp-overlay');
    if (!overlay) {
      overlay = document.createElement('div');
      overlay.className = 'sp-overlay';
      const panel = document.createElement('div');
      panel.className = 'sp-panel';
      overlay.appendChild(panel);
      overlay.addEventListener('mousedown', (e) => { if (e.target === overlay) closeOverlay(); });
      sh.appendChild(overlay);
      mounted = await SP.ui.mount(panel, { embedded: true, onClose: closeOverlay });
    } else if (mounted) {
      await mounted.reload();
    }
    overlay.dataset.open = 'true';
    overlayOpen = true;
    document.addEventListener('keydown', escHandler, true);
    const search = sh.querySelector('[data-act="search"]');
    if (search) setTimeout(() => search.focus(), 60);
  }

  function closeOverlay() {
    const overlay = shadow && shadow.querySelector('.sp-overlay');
    if (overlay) overlay.dataset.open = 'false';
    overlayOpen = false;
    document.removeEventListener('keydown', escHandler, true);
  }

  const escHandler = (e) => { if (e.key === 'Escape' && overlayOpen) { e.stopPropagation(); closeOverlay(); } };

  async function showLauncher(stats) {
    const sh = await ensureShadow();
    let btn = sh.querySelector('.sp-launcher');
    if (!btn) {
      btn = document.createElement('button');
      btn.className = 'sp-launcher';
      btn.addEventListener('click', () => (overlayOpen ? closeOverlay() : openOverlay()));
      sh.appendChild(btn);
    }
    const data = await S.load();
    const n = Object.keys(data.courses).length;
    btn.innerHTML = `<b>Skyward+</b>${n ? `<span class="count">${n}</span>` : ''}`;
    btn.title = stats && stats.courses
      ? `Captured ${stats.courses} class(es) on this page — click to open`
      : 'Open Skyward+';
  }

  /* ---------- lifecycle ---------- */
  async function boot() {
    const data = await S.load();
    let stats = null;
    if (data.settings.autoCapture) stats = await captureNow();
    if (isTop) {
      await showLauncher(stats);
      // Re-capture when the gradebook re-renders (Qmlativ SPA / partial postbacks).
      let last = document.body ? document.body.innerHTML.length : 0;
      const tick = SP.util.debounce(async () => {
        const now = document.body.innerHTML.length;
        if (Math.abs(now - last) < 400) return;
        last = now;
        const s = await captureNow();
        if (s && s.courses) { showLauncher(s); if (mounted && overlayOpen) mounted.reload(); }
      }, 1200);
      new MutationObserver(tick).observe(document.body, { childList: true, subtree: true });
    } else if (stats && stats.courses) {
      // Frame-based Skyward: tell the top frame that new data landed.
      try { chrome.runtime.sendMessage({ type: 'captured', stats }); } catch { /* no-op */ }
    }
  }

  chrome.runtime.onMessage.addListener((msg, sender, respond) => {
    if (msg.type === 'open-overlay') { if (isTop) openOverlay(); respond({ ok: true }); return true; }
    if (msg.type === 'capture') { captureNow().then(respond); return true; }
    if (msg.type === 'captured') { if (isTop) showLauncher(msg.stats); return false; }
    return false;
  });

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
