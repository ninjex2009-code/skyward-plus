/* Skyward+ — standalone dashboard page. */
(async function () {
  const SP = globalThis.SkywardPlus;
  const params = new URLSearchParams(location.search);
  const app = await SP.ui.mount(document.getElementById('root'), {
    embedded: false,
    courseId: params.get('course') || null,
  });

  const syncBodyTheme = () => {
    document.body.classList.toggle('light', SP.state.data.settings.theme === 'light');
  };
  syncBodyTheme();
  new MutationObserver(syncBodyTheme).observe(SP.state.root, { attributes: true, attributeFilter: ['data-theme'] });

  if (params.get('welcome') && !Object.keys(SP.state.data.courses).length) {
    SP.ui.toast('Welcome — open your Skyward gradebook and hit Capture, or load the sample data.');
  }
  globalThis.__skywardPlus = app;
})();
