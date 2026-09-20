# Saved recording intervals

Recipe `saved-signal-intervals/1.0.0` operates on one exact complete processed
physiology time-series table. It preserves recording, channel, person/session and
clock identity. Frequency/event tables use different summaries. The original
scientific report and processed artifact never change.

Researchers name up to64 windows, with optional categories/notes. Bounds use the
saved recording's seconds: start inclusive, end exclusive. Adjacent windows do
not double-count their boundary; overlapping windows deliberately reuse samples.
Editing, removing and restoring an earlier version all create new immutable
annotation revisions. A result pins the exact version, table and full source.

The worker scans complete verified rows. For each selected measure/window it
retains selected, eligible, missing-value and excluded-support counts, first/last
observed eligible coordinates/values, min/max, sample-weighted arithmetic mean
and sample standard deviation (n−1). A mean with zero eligible values and SD
with fewer than two eligible values remain null. Missing coordinates cannot be
assigned to a window. No missing/excluded value becomes zero.

The plot shows means and one sample SD, **not** confidence intervals. The exact
table, full JSON/provenance, spreadsheet-safe CSV and standalone SVG can be
downloaded. The numerical source is never a reduced plot preview. Means are not
time weighted; gaps are not interpolated and sample support does not establish
continuous coverage, synchronization, causality or between-person inference.

This version supports one table per annotation set,1–16 numeric measures,
64 intervals and at most20million source row×measure contributions. Scientific
baseline correction and synchronized multimedia review require their own explicit
methods/alignment. [Interval reuse](SIGNAL-INTERVAL-REUSE.md) separately copies
labels and declared translated boundaries into a fresh source-bound set; this
calculation still reads only that set's target data.

See [executed acceptance](../qa/SIGNAL-INTERVAL-ACCEPTANCE.md).
