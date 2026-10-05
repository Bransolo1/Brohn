/* Inactive public-view component. No protocol, transport, storage or authority. */
(function (global) {
  'use strict';
  const finiteTypes = ['rating', 'single_choice', 'dropdown', 'multiple_choice', 'matrix', 'ranking', 'allocation'];
  const types = [...finiteTypes, 'number', 'slider', 'text', 'long_text', 'information'];
  const own = (x, k) => Object.prototype.hasOwnProperty.call(x, k);
  const require = (ok, message) => { if (!ok) throw new TypeError(message); };
  const object = x => x !== null && typeof x === 'object' && !Array.isArray(x) &&
    [Object.prototype, null].includes(Object.getPrototypeOf(x));
  const key = (x, prefix) => typeof x === 'string' && x.length === 68 && new RegExp('^' + prefix + '-[a-f0-9]{64}$').test(x);
  const number = x => typeof x === 'number' && Number.isFinite(x);
  const text = (x, max, empty = false) => typeof x === 'string' && (empty || x.length > 0) && [...x].length <= max;
  function encodingIssue(value) {
    for (let i = 0; i < value.length; i++) {
      const c = value.charCodeAt(i);
      if (c === 0) return 'Text contains an embedded NUL character.';
      if (c >= 0xd800 && c <= 0xdbff) {
        const low = value.charCodeAt(++i);
        if (!(low >= 0xdc00 && low <= 0xdfff)) return 'Invalid Unicode text.';
      } else if (c >= 0xdc00 && c <= 0xdfff) return 'Invalid Unicode text.';
    }
    return null;
  }
  // Inspect descriptors before values: no hidden fields, accessors, sparse arrays,
  // foreign prototypes or cycles are admitted at the public JSON boundary.
  function plain(x, seen = new Set()) {
    if (x === null || typeof x === 'boolean' || number(x)) return;
    if (typeof x === 'string') {
      const issue = encodingIssue(x); require(issue === null, issue);
      return;
    }
    require(object(x) || Array.isArray(x) && Object.getPrototypeOf(x) === Array.prototype, 'Expected a plain JSON value.');
    require(!seen.has(x), 'Cyclic values are unsupported.'); seen.add(x);
    const names = Reflect.ownKeys(x);
    if (Array.isArray(x)) require(names.length === x.length + 1 && names.every((k, i) => i === x.length ? k === 'length' : k === String(i)), 'Expected a dense plain array.');
    for (const k of names) {
      if (Array.isArray(x) && k === 'length') continue;
      const d = Object.getOwnPropertyDescriptor(x, k);
      require(typeof k === 'string' && d.enumerable && own(d, 'value'), 'Hidden or computed JSON fields are unsupported.');
      plain(k, seen); plain(d.value, seen);
    }
    seen.delete(x);
  }
  function fields(x, required, optional = []) {
    require(object(x) && required.every(k => own(x, k)) && Object.keys(x).every(k => required.includes(k) || optional.includes(k)), 'Unsupported public fields.');
  }
  const copy = x => x === null || typeof x !== 'object' ? x : Array.isArray(x) ? x.map(copy) : Object.fromEntries(Object.entries(x).map(([k, v]) => [k, copy(v)]));
  const freeze = x => { if (x !== null && typeof x === 'object') { Object.values(x).forEach(freeze); Object.freeze(x); } return x; };
  const same = (a, b) => {
    if (Object.is(a, b)) return true;
    if (!a || !b || typeof a !== 'object' || typeof b !== 'object' || Array.isArray(a) !== Array.isArray(b)) return false;
    const aa = Object.keys(a), bb = Object.keys(b);
    return aa.length === bb.length && aa.every((k, i) => k === bb[i] && same(a[k], b[k]));
  };
  const scalar = x => x !== null && ['string', 'number', 'boolean'].includes(typeof x);
  const answered = x => x !== null && x !== undefined && (typeof x === 'string' ? x.length > 0 : typeof x === 'object' ? Object.keys(x).length > 0 : true);
  function questionShape(q) {
    plain(q); require(types.includes(q.type), 'Unsupported question profile.');
    const required = ['question_key', 'type', 'prompt', 'required', 'scope', 'rule'];
    if (finiteTypes.includes(q.type)) required.push('options');
    if (q.type === 'matrix') required.push('rows');
    if (['number', 'slider'].includes(q.type)) required.push('min', 'max', 'step');
    if (q.type === 'allocation') required.push('max', 'step');
    fields(q, required, ['illustration']);
    require(key(q.question_key, 'pvq') && text(q.prompt, 12000) && typeof q.required === 'boolean' && ['before', 'after_each', 'end'].includes(q.scope), 'Invalid public question.');
    const keys = [q.question_key];
    for (const [name, field, minimum] of [['options', 'option_key', 2], ['rows', 'row_key', 1]]) {
      if (!own(q, name)) continue;
      require(Array.isArray(q[name]) && q[name].length >= minimum && q[name].length <= 100, 'Invalid question entries.');
      for (const item of q[name]) { fields(item, [field, 'label']); require(key(item[field], 'pvq') && text(item.label, 2000), 'Invalid public entry.'); keys.push(item[field]); }
    }
    require(new Set(keys).size === keys.length, 'Question keys collide.');
    if (own(q, 'max')) require(number(q.max) && number(q.step) && q.step >= 0.000001, 'Invalid question bounds.');
    if (own(q, 'min')) require(number(q.min) && q.min <= q.max, 'Invalid question range.');
    if (own(q, 'illustration')) {
      fields(q.illustration, ['resource_key', 'image_alt']);
      require(key(q.illustration.resource_key, 'pvr') && text(q.illustration.image_alt, 2000), 'Invalid question illustration.');
    }
    ruleShape(q.rule, null);
    return q;
  }
  function ruleShape(rule, questions, depth = 0) {
    if (rule === null) return;
    require(depth < 12, 'Question logic is nested too deeply.');
    fields(rule, ['kind'], ['rules', 'rule', 'question_key', 'result', 'shape', 'keys', 'op', 'value']);
    if (rule.kind === 'all' || rule.kind === 'any') {
      fields(rule, ['kind', 'rules']); require(Array.isArray(rule.rules) && rule.rules.length >= 1 && rule.rules.length <= 20 && rule.rules.every(r => r !== null), 'Invalid compound rule.');
      rule.rules.forEach(r => ruleShape(r, questions, depth + 1)); return;
    }
    if (rule.kind === 'not') { fields(rule, ['kind', 'rule']); require(rule.rule !== null, 'A negated rule cannot be null.'); ruleShape(rule.rule, questions, depth + 1); return; }
    require(key(rule.question_key, 'pvq'), 'Invalid rule question key.');
    const q = questions && questions.get(rule.question_key);
    if (questions) require(q, 'Rule question is outside this scope.');
    if (rule.kind === 'answered') { fields(rule, ['kind', 'question_key']); return; }
    if (rule.kind === 'answered_constant') { fields(rule, ['kind', 'question_key', 'result']); require(typeof rule.result === 'boolean', 'Invalid constant rule.'); return; }
    if (rule.kind === 'token_match') {
      fields(rule, ['kind', 'question_key', 'shape', 'keys']);
      require(['scalar', 'array', 'row_values'].includes(rule.shape) && Array.isArray(rule.keys) && rule.keys.every(k => key(k, 'pvq')) && new Set(rule.keys).size === rule.keys.length, 'Invalid token rule.');
      if (q) {
        require(finiteTypes.includes(q.type) && q.type !== 'allocation', 'Token rule requires a finite-choice profile.');
        const shape = q.type === 'matrix' ? 'row_values' : ['ranking', 'multiple_choice'].includes(q.type) ? 'array' : 'scalar';
        require(shape === rule.shape && rule.keys.every(k => q.options.some(o => o.option_key === k)), 'Rule tokens differ from the question.');
      }
      return;
    }
    require(rule.kind === 'input_compare', 'Unsupported public rule.'); fields(rule, ['kind', 'question_key', 'op', 'value']);
    require(['equals', 'not_equals', 'contains', 'greater', 'less'].includes(rule.op) && scalar(rule.value), 'Invalid input comparison.');
    require(typeof rule.value !== 'string' || text(rule.value, 10000, true), 'Comparison text exceeds the source bound.');
    if (['greater', 'less'].includes(rule.op)) require(number(rule.value), 'Ordered comparisons require a number.');
    if (q) require(['allocation', 'number', 'slider', 'text', 'long_text'].includes(q.type), 'Input comparison differs from the question.');
  }
  // Shape admission deliberately permits incomplete drafts. Final answer validity
  // is checked separately and remains authoritative at the parent/server boundary.
  function answerShape(q, value) {
    plain(value); if (value === null) return;
    const options = (q.options || []).map(o => o.option_key);
    if (['rating', 'single_choice', 'dropdown'].includes(q.type)) require(options.includes(value), 'Unknown answer token.');
    else if (['multiple_choice', 'ranking'].includes(q.type)) require(Array.isArray(value) && value.length <= options.length && value.every(k => options.includes(k)) && new Set(value).size === value.length, 'Invalid answer array.');
    else if (['matrix', 'allocation'].includes(q.type)) {
      const keys = q.type === 'matrix' ? q.rows.map(r => r.row_key) : options;
      require(object(value) && Object.keys(value).every(k => keys.includes(k)), 'Invalid answer object.');
      require(Object.values(value).every(v => v === null || (q.type === 'matrix' ? options.includes(v) : number(v))), 'Invalid answer entry.');
    } else if (['number', 'slider'].includes(q.type)) require(number(value), 'Invalid numeric answer.');
    else if (['text', 'long_text'].includes(q.type)) require(text(value, q.type === 'text' ? 20000 : 200000, true), 'Invalid text answer.');
    else require(false, 'Information has no answer value.');
  }
  function evaluate(rule, scopedAnswers, publicQuestions) {
    plain(rule); plain(scopedAnswers); plain(publicQuestions);
    require(Array.isArray(publicQuestions) && publicQuestions.length <= 200 && object(scopedAnswers), 'Invalid public question scope.');
    const questions = new Map(); const keys = new Set();
    for (const q of publicQuestions) {
      questionShape(q);
      for (const k of [q.question_key, ...(q.options || []).map(o => o.option_key), ...(q.rows || []).map(r => r.row_key)]) { require(!keys.has(k), 'Public question scope repeats a key.'); keys.add(k); }
      questions.set(q.question_key, q);
    }
    for (const [k, value] of Object.entries(scopedAnswers)) { require(questions.has(k), 'Answer is outside this scope.'); answerShape(questions.get(k), value); }
    ruleShape(rule, questions);
    const flatten = x => x === null || x === undefined ? [] : typeof x === 'object' ? Object.values(x).flatMap(flatten) : [x];
    const equal = (a, b) => scalar(a) && scalar(b) && typeof a === typeof b && a === b;
    function visit(r) {
      if (r === null) return true;
      if (r.kind === 'all') return r.rules.every(visit);
      if (r.kind === 'any') return r.rules.some(visit);
      if (r.kind === 'not') return !visit(r.rule);
      const value = scopedAnswers[r.question_key];
      if (r.kind === 'answered') return answered(value);
      if (!answered(value)) return false;
      if (r.kind === 'answered_constant') return r.result;
      if (r.kind === 'token_match') return (r.shape === 'scalar' ? [value] : Object.values(value)).some(x => r.keys.includes(x));
      if (r.op === 'equals') return equal(value, r.value);
      if (r.op === 'not_equals') return !equal(value, r.value);
      if (r.op === 'contains') return flatten(value).some(x => equal(x, r.value));
      return number(value) && number(r.value) && (r.op === 'greater' ? value > r.value : value < r.value);
    }
    return visit(rule);
  }

  function mount({container, stepKey, question, initialDraft = null, onDraft, onComplete, onSubmitIntent, onDiscardSubmitIntent, prepareIllustration, signal}) {
    questionShape(question); answerShape(question, initialDraft);
    require(key(stepKey, 'pvs') && container && container.nodeType === 1 && typeof onDraft === 'function' && typeof onComplete === 'function', 'Invalid question mount.');
    const intentHooks = onSubmitIntent !== undefined || onDiscardSubmitIntent !== undefined;
    require(!intentHooks || typeof onSubmitIntent === 'function' && typeof onDiscardSubmitIntent === 'function', 'Submit intent hooks must be paired.');
    require(!signal || (typeof signal.addEventListener === 'function' && typeof signal.aborted === 'boolean'), 'Invalid abort signal.');
    const doc = container.ownerDocument, q = copy(question), initial = copy(initialDraft), controller = new AbortController();
    if (q.type === 'ranking' && initial !== null) require(initial.length === q.options.length, 'A restored ranking must contain every offered option.');
    if (['text', 'long_text'].includes(q.type) && initial !== null) require(initial.length <= 20000, 'This text draft exceeds the current UI limit.');
    require(!q.illustration || typeof prepareIllustration === 'function', 'Assigned illustration preparation is required.');
    require(!doc.getElementById(stepKey + '-question'), 'This question step is already mounted.');
    let live = true, completing = false, completed = false, revision = 0, savedRevision = 0, invalidEditing = false, controlsEdited = false;
    let latest = {revision: 0, value: copy(initial)}, pending = null, inFlight = null, draftError = null, waiters = [];
    let submitIntent = null, releaseFailure = null;
    let editIssue = null, errorOrigin = null;
    const fatalMessage = 'Your pending submission needs recovery before you can continue.';
    let imageHandle = null, imageReady = !q.illustration, imageError = null, readControls = () => null;
    const listeners = [], controls = [];
    function el(tag, textValue, className) { const n = doc.createElement(tag); if (textValue !== undefined) n.textContent = textValue; if (className) n.className = className; return n; }
    const root = el('section', undefined, 'bvq'); root.id = stepKey + '-question';
    const heading = el('h2', q.prompt); heading.id = stepKey + '-prompt'; heading.tabIndex = -1; root.setAttribute('aria-labelledby', heading.id); root.append(heading);
    root.append(el('p', q.type === 'information' ? 'Information' : q.required ? 'Required' : 'Optional', 'bvq-help'));
    const illustration = el('div', undefined, 'bvq-illustration'); root.append(illustration);
    const form = el('form'); form.noValidate = true; root.append(form);
    const field = el('div', undefined, 'bvq-fields'); form.append(field);
    const error = el('p', undefined, 'bvq-error'); error.id = stepKey + '-error'; error.setAttribute('role', 'alert'); error.tabIndex = -1; error.hidden = true; form.append(error);
    const status = el('p', '', 'bvq-status'); status.setAttribute('role', 'status'); status.setAttribute('aria-live', 'polite'); form.append(status);
    const retry = el('button', 'Retry saving'); retry.type = 'button'; retry.hidden = true; form.append(retry);
    const next = el('button', q.type === 'information' ? 'Continue' : 'Save and continue', 'bvq-primary'); next.type = 'submit'; form.append(next);
    function listen(node, type, callback) { node.addEventListener(type, callback); listeners.push(() => node.removeEventListener(type, callback)); }
    function control(node, boundary = () => false) { controls.push({node, boundary}); node.setAttribute('aria-describedby', error.id); return node; }
    const answerLocked = () => completing || completed || !!releaseFailure || submitIntent?.phase === 'handed_off';
    function primaryLabel() { next.textContent = completed ? 'Completed' : submitIntent?.phase === 'handed_off' ? 'Retry submission' : q.type === 'information' ? 'Continue' : 'Save and continue'; }
    function enabled() { for (const c of controls) c.node.disabled = answerLocked() || c.boundary(); next.disabled = completing || completed || !!releaseFailure; retry.disabled = answerLocked(); primaryLabel(); }
    function showError(message, target = null, {focus = true, origin = null} = {}) {
      if (!live) return; errorOrigin = origin; error.textContent = message; error.hidden = false;
      for (const c of controls) c.node.removeAttribute('aria-invalid');
      if (target) target.setAttribute('aria-invalid', 'true');
      if (focus) (target || error).focus();
      updateStatus();
    }
    function clearError() { errorOrigin = null; error.textContent = ''; error.hidden = true; for (const c of controls) c.node.removeAttribute('aria-invalid'); updateStatus(); }
    function updateStatus() {
      if (!live) return;
      primaryLabel();
      retry.hidden = !draftError;
      const message = releaseFailure ? fatalMessage : submitIntent?.phase === 'handed_off' ? completing ? 'Submitting your answer…' : 'Your answer is waiting for confirmation. Retry submission to confirm this same answer.' : editIssue ? editIssue.message : draftError ? 'Your latest answer has not been saved. Retry saving.' : invalidEditing ? 'Enter a valid number. Your current edit has not been saved.' : completing ? intentHooks ? 'Saving your answer before submitting…' : 'Saving your answer…' : pending || inFlight || savedRevision < revision ? 'Saving changes…' : revision ? 'Changes saved.' : '';
      // The blocking alert is the single error announcement. Do not announce an
      // older save or duplicate recovery wording from the polite live region.
      status.hidden = !error.hidden; status.textContent = status.hidden ? '' : message;
    }
    function discardIntent(reason) {
      const item = submitIntent;
      if (!item || item.phase !== 'captured') return;
      // Transfer the once-only notification before calling trusted parent code:
      // it may reenter destroy/abort or throw while releasing its reservation.
      item.phase = 'discarded'; submitIntent = null;
      try { require(onDiscardSubmitIntent(Object.freeze({submitIntent: item.handle, reason})) === undefined, 'Intent discard must be synchronous and return undefined.'); }
      catch (error) {
        releaseFailure = error || new Error('Intent release failed.');
        if (live) { enabled(); showError(fatalMessage); }
        throw releaseFailure;
      }
    }
    function settleWaiters() {
      if (!live || draftError) { const old = waiters; waiters = []; old.forEach(w => w.reject(draftError || new Error('Question closed.'))); }
      else if (!pending && !inFlight && savedRevision === revision) { const old = waiters; waiters = []; old.forEach(w => w.resolve()); }
    }
    function pump() {
      if (!live || draftError || inFlight || !pending) { settleWaiters(); return; }
      const item = pending; pending = null; inFlight = item; updateStatus();
      // A promise boundary captures synchronous callback throws too. No second
      // callback starts until this one has settled, including after edits.
      Promise.resolve().then(() => {
        if (!live) throw new Error('Question closed.');
        return onDraft({step_key: stepKey, question_key: q.question_key, draft_revision: item.revision, value: copy(item.value)});
      }).then(() => { if (live) savedRevision = item.revision; }, err => {
        if (live) { draftError = err || new Error('Draft save failed.'); if (!editIssue) showError('Your answer could not be saved. Use Retry saving.', null, {focus: false}); }
      }).finally(() => { inFlight = null; if (live) { updateStatus(); if (!draftError) pump(); } settleWaiters(); });
    }
    function capture(value) {
      answerShape(q, value);
      if (same(value, latest.value)) return;
      require(revision < Number.MAX_SAFE_INTEGER, 'Draft revision limit reached.');
      revision++; latest = {revision, value: copy(value)}; pending = latest; updateStatus(); pump();
    }
    function localAnswerIssue(value) {
      const control = ['text', 'long_text'].includes(q.type) ? controls[0]?.node : null;
      if (typeof value === 'string' && encodingIssue(value)) return {message: 'Your answer contains an unsupported character. Remove it before saving.', control};
      // Only the known local domain validator is caught. Parent callbacks and
      // control/programming errors are not relabeled as encoding problems.
      try { answerShape(q, value); }
      catch (problem) {
        if (!(problem instanceof TypeError)) throw problem;
        return {message: 'This answer cannot be saved. Check its format and length.', control};
      }
      return null;
    }
    function changed() {
      if (!live || answerLocked()) return;
      controlsEdited = true;
      // Invalid numeric editing remains in the native control. It is not NaN,
      // zero, or a valid blank draft and must not escape through callbacks.
      invalidEditing = controls.some(c => c.node.validity && c.node.validity.badInput);
      if (invalidEditing) { updateStatus(); return; }
      const value = readControls(); editIssue = localAnswerIssue(value);
      if (editIssue) { showError(editIssue.message, editIssue.control, {focus: false}); return; }
      // A native change after blur may repeat the already captured input value.
      // It does not resolve a failed save, including after a local text correction.
      if (draftError) showError('Your answer could not be saved. Use Retry saving.', null, {focus: false});
      else clearError();
      capture(value);
    }
    function labelledInput(type, id, labelText, parent = field) {
      const box = el('div', undefined, 'bvq-control'), label = el('label', labelText), input = control(el('input'));
      input.type = type; input.id = id; label.htmlFor = id; box.append(label, input); parent.append(box); return input;
    }
    function choices(parent, options, type, name, selected) {
      return options.map(o => {
        const label = el('label', undefined, 'bvq-choice'), input = control(el('input'));
        input.type = type; input.name = name; input.id = name + '-' + o.option_key; input.value = o.option_key; input.checked = selected.includes(o.option_key);
        label.htmlFor = input.id; label.append(input, el('span', o.label)); parent.append(label); return input;
      });
    }
    if (['rating', 'single_choice', 'multiple_choice'].includes(q.type)) {
      const group = el('fieldset'); group.append(el('legend', q.type === 'multiple_choice' ? 'Choose all that apply' : 'Choose one answer')); field.append(group);
      const multiple = q.type === 'multiple_choice', inputs = choices(group, q.options, multiple ? 'checkbox' : 'radio', stepKey + '-' + q.question_key, initial === null ? [] : multiple ? initial : [initial]);
      readControls = () => multiple ? inputs.filter(x => x.checked).map(x => x.value) : (inputs.find(x => x.checked) || {}).value || null;
    } else if (q.type === 'dropdown') {
      const label = el('label', 'Choose one answer'), select = control(el('select')); select.id = stepKey + '-' + q.question_key; label.htmlFor = select.id;
      const empty = el('option', 'Select an option'); empty.value = ''; select.append(empty);
      q.options.forEach(o => { const n = el('option', o.label); n.value = o.option_key; select.append(n); }); select.value = initial || ''; field.append(label, select); readControls = () => select.value || null;
    } else if (['text', 'long_text'].includes(q.type)) {
      const label = el('label', 'Your answer'), input = control(el(q.type === 'long_text' ? 'textarea' : 'input'));
      if (q.type === 'text') input.type = 'text'; else input.rows = 6;
      input.maxLength = 20000; input.id = stepKey + '-' + q.question_key; input.value = initial === null ? '' : initial; label.htmlFor = input.id; field.append(label, input); readControls = () => input.value;
    } else if (['number', 'slider'].includes(q.type)) {
      const input = labelledInput(q.type === 'slider' ? 'range' : 'number', stepKey + '-' + q.question_key, 'Your answer');
      input.min = q.min; input.max = q.max; input.step = q.step; input.value = initial === null ? (q.type === 'slider' ? q.min : '') : initial;
      let touched = initial !== null;
      if (q.type === 'slider') {
        const value = el('output', initial === null ? 'Not confirmed' : String(initial)); value.htmlFor = input.id; field.append(value);
        const confirm = control(el('button', 'Confirm this value')); confirm.type = 'button'; field.append(confirm);
        listen(input, 'input', () => { touched = true; value.textContent = input.value; });
        listen(confirm, 'click', () => { touched = true; value.textContent = input.value; changed(); });
      }
      readControls = () => q.type === 'slider' && !touched || input.value === '' ? null : input.valueAsNumber;
    } else if (q.type === 'matrix') {
      const rows = q.rows.map(row => { const group = el('fieldset'); group.append(el('legend', row.label)); field.append(group); return [row.row_key, choices(group, q.options, 'radio', stepKey + '-' + row.row_key, initial && initial[row.row_key] ? [initial[row.row_key]] : [])]; });
      readControls = () => { const value = Object.fromEntries(rows.map(([k, inputs]) => [k, (inputs.find(x => x.checked) || {}).value || null])); return Object.values(value).some(v => v !== null) ? value : null; };
    } else if (q.type === 'ranking') {
      let order = initial === null ? q.options.map(o => o.option_key) : [...initial], confirmed = initial !== null;
      const list = el('ol', undefined, 'bvq-ranking'); field.append(list);
      const rankStatus = el('p', confirmed ? 'Order confirmed.' : 'Move an answer or confirm this order.', 'bvq-help'); rankStatus.setAttribute('aria-live', 'polite'); field.append(rankStatus);
      const confirm = control(el('button', 'Confirm this order')); confirm.type = 'button'; field.append(confirm);
      function draw(focusKey = null, direction = null) {
        // Remove obsolete controls/listeners through the component's lifetime;
        // each list redraw retains only live buttons in the disabled-state set.
        for (let i = controls.length - 1; i >= 0; i--) if (list.contains(controls[i].node)) controls.splice(i, 1);
        list.replaceChildren();
        order.forEach((k, i) => {
          const label = q.options.find(o => o.option_key === k).label, row = el('li'), name = el('span', label), buttons = el('span', undefined, 'bvq-move'); row.append(name, buttons);
          for (const [d, word] of [[-1, 'up'], [1, 'down']]) {
            const button = control(el('button', 'Move ' + word), () => i + d < 0 || i + d >= order.length); button.type = 'button'; button.dataset.optionKey = k; button.dataset.direction = word; button.setAttribute('aria-label', 'Move ' + label + ' ' + word);
            buttons.append(button);
          }
          list.append(row);
        }); enabled();
        if (focusKey) { const buttons = [...list.querySelectorAll('button')].filter(x => x.dataset.optionKey === focusKey && !x.disabled); (buttons.find(x => x.dataset.direction === direction) || buttons[0] || confirm).focus(); }
      }
      listen(list, 'click', event => {
        const button = event.target.closest('button'); if (!button || !list.contains(button) || answerLocked()) return;
        const k = button.dataset.optionKey, i = order.indexOf(k), word = button.dataset.direction, d = word === 'up' ? -1 : 1;
        if (i < 0 || i + d < 0 || i + d >= order.length) return;
        [order[i], order[i + d]] = [order[i + d], order[i]]; confirmed = true; rankStatus.textContent = 'Order confirmed.'; draw(k, word); changed();
      });
      draw(); listen(confirm, 'click', () => { confirmed = true; rankStatus.textContent = 'Order confirmed.'; changed(); }); readControls = () => confirmed ? [...order] : null;
    } else if (q.type === 'allocation') {
      const inputs = q.options.map(o => { const input = labelledInput('number', stepKey + '-' + o.option_key, o.label); input.min = 0; input.max = q.max; input.step = q.step; input.value = initial && initial[o.option_key] !== null && own(initial, o.option_key) ? initial[o.option_key] : ''; return [o.option_key, input]; });
      const total = el('p', '', 'bvq-total'); total.setAttribute('role', 'status'); field.append(total);
      const update = () => { const values = inputs.map(([, input]) => input.value === '' ? 0 : input.valueAsNumber); total.textContent = values.every(number) ? values.reduce((a, b) => a + b, 0) + ' of ' + q.max + ' allocated.' : 'Enter valid amounts.'; };
      listen(field, 'input', update); update(); readControls = () => { const values = Object.fromEntries(inputs.map(([k, input]) => [k, input.value === '' ? null : input.valueAsNumber])); return Object.values(values).some(v => v !== null) ? values : null; };
    }
    const readRenderedControls = readControls;
    // A sparse restored object is evidence of omitted entries, not a request to
    // insert null keys. The ordinary controls materialize all rows after an edit.
    // Preserve all other nonnull typed drafts too, including untouched -0.
    readControls = () => !controlsEdited && initial !== null ? copy(initial) : readRenderedControls();
    listen(field, 'input', changed); listen(field, 'change', changed);
    function completeValue() {
      if (!live) return {valid: false, message: 'This question is closed.'};
      if (releaseFailure) return {valid: false, message: fatalMessage};
      if (!imageReady) return {valid: false, origin: 'illustration', message: imageError ? 'The question illustration could not be prepared. Retry the illustration.' : 'The question illustration is still loading.'};
      if (q.type === 'information') return {valid: true, value: null};
      const bad = controls.find(c => c.node.validity && !c.node.validity.valid);
      if (bad) return {valid: false, message: bad.node.validationMessage || 'Check this answer.', control: bad.node};
      let value = readControls(); editIssue = localAnswerIssue(value);
      if (editIssue) return {valid: false, ...editIssue};
      const empty = !answered(value) || typeof value === 'string' && !value.trim();
      if (empty) return q.required ? {valid: false, message: 'Please answer this question.', control: controls.find(c => !c.node.disabled)?.node} : {valid: true, value: null};
      if (q.type === 'matrix' && q.required && q.rows.some(r => !own(value, r.row_key) || value[r.row_key] === null)) return {valid: false, message: 'Please answer every row.'};
      if (q.type === 'ranking' && value.length !== q.options.length) return {valid: false, message: 'Confirm a complete order.'};
      if (q.type === 'allocation' && (q.options.some(o => !number(value[o.option_key]) || value[o.option_key] < 0) || Math.abs(Object.values(value).reduce((a, b) => a + b, 0) - q.max) > 1e-7)) return {valid: false, message: 'Enter every amount and allocate exactly ' + q.max + '.'};
      return {valid: true, value: copy(value)};
    }
    listen(retry, 'click', () => {
      if (!live || answerLocked()) return;
      if (invalidEditing) { showError('Enter a valid number before retrying your latest draft.'); return; }
      editIssue = localAnswerIssue(readControls());
      if (editIssue) { showError(editIssue.message, editIssue.control); return; }
      draftError = null; pending = latest; clearError(); updateStatus(); pump();
    });
    listen(form, 'submit', async event => {
      event.preventDefault(); if (!live || completing || completed || releaseFailure) return;
      let item = submitIntent, payload;
      const result = item?.phase === 'handed_off' ? null : completeValue();
      if (result && !result.valid) { showError(result.message, result.control, {origin: result.origin}); return; }
      if (!item && draftError) { showError('Your answer has not been saved. Use Retry saving.'); return; }
      clearError(); completing = true; enabled();
      try {
        if (!item) {
          if (q.type !== 'information') capture(result.value);
          payload = {kind: q.type === 'information' ? 'acknowledge' : 'answer', step_key: stepKey, question_key: q.question_key, draft_revision: revision};
          if (q.type !== 'information') payload.value = copy(result.value);
          if (intentHooks) {
            payload = freeze(payload);
            // Synchronous observation/reservation only. A parent must undo its
            // own reservation if it throws or returns an invalid handle.
            const handle = onSubmitIntent(payload);
            require(handle !== null && typeof handle === 'object' && typeof handle.then !== 'function', 'Submit intent must return a synchronous opaque handle.');
            item = {payload, handle, phase: 'captured'}; submitIntent = item;
            // The capture hook itself may synchronously destroy the component.
            if (!live) { discardIntent('destroy'); return; }
          }
        }
        updateStatus();
        if (!item || item.phase === 'captured') {
          await new Promise((resolve, reject) => { waiters.push({resolve, reject}); pump(); settleWaiters(); });
          if (!live) return;
        }
        if (item) {
          // A synchronous throw may already be an ambiguous parent outcome.
          // Mark handoff before invoking; retries retain this exact snapshot.
          item.phase = 'handed_off';
          updateStatus();
          await onComplete(item.payload, Object.freeze({submitIntent: item.handle}));
        } else await onComplete(payload);
        if (live) { completed = true; status.textContent = q.type === 'information' ? 'Step complete.' : 'Answer complete.'; }
      } catch (_) {
        if (item?.phase === 'captured') { try { discardIntent('draft_failure'); } catch (_) { /* Fatal release state remains visible and cannot retry. */ } }
        if (live) {
          showError(releaseFailure ? fatalMessage : item?.phase === 'handed_off' ? 'Your answer is waiting for confirmation. Retry submission to confirm this same answer.' : draftError ? 'Your answer has not been saved. Use Retry saving.' : 'Your answer could not be submitted. Try again.');
        }
      }
      finally { if (live) { completing = false; enabled(); if (!completed) updateStatus(); } }
    });
    function release(handle) {
      if (!handle) return;
      try { if (handle.image && handle.image.parentNode === illustration) handle.image.remove(); handle.release(); }
      catch (_) { if (live) { imageReady = false; imageError = true; showError('The illustration could not be released. Reopen this question before continuing.'); } }
    }
    function refreshIllustrationError() {
      // Image transitions may replace only the validation they originally raised.
      // A later draft/submit error owns the alert and must remain untouched.
      if (!live || errorOrigin !== 'illustration') return;
      if (draftError) showError('Your answer could not be saved. Use Retry saving.', null, {focus: false});
      else if (imageReady) clearError();
      else showError(imageError ? 'The question illustration could not be prepared. Retry the illustration.' : 'The question illustration is still loading.', null, {focus: false, origin: 'illustration'});
    }
    let preparing = false;
    async function prepareImage() {
      if (!live || preparing) return; preparing = true; imageReady = false; imageError = null;
      illustration.replaceChildren(el('p', 'Loading question illustration…', 'bvq-help')); refreshIllustrationError();
      let handle = null;
      try {
        handle = await prepareIllustration(q.illustration.resource_key, {signal: controller.signal});
        // A returned release function is owned even when the rest is invalid.
        const validRelease = handle && typeof handle.release === 'function';
        if (!live) { if (validRelease) release(handle); return; }
        require(object(handle) && Object.keys(handle).length === 3 && ['resource_key', 'image', 'release'].every(k => own(handle, k)) && validRelease, 'Invalid illustration handle.');
        const image = handle.image;
        require(handle.resource_key === q.illustration.resource_key && image instanceof doc.defaultView.HTMLImageElement && image.ownerDocument === doc && image.parentNode === null && image.complete && image.naturalWidth > 0 && image.naturalHeight > 0 && image.src.startsWith('blob:') && image.currentSrc === image.src && image.srcset === '', 'Illustration is not ready for this question.');
        image.alt = q.illustration.image_alt; imageHandle = handle; handle = null; illustration.replaceChildren(image); imageReady = true;
      } catch (_) {
        if (handle && typeof handle.release === 'function') release(handle);
        if (live) { imageError = true; illustration.replaceChildren(el('p', 'The question illustration could not be loaded.', 'bvq-error')); const again = el('button', 'Retry illustration'); again.type = 'button'; listen(again, 'click', prepareImage); illustration.append(again); }
      } finally { preparing = false; refreshIllustrationError(); }
    }
    function destroy() {
      if (!live) return; live = false;
      try { discardIntent('destroy'); }
      finally {
        controller.abort(); listeners.splice(0).forEach(remove => remove());
        if (signal) signal.removeEventListener('abort', destroy);
        pending = null; settleWaiters(); const handle = imageHandle; imageHandle = null; release(handle); root.remove();
      }
    }
    container.append(root); enabled();
    if (signal) signal.addEventListener('abort', destroy, {once: true});
    if (signal && signal.aborted) destroy(); else if (q.illustration) prepareImage();
    return Object.freeze({readDraft() { require(live, 'Question is closed.'); const value = readControls(); answerShape(q, value); return copy(value); }, validateComplete() { const r = completeValue(); return r.valid ? {valid: true, value: copy(r.value)} : {valid: false, message: r.message}; }, focus() { if (live) heading.focus(); }, destroy});
  }
  require(!own(global, 'BrohnViewQuestion'), 'Question component is already registered.');
  Object.defineProperty(global, 'BrohnViewQuestion', {value: Object.freeze({mount, evaluate}), writable: false, configurable: false});
})(globalThis);
