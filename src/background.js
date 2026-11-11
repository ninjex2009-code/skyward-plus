/* Skyward+ — service worker. Bridges the popup/dashboard to the page. */
const DASHBOARD = 'dashboard/dashboard.html';

chrome.runtime.onMessage.addListener((msg, sender, respond) => {
  if (msg.type === 'capture-active') {
    (async () => {
      try {
        const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
        if (!tab) return respond({ error: 'No active tab' });
        const results = await chrome.scripting.executeScript({
          target: { tabId: tab.id, allFrames: true },
          func: async () => {
            const SP = globalThis.SkywardPlus;
            if (!SP || !SP.captureNow) return null;
            return SP.captureNow();
          },
        });
        const hits = results.map((r) => r.result).filter((r) => r && r.courses);
        if (!hits.length) return respond({ courses: 0, assignments: 0 });
        respond({
          courses: hits.reduce((s, r) => s + r.courses, 0),
          assignments: hits.reduce((s, r) => s + r.assignments, 0),
        });
      } catch (e) {
        respond({ error: e.message });
      }
    })();
    return true;
  }

  if (msg.type === 'open-dashboard') {
    chrome.tabs.create({ url: chrome.runtime.getURL(DASHBOARD) });
    respond({ ok: true });
    return true;
  }
  return false;
});

chrome.runtime.onInstalled.addListener(({ reason }) => {
  if (reason === 'install') chrome.tabs.create({ url: chrome.runtime.getURL(DASHBOARD + '?welcome=1') });
});
