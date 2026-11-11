/* Skyward+ — toolbar popup: quick grades, capture, open dashboard. */
(async function () {
  const SP = globalThis.SkywardPlus;
  const U = SP.util, M = SP.model, S = SP.storage;
  const h = U.escapeHtml;
  const root = document.getElementById('pop');
  let data = await S.load();

  const gradeVar = (p) =>
    p === null ? 'var(--text-faint)' : p >= 90 ? 'var(--a)' : p >= 80 ? 'var(--b)' : p >= 70 ? 'var(--c)' : p >= 60 ? 'var(--d)' : 'var(--f)';

  function render(note = '') {
    root.dataset.theme = data.settings.theme;
    const courses = U.sortBy(Object.values(data.courses), (c) => (U.num(c.period) === null ? 99 : U.num(c.period)), (c) => c.name);
    const results = {};
    for (const c of courses)
      results[c.id] = M.computeCourse(c, {
        edits: data.edits[c.id] || {}, extra: data.hypotheticals[c.id] || [],
        mode: data.settings.mode, scale: data.settings.scale,
      });
    const gpa = M.gpa(courses, results, data.settings.scale, data.settings.weightedGpa);

    root.innerHTML = `
      <div class="sp-pop-head">
        <span class="sp-mark" style="width:20px;height:20px;border-radius:6px;display:grid;place-items:center;background:linear-gradient(145deg,var(--accent),#8a6bff);color:#fff;font:800 12px/1 sans-serif">S</span>
        <b style="font-size:13px">Skyward<span style="color:var(--accent)">+</span></b>
        <span style="flex:1"></span>
        <span class="sp-sub">${gpa === null ? '' : 'GPA ' + gpa.toFixed(2)}</span>
      </div>
      ${courses.length ? `<div class="sp-pop-list">${courses.map((c) => {
        const r = results[c.id];
        return `<div class="sp-pop-row" data-course="${h(c.id)}">
          <span class="grow"><b>${h(c.name)}</b><span>${[c.period ? 'P' + h(c.period) : '', h(c.term || ''), r.missingCount ? r.missingCount + ' missing' : ''].filter(Boolean).join(' · ')}</span></span>
          <span style="text-align:right;font-weight:700;color:${gradeVar(r.percent)}">${r.letter || '--'}
            <span style="display:block;font-size:10px;font-weight:500;color:var(--text-faint)">${U.fmtPct(r.percent, 1)}</span></span>
        </div>`;
      }).join('')}</div>`
        : `<p class="sp-help" style="margin:6px 0 10px">No grades yet. Open your Skyward gradebook and hit Capture.</p>`}
      <div class="sp-pop-actions">
        <button class="sp-btn primary" id="cap">Capture page</button>
        <button class="sp-btn" id="dash">Open dashboard</button>
      </div>
      ${note ? `<p class="sp-help" style="margin-top:8px">${h(note)}</p>` : ''}`;

    root.querySelectorAll('[data-course]').forEach((el) =>
      el.addEventListener('click', () =>
        chrome.tabs.create({ url: chrome.runtime.getURL('dashboard/dashboard.html?course=' + encodeURIComponent(el.dataset.course)) })));
    root.querySelector('#dash').addEventListener('click', () =>
      chrome.tabs.create({ url: chrome.runtime.getURL('dashboard/dashboard.html') }));
    root.querySelector('#cap').addEventListener('click', async () => {
      const btn = root.querySelector('#cap');
      btn.textContent = 'Capturing...'; btn.disabled = true;
      const res = await chrome.runtime.sendMessage({ type: 'capture-active' });
      data = await S.load();
      render(res && res.error ? 'Capture failed: ' + res.error
        : res && res.courses ? `Captured ${res.courses} class(es), ${res.assignments} assignments.`
        : 'No gradebook found on that page — open the assignments view first.');
    });
  }

  render();
})();
