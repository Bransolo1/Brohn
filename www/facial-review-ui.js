/* Report actual chart CSS width so compact SVG glyphs remain legible on phones. */
(() => {
  if (window.brohnFacialReviewWidthInstalled) return;
  window.brohnFacialReviewWidthInstalled = true;
  let pending = false, last = null;
  function measure() {
    pending = false;
    const svg = document.querySelector('#facial_plot svg');
    if (!svg || !window.Shiny || !Shiny.setInputValue) return;
    const width = Math.max(280, Math.min(900, Math.floor(svg.getBoundingClientRect().width)));
    if (width !== last) { last = width; Shiny.setInputValue('facial_width', width, {priority:'event'}); }
  }
  function schedule() { if (!pending) { pending = true; requestAnimationFrame(measure); } }
  window.addEventListener('resize', schedule);
  document.addEventListener('shiny:connected', schedule);
  new MutationObserver(schedule).observe(document.documentElement, {childList:true,subtree:true});
  schedule();
})();
