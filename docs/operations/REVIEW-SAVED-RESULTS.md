# Review results and reopen saved views

Open a saved report from its study or dataset. The report starts with **Results**.
The Brohn GNAT view leads with the saved eligible scores and target/deadline
labels. Acoustic reports lead with saved recording measurements, their units
and source context. Unsupported values say **Unavailable**; they are not zero.

Use **Explore** to inspect the supporting plots, original signals or media.
Use **Evidence** for saved-date information, complete numerical downloads,
processing provenance and other supported exports. **Download report** remains
available at the top. **Back to results** returns to the result section without
closing the report or recomputing an analysis. The standalone report keeps its
existing full content.

In a saved media or linked-signal history:

1. Use **Older** and **Newer** to browse pages of 20 saved views. The page summary
   announces the current range and receives keyboard focus after navigation.
2. Use **Show latest** to include later additions and revisions. A page sequence
   otherwise stays on its original snapshot. Entries that are no longer
   accessible can disappear.
3. Open the saved view you need. Its original source, window and exact exports
   remain attached to that view. Media history can still find an earlier track
   inventory when it is older than the first 40 entries.
4. For linked signals, reopening also restores that view's original preserved
   import, selected channels and numerical page. A new import arriving while
   you edit a draft does not discard the draft.

Opening a saved view does not rerun scientific analysis. Current source access
and integrity are checked again, including before downloads. A genuine video
gap remains a gap; Brohn does not substitute a guessed frame.

When source preparation takes time, Brohn shows an opening message before the
full read. That message is brought into view and receives keyboard focus. The
matching result heading receives focus when ready, unless you moved elsewhere
or deliberately scrolled. Media cursor controls are temporarily unavailable
during restoration and usable again after completion or a recoverable failure.
A real later cursor edit still requires opening the newly selected view.

Complete source opening is still being improved. On the latest tested local
corpus, media progress appeared around one second and the result heading around
13–14 seconds; complete task-source preparation took around 8–12 seconds. The
frame image can load separately after its heading and links appear. These are
scoped observations, not general performance guarantees. See the
[responsiveness checkpoint](../qa/PUBLICATION-REVIEW-RESPONSIVENESS-20260925.md)
for the exact source phases and remaining responsiveness work.
