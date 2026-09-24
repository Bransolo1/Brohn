/* Reveal this request's loading status before acknowledging expensive work. */
(() => {
  if (window.brohnTaskPlotPreparationInstalled) return;
  window.brohnTaskPlotPreparationInstalled = true;
  const acknowledged = new Set(), focused = new Set(), completed = new Set();
  let scheduled = false, owner = null, lastFocus = null, yielded = false;
  function remember(set, token) {
    set.add(token);
    if (set.size > 128) set.delete(set.values().next().value);
  }
  function reveal(element) {
    element.setAttribute('tabindex', '-1');
    lastFocus = element;
    element.focus({preventScroll: true});
    element.scrollIntoView({behavior: 'instant', block: 'center', inline: 'nearest'});
  }
  function inViewport(element) {
    const r = element.getBoundingClientRect();
    return r.width > 0 && r.height > 0 && r.top >= -1 && r.left >= -1 &&
      r.bottom <= window.innerHeight + 1 && r.right <= window.innerWidth + 1;
  }
  function ownsFocus() {
    return !yielded && (document.activeElement === lastFocus || document.activeElement === document.body);
  }
  function current() {
    const element = document.querySelector('#task_plot_status [data-task-plot-ticket]');
    if (!element) { owner = null; lastFocus = null; yielded = false; return null; }
    if (document.visibilityState === 'hidden' || !element.getClientRects().length) return null;
    const token = element.getAttribute('data-task-plot-ticket');
    const phase = element.getAttribute('data-task-plot-phase');
    if (phase !== 'preparing') {
      if (token === owner && !completed.has(token) && ['ready', 'failed'].includes(phase)) {
        const target = phase === 'failed' ? element : Array.from(document.querySelectorAll('[data-task-plot-complete]'))
          .find(node => node.getAttribute('data-task-plot-complete') === token);
        if (target && target.getClientRects().length) {
          remember(completed, token);
          if (ownsFocus()) reveal(target);
        }
      }
      return null;
    }
    return {element, token};
  }
  function schedule() {
    const initial = current();
    if (scheduled || !initial || !initial.token || acknowledged.has(initial.token)) return;
    if (!focused.has(initial.token)) {
      owner = initial.token; yielded = false;
      remember(focused, initial.token); reveal(initial.element);
    }
    if (!inViewport(initial.element)) return;
    scheduled = true;
    requestAnimationFrame(() => requestAnimationFrame(() => {
      scheduled = false;
      const state = current();
      if (!state || state.element !== initial.element || state.token !== initial.token) {
        schedule(); return;
      }
      if (!inViewport(state.element) || acknowledged.has(state.token) || !window.Shiny || !Shiny.setInputValue) return;
      remember(acknowledged, state.token);
      Shiny.setInputValue('task_plot_prepare_ack', state.token, {priority: 'event'});
    }));
  }
  new MutationObserver(schedule).observe(document.documentElement, {
    childList: true, subtree: true, attributes: true,
    attributeFilter: ['data-task-plot-ticket', 'data-task-plot-phase', 'data-task-plot-complete', 'class', 'style', 'open']
  });
  document.addEventListener('focusin', event => {
    if (owner && lastFocus && event.target !== lastFocus) yielded = true;
  });
  const yieldToScroll = event => { if (owner && event.isTrusted) yielded = true; };
  document.addEventListener('wheel', yieldToScroll, {passive: true});
  document.addEventListener('touchmove', yieldToScroll, {passive: true});
  document.addEventListener('shiny:connected', schedule);
  document.addEventListener('visibilitychange', schedule);
  document.addEventListener('scroll', schedule, true);
  window.addEventListener('resize', schedule);
  schedule();
})();
