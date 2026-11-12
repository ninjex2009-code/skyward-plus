import Foundation

enum QmlativScript {
    static let source = #"""
(() => {
  if (window.__sp) return 'ready';
  const T = e => (e ? (e.innerText || e.textContent || '') : '').replace(/\s+/g, ' ').trim();
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  // Visible on the page: rendered, not hidden by style. getClientRects() is empty
  // for anything not rendered (including inside a display:none parent) and,
  // unlike offsetParent, still works for position:fixed panels and overlays.
  const shown = e => {
    if (!e || !e.isConnected) return false;
    const style = window.getComputedStyle(e);
    if (style.display === 'none' || style.visibility === 'hidden') return false;
    return e.getClientRects().length > 0;
  };

  // Count in-flight XHRs so a click can be awaited until the page stops loading.
  const net = { active: 0, last: Date.now() };
  const send = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function () {
    net.active++; net.last = Date.now();
    this.addEventListener('loadend', () => { net.active = Math.max(0, net.active - 1); net.last = Date.now(); });
    return send.apply(this, arguments);
  };
  const quiet = async (idleMs, limitMs) => {
    const start = Date.now();
    while (Date.now() - start < limitMs) {
      if (net.active === 0 && Date.now() - net.last >= idleMs) return true;
      await sleep(80);
    }
    return false;
  };

  const sp = {};

  // verified: #signOutButton, #myAccountButton, .headerSelect__label, duplicate-session text
  sp.state = () => {
    const path = location.pathname;
    const signedIn = !!document.querySelector('#signOutButton');
    const password = [...document.querySelectorAll('input[type=password]')].some(shown);
    const text = document.body ? document.body.innerText.slice(0, 3000) : '';
    return JSON.stringify({
      host: location.host, path, title: document.title, signedIn,
      signInPage: !signedIn && (password || /\/Session\/Signin/i.test(path)),
      duplicateSession: /sign in was detected from a different window/i.test(text),
      name: T(document.querySelector('#myAccountButton')),
      school: T(document.querySelector('.headerSelect__label'))
    });
  };

  // verified against the real grid
  sp.grid = () => {
    const body = document.querySelector('table.unlockedBrowseTable');
    if (!body) return JSON.stringify({ heads: [], rows: [], missing: '' });
    // Narrow layouts can lack the .browse wrapper; fall back to the whole page.
    const browse = body.closest('.browse') || document;
    const heads = [...browse.querySelectorAll('.unlockedHeaderTableRow td')].map(td => ({
      text: T(td), current: /progressReportDetailsOpenHeader/.test(td.className)
    }));
    const locked = browse.querySelector('table.lockedBrowseTable');
    const rows = [];
    for (let i = 0; i < body.rows.length; i++) {
      const r = body.rows[i];
      const info = r.querySelector('a[data-studentsectionid]')
        || (locked && locked.rows[i] ? locked.rows[i].querySelector('a[data-studentsectionid]') : null);
      if (!info) continue;
      const labels = [...info.querySelectorAll('.visualLabel')].map(T);
      rows.push({
        section: info.getAttribute('data-studentsectionid') || '',
        student: info.getAttribute('data-studentid') || '',
        name: info.getAttribute('data-coursedescription') || labels[0] || '',
        code: info.getAttribute('data-coursecode') || '',
        period: labels[1] || '',
        cells: [...r.cells].map(c => ({
          text: T(c),
          id: c.getAttribute('data-student-grade-bucket-id') || '',
          link: c.classList.contains('linkPanelCell')
        }))
      });
    }
    const missing = ((document.body.innerText || '').match(/Current Missing Assignments:\s*(\d+)/) || [])[1] || '';
    return JSON.stringify({ heads, rows, missing });
  };

  // verified: header order, column classes, category rows, exclamation icon
  sp.panelData = () => {
    const dp = document.querySelector('#detailsPanel');
    if (!dp || !shown(dp) || !dp.querySelector('#GradeBucketAssignmentsSegmentedOuterContainer')) return null;
    const labels = [...dp.querySelectorAll('.visualLabel, .anchorText, .gradeMarkLabel')]
      .filter(e => !e.closest('.browse')).map(T).filter(Boolean);
    const out = { teacher: T(dp.querySelector('a .anchorText')), period: '', lit: '', range: '',
                  grade: T(dp.querySelector('.gradeMarkLabel')), percent: '', rows: [], weights: [] };
    labels.forEach((t, i) => {
      if (/^Period /i.test(t)) { out.period = t; if (labels[i + 1]) out.lit = labels[i + 1]; }
      else if (/^\d{1,2}\/\d{1,2}\/\d{4}\s*-\s*\d{1,2}\//.test(t)) out.range = t;
      else if (/^-?[\d.,]+\s*%$/.test(t) && !out.percent) out.percent = t;
    });
    const table = dp.querySelector('.browse table.unlockedBrowseTable');
    if (table) for (const r of table.rows) {
      const col = n => {
        const hits = [...r.cells].filter(c => c.classList.contains('column' + n)).map(T).filter(Boolean);
        return hits[hits.length - 1] || '';
      };
      const name = col(0);
      if (!name) continue;
      out.rows.push({
        category: /ParentRow/.test(r.className), name, due: col(1), grade: col(2), score: col(3),
        points: col(4), attempts: col(5),
        flagged: !!r.querySelector('.assignmentRowRendererExclamationIcon, svg.exclamation')
      });
    }
    return out;
  };

  // verified: modal markup and close button. unverified: timing inside WKWebView.
  sp.weights = async () => {
    const button = document.querySelector('#detailsPanel a.referenceCalculationButton');
    if (!button) return [];
    button.click();
    let modal = null;
    for (let i = 0; i < 50; i++) {
      await sleep(120);
      modal = document.querySelector('.modalLayerContainer');
      if (modal && shown(modal) && modal.querySelector('table.unlockedBrowseTable')) break;
    }
    await quiet(250, 6000);
    const rows = modal ? [...modal.querySelectorAll('table.unlockedBrowseTable tr')].map(r => [...r.cells].map(T)) : [];
    const close = modal && (modal.querySelector('#cancelButton') || [...modal.querySelectorAll('button, a')].find(b => /^close$/i.test(T(b))));
    if (close) close.click();
    for (let i = 0; i < 30 && document.querySelector('.modalLayerContainer') && shown(document.querySelector('.modalLayerContainer')); i++) await sleep(100);
    return rows.map(r => { while (r.length && !r[0]) r.shift(); return r; })
      .filter(r => r.length >= 2 && /^[\d.]+$/.test(r[1]))
      .map(r => ({ name: r[0], weight: r[1], adjusted: r[2] || '', percent: r[3] || '' }));
  };

  // unverified as a whole (the click and the panel were verified by hand)
  sp.open = async (bucketId, wantWeights) => {
    const cell = document.querySelector('td[data-student-grade-bucket-id="' + bucketId + '"]');
    if (!cell) return JSON.stringify({ error: 'no-cell' });
    if (!cell.classList.contains('linkPanelCell--active')) {
      (cell.querySelector('a') || cell).click();
      await sleep(200);
      await quiet(400, 15000);
    }
    let panel = null;
    for (let i = 0; i < 40 && !(panel = sp.panelData()); i++) await sleep(150);
    if (!panel) return JSON.stringify({ error: 'no-panel' });
    if (wantWeights) {
      try {
        panel.weights = await sp.weights();
      } catch (_) {
        panel.weights = [];
      }
    }
    return JSON.stringify(panel);
  };

  // verified: header, rows, legend button and legend text
  sp.attendance = async () => {
    const body = document.querySelector('table.unlockedBrowseTable');
    const out = { heads: [], rows: [], legend: {}, totals: '' };
    if (!body) return JSON.stringify(out);
    out.heads = [...(body.closest('.browse') || document).querySelectorAll('.unlockedHeaderTableRow td')].map(T);
    out.rows = [...body.rows].map(r => [...r.cells].map(T));
    out.totals = ((document.body.innerText || '').match(/Days Absent[\s\S]{0,120}?Tardy Count\s*[\d.]+/) || [''])[0].replace(/\s+/g, ' ');
    const button = document.querySelector('#btnStudentAttendanceLegend');
    if (button) {
      button.click();
      let modal = null;
      for (let i = 0; i < 40; i++) { await sleep(120); modal = document.querySelector('.modalLayerContainer'); if (modal && shown(modal) && /ATTENDANCE TYPES/i.test(modal.innerText)) break; }
      if (modal) {
        const lines = modal.innerText.split('\n').map(s => s.trim()).filter(Boolean);
        const a = lines.findIndex(l => /^ATTENDANCE TYPES$/i.test(l));
        const b = lines.findIndex(l => /^ATTENDANCE ICONS$/i.test(l));
        if (a >= 0) for (let i = a + 1; i + 1 < (b > a ? b : lines.length); i += 2) out.legend[lines[i]] = lines[i + 1];
        const close = modal.querySelector('#cancelButton');
        if (close) close.click();
      }
    }
    return JSON.stringify(out);
  };

  // unverified: finds the district SSO button on Skyward's sign-in page
  sp.clickSSO = () => {
    const hit = [...document.querySelectorAll('a, button, input[type=button], input[type=submit]')].filter(shown)
      .find(b => /sso|sign in with/i.test(T(b) || b.value || ''));
    if (!hit) return 'none';
    hit.click();
    return 'clicked';
  };

  // Fills the district's own sign-in page (not Skyward's) one step at a time:
  // username first, then the password once that field appears.
  sp.fillLogin = (user, pass, userSent) => {
    if (/skyward\.iscorp\.com$/i.test(location.host)) return 'skyward';
    const setValue = (input, value) => {
      const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
      input.focus();
      setter.call(input, value);
      input.dispatchEvent(new Event('input', { bubbles: true }));
      input.dispatchEvent(new Event('change', { bubbles: true }));
    };
    // The page's own button, a moment after typing so the page has enabled it.
    const submit = (input) => {
      setTimeout(() => {
        const form = input.closest('form');
        const usable = b => b && shown(b) && !/qr|claim|forgot|cancel|back|show|hide|help|language/i.test(T(b) || b.value || b.getAttribute('aria-label') || '');
        const button = [
          document.querySelector('#authn-go-button'),
          ...(form ? form.querySelectorAll('button[type=submit], input[type=submit]') : []),
          ...document.querySelectorAll('button[type=submit], input[type=submit]'),
          ...(form ? form.querySelectorAll('button') : [])
        ].find(usable);
        if (button) { button.click(); return; }
        if (form) { form.requestSubmit ? form.requestSubmit() : form.submit(); return; }
        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true }));
      }, 180);
    };
    const pw = [...document.querySelectorAll('input[type=password]')].find(shown);
    const name = [...document.querySelectorAll('#identification, input[autocomplete=username], input[type=email], input[name*=user i], input[id*=user i], input[type=text]')].find(shown);
    if (pw) {
      if (pw.value) return 'waiting';
      // Username and password on the same page: fill both, submit once.
      if (name && !name.value) setValue(name, user);
      setValue(pw, pass);
      submit(pw);
      return 'password';
    }
    if (name) {
      if (name.value === user) return 'waiting';
      // Already sent once and the page is asking again: it was refused. Do not resend.
      if (userSent) return 'username';
      setValue(name, user);
      submit(name);
      return 'username';
    }
    return 'none';
  };

  // After the password has been sent: is the page asking for it again, empty?
  sp.passwordAskedAgain = () => {
    if (/skyward\.iscorp\.com$/i.test(location.host)) return '0';
    const pw = [...document.querySelectorAll('input[type=password]')].find(shown);
    return pw && !pw.value ? '1' : '0';
  };

  // True on the district's own sign-in page when it is waiting for someone to type.
  sp.loginFormShown = () => {
    if (/skyward\.iscorp\.com$/i.test(location.host)) return '0';
    const inputs = [...document.querySelectorAll('input[type=password], input[type=text], input[type=email], input:not([type])')].filter(shown);
    return inputs.length ? '1' : '0';
  };

  window.__sp = sp;
  return 'ready';
})()
"""#
}
