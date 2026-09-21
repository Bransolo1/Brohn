(() => {
  if (window.brohnVisionExplorerInstalled) return;
  window.brohnVisionExplorerInstalled = true;
  let serial = 0;
  const value = (id) => document.getElementById(id)?.value ?? '';
  const fields = () => ({channel:value('vision_channel'), metric:value('vision_metric'), start:value('vision_start'),
    end:value('vision_end'), limit:value('vision_limit'), frame:value('vision_frame_index')});
  const dispatch = (button) => {
    const root = button.closest('#vision-explorer');
    if (!root || !window.Shiny) return;
    let payload;
    try { payload = JSON.parse(button.dataset.visionPayload || '{}'); } catch { return; }
    Shiny.setInputValue('vision_action', {...payload, action:button.dataset.visionAction, source:root.dataset.source,
      epoch:root.dataset.epoch, fields:fields(), serial:++serial}, {priority:'event'});
    if (['apply','open','rebuild'].includes(button.dataset.visionAction)) {
      const hint = document.getElementById('vision-pending-copy');
      if (hint) hint.textContent = '';
    }
  };
  document.addEventListener('click', (event) => {
    const button = event.target.closest?.('[data-vision-action]');
    if (button) { event.preventDefault(); dispatch(button); }
  });
  document.addEventListener('input', (event) => {
    if (!['vision_channel','vision_metric','vision_start','vision_end','vision_limit'].includes(event.target.id)) return;
    const hint = document.getElementById('vision-pending-copy');
    if (hint) hint.textContent = 'View settings changed. Apply them to update the displayed observations and downloads.';
  });
  let observed;
  const resize = new ResizeObserver(entries => {
    const width = Math.max(280, Math.min(900, Math.floor(entries[0].contentRect.width - 32)));
    if (window.Shiny && width > 0) Shiny.setInputValue('vision_width', width);
  });
  const attach = () => {
    const root = document.getElementById('vision-explorer');
    if (root === observed) return;
    if (observed) resize.unobserve(observed);
    observed = root;
    if (root) resize.observe(root);
  };
  new MutationObserver(attach).observe(document.documentElement, {childList:true,subtree:true});
  attach();
})();
