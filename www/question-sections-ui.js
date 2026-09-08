'use strict';
// Read the visible form in the same event as its command. Shiny text-input
// debouncing must not turn a rapid type-then-click into the previous name.
(() => {
  if (window.brohnQuestionSectionsBound) return;
  window.brohnQuestionSectionsBound = true;
  document.addEventListener('click', event => {
    const button = event.target.closest('[data-brohn-sections-form]');
    if (!button || button.disabled || !window.Shiny) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    const command = JSON.parse(button.dataset.brohnValue);
    const value = id => document.getElementById(id)?.value ?? null;
    command.form = {
      node_identity: value('sections_node_identity'),
      label: value('sections_label'),
      placement: value('sections_placement'),
      new_label: value('sections_new_label'),
      target_id: value('sections_target')
    };
    Shiny.setInputValue(button.dataset.brohnEvent, command, {priority: 'event'});
  }, true);
})();
