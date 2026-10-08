/* Report preparation feedback. Durable job ownership remains on the server. */
(() => {
  if (window.brohnReportPackageFeedbackInstalled) return;
  window.brohnReportPackageFeedbackInstalled = true;
  const acknowledged = new Set(), focused = new Set(), completed = new Set();
  let scheduled = false, owner = null, lastFocus = null, yielded = false;
  let contentsRoot = null, contentsNode = null;
  function preserveContents() {
    const root = document.querySelector('#rpk_root');
    if (root !== contentsRoot) { contentsRoot = root; contentsNode = null; }
    if (!root) return;
    const fresh = root.querySelector('#rpk_contents_details');
    if (!fresh || fresh === contentsNode) return;
    // The detached prior node retains the latest deliberate open/close toggle.
    // Only this disclosure survives a render within the same mounted page.
    if (contentsNode) fresh.open = contentsNode.open;
    contentsNode = fresh;
  }
  const remember = (set, value) => { set.add(value); if (set.size > 128) set.delete(set.values().next().value); };
  function reveal(node, block) {
    node.setAttribute('tabindex', '-1'); lastFocus = node;
    node.focus({preventScroll: true});
    node.scrollIntoView({behavior: 'instant', block, inline: 'nearest'});
  }
  function ownsFocus() {
    return !yielded && (document.activeElement === lastFocus || document.activeElement === document.body);
  }
  function fits(node) {
    const r = node.getBoundingClientRect();
    return r.top >= 0 && r.left >= 0 && r.bottom <= window.innerHeight && r.right <= window.innerWidth;
  }
  function current() {
    const node = document.querySelector('#rpk_root #rpk_status');
    if (!node) { owner = null; lastFocus = null; yielded = false; return null; }
    if (document.visibilityState === 'hidden' || !node.getClientRects().length) return null;
    return {node, ticket: node.getAttribute('data-rpk-ticket'), focus: node.getAttribute('data-rpk-focus'),
      phase: node.getAttribute('data-rpk-phase'), passive: node.getAttribute('data-rpk-passive') === 'true'};
  }
  function schedule() {
    preserveContents();
    const initial = current(); if (!initial) return;
    if (initial.phase !== 'preparing') {
      if (initial.focus && initial.focus === owner && !completed.has(owner) && ['ready', 'failed'].includes(initial.phase)) {
        const target = initial.phase === 'failed' ? initial.node :
          Array.from(document.querySelectorAll('[data-rpk-complete]')).find(node => node.getAttribute('data-rpk-complete') === owner);
        if (target && target.getClientRects().length) {
          remember(completed, owner); if (ownsFocus()) reveal(target, initial.phase === 'ready' ? 'start' : 'center');
        }
      }
      return;
    }
    if (!initial.passive && initial.focus && !focused.has(initial.focus)) {
      owner = initial.focus; yielded = false; remember(focused, owner); reveal(initial.node, 'center');
    }
    if (scheduled || !initial.ticket || acknowledged.has(initial.ticket) || (!initial.passive && !fits(initial.node))) return;
    scheduled = true;
    requestAnimationFrame(() => requestAnimationFrame(() => {
      scheduled = false; const fresh = current();
      if (!fresh || fresh.node !== initial.node || fresh.ticket !== initial.ticket || fresh.phase !== 'preparing') { schedule(); return; }
      if ((!fresh.passive && !fits(fresh.node)) || !window.Shiny || !Shiny.setInputValue || acknowledged.has(fresh.ticket)) return;
      remember(acknowledged, fresh.ticket);
      Shiny.setInputValue('rpk_prepare_ack', fresh.ticket, {priority: 'event'});
    }));
  }
  new MutationObserver(schedule).observe(document.documentElement, {childList: true, subtree: true, attributes: true,
    attributeFilter: ['data-rpk-ticket', 'data-rpk-phase', 'data-rpk-focus', 'data-rpk-passive', 'data-rpk-complete', 'class', 'style', 'open']});
  document.addEventListener('focusin', event => { if (owner && lastFocus && event.target !== lastFocus) yielded = true; });
  for (const event of ['wheel', 'touchmove']) document.addEventListener(event, value => { if (owner && value.isTrusted) yielded = true; }, {passive: true});
  document.addEventListener('shiny:connected', schedule);
  document.addEventListener('visibilitychange', schedule);
  document.addEventListener('scroll', schedule, true);
  window.addEventListener('resize', schedule);
  schedule();
})();
