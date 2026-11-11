/* Skyward+ — UI. Mounts into a shadow root (overlay) or a plain div (dashboard). */
(function () {
  const SP = (globalThis.SkywardPlus = globalThis.SkywardPlus || {});
  const U = SP.util, M = SP.model, S = SP.storage;
  const h = U.escapeHtml;

  const state = {
    host: null, root: null, data: null,
    results: {}, baseResults: {}, impacts: {},
    view: 'overview', courseId: null,
    query: '', term: 'all', sort: 'due', dir: -1, filterCat: null,
    expanded: new Set(), whatIf: true, onClose: null, embedded: false,
    debugInfo: null, toastTimer: null,
  };
  SP.state = state;

  /* ---------- small view helpers ---------- */
  const gradeVar = (p) =>
    p === null || p === undefined ? 'var(--text-faint)'
      : p >= 90 ? 'var(--a)' : p >= 80 ? 'var(--b)' : p >= 70 ? 'var(--c)' : p >= 60 ? 'var(--d)' : 'var(--f)';

  const deltaClass = (d) => (d === null || d === undefined || Math.abs(d) < 0.005 ? 'flat' : d > 0 ? 'up' : 'down');

  const ring = (percent, size = 108, stroke = 9) => {
    const r = (size - stroke) / 2, c = 2 * Math.PI * r;
    const p = percent === null ? 0 : U.clamp(percent, 0, 100);
    return `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" aria-hidden="true">
      <circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="var(--surface-3)" stroke-width="${stroke}"/>
      <circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="${gradeVar(percent)}"
        stroke-width="${stroke}" stroke-linecap="round"
        stroke-dasharray="${(c * p) / 100} ${c}" style="transition:stroke-dasharray .35s ease"/>
    </svg>`;
  };

  const sparkline = (series, w = 96, hgt = 26) => {
    if (!series || series.length < 2) return '';
    const vals = series.map((s) => s.value);
    const min = Math.min(...vals), max = Math.max(...vals);
    const span = Math.max(1.2, max - min);
    const pts = series.map((s, i) => {
      const x = (i / (series.length - 1)) * w;
      const y = hgt - ((s.value - min) / span) * (hgt - 4) - 2;
      return `${U.round(x, 1)},${U.round(y, 1)}`;
    });
    const last = vals[vals.length - 1];
    return `<svg class="sp-sparkline" width="${w}" height="${hgt}" viewBox="0 0 ${w} ${hgt}">
      <polyline points="${pts.join(' ')}" fill="none" stroke="${gradeVar(last)}" stroke-width="1.6"
        stroke-linejoin="round" stroke-linecap="round" opacity=".9"/>
      <circle cx="${pts[pts.length - 1].split(',')[0]}" cy="${pts[pts.length - 1].split(',')[1]}" r="2.2" fill="${gradeVar(last)}"/>
    </svg>`;
  };

  const vsBars = (yours, classAvg) => {
    if (yours === null || classAvg === null || classAvg === undefined) return '';
    const cap = Math.max(100, yours, classAvg);
    return `<div class="sp-vs">
      <div class="sp-vs-row"><span>you</span><div class="sp-vs-track"><i style="width:${U.clamp((yours / cap) * 100, 0, 100)}%;background:${gradeVar(yours)}"></i></div></div>
      <div class="sp-vs-row"><span>class</span><div class="sp-vs-track"><i style="width:${U.clamp((classAvg / cap) * 100, 0, 100)}%;background:var(--text-faint)"></i></div></div>
    </div>`;
  };

  const chip = (label, value, kind = '') =>
    `<span class="sp-chip ${kind}">${h(label)}${value !== undefined && value !== null ? ` <b>${h(value)}</b>` : ''}</span>`;

  /* ---------- data access ---------- */
  const allCourses = () =>
    Object.values(state.data.courses).map((c) => ({ ...c, level: state.data.levels[c.id] || c.level || 'regular' }));

  const termsAvailable = () => {
    const t = [...new Set(allCourses().map((c) => c.term).filter(Boolean))];
    return U.sortBy(t, (x) => x);
  };

  const visibleCourses = () => {
    let list = allCourses();
    if (state.term !== 'all') list = list.filter((c) => (c.term || '') === state.term);
    if (state.query) {
      const q = state.query.toLowerCase();
      list = list.filter(
        (c) => c.name.toLowerCase().includes(q) || (c.teacher || '').toLowerCase().includes(q) ||
          c.assignments.some((a) => a.name.toLowerCase().includes(q))
      );
    }
    return U.sortBy(list, (c) => (U.num(c.period) === null ? 99 : U.num(c.period)), (c) => c.name.toLowerCase());
  };

  const optsFor = (c, withEdits = true) => ({
    edits: withEdits && state.whatIf ? state.data.edits[c.id] || {} : {},
    extra: withEdits && state.whatIf ? state.data.hypotheticals[c.id] || [] : [],
    mode: state.data.settings.mode,
    scale: state.data.settings.scale,
  });

  const hasWhatIf = (id) =>
    Object.keys(state.data.edits[id] || {}).length > 0 || (state.data.hypotheticals[id] || []).length > 0;
  const anyWhatIf = () => allCourses().some((c) => hasWhatIf(c.id));

  function recompute() {
    state.results = {}; state.baseResults = {};
    for (const c of allCourses()) {
      state.results[c.id] = M.computeCourse(c, optsFor(c, true));
      state.baseResults[c.id] = M.computeCourse(c, optsFor(c, false));
    }
  }

  const resultFor = (id) => state.results[id];
  const courseById = (id) => allCourses().find((c) => c.id === id);

  /* ---------- rail ---------- */
  function railHtml() {
    const courses = visibleCourses();
    const d = state.data;
    const gpa = M.gpa(courses, state.results, d.settings.scale, d.settings.weightedGpa);
    const gpaBase = M.gpa(courses, state.baseResults, d.settings.scale, d.settings.weightedGpa);
    const gpaDelta = gpa !== null && gpaBase !== null ? U.round(gpa - gpaBase, 2) : 0;
    const terms = termsAvailable();

    const courseRows = courses.map((c) => {
      const r = resultFor(c.id);
      const pct = r ? r.percent : null;
      const basePct = state.baseResults[c.id] ? state.baseResults[c.id].percent : pct;
      const change = S.changeSince(d.snapshots, c.id, basePct);
      return `<button class="sp-course-btn" data-act="nav-course" data-id="${h(c.id)}" aria-current="${state.view === 'course' && state.courseId === c.id}">
        <span class="sp-course-name">${h(c.name)}</span>
        <span class="sp-course-grade" style="color:${gradeVar(pct)}">${pct === null ? '--' : U.round(pct, 1)}<small>${r && r.letter ? h(r.letter) : ''}</small></span>
        <span class="sp-course-meta">
          ${c.period ? `P${h(c.period)}` : ''}${c.period && c.term ? ' · ' : ''}${c.term ? h(c.term) : ''}
          ${r && r.missingCount ? `<span style="color:var(--bad)">· ${r.missingCount} missing</span>` : ''}
          ${change && Math.abs(change.delta) >= 0.05 ? `<span class="sp-delta ${deltaClass(change.delta)}">· ${U.fmtSigned(change.delta, 1)}</span>` : ''}
          ${hasWhatIf(c.id) ? '<span style="color:var(--accent)">· what-if</span>' : ''}
        </span>
        <span class="sp-bar"><i style="width:${pct === null ? 0 : U.clamp(pct, 0, 100)}%;background:${gradeVar(pct)}"></i></span>
      </button>`;
    }).join('');

    return `
      <div class="sp-gpa">
        <div class="sp-gpa-row">
          <div>
            <div class="sp-gpa-val" style="color:${gpa === null ? 'var(--text)' : gradeVar(gpa * 25)}">${gpa === null ? '--' : gpa.toFixed(2)}</div>
            <small>${d.settings.weightedGpa ? 'Weighted' : 'Unweighted'} GPA · ${courses.length} class${courses.length === 1 ? '' : 'es'}</small>
          </div>
          <button class="sp-btn ghost" data-act="toggle-gpa" title="Toggle weighted GPA">${d.settings.weightedGpa ? 'W' : 'U'}</button>
        </div>
        ${gpaDelta ? `<div class="sp-delta ${deltaClass(gpaDelta)}" style="font-size:12px;margin-top:4px">${gpaDelta > 0 ? '+' : ''}${gpaDelta.toFixed(2)} with what-if</div>` : ''}
      </div>
      <button class="sp-course-btn" data-act="nav-overview" aria-current="${state.view === 'overview'}" style="grid-template-columns:1fr">
        <span class="sp-course-name">All classes</span>
        <span class="sp-course-meta">Overview, GPA, what needs work</span>
      </button>
      ${terms.length > 1 ? `<div class="sp-rail-title">Term
        <select class="sp-select" data-act="set-term" style="font-size:11px;padding:2px 4px">
          <option value="all"${state.term === 'all' ? ' selected' : ''}>All</option>
          ${terms.map((t) => `<option value="${h(t)}"${state.term === t ? ' selected' : ''}>${h(t)}</option>`).join('')}
        </select></div>` : ''}
      <div class="sp-rail-title">Classes</div>
      ${courseRows || '<p class="sp-help" style="padding:0 6px">No classes yet — capture a Skyward page or import.</p>'}
      <div style="flex:1"></div>
      <div class="sp-rail-title">Data</div>
      <button class="sp-course-btn" data-act="nav-import" aria-current="${state.view === 'import'}" style="grid-template-columns:1fr">
        <span class="sp-course-name">Import / export</span>
        <span class="sp-course-meta">Paste grades, JSON, CSV</span>
      </button>
      <button class="sp-course-btn" data-act="nav-settings" aria-current="${state.view === 'settings'}" style="grid-template-columns:1fr">
        <span class="sp-course-name">Settings</span>
        <span class="sp-course-meta">Scale, weighting, theme</span>
      </button>`;
  }

  /* ---------- overview ---------- */
  function overviewHtml() {
    const courses = visibleCourses();
    if (!courses.length) return emptyStateHtml();
    const d = state.data;

    const withPct = courses.map((c) => ({ c, r: resultFor(c.id) })).filter((x) => x.r && x.r.percent !== null);
    const avg = withPct.length ? withPct.reduce((s, x) => s + x.r.percent, 0) / withPct.length : null;
    const missing = courses.reduce((s, c) => s + (resultFor(c.id) ? resultFor(c.id).missingCount : 0), 0);
    const graded = courses.reduce((s, c) => s + (resultFor(c.id) ? resultFor(c.id).gradedCount : 0), 0);
    const vsAll = M.vsClassSummary(courses.flatMap((c) => resultFor(c.id) ? resultFor(c.id).assignments : []));
    const captured = courses.map((c) => c.capturedAt).filter(Boolean).sort().pop();

    const cards = courses.map((c) => {
      const r = resultFor(c.id);
      const base = state.baseResults[c.id];
      const series = S.seriesFor(d.snapshots, c.id);
      const change = S.changeSince(d.snapshots, c.id, base ? base.percent : null);
      const weakest = r && r.categories.length
        ? U.sortBy(r.categories.filter((k) => k.percent !== null), (k) => k.percent)[0] : null;
      const vs = r ? M.vsClassSummary(r.assignments) : null;
      const whatIfDelta = r && base && r.percent !== null && base.percent !== null ? U.round(r.percent - base.percent, 2) : 0;
      return `<button class="sp-card" data-act="nav-course" data-id="${h(c.id)}" style="text-align:left;cursor:pointer;display:block;width:100%;margin:0">
        <div style="display:flex;justify-content:space-between;gap:10px;align-items:flex-start">
          <div style="min-width:0">
            <div style="font-weight:620;letter-spacing:-.01em;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${h(c.name)}</div>
            <div class="sp-sub">${[c.period ? 'Period ' + h(c.period) : '', h(c.teacher || ''), h(c.term || '')].filter(Boolean).join(' · ') || 'No period listed'}</div>
          </div>
          <div style="text-align:right">
            <div style="font-size:24px;font-weight:700;letter-spacing:-.03em;color:${gradeVar(r ? r.percent : null)};line-height:1">
              ${r && r.letter ? h(r.letter) : '--'}
            </div>
            <div class="sp-sub">${r ? U.fmtPct(r.percent, 2) : '--'}</div>
          </div>
        </div>
        <div class="sp-bar" style="margin:12px 0 8px;height:5px">
          <i style="width:${r && r.percent !== null ? U.clamp(r.percent, 0, 100) : 0}%;background:${gradeVar(r ? r.percent : null)}"></i>
        </div>
        <div style="display:flex;justify-content:space-between;align-items:flex-end;gap:8px">
          <div class="sp-chips" style="margin:0">
            ${r && r.missingCount ? chip(r.missingCount + ' missing', null, 'bad') : ''}
            ${change && Math.abs(change.delta) >= 0.05 ? chip(U.fmtSigned(change.delta, 1) + ' since ' + U.fmtDate(change.date), null, change.delta > 0 ? 'good' : 'bad') : ''}
            ${whatIfDelta ? chip('what-if ' + U.fmtSigned(whatIfDelta, 1), null, 'accent') : ''}
            ${vs ? chip((vs.avgDelta >= 0 ? 'Above class by ' : 'Below class by ') + Math.abs(vs.avgDelta).toFixed(1) + '%', null, vs.avgDelta >= 0 ? 'good' : 'warn') : ''}
            ${weakest ? chip('Weakest: ' + weakest.name + ' ' + U.round(weakest.percent, 0) + '%') : ''}
          </div>
          ${sparkline(series)}
        </div>
      </button>`;
    }).join('');

    /* Highest-leverage fixes across every class. */
    const fixes = [];
    for (const c of courses) {
      const r = resultFor(c.id);
      if (!r) continue;
      for (const a of r.assignments) {
        if (a.excluded || a.noCount) continue;
        const isZeroish = a.missing || (a.percent !== null && a.percent < 70);
        if (!isZeroish || a.possible === null) continue;
        const up = M.assignmentUpside(c, optsFor(c), a);
        if (up === null || up < 0.05) continue;
        fixes.push({ course: c, a, up });
      }
    }
    const topFixes = U.sortBy(fixes, { fn: (f) => f.up, dir: -1 }).slice(0, 8);

    const recent = recentChanges(courses).slice(0, 8);

    return `
      <div style="display:flex;align-items:flex-end;justify-content:space-between;gap:12px;margin-bottom:16px;flex-wrap:wrap">
        <div>
          <h1 style="margin:0;font-size:24px;letter-spacing:-.03em;font-weight:680">All classes</h1>
          <p class="sp-help" style="margin-top:2px">
            ${captured ? 'Last captured ' + new Date(captured).toLocaleString() : 'Imported data'} ·
            ${graded} graded assignment${graded === 1 ? '' : 's'}
          </p>
        </div>
        <div class="sp-stat-row">
          <div class="sp-stat"><b style="color:${gradeVar(avg)}">${avg === null ? '--' : U.round(avg, 1) + '%'}</b><span>Mean grade</span></div>
          <div class="sp-stat"><b style="color:${missing ? 'var(--bad)' : 'var(--good)'}">${missing}</b><span>Missing</span></div>
          ${vsAll ? `<div class="sp-stat"><b class="sp-delta ${deltaClass(vsAll.avgDelta)}">${U.fmtSigned(vsAll.avgDelta, 1)}</b><span>vs class avg</span></div>` : ''}
        </div>
      </div>
      <div class="sp-grid" style="margin-bottom:16px">${cards}</div>

      ${topFixes.length ? `<div class="sp-card pad0">
        <div class="sp-card-head" style="padding:14px 16px 0;margin:0">
          <h2>Biggest wins available</h2>
          <p>What each assignment is worth if you fix it — full credit vs. now</p>
        </div>
        <div class="sp-list" style="margin-top:10px">
          ${topFixes.map((f) => `<div class="sp-list-item" data-act="open-assignment" data-id="${h(f.course.id)}" data-aid="${h(f.a.id)}">
            <span style="width:8px;height:8px;border-radius:99px;background:${f.a.missing ? 'var(--bad)' : 'var(--warn)'};flex:0 0 auto"></span>
            <span class="grow"><b>${h(f.a.name)}${f.a.missing ? '<span class="sp-tag miss">missing</span>' : ''}</b>
              <span>${h(f.course.name)} · ${h(f.a.category)} · ${f.a.earned === null ? '--' : U.round(f.a.earned, 1)}/${f.a.possible}</span></span>
            <span class="sp-delta up" style="font-size:13px">+${f.up.toFixed(2)}%</span>
          </div>`).join('')}
        </div>
      </div>` : ''}

      ${recent.length ? `<div class="sp-card pad0">
        <div class="sp-card-head" style="padding:14px 16px 0;margin:0"><h2>Recent movement</h2><p>Grade changes since earlier snapshots</p></div>
        <div class="sp-list" style="margin-top:10px">
          ${recent.map((r) => `<div class="sp-list-item" data-act="nav-course" data-id="${h(r.course.id)}">
            <span class="grow"><b>${h(r.course.name)}</b><span>${U.fmtDate(r.date)} → today</span></span>
            <span class="sp-sub">${U.round(r.from, 1)}% → ${U.round(r.to, 1)}%</span>
            <span class="sp-delta ${deltaClass(r.delta)}" style="width:64px;text-align:right">${U.fmtSigned(r.delta, 2)}</span>
          </div>`).join('')}
        </div>
      </div>` : ''}`;
  }

  function recentChanges(courses) {
    const out = [];
    for (const c of courses) {
      const r = resultFor(c.id);
      if (!r || r.percent === null) continue;
      const b = state.baseResults[c.id];
      const cur = b && b.percent !== null ? b.percent : r.percent;
      const ch = S.changeSince(state.data.snapshots, c.id, cur);
      if (ch && Math.abs(ch.delta) >= 0.05) out.push({ course: c, ...ch, to: cur });
    }
    return U.sortBy(out, { fn: (x) => Math.abs(x.delta), dir: -1 });
  }

  function emptyStateHtml() {
    return `<div class="sp-empty">
      <h2>No grades loaded yet</h2>
      <p>Open your Skyward gradebook and hit <b>Capture</b> — Skyward+ reads the page you're on and keeps everything it finds. You can also paste grades in by hand.</p>
      <div class="sp-row-actions" style="justify-content:center">
        <button class="sp-btn primary" data-act="capture">Capture this page</button>
        <button class="sp-btn" data-act="nav-import">Paste grades</button>
        <button class="sp-btn" data-act="load-demo">Load sample data</button>
      </div>
    </div>`;
  }

  /* ---------- course view ---------- */
  const SORTS = {
    due: (a) => a.due || '',
    name: (a) => a.name.toLowerCase(),
    category: (a) => a.category.toLowerCase(),
    score: (a) => (a.possible === null ? null : a.possible),
    percent: (a) => a.percent,
    classavg: (a) => a.classAverage,
    delta: (a) => (a.percent !== null && a.classAverage !== null ? a.percent - a.classAverage : null),
    impact: (a) => a.__impact,
  };

  function courseHtml() {
    const c = courseById(state.courseId);
    if (!c) return emptyStateHtml();
    const r = resultFor(c.id), base = state.baseResults[c.id];
    const d = state.data;
    const series = S.seriesFor(d.snapshots, c.id);
    const change = S.changeSince(d.snapshots, c.id, base.percent);
    const vs = M.vsClassSummary(r.assignments);
    const whatIfDelta = r.percent !== null && base.percent !== null ? U.round(r.percent - base.percent, 2) : 0;
    const band = r.band;

    const impacts = M.impactTable(c, optsFor(c));
    const impactById = new Map(impacts.map((x) => [x.assignment.id, x.impact]));
    let rows = r.assignments.map((a) => ({ ...a, __impact: impactById.has(a.id) ? impactById.get(a.id) : null }));

    if (state.filterCat) rows = rows.filter((a) => a.category === state.filterCat);
    if (state.query) {
      const q = state.query.toLowerCase();
      rows = rows.filter((a) => a.name.toLowerCase().includes(q) || a.category.toLowerCase().includes(q));
    }
    rows = U.sortBy(rows, { fn: SORTS[state.sort] || SORTS.due, dir: state.dir });

    const showAvg = d.settings.showClassAvg;

    return `
      <div class="sp-card">
        <div class="sp-hero">
          <div class="sp-ring">
            ${ring(r.percent)}
            <div class="sp-ring-label">
              <b style="color:${gradeVar(r.percent)}">${r.letter || '--'}</b>
              <span>${U.fmtPct(r.percent, 2)}</span>
            </div>
          </div>
          <div class="sp-hero-info">
            <h1>${h(c.name)}</h1>
            <div class="sp-sub">${[c.teacher ? h(c.teacher) : '', c.period ? 'Period ' + h(c.period) : '', c.room ? 'Room ' + h(c.room) : '', c.term ? h(c.term) : ''].filter(Boolean).join(' · ') || 'No class details captured'}</div>
            <div class="sp-chips">
              ${r.fromReported ? chip('Posted grade — no assignment detail yet', null, 'warn')
                : chip(r.mode === 'weighted' ? 'Weighted categories' : 'Total points', null, 'accent')}
              ${c.reportedPercent !== null
                ? chip('Skyward says ' + U.round(c.reportedPercent, 2) + '%' + (c.reportedLetter ? ' (' + c.reportedLetter + ')' : ''), null,
                    r.matchesReported === true ? 'good' : r.matchesReported === false ? 'warn' : '')
                : ''}
              ${change && Math.abs(change.delta) >= 0.05 ? chip(U.fmtSigned(change.delta, 2) + ' since ' + U.fmtDate(change.date), null, change.delta > 0 ? 'good' : 'bad') : ''}
              ${r.missingCount ? chip(r.missingCount + ' missing', null, 'bad') : ''}
              ${r.ungradedCount ? chip(r.ungradedCount + ' not graded yet') : ''}
              ${whatIfDelta ? chip('What-if ' + U.fmtSigned(whatIfDelta, 2), null, 'accent') : ''}
              ${c.courseClassAverage !== null ? chip('Class average ' + U.round(c.courseClassAverage, 1) + '%') : ''}
            </div>
          </div>
          <div class="sp-stat-row" style="align-items:flex-start">
            <div class="sp-stat"><b>${U.round(r.totalEarned, 1)}<span style="color:var(--text-faint);font-weight:500">/${U.round(r.totalPossible, 1)}</span></b><span>Points</span></div>
            <div class="sp-stat"><b>${r.gradedCount}</b><span>Graded</span></div>
            ${vs ? `<div class="sp-stat"><b class="sp-delta ${deltaClass(vs.avgDelta)}">${U.fmtSigned(vs.avgDelta, 1)}</b><span>vs class</span></div>` : ''}
            ${series.length > 1 ? `<div class="sp-stat"><b>${sparkline(series, 84, 24)}</b><span>Trend</span></div>` : ''}
          </div>
        </div>

        ${band ? `<div class="sp-band">
          <div class="sp-band-track">
            <i style="width:${U.clamp(r.percent, 0, 100)}%;background:${gradeVar(r.percent)};opacity:.85"></i>
          </div>
          <div class="sp-band-legend">
            <span>${band.cushion !== null ? `<b style="color:var(--text-dim)">${band.cushion.toFixed(2)}%</b> of cushion above ${h(band.letter)} (${band.floor}%)` : ''}</span>
            <span>${band.next ? `<b style="color:var(--text-dim)">${band.toNext.toFixed(2)}%</b> to ${h(band.next)}` : 'Top of the scale'}</span>
          </div>
        </div>` : ''}
      </div>

      ${vs ? `<div class="sp-card" style="display:flex;gap:26px;flex-wrap:wrap;align-items:center">
        <div class="sp-stat"><b style="color:${gradeVar(vs.yourAvg)}">${vs.yourAvg}%</b><span>Your average</span></div>
        <div class="sp-stat"><b style="color:var(--text-dim)">${vs.classAvg}%</b><span>Class average</span></div>
        <div class="sp-stat"><b class="sp-delta ${deltaClass(vs.avgDelta)}">${U.fmtSigned(vs.avgDelta, 2)}</b><span>Difference</span></div>
        <div style="flex:1;min-width:220px">
          <div class="sp-sub" style="margin-bottom:6px">You beat the class average on <b style="color:var(--good)">${vs.above}</b> of ${vs.count} assignments${vs.below ? `, trailed on <b style="color:var(--bad)">${vs.below}</b>` : ''}.</div>
          <div class="sp-vs-track" style="height:8px"><i style="width:${(vs.above / vs.count) * 100}%;background:var(--good)"></i></div>
        </div>
      </div>` : ''}

      <div class="sp-card">
        <div class="sp-card-head">
          <h2>Category breakdown</h2>
          <p>${r.mode === 'weighted' ? 'Weights come from your gradebook' : 'No weights published — each category counts by its point total'}</p>
          <span class="sp-spacer"></span>
          ${state.filterCat ? `<button class="sp-btn ghost" data-act="cat-filter" data-cat="">Clear filter</button>` : ''}
        </div>
        ${r.categories.length ? r.categories.map((k) => `
          <div class="sp-cat" data-act="cat-filter" data-cat="${h(k.name)}" data-active="${state.filterCat === k.name}">
            <div>
              <div class="sp-cat-name">${h(k.name)} <small>${k.count} item${k.count === 1 ? '' : 's'} · ${U.round(k.earned, 1)}/${U.round(k.possible, 1)} pts</small></div>
              <div class="sp-cat-meter"><i style="width:${k.percent === null ? 0 : U.clamp(k.percent, 0, 100)}%;background:${gradeVar(k.percent)}"></i></div>
            </div>
            <div class="sp-cat-w">${U.round(k.effectiveWeight, 1)}%<br><small style="color:var(--text-faint)">of grade</small></div>
            <div class="sp-cat-p" style="color:${gradeVar(k.percent)}">${U.fmtPct(k.percent, 1)}
              <small>+${U.round(k.contribution, 1)} pts to grade</small></div>
          </div>`).join('') : '<p class="sp-help">No categories found.</p>'}
      </div>

      <div class="sp-card pad0">
        <div class="sp-card-head" style="padding:14px 16px 0;margin:0">
          <h2>Assignments</h2>
          <p>${rows.length} shown${state.filterCat ? ' in ' + h(state.filterCat) : ''} · click a row to edit or see impact</p>
          <span class="sp-spacer"></span>
          <button class="sp-btn" data-act="add-hypo">+ Add assignment</button>
        </div>
        <div style="overflow-x:auto;margin-top:10px">
        <table class="sp-table">
          <thead><tr>
            ${th('name', 'Assignment')}
            ${th('category', 'Category')}
            ${th('due', 'Due')}
            ${th('score', 'Score', 'sp-num')}
            ${th('percent', '%', 'sp-num')}
            ${showAvg ? th('classavg', 'Class avg', 'sp-num') : ''}
            ${showAvg ? th('delta', 'You vs class', 'sp-num') : ''}
            ${th('impact', 'Grade impact', 'sp-num')}
          </tr></thead>
          <tbody>
            ${rows.length ? rows.map((a) => assignmentRow(c, a, showAvg)).join('') :
              `<tr><td colspan="8" style="height:96px;text-align:center;color:var(--text-faint)">${
                c.assignments.length
                  ? 'Nothing matches that filter.'
                  : 'Only the posted grade was captured for this class. Open it in Skyward so the assignment list is on screen, then hit Capture.'
              }</td></tr>`}
          </tbody>
        </table>
        </div>
      </div>

      ${calculatorHtml(c, r)}`;
  }

  const th = (key, label, cls = '') =>
    `<th class="${cls}" data-act="sort" data-key="${key}"${state.sort === key ? ' data-sorted="true"' : ''}>${h(label)}${state.sort === key ? (state.dir > 0 ? ' ↑' : ' ↓') : ''}</th>`;

  function assignmentRow(c, a, showAvg) {
    const delta = a.percent !== null && a.classAverage !== null ? a.percent - a.classAverage : null;
    const edited = (state.data.edits[c.id] || {})[a.id];
    const open = state.expanded.has(a.id);
    const impact = a.__impact;
    return `<tr data-act="toggle-row" data-id="${h(a.id)}" data-missing="${!!a.missing}" data-excluded="${!!a.excluded}" data-hypo="${!!a.hypothetical}">
      <td class="sp-name-cell" title="${h(a.name)}">${h(a.name)}
        ${a.missing ? '<span class="sp-tag miss">missing</span>' : ''}
        ${a.hypothetical ? '<span class="sp-tag new">what-if</span>' : ''}
        ${a.noCount ? '<span class="sp-tag nc">no count</span>' : ''}
        ${edited ? '<span class="sp-tag new">edited</span>' : ''}</td>
      <td class="sp-sub">${h(a.category)}</td>
      <td class="sp-sub">${U.fmtDate(a.due)}</td>
      <td class="sp-num">${a.earned === null ? '<span class="sp-sub">--</span>' : U.round(a.earned, 2)}<span class="sp-sub">/${a.possible === null ? '--' : U.round(a.possible, 2)}</span></td>
      <td class="sp-num" style="color:${gradeVar(a.percent)};font-weight:600">${U.fmtPct(a.percent, 1)}</td>
      ${showAvg ? `<td class="sp-num sp-sub">${a.classAverage === null ? '--' : U.round(a.classAverage, 1) + '%'}</td>` : ''}
      ${showAvg ? `<td class="sp-num">${delta === null ? '<span class="sp-sub">--</span>' : `<span class="sp-delta ${deltaClass(delta)}">${U.fmtSigned(delta, 1)}</span>`}</td>` : ''}
      <td class="sp-num">${impact === null || impact === undefined ? '<span class="sp-sub">--</span>' :
        `<span class="sp-delta ${deltaClass(impact)}">${U.fmtSigned(impact, 2)}</span>`}</td>
    </tr>
    ${open ? assignmentDetail(c, a, delta) : ''}`;
  }

  function assignmentDetail(c, a, delta) {
    const upside = M.assignmentUpside(c, optsFor(c), a);
    const edited = (state.data.edits[c.id] || {})[a.id] || {};
    return `<tr class="sp-detail"><td colspan="8"><div class="sp-detail-inner">
      <div class="sp-field">
        <label>What-if score</label>
        <div class="sp-field-row">
          <input class="sp-input" type="number" step="0.01" data-act="edit" data-field="earned" data-id="${h(a.id)}" value="${a.earned === null ? '' : a.earned}" placeholder="--">
          <span class="sp-sub">/</span>
          <input class="sp-input" type="number" step="0.01" data-act="edit" data-field="possible" data-id="${h(a.id)}" value="${a.possible === null ? '' : a.possible}">
          ${Object.keys(edited).length ? `<button class="sp-btn ghost" data-act="clear-edit" data-id="${h(a.id)}">Reset</button>` : ''}
        </div>
        <p class="sp-help">Change it and every number above updates live.</p>
      </div>
      <div class="sp-field">
        <label>Class average</label>
        <div class="sp-field-row">
          <input class="sp-input" type="number" step="0.1" data-act="edit" data-field="classAverage" data-id="${h(a.id)}" value="${a.classAverage === null ? '' : U.round(a.classAverage, 1)}" placeholder="percent">
          <span class="sp-sub">%</span>
        </div>
        ${delta !== null ? `<p class="sp-help">You're <b class="sp-delta ${deltaClass(delta)}">${U.fmtSigned(delta, 1)}</b> vs the class here.</p>`
          : '<p class="sp-help">Skyward didn\'t publish one — type it in if your teacher shows it.</p>'}
        ${a.classAverage !== null ? vsBars(a.percent, a.classAverage) : ''}
      </div>
      <div class="sp-field">
        <label>Leverage</label>
        <div class="sp-sub" style="line-height:1.7">
          Worth <b style="color:var(--text)">${a.__impact === null || a.__impact === undefined ? '--' : U.fmtSigned(a.__impact, 2)}</b> of your final grade right now.<br>
          ${upside !== null && upside > 0.004 ? `Full credit would move you <b class="sp-delta up">+${upside.toFixed(2)}%</b>.` : 'Already at full credit here.'}
        </div>
      </div>
      <div class="sp-field">
        <label>Actions</label>
        <div class="sp-row-actions">
          <button class="sp-btn" data-act="toggle-exclude" data-id="${h(a.id)}">${a.excluded ? 'Include again' : 'Drop from math'}</button>
          ${a.missing ? `<button class="sp-btn" data-act="assume-full" data-id="${h(a.id)}">Assume turned in</button>` : ''}
          ${a.hypothetical ? `<button class="sp-btn danger" data-act="del-hypo" data-id="${h(a.id)}">Delete</button>` : ''}
        </div>
      </div>
    </div></td></tr>`;
  }

  function calculatorHtml(c, r) {
    const cats = r.categories.length ? r.categories.map((k) => k.name) : ['Uncategorized'];
    const calc = state.calc || (state.calc = { target: null, possible: 100, category: cats[0], examWeight: 20 });
    if (!cats.includes(calc.category)) calc.category = cats[0];
    const target = calc.target !== null && calc.target !== undefined
      ? calc.target
      : (r.band && r.band.next ? M.SCALES[state.data.settings.scale].cuts.find((x) => x[1] === r.band.next)[0] : 90);

    const need = M.scoreNeeded(c, optsFor(c), { possible: U.num(calc.possible) || 100, category: calc.category, target });
    const exam = M.finalExamNeeded(r.percent, U.num(calc.examWeight) || 20, target);

    let needText;
    if (need.status === 'secured') needText = `<b style="color:var(--good)">Already locked in.</b> Even a zero keeps you at ${U.round(need.worst, 2)}%.`;
    else if (need.status === 'impossible') needText = `<b style="color:var(--bad)">Not reachable with this one assignment.</b> A perfect score gets you to ${U.round(need.best, 2)}%.`;
    else needText = `You need <b style="color:${gradeVar(need.neededPercent)};font-size:16px">${U.round(need.needed, 1)} / ${U.num(calc.possible) || 100}</b> (${U.round(need.neededPercent, 1)}%) to reach ${U.round(target, 1)}%.`;

    return `<div class="sp-card">
      <div class="sp-card-head"><h2>Grade calculator</h2><p>Every number respects this class's real weighting</p></div>
      <div class="sp-detail-inner" style="padding:0">
        <div class="sp-field">
          <label>Target grade</label>
          <div class="sp-field-row">
            <input class="sp-input" type="number" step="0.5" data-act="calc" data-field="target" value="${U.round(target, 1)}">
            <span class="sp-sub">%</span>
          </div>
        </div>
        <div class="sp-field">
          <label>Next assignment worth</label>
          <div class="sp-field-row">
            <input class="sp-input" type="number" step="1" data-act="calc" data-field="possible" value="${h(calc.possible)}">
            <span class="sp-sub">pts in</span>
            <select class="sp-select" data-act="calc" data-field="category">
              ${cats.map((k) => `<option value="${h(k)}"${k === calc.category ? ' selected' : ''}>${h(k)}</option>`).join('')}
            </select>
          </div>
        </div>
        <div class="sp-field" style="grid-column:span 2">
          <label>Result</label>
          <p style="margin:0;line-height:1.6">${needText}</p>
        </div>
      </div>
      <hr class="sp-hr">
      <div class="sp-detail-inner" style="padding:0">
        <div class="sp-field">
          <label>Final exam is worth</label>
          <div class="sp-field-row">
            <input class="sp-input" type="number" step="1" data-act="calc" data-field="examWeight" value="${h(calc.examWeight)}">
            <span class="sp-sub">% of the course</span>
          </div>
        </div>
        <div class="sp-field" style="grid-column:span 2">
          <label>Exam score needed</label>
          <p style="margin:0;line-height:1.6">
            ${exam === null ? 'Add a current grade first.'
              : exam <= 0 ? `<b style="color:var(--good)">Anything passes</b> — you'd keep ${U.round(target, 1)}% even with a zero.`
              : exam > 100 ? `<b style="color:var(--bad)">Out of reach</b> — you'd need ${exam.toFixed(1)}% on the exam.`
              : `You need <b style="color:${gradeVar(exam)};font-size:16px">${exam.toFixed(1)}%</b> on the final to finish at ${U.round(target, 1)}%.`}
          </p>
        </div>
      </div>
    </div>`;
  }

  /* ---------- import / settings / debug ---------- */
  function importHtml() {
    const count = Object.keys(state.data.courses).length;
    return `
      <h1 style="margin:0 0 4px;font-size:22px;letter-spacing:-.03em">Import &amp; export</h1>
      <p class="sp-help" style="margin-bottom:16px">${count} class${count === 1 ? '' : 'es'} stored on this device. Nothing ever leaves your browser.</p>

      <div class="sp-card">
        <div class="sp-card-head"><h2>Paste grades</h2><p>Copy a gradebook page and paste it, or write it out by hand</p></div>
        <textarea class="sp-textarea" data-act="import-text" placeholder="# Algebra II - Mr. Reyes - Period 3 - Q2
[Homework 20%]
Section 4.2 practice | 18/20 | avg 16.4 | due 12/4
Section 4.3 practice | 0/20 | missing
[Tests 50%]
Unit 4 exam | 88/100 | avg 79.5"></textarea>
        <div class="sp-row-actions" style="margin-top:12px">
          <button class="sp-btn primary" data-act="do-import">Import</button>
          <button class="sp-btn" data-act="capture">Capture current page instead</button>
          <button class="sp-btn" data-act="load-demo">Load sample data</button>
        </div>
        <p class="sp-note" style="margin-top:12px">
          Understood formats: this shorthand, a raw copy-paste of most gradebook tables,
          <code>CSV</code> with headers like <code>course, assignment, category, score, possible, class average</code>,
          and Skyward+ <code>JSON</code>. Lines like <code>avg 16.4</code> or <code>avg 82%</code> set the class average.
        </p>
      </div>

      <div class="sp-card">
        <div class="sp-card-head"><h2>Your data</h2><p>Back it up, move it to another browser, or wipe it</p></div>
        <div class="sp-row-actions">
          <button class="sp-btn" data-act="export-json">Download JSON</button>
          <button class="sp-btn" data-act="copy-json">Copy JSON</button>
          <button class="sp-btn" data-act="export-csv">Download CSV</button>
          <button class="sp-btn danger" data-act="clear-all">Delete everything</button>
        </div>
      </div>

      <div class="sp-card">
        <div class="sp-card-head"><h2>What Skyward+ sees on this page</h2><p>Useful if a capture came back empty</p></div>
        <button class="sp-btn" data-act="run-debug">Scan this page</button>
        ${state.debugInfo ? `<pre class="sp-textarea" style="margin-top:12px;min-height:auto;white-space:pre-wrap">${h(JSON.stringify(state.debugInfo, null, 2))}</pre>` : ''}
      </div>`;
  }

  function settingsHtml() {
    const s = state.data.settings;
    const courses = allCourses();
    const row = (title, desc, control) => `<div class="sp-settings-row"><div class="grow"><b>${title}</b><span>${desc}</span></div>${control}</div>`;
    const sel = (act, value, options) =>
      `<select class="sp-select" data-act="set" data-key="${act}">${options.map(([v, l]) => `<option value="${h(v)}"${v === value ? ' selected' : ''}>${h(l)}</option>`).join('')}</select>`;
    const toggle = (key, on) => `<button class="sp-btn" data-act="set" data-key="${key}" data-value="${!on}" data-on="${on}">${on ? 'On' : 'Off'}</button>`;

    return `
      <h1 style="margin:0 0 16px;font-size:22px;letter-spacing:-.03em">Settings</h1>
      <div class="sp-card">
        <div class="sp-card-head"><h2>Grading</h2></div>
        ${row('Letter scale', 'How percents become letters and GPA points',
          sel('scale', s.scale, Object.entries(M.SCALES).map(([k, v]) => [k, v.label])))}
        ${row('Grade math', 'Auto matches whichever method reproduces the grade Skyward shows',
          sel('mode', s.mode, [['auto', 'Auto-detect'], ['weighted', 'Always weighted categories'], ['points', 'Always total points']]))}
        ${row('Weighted GPA', 'Adds +1.0 for AP and +0.5 for Honors classes', toggle('weightedGpa', s.weightedGpa))}
      </div>
      <div class="sp-card">
        <div class="sp-card-head"><h2>Display</h2></div>
        ${row('Theme', 'Dark or light', sel('theme', s.theme, [['dark', 'Dark'], ['light', 'Light']]))}
        ${row('Density', 'Row height in the assignment table', sel('density', s.density, [['comfortable', 'Comfortable'], ['compact', 'Compact']]))}
        ${row('Class average columns', 'Show class average and your difference next to every score', toggle('showClassAvg', s.showClassAvg))}
        ${row('Auto-capture', 'Read grades automatically whenever a Skyward page loads', toggle('autoCapture', s.autoCapture))}
      </div>
      <div class="sp-card">
        <div class="sp-card-head"><h2>Course levels</h2><p>Only affects weighted GPA</p></div>
        ${courses.length ? courses.map((c) => `<div class="sp-settings-row">
          <div class="grow"><b>${h(c.name)}</b><span>${[c.period ? 'Period ' + h(c.period) : '', h(c.teacher || '')].filter(Boolean).join(' · ')}</span></div>
          <select class="sp-select" data-act="set-level" data-id="${h(c.id)}">
            ${[['regular', 'Regular'], ['honors', 'Honors +0.5'], ['ap', 'AP / IB +1.0']].map(([v, l]) =>
              `<option value="${v}"${(c.level || 'regular') === v ? ' selected' : ''}>${l}</option>`).join('')}
          </select>
          <button class="sp-btn danger" data-act="del-course" data-id="${h(c.id)}">Remove</button>
        </div>`).join('') : '<p class="sp-help">No classes yet.</p>'}
      </div>`;
  }

  /* ---------- shell ---------- */
  function shellHtml() {
    const s = state.data.settings;
    return `
      <header class="sp-top">
        <div class="sp-brand"><span class="sp-mark">S</span><span>Skyward<span style="color:var(--accent)">+</span></span>
          <small>${state.embedded ? 'overlay' : 'dashboard'}</small></div>
        <label class="sp-search">
          <span class="sp-sub" aria-hidden="true">⌕</span>
          <input type="search" placeholder="Search classes and assignments" value="${h(state.query)}" data-act="search" aria-label="Search">
        </label>
        <span class="sp-spacer"></span>
        <button class="sp-btn" data-act="toggle-whatif" data-on="${state.whatIf}" title="Include your what-if edits in every calculation">What-if</button>
        <button class="sp-btn" data-act="capture" title="Read grades off the page behind this window">Capture</button>
        <button class="sp-btn ghost" data-act="toggle-theme" title="Theme">${s.theme === 'dark' ? '☾' : '☀'}</button>
        ${state.embedded ? '<button class="sp-btn ghost" data-act="close" title="Close (Esc)">✕</button>' : ''}
      </header>
      <div class="sp-body">
        <aside class="sp-rail" data-region="rail"></aside>
        <main class="sp-main" data-region="main" tabindex="-1"><div class="sp-main-inner"></div></main>
      </div>
      <div data-region="whatif"></div>`;
  }

  function whatIfHtml() {
    if (!anyWhatIf()) return '';
    const affected = allCourses().filter((c) => hasWhatIf(c.id));
    const summary = affected.map((c) => {
      const r = state.results[c.id], b = state.baseResults[c.id];
      const d = r.percent !== null && b.percent !== null ? U.round(r.percent - b.percent, 2) : 0;
      return `${c.name}: ${U.fmtPct(b.percent, 1)} → ${U.fmtPct(r.percent, 1)} (${U.fmtSigned(d, 2)})`;
    }).join('  ·  ');
    return `<div class="sp-whatif">
      <span>What-if active${state.whatIf ? '' : ' (paused)'}</span>
      <span style="flex:1;font-weight:450;opacity:.92;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${h(summary)}</span>
      <button class="sp-btn" data-act="toggle-whatif">${state.whatIf ? 'Pause' : 'Resume'}</button>
      <button class="sp-btn" data-act="reset-whatif">Reset all</button>
    </div>`;
  }

  /* ---------- render ---------- */
  function render() {
    recompute();
    const app = state.root;
    app.dataset.theme = state.data.settings.theme;
    app.dataset.density = state.data.settings.density;
    const main = app.querySelector('[data-region="main"] .sp-main-inner');
    const rail = app.querySelector('[data-region="rail"]');
    const foot = app.querySelector('[data-region="whatif"]');
    const focus = captureFocus();
    rail.innerHTML = railHtml();
    main.innerHTML =
      state.view === 'course' ? courseHtml()
        : state.view === 'import' ? importHtml()
        : state.view === 'settings' ? settingsHtml()
        : overviewHtml();
    foot.innerHTML = whatIfHtml();
    restoreFocus(focus);
  }

  function captureFocus() {
    const rootNode = state.host.getRootNode ? state.host : document;
    const active = (state.host.activeElement) || document.activeElement;
    if (!active || !active.dataset || !active.dataset.act) return null;
    return {
      act: active.dataset.act, field: active.dataset.field || '', id: active.dataset.id || '',
      start: active.selectionStart, end: active.selectionEnd,
    };
  }

  function restoreFocus(f) {
    if (!f) return;
    const sel = `[data-act="${f.act}"]${f.field ? `[data-field="${f.field}"]` : ''}${f.id ? `[data-id="${f.id}"]` : ''}`;
    const el = state.root.querySelector(sel);
    if (!el) return;
    el.focus();
    if (f.start !== null && f.start !== undefined && el.setSelectionRange) {
      try { el.setSelectionRange(f.start, f.end); } catch { /* number inputs refuse */ }
    }
  }

  const persist = U.debounce(() => S.save(state.data), 220);

  function toast(msg) {
    const old = state.root.querySelector('.sp-toast');
    if (old) old.remove();
    const el = document.createElement('div');
    el.className = 'sp-toast';
    el.textContent = msg;
    state.root.appendChild(el);
    clearTimeout(state.toastTimer);
    state.toastTimer = setTimeout(() => el.remove(), 2600);
  }

  /* ---------- mutations ---------- */
  function setEdit(courseId, aid, field, value) {
    const edits = (state.data.edits[courseId] = state.data.edits[courseId] || {});
    const hypos = state.data.hypotheticals[courseId] || [];
    const hypo = hypos.find((x) => x.id === aid);
    if (hypo) { hypo[field] = value; persist(); return; }
    const e = (edits[aid] = edits[aid] || {});
    if (value === null || value === '') delete e[field]; else e[field] = value;
    if (!Object.keys(e).length) delete edits[aid];
    if (!Object.keys(edits).length) delete state.data.edits[courseId];
    persist();
  }

  function clearEdit(courseId, aid) {
    if (state.data.edits[courseId]) delete state.data.edits[courseId][aid];
    persist();
  }

  function addHypothetical(courseId) {
    const c = courseById(courseId);
    const r = resultFor(courseId);
    const cat = state.filterCat || (r.categories[0] ? r.categories[0].name : 'Uncategorized');
    const list = (state.data.hypotheticals[courseId] = state.data.hypotheticals[courseId] || []);
    const a = {
      id: 'hypo-' + U.hash(courseId, String(list.length), String(Object.keys(state.data.courses).length), cat),
      name: 'Upcoming assignment ' + (list.length + 1),
      category: cat, earned: null, possible: 100, due: null, hypothetical: true, source: 'manual',
    };
    list.push(a);
    state.expanded.add(a.id);
    persist();
    return a;
  }

  /* ---------- import / export ---------- */
  function toCsv() {
    const head = ['course', 'period', 'teacher', 'term', 'category', 'assignment', 'due', 'score', 'possible', 'percent', 'class average', 'missing'];
    const esc = (v) => {
      const s = v === null || v === undefined ? '' : String(v);
      return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
    };
    const lines = [head.join(',')];
    for (const c of allCourses())
      for (const a of c.assignments)
        lines.push([c.name, c.period, c.teacher, c.term, a.category, a.name, a.due, a.earned, a.possible,
          a.percent === null ? '' : U.round(a.percent, 2), a.classAverage === null ? '' : U.round(a.classAverage, 2),
          a.missing ? 'yes' : ''].map(esc).join(','));
    return lines.join('\n');
  }

  function download(filename, text, type = 'application/json') {
    const blob = new Blob([text], { type });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url; a.download = filename;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 4000);
  }

  function demoCourses() {
    // avg is given in points when it fits inside the point value, else as a percent
    const mk = (name, cat, pts, score, avg, day, extra = {}) => ({
      name, category: cat, possible: pts, earned: score,
      classAverage: avg === null || avg === undefined ? null : avg <= pts ? (avg / pts) * 100 : avg,
      due: `2026-0${day < 10 ? '4' : '5'}-${String(day % 30 || 1).padStart(2, '0')}`, ...extra,
    });
    return [
      { name: 'AP Biology', teacher: 'Ms. Okonkwo', period: '2', term: 'Q4', reportedPercent: 91.34, reportedLetter: 'A-',
        categories: [{ name: 'Labs', weight: 30 }, { name: 'Tests', weight: 45 }, { name: 'Homework', weight: 25 }],
        assignments: [
          mk('Osmosis lab writeup', 'Labs', 50, 47, 86), mk('Enzyme lab', 'Labs', 50, 44, 82, 12),
          mk('Photosynthesis lab', 'Labs', 40, 39, 78, 19), mk('Unit 6 exam', 'Tests', 100, 88, 81, 15),
          mk('Unit 7 exam', 'Tests', 100, 94, 79, 24), mk('Genetics quiz', 'Tests', 30, 27, 24.5, 8),
          mk('Ch. 12 reading', 'Homework', 10, 10, 9.1, 3), mk('Ch. 13 reading', 'Homework', 10, 0, 8.7, 10, { missing: true }),
          mk('Punnett practice', 'Homework', 20, 19, 17.2, 17),
        ] },
      { name: 'Algebra II Honors', teacher: 'Mr. Reyes', period: '3', term: 'Q4', reportedPercent: 84.2, reportedLetter: 'B',
        categories: [{ name: 'Tests', weight: 60 }, { name: 'Homework', weight: 20 }, { name: 'Quizzes', weight: 20 }],
        assignments: [
          mk('Unit 5 test', 'Tests', 100, 79, 74, 14), mk('Unit 6 test', 'Tests', 100, 86, 77, 26),
          mk('Quadratics quiz', 'Quizzes', 25, 22, 19.8, 7), mk('Logs quiz', 'Quizzes', 25, 16, 20.1, 21),
          mk('4.2 practice', 'Homework', 20, 20, 18.4, 4), mk('4.3 practice', 'Homework', 20, 0, 17.9, 11, { missing: true }),
          mk('5.1 practice', 'Homework', 20, 18, 18.1, 18),
        ] },
      { name: 'US History', teacher: 'Mr. Delacroix', period: '5', term: 'Q4', reportedPercent: 96.1, reportedLetter: 'A',
        categories: [{ name: 'Essays', weight: 40 }, { name: 'Tests', weight: 40 }, { name: 'Participation', weight: 20 }],
        assignments: [
          mk('DBQ: Reconstruction', 'Essays', 100, 95, 84, 9), mk('DBQ: Industrialism', 'Essays', 100, 97, 85, 22),
          mk('Gilded Age exam', 'Tests', 100, 96, 82, 16), mk('Progressive Era exam', 'Tests', 100, 94, 80, 28),
          mk('Seminar week 3', 'Participation', 20, 20, 18, 6), mk('Seminar week 5', 'Participation', 20, 20, 17.5, 20),
        ] },
      { name: 'Spanish III', teacher: 'Sra. Villalobos', period: '6', term: 'Q4', reportedPercent: 78.5, reportedLetter: 'C+',
        categories: [{ name: 'Speaking', weight: 35 }, { name: 'Written', weight: 40 }, { name: 'Vocab', weight: 25 }],
        assignments: [
          mk('Oral exam 2', 'Speaking', 50, 38, 40.5, 13), mk('Presentación', 'Speaking', 50, 41, 42, 25),
          mk('Composición 3', 'Written', 40, 30, 32.8, 10), mk('Composición 4', 'Written', 40, 0, 33.1, 23, { missing: true }),
          mk('Vocab quiz 7', 'Vocab', 20, 17, 16.4, 5), mk('Vocab quiz 8', 'Vocab', 20, 19, 16.9, 19),
        ] },
    ];
  }

  async function reload() {
    state.data = await S.load();
    render();
  }

  async function capture() {
    let res = null;
    if (typeof SP.captureNow === 'function') {
      res = await SP.captureNow();
    } else if (S.hasChrome && chrome.runtime && chrome.runtime.sendMessage) {
      try { res = await chrome.runtime.sendMessage({ type: 'capture-active' }); } catch (e) { res = { error: e.message }; }
    }
    if (!res || res.error) { toast(res && res.error ? 'Capture failed: ' + res.error : 'Open your Skyward gradebook, then hit Capture there.'); return; }
    if (!res.courses) { toast('No gradebook found on that page. Try the Skyward assignments view.'); return; }
    await reload();
    toast(`Captured ${res.courses} class${res.courses === 1 ? '' : 'es'}, ${res.assignments} assignment${res.assignments === 1 ? '' : 's'}.`);
  }

  /* ---------- events ---------- */
  function wire(app) {
    app.addEventListener('click', async (ev) => {
      const el = ev.target.closest('[data-act]');
      if (!el) return;
      const act = el.dataset.act;
      if (['search', 'edit', 'calc', 'import-text', 'set-term', 'set', 'set-level'].includes(act) && el.tagName !== 'BUTTON') return;
      const id = el.dataset.id;

      switch (act) {
        case 'nav-overview': state.view = 'overview'; state.filterCat = null; break;
        case 'nav-course': state.view = 'course'; state.courseId = id; state.filterCat = null; state.expanded.clear(); break;
        case 'nav-import': state.view = 'import'; break;
        case 'nav-settings': state.view = 'settings'; break;
        case 'open-assignment':
          state.view = 'course'; state.courseId = id; state.filterCat = null;
          state.expanded.clear(); state.expanded.add(el.dataset.aid); break;
        case 'toggle-row':
          if (ev.target.closest('.sp-detail')) return;
          state.expanded.has(id) ? state.expanded.delete(id) : state.expanded.add(id); break;
        case 'sort': {
          const k = el.dataset.key;
          if (state.sort === k) state.dir = -state.dir; else { state.sort = k; state.dir = k === 'due' ? -1 : 1; }
          break;
        }
        case 'cat-filter': state.filterCat = el.dataset.cat || null; break;
        case 'toggle-theme':
          state.data.settings.theme = state.data.settings.theme === 'dark' ? 'light' : 'dark'; persist(); break;
        case 'toggle-gpa':
          state.data.settings.weightedGpa = !state.data.settings.weightedGpa; persist(); break;
        case 'toggle-whatif': state.whatIf = !state.whatIf; break;
        case 'reset-whatif':
          state.data.edits = {}; state.data.hypotheticals = {}; persist(); toast('What-if edits cleared.'); break;
        case 'clear-edit': clearEdit(state.courseId, id); break;
        case 'toggle-exclude': {
          const r = resultFor(state.courseId);
          const a = r.assignments.find((x) => x.id === id);
          setEdit(state.courseId, id, 'excluded', a && a.excluded ? null : true);
          break;
        }
        case 'assume-full': {
          const a = resultFor(state.courseId).assignments.find((x) => x.id === id);
          if (a) { setEdit(state.courseId, id, 'earned', a.possible); setEdit(state.courseId, id, 'missing', false); }
          break;
        }
        case 'add-hypo': addHypothetical(state.courseId); break;
        case 'del-hypo':
          state.data.hypotheticals[state.courseId] =
            (state.data.hypotheticals[state.courseId] || []).filter((x) => x.id !== id);
          persist(); break;
        case 'del-course':
          delete state.data.courses[id]; delete state.data.edits[id]; delete state.data.hypotheticals[id];
          if (state.courseId === id) { state.view = 'overview'; state.courseId = null; }
          persist(); toast('Class removed.'); break;
        case 'set': {
          const key = el.dataset.key;
          state.data.settings[key] = el.dataset.value === 'true' ? true : el.dataset.value === 'false' ? false : el.dataset.value;
          persist(); break;
        }
        case 'capture': await capture(); return;
        case 'load-demo': {
          const res = await S.ingest(demoCourses(), { source: 'demo' });
          await reload();
          toast(`Loaded ${res.added + res.updated} sample classes.`);
          state.view = 'overview'; render(); return;
        }
        case 'do-import': {
          const ta = app.querySelector('[data-act="import-text"]');
          const parsed = SP.parse.parseAny(ta.value || '');
          if (!parsed.length) { toast('Could not find any assignments in that text.'); return; }
          const res = await S.ingest(parsed, { source: 'manual' });
          await reload();
          toast(`Imported ${res.added} new and updated ${res.updated} class${res.updated === 1 ? '' : 'es'}.`);
          return;
        }
        case 'export-json': download('skyward-plus-' + U.today() + '.json', JSON.stringify(state.data, null, 2)); return;
        case 'export-csv': download('skyward-plus-' + U.today() + '.csv', toCsv(), 'text/csv'); return;
        case 'copy-json':
          try { await navigator.clipboard.writeText(JSON.stringify(state.data, null, 2)); toast('Copied to clipboard.'); }
          catch { toast('Clipboard blocked — use Download JSON.'); }
          return;
        case 'clear-all':
          if (el.dataset.confirm !== 'yes') { el.dataset.confirm = 'yes'; el.textContent = 'Really delete everything?'; return; }
          state.data = { ...S.DEFAULTS, courses: {}, edits: {}, hypotheticals: {}, levels: {}, snapshots: [], settings: state.data.settings };
          await S.save(state.data); state.view = 'overview'; toast('All data deleted.'); break;
        case 'run-debug':
          state.debugInfo = SP.parse.scrapePage(document, location.href).debug; break;
        case 'close': if (state.onClose) state.onClose(); return;
        default: return;
      }
      render();
    });

    const onInput = U.debounce(() => render(), 160);
    app.addEventListener('input', (ev) => {
      const el = ev.target.closest('[data-act]');
      if (!el) return;
      if (el.dataset.act === 'search') { state.query = el.value.trim(); onInput(); return; }
      if (el.dataset.act === 'edit') {
        const field = el.dataset.field;
        const raw = el.value === '' ? null : U.num(el.value);
        setEdit(state.courseId, el.dataset.id, field, raw);
        onInput(); return;
      }
      if (el.dataset.act === 'calc') {
        state.calc = state.calc || {};
        state.calc[el.dataset.field] = el.value === '' ? null : U.num(el.value);
        onInput(); return;
      }
    });

    app.addEventListener('change', (ev) => {
      const el = ev.target.closest('[data-act]');
      if (!el) return;
      const act = el.dataset.act;
      if (act === 'set-term') { state.term = el.value; render(); }
      else if (act === 'set') { state.data.settings[el.dataset.key] = el.value; persist(); render(); }
      else if (act === 'set-level') { state.data.levels[el.dataset.id] = el.value; persist(); render(); }
      else if (act === 'calc' && el.dataset.field === 'category') { state.calc.category = el.value; render(); }
    });

    app.addEventListener('keydown', (ev) => {
      if (ev.key === '/' && !/input|textarea|select/i.test(ev.target.tagName)) {
        ev.preventDefault();
        const s = app.querySelector('[data-act="search"]');
        if (s) s.focus();
      }
      if (ev.key === 'Escape' && state.onClose && !/input|textarea/i.test(ev.target.tagName)) state.onClose();
    });
  }

  /* ---------- mount ---------- */
  async function mount(host, opts = {}) {
    state.host = host;
    state.embedded = !!opts.embedded;
    state.onClose = opts.onClose || null;
    state.data = await S.load();
    if (opts.theme) state.data.settings.theme = opts.theme;

    const app = document.createElement('div');
    app.className = 'sp-app';
    app.innerHTML = shellHtml();
    host.appendChild(app);
    state.root = app;

    // Default to the term that actually has coursework, not "all terms".
    const byTerm = new Map();
    for (const c of allCourses()) {
      const k = c.term || '';
      byTerm.set(k, (byTerm.get(k) || 0) + c.assignments.length);
    }
    const best = [...byTerm.entries()].filter(([k]) => k).sort((a, b) => b[1] - a[1])[0];
    if (best && best[1] > 0 && byTerm.size > 1) state.term = best[0];

    const ids = Object.keys(state.data.courses);
    if (opts.courseId && state.data.courses[opts.courseId]) { state.view = 'course'; state.courseId = opts.courseId; }
    else if (ids.length === 1) { state.view = 'course'; state.courseId = ids[0]; }

    wire(app);
    render();

    await S.snapshot(state.baseResults);
    state.data = await S.load();
    render();

    if (S.hasChrome && chrome.storage.onChanged) {
      chrome.storage.onChanged.addListener((changes, area) => {
        if (area === 'local' && changes[S.KEY]) reload();
      });
    }
    return { render, reload, state };
  }

  SP.ui = { mount, render, reload, toast, demoCourses, state };
})();
