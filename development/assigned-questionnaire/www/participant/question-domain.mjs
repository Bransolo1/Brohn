// Exact accepted component09 pure domain body; no DOM/global registration.
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


export {questionShape, ruleShape, answerShape, evaluate};
