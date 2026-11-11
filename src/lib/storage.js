/* Skyward+ — persistence. chrome.storage.local when available, localStorage otherwise. */
(function () {
  const SP = (globalThis.SkywardPlus = globalThis.SkywardPlus || {});
  const U = SP.util;

  const KEY = 'skywardplus:v1';
  const hasChrome = typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local;

  const DEFAULTS = {
    courses: {},          // id -> course
    settings: {
      scale: 'standard',
      mode: 'auto',       // auto | weighted | points
      theme: 'dark',
      weightedGpa: false,
      showClassAvg: true,
      density: 'comfortable',
      autoCapture: true,
      hideDropped: true,
    },
    edits: {},            // courseId -> { assignmentId -> {earned, possible, excluded} }
    hypotheticals: {},    // courseId -> [assignment]
    levels: {},           // courseId -> regular|honors|ap
    snapshots: [],        // [{date, grades: {courseId: percent}}]
    lastSeen: {},         // courseId -> {percent, at}
    updatedAt: null,
  };

  const deepDefaults = (data) => {
    const out = { ...DEFAULTS, ...(data || {}) };
    out.settings = { ...DEFAULTS.settings, ...(data && data.settings) };
    for (const k of ['courses', 'edits', 'hypotheticals', 'levels', 'lastSeen'])
      out[k] = { ...(data && data[k] ? data[k] : {}) };
    out.snapshots = (data && data.snapshots) || [];
    return out;
  };

  async function load() {
    if (hasChrome) {
      const got = await chrome.storage.local.get(KEY);
      return deepDefaults(got[KEY]);
    }
    try {
      return deepDefaults(JSON.parse(localStorage.getItem(KEY) || '{}'));
    } catch {
      return deepDefaults(null);
    }
  }

  async function save(data) {
    data.updatedAt = new Date().toISOString();
    if (hasChrome) return chrome.storage.local.set({ [KEY]: data });
    localStorage.setItem(KEY, JSON.stringify(data));
  }

  async function update(fn) {
    const data = await load();
    const next = (await fn(data)) || data;
    await save(next);
    return next;
  }

  /* Merge a freshly scraped course into the store without losing prior detail:
     a page that only shows the summary grade must not wipe assignments. */
  function mergeCourse(existing, incoming) {
    if (!existing) return incoming;
    const merged = { ...existing };
    for (const k of ['name', 'teacher', 'period', 'room', 'term', 'url']) {
      if (incoming[k]) merged[k] = incoming[k];
    }
    if (incoming.reportedPercent !== null) merged.reportedPercent = incoming.reportedPercent;
    if (incoming.reportedLetter) merged.reportedLetter = incoming.reportedLetter;
    if (incoming.courseClassAverage !== null) merged.courseClassAverage = incoming.courseClassAverage;
    if (incoming.categories && incoming.categories.length) merged.categories = incoming.categories;

    if (incoming.assignments && incoming.assignments.length) {
      const byId = new Map(existing.assignments.map((a) => [a.id, a]));
      for (const a of incoming.assignments) {
        const prev = byId.get(a.id);
        byId.set(a.id, prev ? { ...prev, ...a, classAverage: a.classAverage != null ? a.classAverage : prev.classAverage } : a);
      }
      // Drop stale scrapes for this term that the latest capture no longer lists.
      const incomingIds = new Set(incoming.assignments.map((a) => a.id));
      const sameTerm = (x) => !incoming.term || !x.term || x.term === incoming.term;
      merged.assignments = [...byId.values()].filter(
        (a) => incomingIds.has(a.id) || a.hypothetical || a.source === 'manual' || !sameTerm(a)
      );
    }
    merged.capturedAt = incoming.capturedAt || existing.capturedAt;
    return merged;
  }

  async function ingest(courses, { source = 'scrape' } = {}) {
    if (!courses || !courses.length) return { added: 0, updated: 0 };
    let added = 0, updated = 0;
    await update((data) => {
      for (const raw of courses) {
        const c = SP.model.normalizeCourse({ ...raw, capturedAt: new Date().toISOString() });
        c.assignments = c.assignments.map((a) => ({ ...a, source: a.source || source }));
        if (data.courses[c.id]) { data.courses[c.id] = mergeCourse(data.courses[c.id], c); updated++; }
        else { data.courses[c.id] = c; added++; }
      }
      return data;
    });
    return { added, updated };
  }

  /* One snapshot per day, so the trend line is daily-resolution. */
  async function snapshot(results) {
    return update((data) => {
      const date = U.today();
      const grades = {};
      for (const [id, r] of Object.entries(results)) if (r && r.percent !== null) grades[id] = U.round(r.percent, 2);
      if (!Object.keys(grades).length) return data;
      const idx = data.snapshots.findIndex((s) => s.date === date);
      if (idx >= 0) data.snapshots[idx] = { date, grades };
      else data.snapshots.push({ date, grades });
      data.snapshots = data.snapshots.slice(-180);
      return data;
    });
  }

  function seriesFor(snapshots, courseId) {
    return snapshots
      .filter((s) => s.grades[courseId] !== undefined)
      .map((s) => ({ date: s.date, value: s.grades[courseId] }));
  }

  function changeSince(snapshots, courseId, current) {
    const s = seriesFor(snapshots, courseId);
    if (!s.length || current === null) return null;
    const prior = [...s].reverse().find((p) => p.value !== U.round(current, 2));
    if (!prior) return null;
    return { delta: U.round(current - prior.value, 2), from: prior.value, date: prior.date };
  }

  SP.storage = { KEY, DEFAULTS, load, save, update, ingest, snapshot, seriesFor, changeSince, mergeCourse, hasChrome };
})();
