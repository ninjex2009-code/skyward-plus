/* Skyward+ — grade math. Weighted categories, total points, impact, what-if, GPA. */
(function () {
  const SP = (globalThis.SkywardPlus = globalThis.SkywardPlus || {});
  const U = SP.util;

  /* ---------- grading scales ---------- */
  const SCALES = {
    standard: {
      label: 'Standard (A / A- / B+ ...)',
      cuts: [[93, 'A', 4.0], [90, 'A-', 3.7], [87, 'B+', 3.3], [83, 'B', 3.0], [80, 'B-', 2.7],
             [77, 'C+', 2.3], [73, 'C', 2.0], [70, 'C-', 1.7], [67, 'D+', 1.3], [63, 'D', 1.0],
             [60, 'D-', 0.7], [0, 'F', 0]],
    },
    simple: {
      label: 'Simple (A B C D F)',
      cuts: [[90, 'A', 4], [80, 'B', 3], [70, 'C', 2], [60, 'D', 1], [0, 'F', 0]],
    },
    seven: {
      label: '7-point (A 93+, B 85+, C 77+, D 70+)',
      cuts: [[93, 'A', 4], [85, 'B', 3], [77, 'C', 2], [70, 'D', 1], [0, 'F', 0]],
    },
  };

  const letterFor = (p, scaleKey = 'standard') => {
    if (p === null || p === undefined || !isFinite(p)) return null;
    const cuts = (SCALES[scaleKey] || SCALES.standard).cuts;
    for (const [min, letter] of cuts) if (p + 1e-9 >= min) return letter;
    return 'F';
  };

  const gpaFor = (p, scaleKey = 'standard') => {
    if (p === null || p === undefined || !isFinite(p)) return null;
    const cuts = (SCALES[scaleKey] || SCALES.standard).cuts;
    for (const [min, , pts] of cuts) if (p + 1e-9 >= min) return pts;
    return 0;
  };

  /* Distance (in %) to the next letter grade up, and the cushion before dropping. */
  const gradeBand = (p, scaleKey = 'standard') => {
    if (p === null || !isFinite(p)) return null;
    const cuts = (SCALES[scaleKey] || SCALES.standard).cuts;
    let current = cuts[cuts.length - 1], next = null;
    for (let i = 0; i < cuts.length; i++) {
      if (p + 1e-9 >= cuts[i][0]) { current = cuts[i]; next = cuts[i - 1] || null; break; }
    }
    return {
      letter: current[1],
      floor: current[0],
      cushion: U.round(p - current[0], 2),
      next: next ? next[1] : null,
      toNext: next ? U.round(next[0] - p, 2) : null,
    };
  };

  /* ---------- normalization ---------- */
  function normalizeAssignment(a, courseId) {
    const name = U.clean(a.name || a.title || 'Untitled');
    const due = a.due || null;
    const earned = U.num(a.earned);
    const possible = U.num(a.possible);
    const percent = a.percent != null ? U.num(a.percent) : U.pct(earned, possible);
    return {
      id: a.id || U.hash(courseId, name, due || '', String(possible)),
      name,
      category: U.clean(a.category || 'Uncategorized'),
      due,
      assigned: a.assigned || null,
      earned,
      possible,
      percent,
      classAverage: a.classAverage != null ? U.num(a.classAverage) : null, // percent, 0-100
      classAveragePoints: a.classAveragePoints != null ? U.num(a.classAveragePoints) : null,
      missing: !!a.missing,
      absent: !!a.absent,
      noCount: !!a.noCount,        // teacher marked "does not count"
      excluded: !!a.excluded,      // user hid it in Skyward+
      hypothetical: !!a.hypothetical,
      note: a.note || '',
      source: a.source || 'scrape',
    };
  }

  function normalizeCourse(c) {
    const id = c.id || U.hash(c.name, c.period || '', c.term || '');
    const assignments = (c.assignments || []).map((a) => normalizeAssignment(a, id));
    const categories = (c.categories || []).map((k) => ({
      name: U.clean(k.name),
      weight: U.num(k.weight),
      reportedPercent: U.num(k.percent),
    }));
    return {
      id,
      name: U.clean(c.name || 'Unnamed course'),
      teacher: U.clean(c.teacher || ''),
      period: c.period != null ? U.clean(c.period) : '',
      room: U.clean(c.room || ''),
      term: U.clean(c.term || ''),
      reportedPercent: U.num(c.reportedPercent),
      reportedLetter: U.clean(c.reportedLetter || '') || null,
      courseClassAverage: U.num(c.courseClassAverage),
      level: c.level || 'regular', // regular | honors | ap
      categories,
      assignments,
      url: c.url || '',
      capturedAt: c.capturedAt || null,
    };
  }

  /* ---------- core computation ---------- */
  const applyEdit = (a, edits) => (edits && edits[a.id] ? { ...a, ...edits[a.id] } : a);

  const counts = (a) =>
    !a.excluded && !a.noCount && a.possible !== null && a.possible > 0 &&
    a.earned !== null && a.earned !== undefined && isFinite(a.earned);

  /* Resolve category weights, spreading any leftover across undeclared categories. */
  function resolveWeights(course, assignments) {
    const declared = new Map();
    for (const k of course.categories) if (k.weight !== null) declared.set(k.name.toLowerCase(), k.weight);
    const present = [...new Set(assignments.map((a) => a.category))];
    if (!declared.size) return null;

    const known = present.filter((n) => declared.has(n.toLowerCase()));
    const unknown = present.filter((n) => !declared.has(n.toLowerCase()));
    const out = new Map();
    for (const n of known) out.set(n, declared.get(n.toLowerCase()));
    if (unknown.length) {
      const used = known.reduce((s, n) => s + out.get(n), 0);
      const leftover = Math.max(0, 100 - used);
      const each = leftover > 0 ? leftover / unknown.length : 0;
      for (const n of unknown) out.set(n, each);
    }
    return out;
  }

  function computeWeighted(assignments, weights) {
    const groups = U.groupBy(assignments.filter(counts), (a) => a.category);
    let weightSum = 0, acc = 0;
    const cats = [];
    for (const [name, list] of groups) {
      const earned = list.reduce((s, a) => s + a.earned, 0);
      const possible = list.reduce((s, a) => s + a.possible, 0);
      const p = U.pct(earned, possible);
      const w = weights.has(name) ? weights.get(name) : 0;
      if (p !== null && w > 0) { weightSum += w; acc += (p * w) / 100; }
      cats.push({ name, earned, possible, percent: p, weight: w, count: list.length });
    }
    const percent = weightSum > 0 ? (acc / (weightSum / 100)) : null;
    for (const c of cats) {
      c.effectiveWeight = weightSum > 0 && c.percent !== null ? (c.weight / weightSum) * 100 : 0;
      c.contribution = c.percent !== null ? (c.percent * c.effectiveWeight) / 100 : 0;
    }
    return { percent, categories: cats, weightSum };
  }

  function computePoints(assignments) {
    const list = assignments.filter(counts);
    const earned = list.reduce((s, a) => s + a.earned, 0);
    const possible = list.reduce((s, a) => s + a.possible, 0);
    const groups = U.groupBy(list, (a) => a.category);
    const cats = [];
    for (const [name, items] of groups) {
      const e = items.reduce((s, a) => s + a.earned, 0);
      const p = items.reduce((s, a) => s + a.possible, 0);
      cats.push({
        name, earned: e, possible: p, percent: U.pct(e, p), count: items.length,
        weight: possible > 0 ? (p / possible) * 100 : 0,
        effectiveWeight: possible > 0 ? (p / possible) * 100 : 0,
        contribution: possible > 0 ? (e / possible) * 100 : 0,
      });
    }
    return { percent: U.pct(earned, possible), categories: cats, earned, possible };
  }

  /* mode: 'auto' | 'weighted' | 'points' */
  function computeCourse(course, opts = {}) {
    const { edits = {}, extra = [], mode = 'auto', scale = 'standard' } = opts;
    const assignments = course.assignments
      .map((a) => applyEdit(a, edits))
      .concat(extra.map((a) => normalizeAssignment(a, course.id)));

    const weights = resolveWeights(course, assignments);
    const weighted = weights ? computeWeighted(assignments, weights) : null;
    const points = computePoints(assignments);

    let chosen = 'points', result = points;
    if (mode === 'weighted' && weighted) { chosen = 'weighted'; result = weighted; }
    else if (mode === 'points') { chosen = 'points'; result = points; }
    else if (weighted && weighted.percent !== null) {
      // Auto: if Skyward reported a percent, trust whichever math reproduces it.
      const rep = course.reportedPercent;
      if (rep !== null && points.percent !== null) {
        const dw = Math.abs(weighted.percent - rep), dp = Math.abs(points.percent - rep);
        // Published weights win ties and near-ties; only a clearly better fit
        // (>1 point closer) means the teacher is really grading on total points.
        chosen = dp < dw - 1 ? 'points' : 'weighted';
      } else chosen = 'weighted';
      result = chosen === 'weighted' ? weighted : points;
    }

    // A class captured from the summary page only (no assignment detail yet)
    // still has a real grade — fall back to what Skyward posted.
    let percent = result.percent;
    let fromReported = false;
    if (percent === null && course.reportedPercent !== null) { percent = course.reportedPercent; fromReported = true; }
    const band = gradeBand(percent, scale);
    const matchesReported =
      course.reportedPercent !== null && percent !== null
        ? Math.abs(percent - course.reportedPercent) < 0.55
        : null;

    return {
      courseId: course.id,
      mode: chosen,
      percent,
      fromReported,
      letter: fromReported && course.reportedLetter ? course.reportedLetter : letterFor(percent, scale),
      band,
      categories: U.sortBy(result.categories, { fn: (c) => c.effectiveWeight, dir: -1 }),
      totalEarned: points.earned,
      totalPossible: points.possible,
      gradedCount: assignments.filter(counts).length,
      missingCount: assignments.filter((a) => a.missing && !a.excluded).length,
      ungradedCount: assignments.filter((a) => !counts(a) && !a.excluded && !a.noCount).length,
      matchesReported,
      assignments,
      weights,
    };
  }

  /* Recompute without one assignment -> how many points of final grade it is worth. */
  function assignmentImpact(course, opts, assignmentId) {
    const base = computeCourse(course, opts);
    const without = computeCourse(
      { ...course, assignments: course.assignments.filter((a) => a.id !== assignmentId) },
      { ...opts, extra: (opts.extra || []).filter((a) => a.id !== assignmentId) }
    );
    if (base.percent === null || without.percent === null) return null;
    return U.round(base.percent - without.percent, 3);
  }

  /* Potential gain if this assignment became a perfect score. */
  function assignmentUpside(course, opts, assignment) {
    const base = computeCourse(course, opts);
    const edits = { ...(opts.edits || {}), [assignment.id]: { earned: assignment.possible } };
    const fixed = computeCourse(course, { ...opts, edits });
    if (base.percent === null || fixed.percent === null) return null;
    return U.round(fixed.percent - base.percent, 3);
  }

  function impactTable(course, opts) {
    const base = computeCourse(course, opts);
    return base.assignments
      .filter((a) => counts(a))
      .map((a) => {
        const without = computeCourse(
          { ...course, assignments: course.assignments.filter((x) => x.id !== a.id) },
          { ...opts, extra: (opts.extra || []).filter((x) => x.id !== a.id) }
        );
        const impact = base.percent !== null && without.percent !== null
          ? U.round(base.percent - without.percent, 3) : null;
        return { assignment: a, impact };
      });
  }

  /* What score do I need on a future assignment to hit `target`? Binary search
     handles weighted + points modes identically, including weird weight setups. */
  function scoreNeeded(course, opts, { possible, category, target }) {
    const probe = (earned) => {
      const extra = (opts.extra || []).concat([
        { id: '__probe__', name: 'Probe', category: category || 'Uncategorized', earned, possible },
      ]);
      return computeCourse(course, { ...opts, extra }).percent;
    };
    const best = probe(possible), worst = probe(0);
    if (best === null) return { status: 'unknown' };
    if (worst >= target) return { status: 'secured', needed: 0, best, worst };
    if (best < target) return { status: 'impossible', needed: null, best, worst };
    let lo = 0, hi = possible;
    for (let i = 0; i < 60; i++) {
      const mid = (lo + hi) / 2;
      if (probe(mid) >= target) hi = mid; else lo = mid;
    }
    const needed = Math.ceil(hi * 100) / 100;
    return { status: 'ok', needed, neededPercent: U.pct(needed, possible), best, worst };
  }

  /* Grade needed on a final exam worth `weight`% of the course. */
  function finalExamNeeded(currentPercent, examWeight, target) {
    if (currentPercent === null || !examWeight) return null;
    const w = examWeight / 100;
    const need = (target - currentPercent * (1 - w)) / w;
    return U.round(need, 2);
  }

  const LEVEL_BONUS = { regular: 0, honors: 0.5, ap: 1.0 };

  function gpa(courses, results, scale = 'standard', weightedGpa = false) {
    const pts = [];
    for (const c of courses) {
      const r = results[c.id];
      const p = r && r.percent !== null ? r.percent : c.reportedPercent;
      if (p === null || p === undefined) continue;
      let g = gpaFor(p, scale);
      if (weightedGpa) g = Math.min(5, g + (LEVEL_BONUS[c.level] || 0));
      pts.push(g);
    }
    if (!pts.length) return null;
    return U.round(pts.reduce((a, b) => a + b, 0) / pts.length, 3);
  }

  /* Class-average comparison across everything you have data for. */
  function vsClassSummary(assignments) {
    const withAvg = assignments.filter(
      (a) => a.classAverage !== null && a.percent !== null && !a.excluded
    );
    if (!withAvg.length) return null;
    const deltas = withAvg.map((a) => a.percent - a.classAverage);
    const above = deltas.filter((d) => d > 0.01).length;
    const below = deltas.filter((d) => d < -0.01).length;
    return {
      count: withAvg.length,
      above,
      below,
      even: withAvg.length - above - below,
      avgDelta: U.round(deltas.reduce((a, b) => a + b, 0) / deltas.length, 2),
      yourAvg: U.round(withAvg.reduce((s, a) => s + a.percent, 0) / withAvg.length, 2),
      classAvg: U.round(withAvg.reduce((s, a) => s + a.classAverage, 0) / withAvg.length, 2),
    };
  }

  SP.model = {
    SCALES, LEVEL_BONUS, letterFor, gpaFor, gradeBand,
    normalizeCourse, normalizeAssignment, counts, resolveWeights,
    computeCourse, assignmentImpact, assignmentUpside, impactTable,
    scoreNeeded, finalExamNeeded, gpa, vsClassSummary,
  };
})();
