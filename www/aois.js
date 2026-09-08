(function () {
  let drag = null;
  function coordinates(svg, event) {
    const r = svg.getBoundingClientRect();
    return { x: Number(Math.max(0, Math.min(1, (event.clientX - r.left) / r.width)).toFixed(4)),
             y: Number(Math.max(0, Math.min(1, (event.clientY - r.top) / r.height)).toFixed(4)) };
  }
  function paint(values) {
    const svg = document.getElementById('aoi_canvas');
    const rectangle = document.getElementById('aoi_rectangle');
    if (!svg || !rectangle) return;
    const width = Number(svg.dataset.imageWidth), height = Number(svg.dataset.imageHeight);
    for (const [field, scale] of [['x', width], ['y', height], ['width', width], ['height', height]])
      rectangle.setAttribute(field, Math.max(0, Number(values[field])) * scale);
  }
  document.addEventListener('pointerdown', function (event) {
    const svg = event.target.closest('svg[data-aoi-editor]');
    if (!svg || event.button !== 0) return;
    event.preventDefault(); svg.setPointerCapture(event.pointerId);
    drag = { svg, start: coordinates(svg, event), pointerId: event.pointerId };
    window.aoiHasUnsavedChanges = true;
  });
  document.addEventListener('pointermove', function (event) {
    if (!drag || drag.pointerId !== event.pointerId) return;
    const current = coordinates(drag.svg, event), start = drag.start;
    paint({ x: Math.min(start.x, current.x), y: Math.min(start.y, current.y),
            width: Math.abs(current.x - start.x), height: Math.abs(current.y - start.y) });
  });
  document.addEventListener('pointerup', function (event) {
    if (!drag || drag.pointerId !== event.pointerId) return;
    const end = coordinates(drag.svg, event), start = drag.start;
    const values = { x: Math.min(start.x, end.x), y: Math.min(start.y, end.y),
                     width: Number(Math.abs(end.x - start.x).toFixed(4)), height: Number(Math.abs(end.y - start.y).toFixed(4)) };
    drag = null;
    paint(values);
    // Also set the fields immediately so a rapid Save area sees the drawn values.
    for (const key of ['x', 'y', 'width', 'height']) {
      const input = document.getElementById('aoi_' + key);
      if (input) input.value = String(Number((values[key] * 100).toFixed(2)));
      Shiny.setInputValue('aoi_' + key, values[key] * 100, { priority: 'event' });
    }
    Shiny.setInputValue('aoi_draw', { ...values, nonce: Date.now() }, { priority: 'event' });
  });
  document.addEventListener('pointercancel', function () { drag = null; });
  $(document).on('shiny:connected', function () { Shiny.addCustomMessageHandler('aoi-preview', paint); });
  $(document).on('hidden.bs.modal', function () { drag = null; window.aoiHasUnsavedChanges = false; });
})();
