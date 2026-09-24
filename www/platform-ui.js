'use strict';
document.addEventListener('click', async event => {
  const button = event.target.closest('[data-brohn-event]');
  if (button && window.Shiny) {
    event.preventDefault();
    try { Shiny.setInputValue(button.dataset.brohnEvent, JSON.parse(button.dataset.brohnValue), { priority: 'event' }); }
    catch (error) { console.error('Invalid command data', error); }
  }
  const copy = event.target.closest('[data-brohn-copy]');
  if (copy) {
    try { await navigator.clipboard.writeText(copy.dataset.brohnCopy); copy.textContent = 'Link copied'; }
    catch { copy.textContent = 'Open the study and copy its address'; }
  }
});
function registerBrohnHandlers() {
  if (!window.Shiny || registerBrohnHandlers.done) return;
  registerBrohnHandlers.done = true;
  Shiny.addCustomMessageHandler('brohn-navigation', message => {
    document.querySelectorAll('.brohn-nav-button').forEach(button => {
      if (button.dataset.page === message.page) button.setAttribute('aria-current', 'page'); else button.removeAttribute('aria-current');
    });
    if (message.focus) requestAnimationFrame(() => document.getElementById('brohn-main')?.focus());
  });
  Shiny.addCustomMessageHandler('brohn-focus', id => requestAnimationFrame(() => document.getElementById(id)?.focus()));
}
if (window.jQuery) jQuery(document).on('shiny:connected', registerBrohnHandlers);
registerBrohnHandlers();
const registerTimer = setInterval(() => {registerBrohnHandlers(); if (registerBrohnHandlers.done) clearInterval(registerTimer);}, 100);
// Shiny appends dialogs outside the application root; apply the same researcher
// tokens there without touching the independently served participant renderer.
new MutationObserver(() => document.querySelectorAll('.modal-content').forEach(element => {
  element.classList.add('brohn-app', 'brohn-dialog-surface');
  const dialog=element.closest('.modal'), heading=element.querySelector('.modal-title');
  if(dialog&&heading) {
    const titleId=`${dialog.id||'brohn-dialog'}-title`;
    if(heading.tagName!=='H2'||heading.id!==titleId) {
      const title=document.createElement('h2');title.className=heading.className;title.id=titleId;
      title.append(...heading.childNodes);heading.replaceWith(title);
    }
    dialog.setAttribute('aria-labelledby',titleId);
  }
})).observe(document.body, {childList:true, subtree:true});

// Shiny's bundled selectize identifies its generated listbox with aria-owns.
// ARIA comboboxes also require aria-controls while expanded. Reuse the actual
// live listbox identity through dynamic/server-side updates, never invent one.
function brohnRepairComboboxControls() {
  document.querySelectorAll('.selectize-input input[role="combobox"]').forEach(input => {
    const target = input.getAttribute('aria-owns');
    const listbox = target && document.getElementById(target);
    if (listbox?.getAttribute('role') === 'listbox') {
      if (input.getAttribute('aria-controls') !== target) input.setAttribute('aria-controls', target);
    } else if (input.hasAttribute('aria-controls')) input.removeAttribute('aria-controls');
  });
}
new MutationObserver(brohnRepairComboboxControls).observe(document.body, {
  childList: true, subtree: true, attributes: true, attributeFilter: ['aria-owns', 'aria-expanded', 'role', 'id']
});
brohnRepairComboboxControls();

// Shiny appends notifications outside the main landmark and uses a plain div
// for its close control. Keep the installed click handler while exposing the
// same dismissal to keyboard and assistive-technology users.
function brohnRepairNotifications() {
  const panel = document.getElementById('shiny-notification-panel');
  if (!panel) return;
  panel.setAttribute('role', 'region');
  panel.setAttribute('aria-label', 'Workspace notifications');
  panel.querySelectorAll('.shiny-notification-close').forEach(close => {
    close.setAttribute('role', 'button');
    close.setAttribute('aria-label', 'Dismiss notification');
    close.tabIndex = 0;
  });
}
new MutationObserver(brohnRepairNotifications).observe(document.body, {childList:true, subtree:true});
document.addEventListener('keydown', event => {
  const close = event.target.closest('#shiny-notification-panel .shiny-notification-close');
  if (!close || !['Enter', ' '].includes(event.key) || event.repeat) return;
  event.preventDefault();
  close.click();
  document.getElementById('brohn-main')?.focus({preventScroll:true});
});
brohnRepairNotifications();
