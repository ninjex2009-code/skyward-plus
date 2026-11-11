/* Skyward+ — shared helpers. Attaches to globalThis.SkywardPlus. */
(function () {
  const SP = (globalThis.SkywardPlus = globalThis.SkywardPlus || {});

  const num = (v) => {
    if (v === null || v === undefined || v === '') return null;
    if (typeof v === 'number') return isFinite(v) ? v : null;
    const m = String(v).replace(/,/g, '').match(/-?\d+(\.\d+)?/);
    return m ? parseFloat(m[0]) : null;
  };

  const clamp = (n, lo, hi) => Math.min(hi, Math.max(lo, n));

  const round = (n, places = 2) => {
    if (n === null || n === undefined || !isFinite(n)) return null;
    const f = Math.pow(10, places);
    return Math.round(n * f) / f;
  };

  /* Deterministic id from arbitrary strings — keeps assignments stable across scrapes. */
  const hash = (...parts) => {
    const s = parts.filter(Boolean).join('|').toLowerCase().trim();
    let h = 2166136261;
    for (let i = 0; i < s.length; i++) {
      h ^= s.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    return (h >>> 0).toString(36);
  };

  const clean = (s) =>
    String(s == null ? '' : s)
      .replace(/[\u00a0\u200b]/g, " ")
      .replace(/\s+/g, ' ')
      .trim();

  const titleCase = (s) =>
    clean(s).replace(/\w\S*/g, (t) => t[0].toUpperCase() + t.slice(1).toLowerCase());

  const pad = (n) => String(n).padStart(2, '0');

  /* "12/04/2025", "Dec 4", "2025-12-04" -> sortable ISO date (or null). */
  const parseDate = (s) => {
    const t = clean(s);
    if (!t) return null;
    let m = t.match(/(\d{4})-(\d{1,2})-(\d{1,2})/);
    if (m) return `${m[1]}-${pad(m[2])}-${pad(m[3])}`;
    m = t.match(/(\d{1,2})\/(\d{1,2})\/(\d{2,4})/);
    if (m) {
      const y = m[3].length === 2 ? '20' + m[3] : m[3];
      return `${y}-${pad(m[1])}-${pad(m[2])}`;
    }
    m = t.match(/^(\d{1,2})\/(\d{1,2})$/);
    if (m) return `${new Date().getFullYear()}-${pad(m[1])}-${pad(m[2])}`;
    const d = new Date(t);
    if (!isNaN(d.getTime())) return d.toISOString().slice(0, 10);
    return null;
  };

  const fmtDate = (iso) => {
    if (!iso) return '--';
    const [y, m, d] = iso.split('-').map(Number);
    if (!y) return iso;
    return new Date(y, m - 1, d).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
  };

  const today = () => new Date().toISOString().slice(0, 10);

  const pct = (earned, possible) =>
    possible && possible > 0 && earned !== null && earned !== undefined
      ? (earned / possible) * 100
      : null;

  const fmtPct = (p, places = 2) => {
    if (p === null || p === undefined || !isFinite(p)) return '--';
    return round(p, places).toFixed(places) + '%';
  };

  const fmtSigned = (n, places = 2) => {
    if (n === null || n === undefined || !isFinite(n)) return '--';
    const r = round(n, places);
    const sign = r > 0 ? '+' : r < 0 ? '-' : '';
    return sign + Math.abs(r).toFixed(places) + '%';
  };

  const sortBy = (arr, ...keys) =>
    arr.slice().sort((a, b) => {
      for (const k of keys) {
        const fn = typeof k === 'function' ? k : k.fn;
        const dir = typeof k === 'function' ? 1 : k.dir || 1;
        const av = fn(a), bv = fn(b);
        if (av === bv) continue;
        if (av === null || av === undefined) return 1;
        if (bv === null || bv === undefined) return -1;
        return (av > bv ? 1 : -1) * dir;
      }
      return 0;
    });

  const groupBy = (arr, fn) => {
    const map = new Map();
    for (const item of arr) {
      const k = fn(item);
      if (!map.has(k)) map.set(k, []);
      map.get(k).push(item);
    }
    return map;
  };

  const debounce = (fn, ms) => {
    let t;
    return (...a) => {
      clearTimeout(t);
      t = setTimeout(() => fn(...a), ms);
    };
  };

  const escapeHtml = (s) =>
    String(s == null ? '' : s).replace(/[&<>"']/g, (c) =>
      ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])
    );

  SP.util = { num, clamp, round, hash, clean, titleCase, parseDate, fmtDate, today, pct, fmtPct, fmtSigned, sortBy, groupBy, debounce, escapeHtml };
})();
