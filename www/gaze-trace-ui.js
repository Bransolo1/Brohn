/* Capture the visible source window before Shiny's text-input debounce. */
(() => {
  if (window.brohnGazeTraceInstalled) return;
  window.brohnGazeTraceInstalled = true;
  let sequence = 0;
  const send = (name, value) => {
    if (window.Shiny) Shiny.setInputValue(name, {...value, sequence: ++sequence}, {priority: 'event'});
  };
  function fields(root) {
    return {
      form: root.dataset.gazeTraceForm,
      start: root.querySelector('#gaze_trace_start')?.value ?? '',
      end: root.querySelector('#gaze_trace_end')?.value ?? '',
      full: root.querySelector('#gaze_trace_full')?.checked === true
    };
  }
  document.addEventListener('click', event => {
    const button = event.target.closest('[data-gaze-trace-action]');
    if (!button) return;
    const root = button.closest('[data-gaze-trace-form]');
    const command = JSON.parse(button.dataset.gazeTracePayload);
    event.preventDefault();
    send('gaze_trace_action', {...command, action: button.dataset.gazeTraceAction, fields: root ? fields(root) : null});
  }, true);
  document.addEventListener('input', event => {
    if (!['gaze_trace_start', 'gaze_trace_end', 'gaze_trace_full'].includes(event.target.id)) return;
    const root = event.target.closest('[data-gaze-trace-form]');
    if (root) send('gaze_trace_dirty', fields(root));
  }, true);
})();
