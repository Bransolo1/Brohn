// Commit this small form's visible values before its Preview/Apply command.
// Shiny's number/text debounce can otherwise arrive after a fast button click.
(() => {
  if (window.brohnSignalReuseInputs) return;
  window.brohnSignalReuseInputs = true;
  document.addEventListener('click', event => {
    const button = event.target.closest('#preview_interval_reuse,[data-brohn-event="apply_interval_reuse"]');
    const form = document.getElementById('signal_interval_reuse_form');
    if (!button || !form || !window.Shiny) return;
    const numeric = new Set(['interval_reuse_version', 'interval_reuse_source_anchor', 'interval_reuse_target_anchor']);
    for (const id of [...numeric, 'interval_reuse_title', 'interval_reuse_reason']) {
      const field = document.getElementById(id);
      if (!field) continue;
      const value = numeric.has(id) ? (field.value === '' || !Number.isFinite(Number(field.value)) ? null : Number(field.value)) : field.value;
      Shiny.setInputValue(id + (numeric.has(id) ? ':shiny.number' : ''), value, {priority: 'event'});
    }
  }, true);
})();
