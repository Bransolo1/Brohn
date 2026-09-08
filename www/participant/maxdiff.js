/* Explicit paired best-worst choices. The caller owns consent, the frozen
 * protocol, clocks, durable transport and scientific scoring. */
(() => {
  "use strict";
  let instance = 0;
  const assert = (value, message) => { if (!value) throw new Error(message); };
  const text = (value, maximum) => typeof value === "string" && value.trim().length > 0 && value.length <= maximum;
  const object = value => value && typeof value === "object" && !Array.isArray(value);
  const node = (tag, content, attributes = {}) => {
    const element = document.createElement(tag);
    if (content !== null && content !== undefined) element.textContent = content;
    for (const [name, value] of Object.entries(attributes)) element.setAttribute(name, String(value));
    return element;
  };
  function validatedChoice(value) {
    const keys = ["exercise_id", "design_hash", "set_id", "trial_id", "position", "item_order", "items", "prompt", "best_label", "worst_label", "required"];
    assert(object(value) && keys.every(key => Object.hasOwn(value, key)) && Object.keys(value).every(key => keys.includes(key)), "The saved best-worst choice screen has an unsupported contract.");
    assert([value.exercise_id, value.set_id, value.trial_id].every(id => text(id, 240)) && /^[a-f0-9]{64}$/.test(value.design_hash), "The best-worst choice screen needs its exact saved identities and design hash.");
    assert(Number.isInteger(value.position) && value.position >= 1 && value.position <= 200 && typeof value.required === "boolean", "The saved best-worst position or answer requirement is invalid.");
    assert(text(value.prompt, 4000) && text(value.best_label, 100) && text(value.worst_label, 100) && value.best_label !== value.worst_label, "The best-worst question needs its saved question and distinct choice labels.");
    assert(Array.isArray(value.item_order) && value.item_order.length >= 3 && value.item_order.length <= 8 && value.item_order.every(id => text(id, 96)) && new Set(value.item_order).size === value.item_order.length, "A choice set must contain 3 to 8 distinct saved item identities.");
    assert(Array.isArray(value.items) && value.items.length === value.item_order.length && value.items.every((item, i) => object(item) && Object.keys(item).length === 2 && text(item.label, 1000) && item.id === value.item_order[i]), "The offered item labels must match the exact saved item order.");
    return Object.freeze({...value, item_order: Object.freeze([...value.item_order]), items: Object.freeze(value.items.map(item => Object.freeze({...item})))});
  }
  function validatedDraft(value, ids) {
    if (value === null || value === undefined) return {best_id: null, worst_id: null};
    assert(object(value) && Object.keys(value).length === 2 && ["best_id", "worst_id"].every(key => Object.hasOwn(value, key)), "The saved choice draft has unsupported fields.");
    assert([value.best_id, value.worst_id].every(id => id === null || (typeof id === "string" && ids.includes(id))), "A saved best-worst draft refers to an item outside this exact choice set.");
    assert(value.best_id === null || value.worst_id === null || value.best_id !== value.worst_id, "The saved best and worst cannot be the same item.");
    return {...value};
  }
  function create({container, choice: supplied, draft, onDraft, onSubmit, onError}) {
    assert(container instanceof Element && typeof onDraft === "function" && typeof onSubmit === "function" && typeof onError === "function", "Best-worst choices need a container and the caller's draft, submit and error handlers.");
    const choice = validatedChoice(supplied), uid = `brohn-maxdiff-${++instance}`;
    let value = validatedDraft(draft, choice.item_order), alive = true, pending = false, accepted = false;
    let draftQueue = Promise.resolve(), draftVersion = 0;
    const root = node("section", null, {class: "brohn-maxdiff", "aria-labelledby": `${uid}-question`});
    const heading = node("h1", choice.prompt, {id: `${uid}-question`, tabindex: "-1"});
    const instruction = node("p", `Choose one item for “${choice.best_label}” and a different item for “${choice.worst_label}”.`, {id: `${uid}-instruction`});
    const meta = node("p", `Choice set ${choice.position}. ${choice.required ? "A complete pair is required to continue." : "You may skip this set without choosing a pair."}`, {class: "hint"});
    const form = node("form", null, {"aria-describedby": `${uid}-instruction`});
    const groups = node("div", null, {class: "maxdiff-groups"});
    const controls = [], radio = {best_id: [], worst_id: []};
    const error = node("p", null, {class: "maxdiff-error", role: "alert", id: `${uid}-error`, hidden: ""});
    const status = node("p", null, {class: "hint", role: "status", "aria-live": "polite"});
    const actions = node("div", null, {class: "actions"});
    const submit = node("button", "Continue", {type: "submit", class: "primary"});
    const clear = node("button", "Clear choices", {type: "button"});
    const skip = choice.required ? null : node("button", "Skip this set", {type: "button"});
    const abort = new AbortController();
    function showError(problem) {
      if (!alive) return;
      const actual = problem instanceof Error ? problem : new Error("The choice could not be saved. Try again.");
      error.textContent = actual.message; error.hidden = false; status.textContent = "Choices are still on this screen.";
      try { onError(actual); } catch (_) { /* Error reporting cannot unlock or alter an accepted pair. */ }
    }
    function clearError() {error.hidden = true; error.textContent = "";}
    function render() {
      if (!alive) return;
      for (const key of ["best_id", "worst_id"]) for (const input of radio[key]) {
        input.checked = value[key] === input.value;
        input.disabled = pending || accepted || value[key === "best_id" ? "worst_id" : "best_id"] === input.value;
      }
      submit.disabled = pending || accepted;
      clear.disabled = pending || accepted || (value.best_id === null && value.worst_id === null);
      if (skip) {skip.disabled = pending || accepted; skip.textContent = value.best_id !== null || value.worst_id !== null ? "Clear choices and skip this set" : "Skip this set";}
      root.setAttribute("aria-busy", String(pending));
    }
    function persist() {
      const snapshot = Object.freeze({...value}), version = ++draftVersion;
      // Queue caller-owned writes in order. A later valid draft can supersede
      // a failed earlier write; submission explicitly waits for its own write.
      draftQueue = draftQueue.catch(() => {}).then(() => onDraft({...snapshot}));
      draftQueue.catch(problem => {if (alive && !pending && version === draftVersion) showError(problem);});
      return draftQueue;
    }
    function change(key, id) {
      if (!alive || pending || accepted) return;
      assert(choice.item_order.includes(id) && id !== value[key === "best_id" ? "worst_id" : "best_id"], "Choose different best and worst items.");
      value = {...value, [key]: id}; clearError(); status.textContent = ""; render(); persist();
    }
    async function send(blank = false) {
      if (!alive || pending || accepted) return;
      if (blank) {
        assert(!choice.required, "This set requires a complete pair to continue.");
        value = {best_id: null, worst_id: null};
      } else if (value.best_id === null || value.worst_id === null) {
        error.textContent = "Choose both a best and a different worst item before continuing."; error.hidden = false;
        radio[value.best_id === null ? "best_id" : "worst_id"].find(input => !input.disabled)?.focus();
        return;
      }
      const snapshot = blank ? null : Object.freeze({...value});
      pending = true; clearError(); status.textContent = "Saving your choice…"; render();
      try {
        await persist();
        if (!alive) return;
        await onSubmit(snapshot === null ? null : {...snapshot});
        if (!alive) return;
        accepted = true; status.textContent = "Choice accepted. Continuing…";
      } catch (problem) {showError(problem);}
      finally {pending = false; render();}
    }
    for (const [key, label] of [["best_id", choice.best_label], ["worst_id", choice.worst_label]]) {
      const fieldset = node("fieldset"); fieldset.append(node("legend", label));
      for (const item of choice.items) {
        const wrapper = node("label", null, {class: "choice maxdiff-choice"});
        const input = node("input", null, {type: "radio", name: `${uid}-${key}`, value: item.id, "aria-describedby": `${uid}-instruction`});
        input.addEventListener("change", () => {if (input.checked) change(key, item.id);}, {signal: abort.signal});
        wrapper.append(input, node("span", item.label)); fieldset.append(wrapper); radio[key].push(input); controls.push(input);
      }
      groups.append(fieldset);
    }
    form.addEventListener("submit", event => {event.preventDefault(); void send();}, {signal: abort.signal});
    clear.addEventListener("click", () => {
      if (!alive || pending || accepted) return;
      value = {best_id: null, worst_id: null}; clearError(); status.textContent = "Choices cleared."; render(); persist(); radio.best_id[0].focus();
    }, {signal: abort.signal});
    if (skip) skip.addEventListener("click", () => {void send(true);}, {signal: abort.signal});
    actions.append(submit, clear); if (skip) actions.append(skip);
    form.append(groups, error, status, actions); root.append(heading, instruction, meta, form); container.append(root); render(); heading.focus();
    return Object.freeze({dispose() {if (!alive) return; alive = false; abort.abort(); root.remove();}});
  }
  window.BrohnMaxDiff = Object.freeze({create});
})();
