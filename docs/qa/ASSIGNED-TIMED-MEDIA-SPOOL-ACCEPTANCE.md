# Timed-media spool — scoped acceptance, 7 October 2026

The inactive spool successor02 passes **52 Chrome checks across 14 cases and
10 syntax checks** in test-only successor03. Its [source receipt](ASSIGNED-TIMED-MEDIA-SPOOL-SOURCE.json)
records exact implementation, test, result and independent closure identities.
It is included for review, separately from the accepted text/image host.

The tests use real Chrome IndexedDB and Web Locks, the original observation
journal and timed-arm implementation. Media observations, clocks and caller
admission descriptors are explicitly synthetic. There is no actual playback,
R receiver, HTTP capability, physical timing or scientific claim in this phase.

## Checked behavior

- A strict native transaction abort after request success retains the exact
  failed head and blocked follower. Retry preserves original capture order,
  values, JSON documents and hashes; closing does not silently discard them.
- Original media records are durable before the containing journal append.
  The public linkage verifies that original journal entry before marking records
  linked. Cold restart recovers journal-before-link and reserved-but-not-journaled
  boundaries without duplicate adoption.
- Multiple arms, later callbacks, cross-page attachment clocks, signed zero and
  blank native error names retain their original evidence. A linked duplicate ID
  confirms exact stored custody without allocating a new order; conflicting
  duplicates refuse while a subsequent new record remains usable.
- Real competing-owner and version-change behavior, complete-history count and
  record corruption, orphan linked rows and changed original bytes refuse.
  Failed integrity recovery retains the lifetime lock and original records;
  capture, registration, snapshot and drain remain unavailable until recovery.
- Duplicate retries join the same recovery. A controlled pause/rejection of an
  actual journal read tests the recovery gate; it does not fabricate a successful
  journal page or authority response.

Independent comparisons inspect complete original documents and stored bytes,
not merely counters. The closure records 53 exact owned process identities and
the listener closed, with no forced termination, page or cleanup errors and all
bound inputs unchanged.

## Preserved failure and boundary

Test02 failed after comparing primary-key ID order with capture order. The stored
records themselves correctly held head order 1 and follower order 2. Test03 sorts
a copy by the stored order, asserts those explicit positions, and compares full
unchanged documents. Runtime bytes were unchanged; the first failure and its
independent closure remain preserved. Original test01 remains frozen and unrun.

The selected host09 does not import this spool. Joining original renderer
callbacks, uncustodied boundary recovery, authenticated immutable release
capability, actual R receive and complete researcher export is still required.
The R media implementation has separate local software acceptance using synthetic
media; its source is not added by this checkpoint and that evidence is not a
browser/HTTP join.

Use the [timed-sequence architecture](../architecture/ASSIGNED-TIMED-SEQUENCES.md)
and [workstream](../WORKSTREAM.md) for remaining work. Local browser durability
does not promise recovery after user deletion, eviction or device loss. The
implementation remains inactive and the whole platform remains unfinished.
