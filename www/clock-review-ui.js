/* Reveal this request's loading status before acknowledging expensive work. */
(() => {
  if (window.brohnClockReviewPreparationInstalled) return;
  window.brohnClockReviewPreparationInstalled = true;
  const acknowledged = new Set(), focused = new Set(), completed = new Set();
  let scheduled = false, owner = null, lastFocus = null, yielded = false;
  function remember(set, token) {
    set.add(token);
    if (set.size > 128) set.delete(set.values().next().value);
  }
  function reveal(element, block = 'center') {
    element.setAttribute('tabindex', '-1');
    lastFocus = element;
    element.focus({preventScroll: true});
    element.scrollIntoView({behavior: 'instant', block, inline: 'nearest'});
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
    const element = document.querySelector('#clock_status [data-clock-review-ticket]');
    if (!element) { owner = null; lastFocus = null; yielded = false; return null; }
    if (document.visibilityState === 'hidden' || !element.getClientRects().length) return null;
    const token = element.getAttribute('data-clock-review-ticket');
    const phase = element.getAttribute('data-clock-review-phase');
    if (phase !== 'preparing') {
      if (token === owner && !completed.has(token) && ['ready', 'failed'].includes(phase)) {
        const target = phase === 'failed' ? element : Array.from(document.querySelectorAll('[data-clock-review-complete]'))
          .find(node => node.getAttribute('data-clock-review-complete') === token);
        if (target && target.getClientRects().length) {
          remember(completed, token);
          if (ownsFocus()) reveal(target, phase === 'ready' ? 'start' : 'center');
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
      Shiny.setInputValue('clock_review_prepare_ack', state.token, {priority: 'event'});
    }));
  }
  new MutationObserver(schedule).observe(document.documentElement, {
    childList: true, subtree: true, attributes: true,
    attributeFilter: ['data-clock-review-ticket', 'data-clock-review-phase', 'data-clock-review-complete', 'class', 'style', 'open']
  });
  document.addEventListener('focusin', event => {
    if (owner && lastFocus && event.target !== lastFocus) yielded = true;
  });
  const yieldToScroll = event => { if (owner && event.isTrusted) yielded = true; };
  document.addEventListener('wheel', yieldToScroll, {passive: true});
  document.addEventListener('touchmove', yieldToScroll, {passive: true});
  document.addEventListener('shiny:connected', schedule);
  document.addEventListener('toggle', event => {
    if (event.target.id === 'clock_review_panel' && !event.target.open && window.Shiny) {
      Shiny.setInputValue('clock_panel_closed', Date.now(), {priority: 'event'});
    }
  }, true);
  document.addEventListener('visibilitychange', schedule);
  document.addEventListener('scroll', schedule, true);
  window.addEventListener('resize', schedule);
  schedule();
})();

/* Automatic charts acknowledge their painted status without moving focus away
 * from the original measurements, exports or a researcher's current control. */
(() => {
  if (window.brohnClockPlotPreparationInstalled) return;
  window.brohnClockPlotPreparationInstalled = true;
  const acknowledged = new Set();
  let scheduled = false;
  function current() {
    const node = document.querySelector('#clock_plot_status [data-clock-plot-ticket]');
    if (!node || document.visibilityState === 'hidden' || !node.getClientRects().length ||
        node.getAttribute('data-clock-plot-phase') !== 'preparing') return null;
    return {node, token: node.getAttribute('data-clock-plot-ticket')};
  }
  function schedule() {
    const initial = current();
    if (scheduled || !initial || !initial.token || acknowledged.has(initial.token)) return;
    scheduled = true;
    requestAnimationFrame(() => requestAnimationFrame(() => {
      scheduled = false;
      const fresh = current();
      if (!fresh || fresh.node !== initial.node || fresh.token !== initial.token) { schedule(); return; }
      if (!window.Shiny || !Shiny.setInputValue || acknowledged.has(fresh.token)) return;
      acknowledged.add(fresh.token);
      if (acknowledged.size > 128) acknowledged.delete(acknowledged.values().next().value);
      Shiny.setInputValue('clock_plot_prepare_ack', fresh.token, {priority: 'event'});
    }));
  }
  new MutationObserver(schedule).observe(document.documentElement, {childList:true, subtree:true, attributes:true,
    attributeFilter:['data-clock-plot-ticket','data-clock-plot-phase','class','style','open']});
  document.addEventListener('shiny:connected', schedule);
  document.addEventListener('visibilitychange', schedule);
  document.addEventListener('toggle', schedule, true);
  schedule();
})();
