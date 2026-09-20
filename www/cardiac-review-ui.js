// Submit the complete visible exclusion form in the same event as its action.
// Native button clicks include Enter/Space activation; debounced Shiny inputs
// are never the authority for the value the researcher just saw.
(() => {
  if (window.brohnCardiacReviewInputs) return;
  window.brohnCardiacReviewInputs = true;
  const fields = ['mode', 'start_time', 'end_time', 'start_sample', 'end_sample', 'reason', 'note'];
  const snapshot = root => Object.fromEntries(fields.map(name => [name, root.querySelector('#cardiac_' + name)?.value ?? '']));
  const identity = root => ({source:root.dataset.source,form:root.querySelector('[data-cardiac-form]')?.dataset.cardiacForm ?? null});
  document.addEventListener('click', event => {
    const button = event.target.closest('[data-cardiac-action]'), root = button?.closest('#cardiac-review-ui');
    if (!button || !root || !window.Shiny || button.disabled) return;
    event.preventDefault();
    Shiny.setInputValue('cardiac_ui_action', {...identity(root), action:button.dataset.cardiacAction,
      payload:JSON.parse(button.dataset.cardiacPayload || '{}'), fields:snapshot(root),
      title:root.querySelector('#cardiac_title')?.value ?? '', choice:root.querySelector('#cardiac_choice')?.value ?? '',
      history:root.querySelector('#cardiac_history_revision')?.value ?? '', nonce:crypto.randomUUID()}, {priority:'event'});
  }, true);
  const changed = event => {
    const root = event.target.closest('#cardiac-review-ui');
    if (!root || !fields.some(name => event.target.id === 'cardiac_' + name) || !window.Shiny) return;
    // Hide stale approval immediately, even before the server receives the edit.
    root.querySelectorAll('[data-cardiac-current-preview]').forEach(node => {node.hidden=true;});
    Shiny.setInputValue('cardiac_ui_dirty', {...identity(root),fields:snapshot(root),nonce:crypto.randomUUID()}, {priority:'event'});
  };
  document.addEventListener('input',changed,true);
  document.addEventListener('change',changed,true);
})();
