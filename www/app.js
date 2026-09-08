let draftHasUnsavedChanges = false;
document.addEventListener('input', function (event) {
  if (event.target.id.startsWith('aoi_')) { window.aoiHasUnsavedChanges = true; return; }
  if (!['study_title', 'question_prompt', 'include_liking', 'control_condition', 'control_rationale', 'presentation_order', 'viewing_seconds'].includes(event.target.id)) return;
  draftHasUnsavedChanges = true;
  const status = document.getElementById('draft_edit_state');
  if (status) status.textContent = 'Unsaved changes - choose Save draft or continue to keep them.';
});
window.addEventListener('beforeunload', function (event) {
  if (draftHasUnsavedChanges || window.aoiHasUnsavedChanges) { event.preventDefault(); event.returnValue = ''; }
});

// Send visible form values before action-button handlers. Otherwise Shiny's
// debounced text input can arrive after a fast Continue click and lose the edit.
document.addEventListener('click', function (event) {
  if (!event.target.closest('button.action-button, a.shiny-download-link')) return;
  ['study_title', 'question_prompt', 'include_liking', 'control_condition', 'control_rationale', 'presentation_order', 'viewing_seconds', 'aoi_selection', 'aoi_label', 'aoi_x', 'aoi_y', 'aoi_width', 'aoi_height'].forEach(function (id) {
    const input = document.getElementById(id);
    if (input) Shiny.setInputValue(id, input.type === 'checkbox' ? input.checked : input.type === 'number' ? (input.value === '' ? null : Number(input.value)) : input.value, { priority: 'event' });
  });
}, true);

$(document).on('shiny:connected', function () {
  Shiny.addCustomMessageHandler('draft-saved', function (message) {
    draftHasUnsavedChanges = false;
    window.aoiHasUnsavedChanges = false;
    const status = document.getElementById('draft_edit_state');
    if (status) status.textContent = '';
  });
  Shiny.addCustomMessageHandler('focus-study', function (message) {
    window.requestAnimationFrame(function () {
      document.getElementById('main-content')?.focus({ preventScroll: false });
    });
  });
});
