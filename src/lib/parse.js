/* Skyward+ — extraction. Reads whatever gradebook DOM is on screen (Skyward
   classic sfgradebook, Qmlativ, or any table-shaped gradebook) and also accepts
   pasted text / CSV / JSON so it still works when a district's markup is odd. */
(function () {
  const SP = (globalThis.SkywardPlus = globalThis.SkywardPlus || {});
  const U = SP.util;

  const KEYS = {
    name: ['assignment', 'description', 'title', 'activity', 'task', 'name'],
    category: ['category', 'type', 'group', 'assignment type', 'cat'],
    due: ['due', 'date', 'due date', 'assigned'],
    score: ['score', 'points', 'grade', 'earned', 'pts', 'points earned', 'my score'],
    possible: ['possible', 'max', 'out of', 'point value', 'points possible', 'total'],
    percent: ['percent', '%', 'pct', 'percentage'],
    classAvg: ['class average', 'average', 'avg', 'mean', 'class avg', 'class median', 'median'],
    weight: ['weight', 'weighting', '% of grade', 'percent of grade'],
    term: ['term', 'quarter', 'semester', 'marking period', 'grading period'],
    course: ['course', 'class', 'subject'],
    teacher: ['teacher', 'instructor'],
    period: ['period', 'per'],
  };

  const matchRole = (header) => {
    const h = U.clean(header).toLowerCase().replace(/[*:()]/g, '').trim();
    if (!h) return null;
    // Longest keyword first so "class average" beats "class".
    let best = null, bestLen = 0;
    for (const [role, words] of Object.entries(KEYS)) {
      for (const w of words) {
        const hit = h === w || h.startsWith(w + ' ') || h.endsWith(' ' + w) || h.includes(w);
        if (hit && w.length > bestLen) { best = role; bestLen = w.length; }
      }
    }
    return best;
  };


  const cleanCourseName = (raw) =>
    U.clean(
      String(raw)
        .replace(/(?:period|per\.?)\s*[:#]?\s*\d{1,2}[A-Za-z]?/i, '')
        .replace(/\s*(?:teacher|instructor)\s*:.*/i, '')
        .replace(/^\s*[|\-\u2013\u2014:]+\s*/, '')
        .replace(/\s*[|\-\u2013\u2014:]+\s*$/, '')
    );

  const cellText = (el) => U.clean(el ? el.textContent : '');

  /* "45 / 50", "45 out of 50", "45.00", "90%", "M", "*" */
  function parseScore(text) {
    const t = U.clean(text);
    if (!t) return {};
    if (/^(m|missing|abs|absent|nc|no count|inc|incomplete|\*|-|--|n\/a)$/i.test(t))
      return { earned: null, missing: /^m|missing/i.test(t), absent: /^abs/i.test(t), noCount: /^nc|no count/i.test(t) };
    let m = t.match(/(-?[\d.]+)\s*(?:\/|out of|of)\s*([\d.]+)/i);
    if (m) return { earned: U.num(m[1]), possible: U.num(m[2]) };
    m = t.match(/^(-?[\d.]+)\s*%$/);
    if (m) return { percent: U.num(m[1]) };
    const n = U.num(t);
    return n === null ? {} : { earned: n };
  }

  /* Grid abstraction: real <table>s plus aria grid/rowgroup markup (Qmlativ). */
  function collectGrids(root) {
    const grids = [];
    root.querySelectorAll('table').forEach((t) => {
      const rows = [...t.querySelectorAll('tr')].map((tr) => [...tr.children].filter((c) => /^(td|th)$/i.test(c.tagName)));
      if (rows.length >= 2) grids.push({ el: t, rows, kind: 'table' });
    });
    root.querySelectorAll('[role="table"],[role="grid"],[role="treegrid"]').forEach((t) => {
      if (t.closest('table')) return;
      const rows = [...t.querySelectorAll('[role="row"]')].map((r) =>
        [...r.querySelectorAll('[role="gridcell"],[role="cell"],[role="columnheader"],[role="rowheader"]')]
      );
      if (rows.length >= 2) grids.push({ el: t, rows, kind: 'aria' });
    });
    return grids;
  }

  function headerRowIndex(rows) {
    for (let i = 0; i < Math.min(4, rows.length); i++) {
      const cells = rows[i];
      if (!cells.length) continue;
      const isTh = cells.every((c) => /^th$/i.test(c.tagName)) ||
        cells.some((c) => c.getAttribute && c.getAttribute('role') === 'columnheader');
      const roles = cells.map((c) => matchRole(cellText(c))).filter(Boolean);
      if ((isTh && roles.length >= 1) || roles.length >= 2) return i;
    }
    return -1;
  }

  function buildColMap(headerCells) {
    const map = {};
    headerCells.forEach((c, i) => {
      const role = matchRole(cellText(c));
      if (role && map[role] === undefined) map[role] = i;
    });
    return map;
  }

  /* Category header row: "Homework  20%" or a row flagged by Skyward's own classes. */
  function categoryRow(cells, colMap) {
    const texts = cells.map(cellText);
    const first = texts[0] || '';
    const filled = texts.filter(Boolean).length;
    const cls = (cells[0] && cells[0].className) || '';
    const flagged = /categ|gbcat|sf_.*cat/i.test(String(cls));
    const weightHere = first.match(/^(.+?)\s*[\(\[]?\s*(\d{1,3}(?:\.\d+)?)\s*%\s*[\)\]]?$/);
    const noName = colMap.name !== undefined && !texts[colMap.name];
    if (flagged && first) {
      const w = (texts.join(' ').match(/(\d{1,3}(?:\.\d+)?)\s*%/) || [])[1];
      return { name: U.clean(first.replace(/\s*\(?\d+(\.\d+)?%\)?/, '')), weight: U.num(w) };
    }
    if (weightHere && (filled <= 4 || noName)) {
      return { name: U.clean(weightHere[1]), weight: U.num(weightHere[2]) };
    }
    return null;
  }

  const looksLikeAssignmentGrid = (colMap) =>
    colMap.name !== undefined &&
    (colMap.score !== undefined || colMap.possible !== undefined || colMap.percent !== undefined);

  /* Course title for a grid: nearest preceding heading / caption / labelled box. */
  function courseContextFor(el, doc) {
    const out = { name: '', teacher: '', period: '', term: '' };
    const cap = el.querySelector && el.querySelector('caption');
    const texts = [];
    if (cap) texts.push(cellText(cap));
    let node = el;
    for (let hops = 0; hops < 6 && node; hops++) {
      let sib = node.previousElementSibling;
      let guard = 0;
      while (sib && guard++ < 8) {
        if (/^(h1|h2|h3|h4|h5|legend|caption)$/i.test(sib.tagName)) texts.push(cellText(sib));
        else if (/title|header|heading|course|classname|sf_heading/i.test(String(sib.className)))
          texts.push(cellText(sib));
        sib = sib.previousElementSibling;
      }
      node = node.parentElement;
    }
    const docTitle = doc && doc.title ? U.clean(doc.title) : '';
    texts.push(docTitle);
    const blob = texts.filter(Boolean).join(' | ');

    const per = blob.match(/(?:period|per\.?)\s*[:#]?\s*(\d{1,2}[A-Za-z]?)/i);
    if (per) out.period = per[1];
    const teach = blob.match(/(?:teacher|instructor)\s*[:]\s*([^|\u2013\u2014]+)/i);
    if (teach) out.teacher = U.clean(teach[1]);
    const term = blob.match(/\b(Q[1-4]|S[12]|Quarter\s*[1-4]|Semester\s*[12]|Term\s*[1-6]|MP\s*[1-6])\b/i);
    if (term) out.term = U.clean(term[1]).toUpperCase().replace(/\s+/g, '');

    const first = texts.find((t) => t && t.length > 2 && t.length < 90 && !/^skyward|family access|student access$/i.test(t));
    if (first) {
      out.name = cleanCourseName(first.replace(/\b(gradebook|assignments|grades?)\b/gi, ''));
    }
    return out;
  }

  function parseAssignmentGrid(grid, doc) {
    const { rows, el } = grid;
    const hi = headerRowIndex(rows);
    if (hi < 0) return null;
    const colMap = buildColMap(rows[hi]);
    if (!looksLikeAssignmentGrid(colMap)) return null;

    const ctx = courseContextFor(el, doc);
    const categories = [];
    const assignments = [];
    let currentCat = '';

    for (let i = hi + 1; i < rows.length; i++) {
      const cells = rows[i];
      if (!cells.length) continue;
      const texts = cells.map(cellText);
      if (!texts.some(Boolean)) continue;

      const cat = categoryRow(cells, colMap);
      if (cat && cat.name) {
        currentCat = cat.name;
        if (!categories.some((c) => c.name.toLowerCase() === cat.name.toLowerCase()))
          categories.push({ name: cat.name, weight: cat.weight });
        continue;
      }

      const rawName = U.clean(texts[colMap.name] || '');
      const name = U.clean(rawName.replace(/[*\u2731]\s*(missing|no count|absent|not graded)\s*$/i, '').replace(/\s*\*+$/, ''));
      if (!name || /^(total|totals|category total|overall|grade)$/i.test(name)) continue;

      const scoreCell = colMap.score !== undefined ? texts[colMap.score] : '';
      const parsed = parseScore(scoreCell);
      let earned = parsed.earned !== undefined ? parsed.earned : null;
      let possible = parsed.possible !== undefined ? parsed.possible : null;
      if (possible === null && colMap.possible !== undefined) {
        const p = parseScore(texts[colMap.possible]);
        possible = p.possible !== undefined ? p.possible : p.earned;
      }
      let percent = parsed.percent !== undefined ? parsed.percent : null;
      if (percent === null && colMap.percent !== undefined) percent = U.num(texts[colMap.percent]);
      if (earned === null && percent !== null && possible !== null) earned = (percent / 100) * possible;

      let classAverage = null, classAveragePoints = null;
      if (colMap.classAvg !== undefined) {
        const a = parseScore(texts[colMap.classAvg]);
        if (a.percent !== undefined) classAverage = a.percent;
        else if (a.possible !== undefined) { classAveragePoints = a.earned; classAverage = U.pct(a.earned, a.possible); }
        else if (a.earned !== undefined && a.earned !== null) {
          if (possible && a.earned <= possible) { classAveragePoints = a.earned; classAverage = U.pct(a.earned, possible); }
          else if (a.earned <= 100) classAverage = a.earned;
        }
      }

      const rowText = (texts.join(' ') + ' ' + rawName).toLowerCase();
      const missing = parsed.missing || /\bmissing\b|\bmis\b/.test(rowText) ||
        cells.some((c) => /missing/i.test(String(c.className)));
      const noCount = parsed.noCount || /no count|not graded|ungraded|excluded/.test(rowText);

      const hasContext = (colMap.due !== undefined && texts[colMap.due]) ||
        (colMap.category !== undefined && texts[colMap.category]) || !!currentCat;
      if (earned === null && possible === null && percent === null && !missing && !hasContext) continue;

      assignments.push({
        name,
        category: colMap.category !== undefined && texts[colMap.category] ? texts[colMap.category] : (currentCat || 'Uncategorized'),
        due: colMap.due !== undefined ? U.parseDate(texts[colMap.due]) : null,
        earned, possible, percent, classAverage, classAveragePoints,
        missing, noCount,
      });
    }

    if (!assignments.length) return null;
    return { ...ctx, categories, assignments };
  }

  /* Summary grid: one row per course, term grades in the columns. */
  function parseSummaryGrid(grid, doc) {
    const { rows } = grid;
    const hi = headerRowIndex(rows);
    const headerTexts = hi >= 0 ? rows[hi].map(cellText) : [];
    const termCols = [];
    headerTexts.forEach((t, i) => {
      if (/^(Q[1-4]|S[12]|SM[12]|T[1-6]|MP[1-6]|PR[1-6]|Sem\s*[12]|Quarter\s*[1-4]|Final|Exam)$/i.test(U.clean(t)))
        termCols.push({ i, term: U.clean(t).toUpperCase().replace(/\s+/g, '') });
    });
    if (!termCols.length) return [];

    const out = [];
    for (let i = (hi < 0 ? 0 : hi + 1); i < rows.length; i++) {
      const texts = rows[i].map(cellText);
      const label = texts.find((t) => t && !/^\d+(\.\d+)?%?$/.test(t) && t.length > 2);
      if (!label) continue;
      if (/^(total|gpa|credits)/i.test(label)) continue;
      const per = (texts.join(' ').match(/(?:period|per\.?)\s*[:#]?\s*(\d{1,2})/i) || [])[1] || '';
      let teacher = (texts.join(' | ').match(/(?:teacher|instructor)\s*:?\s*([A-Z][\w'.-]+(?:\s+[A-Z][\w'.-]+)*)/) || [])[1] || '';
      if (!teacher) teacher = (texts.find((t) => /^[A-Z][\w'.-]+,\s*[A-Z][\w'.-]*\.?$/.test(U.clean(t))) || '');
      for (const tc of termCols) {
        const cellRaw = texts[tc.i] || '';
        const pctVal = U.num((cellRaw.match(/(\d{1,3}(?:\.\d+)?)\s*%?/) || [])[1]);
        const letter = (cellRaw.match(/\b([A-F][+-]?)(?![A-Za-z0-9])/) || [])[1] || null;
        if (pctVal === null && !letter) continue;
        out.push({
          name: cleanCourseName(label),
          period: per, teacher, term: tc.term,
          reportedPercent: pctVal !== null && pctVal <= 130 ? pctVal : null,
          reportedLetter: letter,
          categories: [], assignments: [],
        });
      }
    }
    return out;
  }

  /* Standalone weight legend: "Homework 20% | Tests 50% | Quizzes 30%" */
  function scrapeWeightLegend(root) {
    const found = [];
    const grids = collectGrids(root);
    for (const g of grids) {
      const hi = headerRowIndex(g.rows);
      if (hi < 0) continue;
      const map = buildColMap(g.rows[hi]);
      if (map.weight === undefined) continue;
      const nameCol = map.category !== undefined ? map.category : map.name !== undefined ? map.name : 0;
      for (let i = hi + 1; i < g.rows.length; i++) {
        const t = g.rows[i].map(cellText);
        const n = U.clean(t[nameCol] || '');
        const w = U.num(t[map.weight]);
        if (n && w !== null) found.push({ name: n, weight: w });
      }
    }
    return found;
  }

  function scrapePage(doc = document, url = location.href) {
    const debug = { url, grids: 0, assignmentGrids: 0, summaryGrids: 0, notes: [] };
    const grids = collectGrids(doc.body || doc);
    debug.grids = grids.length;

    const assignmentCourses = [];
    const summaryCourses = [];
    for (const g of grids) {
      let parsed = null;
      try { parsed = parseAssignmentGrid(g, doc); } catch (e) { debug.notes.push('grid error: ' + e.message); }
      if (parsed) { assignmentCourses.push(parsed); debug.assignmentGrids++; continue; }
      try {
        const sums = parseSummaryGrid(g, doc);
        if (sums.length) { summaryCourses.push(...sums); debug.summaryGrids++; }
      } catch (e) { debug.notes.push('summary error: ' + e.message); }
    }

    const legend = scrapeWeightLegend(doc.body || doc);
    for (const c of assignmentCourses) {
      if (!c.categories.some((k) => k.weight !== null && k.weight !== undefined)) {
        const used = new Set(c.assignments.map((a) => a.category.toLowerCase()));
        const hits = legend.filter((l) => used.has(l.name.toLowerCase()));
        if (hits.length) c.categories = hits;
      }
      c.url = url;
      if (!c.name) c.name = U.clean((doc.title || 'Class').replace(/skyward|family access|student access/gi, '')) || 'Class';
    }

    // Merge same-named courses found in different grids on one page.
    const byKey = new Map();
    const push = (c) => {
      const key = U.hash(c.name, c.period || '', c.term || '');
      if (!byKey.has(key)) byKey.set(key, c);
      else {
        const e = byKey.get(key);
        e.assignments = e.assignments.concat(c.assignments || []);
        if ((c.categories || []).length > (e.categories || []).length) e.categories = c.categories;
        if (c.reportedPercent != null) e.reportedPercent = c.reportedPercent;
        if (c.reportedLetter) e.reportedLetter = c.reportedLetter;
      }
    };
    assignmentCourses.forEach(push);
    summaryCourses.forEach(push);

    const courses = [...byKey.values()].filter((c) => c.assignments.length || c.reportedPercent != null || c.reportedLetter);
    debug.courses = courses.map((c) => ({ name: c.name, term: c.term, assignments: c.assignments.length }));
    return { courses, debug };
  }

  /* ---------- paste / file import ---------- */

  /* Structured paste:
       # Algebra II - Mr. Smith - Period 3 - Q2
       [Homework 20%]
       HW 1.4 | 10/10 | avg 8.7 | due 12/4
     Also tolerates raw copy-paste of a gradebook page (tabs or 2+ spaces). */
  function parseText(text) {
    const lines = String(text).split(/\r?\n/).map((l) => l.replace(/\t/g, ' | ')).map(U.clean).filter(Boolean);
    const courses = [];
    let course = null, cat = 'Uncategorized';

    const newCourse = (header) => {
      const parts = header.split(/\s*[|–—]\s*|\s+-\s+/).map(U.clean).filter(Boolean);
      const c = { name: parts[0] || 'Class', teacher: '', period: '', term: '', categories: [], assignments: [] };
      for (const p of parts.slice(1)) {
        if (/^(period|per\.?)\s*\d/i.test(p)) c.period = (p.match(/\d+[A-Za-z]?/) || [''])[0];
        else if (/^(Q[1-4]|S[12]|T[1-6]|MP[1-6])$/i.test(p)) c.term = p.toUpperCase();
        else if (!c.teacher) c.teacher = p;
      }
      courses.push(c);
      cat = 'Uncategorized';
      return c;
    };

    for (const line of lines) {
      let m = line.match(/^#{1,3}\s*(.+)$/);
      if (m) { course = newCourse(m[1]); continue; }
      m = line.match(/^\[(.+?)\s*(?:(\d{1,3}(?:\.\d+)?)\s*%)?\]$/);
      if (m) {
        cat = U.clean(m[1]);
        if (course && m[2]) course.categories.push({ name: cat, weight: U.num(m[2]) });
        continue;
      }
      m = line.match(/^(.+?)\s*[|:]?\s*(\d{1,3}(?:\.\d+)?)\s*%\s*(?:weight|of grade)$/i);
      if (m && course) { course.categories.push({ name: U.clean(m[1]), weight: U.num(m[2]) }); continue; }

      const score = line.match(/(-?[\d.]+)\s*(?:\/|out of)\s*([\d.]+)/i);
      if (!score) {
        // A bare line with no score starts a new class if the next lines have scores.
        if (!/\d/.test(line) && line.length < 80) { course = newCourse(line); }
        continue;
      }
      if (!course) course = newCourse('Imported class');
      const before = U.clean(line.slice(0, score.index).replace(/[|;,]+$/, ''));
      const after = line.slice(score.index + score[0].length);
      const avg = after.match(/(?:avg|average|class avg|mean)\D{0,4}([\d.]+)\s*(%?)/i);
      const due = after.match(/(?:due)\s*[:]?\s*([\d/.-]+)/i);
      const catInline = before.match(/\[(.+?)\]\s*$/);
      const nameParts = before.split(/\s*\|\s*/).filter(Boolean);
      const name = U.clean(catInline ? before.replace(/\[.+?\]\s*$/, '') : nameParts[0] || 'Assignment');
      const possible = U.num(score[2]);
      let classAverage = null;
      if (avg) {
        const v = U.num(avg[1]);
        classAverage = avg[2] === '%' ? v : possible ? U.pct(v, possible) : v;
      }
      course.assignments.push({
        name,
        category: catInline ? U.clean(catInline[1]) : nameParts[1] && !/^\d/.test(nameParts[1]) ? U.clean(nameParts[1]) : cat,
        earned: U.num(score[1]),
        possible,
        classAverage,
        due: due ? U.parseDate(due[1]) : null,
        missing: /\bmissing\b/i.test(line),
        source: 'manual',
      });
    }
    return courses.filter((c) => c.assignments.length);
  }

  function parseCsv(text) {
    const rows = String(text).trim().split(/\r?\n/).map((l) => splitCsvLine(l));
    if (rows.length < 2) return [];
    const header = rows[0].map((h) => U.clean(h).toLowerCase());
    const idx = (names) => header.findIndex((h) => names.some((n) => h === n || h.includes(n)));
    const ci = idx(KEYS.course), ni = idx(KEYS.name), cat = idx(KEYS.category);
    const sc = idx(KEYS.score), po = idx(KEYS.possible), av = idx(KEYS.classAvg), du = idx(KEYS.due);
    if (ni < 0) return [];
    const byCourse = new Map();
    for (const r of rows.slice(1)) {
      const cname = ci >= 0 ? U.clean(r[ci]) : 'Imported class';
      if (!byCourse.has(cname)) byCourse.set(cname, { name: cname, categories: [], assignments: [] });
      const s = parseScore(sc >= 0 ? r[sc] : '');
      byCourse.get(cname).assignments.push({
        name: U.clean(r[ni]),
        category: cat >= 0 ? U.clean(r[cat]) : 'Uncategorized',
        earned: s.earned !== undefined ? s.earned : null,
        possible: po >= 0 ? U.num(r[po]) : s.possible !== undefined ? s.possible : null,
        classAverage: av >= 0 ? U.num(r[av]) : null,
        due: du >= 0 ? U.parseDate(r[du]) : null,
        source: 'manual',
      });
    }
    return [...byCourse.values()];
  }

  function splitCsvLine(line) {
    const out = [];
    let cur = '', q = false;
    for (let i = 0; i < line.length; i++) {
      const c = line[i];
      if (q) {
        if (c === '"' && line[i + 1] === '"') { cur += '"'; i++; }
        else if (c === '"') q = false;
        else cur += c;
      } else if (c === '"') q = true;
      else if (c === ',') { out.push(cur); cur = ''; }
      else cur += c;
    }
    out.push(cur);
    return out;
  }

  function parseAny(text) {
    const t = String(text).trim();
    if (!t) return [];
    if (t.startsWith('{') || t.startsWith('[')) {
      try {
        const data = JSON.parse(t);
        const list = Array.isArray(data) ? data : data.courses ? Object.values(data.courses) : [data];
        return list.filter((c) => c && c.name);
      } catch { /* fall through */ }
    }
    if (/^[^\n]*,[^\n]*,/.test(t) && /\n/.test(t)) {
      const csv = parseCsv(t);
      if (csv.length) return csv;
    }
    return parseText(t);
  }

  SP.parse = { scrapePage, parseAny, parseText, parseCsv, parseScore, collectGrids, matchRole, courseContextFor };
})();
