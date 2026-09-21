/* Capture visible selection at activation, including values not yet sent to Shiny. */
(() => {
  if (window.brohnSignalValuesInstalled) return;
  window.brohnSignalValuesInstalled = true;
  document.addEventListener('click', event => {
    const button = event.target.closest('[data-signal-values-action]');
    if (!button || button.disabled || !window.Shiny) return;
    const command = JSON.parse(button.getAttribute('data-signal-values-payload'));
    command.action = button.getAttribute('data-signal-values-action');
    if (command.action === 'open') {
      const value = id => document.getElementById(id)?.value ?? '';
      command.fields = {
        measure: value('signal_measure'), full_range: !!document.getElementById('signal_full_range')?.checked,
        start: value('signal_range_start'), end: value('signal_range_end'), limit: value('signal_values_limit'),
        form: value('signal_form_identity'), measure_form: value('signal_measure_identity')
      };
    }
    Shiny.setInputValue('signal_values_action', command, {priority: 'event'});
  });
})();
