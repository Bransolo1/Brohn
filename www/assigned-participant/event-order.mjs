/* In-memory ordering only. The parent captures observations synchronously and
 * owns durable operation identity, exact bytes, storage and reconciliation. */
export function createParticipantEventOrder() {
  const slots = [], owned = new WeakMap();
  let scheduled = false;
  const require = (ok, message) => { if (!ok) throw new TypeError(message); };
  const locate = ticket => {
    require(ticket !== null && typeof ticket === 'object' && owned.has(ticket), 'Unknown event ordering reservation.');
    return owned.get(ticket);
  };
  const attempt = slot => {
    let resolve, reject;
    const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
    // Failure remains on the original returned promise and blocks the queue.
    // Retain an observer even if the originating component has been destroyed.
    promise.catch(() => {});
    slot.attempt = {promise, resolve, reject};
  };
  const schedule = () => {
    if (scheduled) return;
    scheduled = true;
    queueMicrotask(() => {
      scheduled = false;
      const slot = slots[0];
      if (!slot || slot.phase !== 'ready') return;
      slot.phase = 'writing';
      // Set the phase before invoking parent code, including synchronous throws
      // and reentrant calls. Later observations cannot overtake this operation.
      Promise.resolve().then(() => slot.write()).then(result => {
        slot.phase = 'committed';
        slots.shift();
        slot.attempt.resolve(result);
        schedule();
      }, error => {
        slot.phase = 'failed';
        slot.attempt.reject(error);
        // No automatic retry, cancellation, advancement or later write.
      });
    });
  };
  return Object.freeze({
    reserve() {
      const ticket = Object.freeze(Object.create(null));
      const slot = {phase: 'reserved', write: null, attempt: null};
      owned.set(ticket, slot); slots.push(slot);
      return ticket;
    },
    fill(ticket, write) {
      const slot = locate(ticket);
      require(typeof write === 'function', 'An ordered event needs its original write operation.');
      if (slot.phase !== 'reserved') {
        require(slot.phase !== 'discarded' && slot.write === write, 'A handed-off event cannot be replaced or discarded.');
        return slot.attempt.promise;
      }
      slot.write = write; slot.phase = 'ready'; attempt(slot); schedule();
      return slot.attempt.promise;
    },
    discard(ticket) {
      const slot = locate(ticket);
      require(slot.phase === 'reserved', 'Only an unfilled observation reservation can be discarded.');
      slot.phase = 'discarded';
      slots.splice(slots.indexOf(slot), 1);
      schedule();
    },
    retry(ticket) {
      const slot = locate(ticket);
      require(slot === slots[0] && slot.phase === 'failed', 'Only the blocked original event can be explicitly retried.');
      slot.phase = 'ready'; attempt(slot); schedule();
      return slot.attempt.promise;
    },
    state() {
      return Object.freeze({pending: slots.length,
        reserved: slots.filter(slot => slot.phase === 'reserved').length,
        ready: slots.filter(slot => slot.phase === 'ready').length,
        writing: slots[0]?.phase === 'writing', failed: slots[0]?.phase === 'failed'});
    }
  });
}
