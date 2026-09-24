/* Scoped source-opening feedback is focused and painted before server work. */
(() => {
  if (window.brohnMediaReopenInstalled) return;
  window.brohnMediaReopenInstalled = true;
  const acknowledged = new Set(), waiting = new Map(), focused = new Set(), completed = new Set();
  let scheduled = false, retry = null, owner = null, lastFocus = null, yielded = null;
  const controls = () => ({track: document.getElementById('media_review_track')?.value ?? null, seconds: document.getElementById('media_review_seconds')?.value ?? null});
  function boundedAdd(set, key) { set.add(key); if (set.size > 128) set.delete(set.values().next().value); }
  function ownsFocus() { return yielded !== owner && (document.activeElement === lastFocus || document.activeElement === document.body); }
  function focusAndReveal(element) {
    element.setAttribute('tabindex', '-1');
    lastFocus = element;
    element.focus({preventScroll: true});
    // Always instant, including reduced-motion preferences; never animate an acknowledgement.
    element.scrollIntoView({behavior: 'instant', block: 'center', inline: 'nearest'});
  }
  function inViewport(element) {
    const r = element.getBoundingClientRect();
    return r.width > 0 && r.height > 0 && r.top >= -1 && r.left >= -1 && r.bottom <= window.innerHeight + 1 && r.right <= window.innerWidth + 1;
  }
  function current() {
    const element = document.querySelector('#media_review_status [data-media-reopen-ticket]');
    const fields = document.getElementById('media_review_cursor_fields');
    if (fields) fields.disabled = !!element;
    if (!element) {
      const heading = document.querySelector('#shiny-modal [data-media-reopen-complete]');
      const token = heading?.getAttribute('data-media-reopen-complete');
      if (heading && token && token === owner && !completed.has(token) && document.visibilityState !== 'hidden' && heading.getClientRects().length) {
        boundedAdd(completed, token);
        if (ownsFocus()) focusAndReveal(heading);
      }
      return null;
    }
    if (document.visibilityState === 'hidden' || !element.getClientRects().length) return null;
    return {element, token: element.getAttribute('data-media-reopen-ticket'), phase: element.getAttribute('data-media-reopen-phase')};
  }
  function schedule() {
    const initial = current();
    if (scheduled || !initial || !initial.token || !['prepare','verify'].includes(initial.phase)) return;
    const key = initial.token + '/' + initial.phase;
    if (acknowledged.has(key)) return;
    if (!focused.has(key)) {
      if (initial.phase === 'prepare' && owner !== initial.token) yielded = null;
      if (initial.phase === 'prepare' || (owner === initial.token && ownsFocus())) focusAndReveal(initial.element);
      owner = initial.token; boundedAdd(focused, key);
    }
    const actual = controls();
    if (initial.phase === 'verify' && (actual.track !== initial.element.getAttribute('data-media-reopen-track') || actual.seconds !== initial.element.getAttribute('data-media-reopen-seconds'))) {
      if (!waiting.has(key)) waiting.set(key, Date.now());
      if (waiting.size > 128) waiting.delete(waiting.keys().next().value);
      if (Date.now() - waiting.get(key) < 15000) {
        if (retry === null) retry = setTimeout(() => { retry = null; schedule(); }, 100);
        return;
      }
    }
    if ((initial.phase === 'prepare' || ownsFocus()) && !inViewport(initial.element)) return;
    scheduled = true;
    requestAnimationFrame(() => requestAnimationFrame(() => {
      scheduled = false;
      const state = current();
      if (!state || state.element !== initial.element || state.token !== initial.token || state.phase !== initial.phase) { schedule(); return; }
      if (((state.phase === 'prepare' || ownsFocus()) && !inViewport(state.element)) || acknowledged.has(key) || !window.Shiny || !Shiny.setInputValue) return;
      boundedAdd(acknowledged, key);
      Shiny.setInputValue('media_review_reopen_ack', {token: state.token, phase: state.phase, controls: controls()}, {priority:'event'});
    }));
  }
  new MutationObserver(schedule).observe(document.documentElement, {childList:true,subtree:true,attributes:true,attributeFilter:['data-media-reopen-ticket','data-media-reopen-phase','data-media-reopen-complete','class','style','open']});
  document.addEventListener('shiny:connected', schedule);
  document.addEventListener('visibilitychange', schedule);
  document.addEventListener('scroll', schedule, true);
  function yieldToResearcher(event) {
    if (event.isTrusted === false) return;
    const marker = document.querySelector('#media_review_status [data-media-reopen-ticket]');
    if (marker?.getAttribute('data-media-reopen-ticket') === owner) yielded = owner;
  }
  // Respect intentional scrolling as well as focus movement during source work.
  document.addEventListener('focusin', event => {
    if (event.target === lastFocus) return;
    const marker = document.querySelector('#media_review_status [data-media-reopen-ticket]');
    if (marker?.getAttribute('data-media-reopen-ticket') === owner) yielded = owner;
  });
  document.addEventListener('wheel', yieldToResearcher, {passive:true,capture:true});
  document.addEventListener('touchmove', yieldToResearcher, {passive:true,capture:true});
  window.addEventListener('resize', schedule);
  schedule();
})();
