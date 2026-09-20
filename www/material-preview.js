'use strict';
(function () {
  if (window.brohnMaterialPreviewBound) return;
  window.brohnMaterialPreviewBound = true;
  document.addEventListener('change', event => {
    if (event.target.id === 'material_file') {
      const attach = document.getElementById('material_attach_button');
      if (attach) attach.disabled = true;
    }
  }, true);
  const mediaState = event => {
    if (!event.target.matches?.('[data-material-media]')) return;
    const dialog = event.target.closest('.brohn-material-dialog');
    const note = dialog?.querySelector('#material_media_status');
    if (note) note.textContent = event.type === 'error'
      ? 'The saved material could not be opened. Retry the preview, or reopen the editor to check this source.'
      : 'Saved material ready.';
  };
  for (const event of ['load', 'loadedmetadata', 'error']) document.addEventListener(event, mediaState, true);
  if (window.jQuery) {
    jQuery(document).on('shiny:inputchanged.brohnMaterial', event => {
      if (event.name === 'material_file') {
        const attach = document.getElementById('material_attach_button');
        if (attach) attach.disabled = !event.value;
      }
    });
    jQuery(document).on('hidden.bs.modal.brohnMaterial', event => {
      const dialog = event.target.querySelector?.('[data-material-dialog]');
      if (dialog && window.Shiny) Shiny.setInputValue('material_cancel', {token: dialog.dataset.materialDialog}, {priority: 'event'});
    });
  }
})();
