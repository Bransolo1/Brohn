# Review two recordings on one timeline

Brohn can place selected original measurements from two recordings on a shared
review timeline. You choose two occurrences recorded by both systems, inspect
the proposed mapping, and save it. Original measurements and their timestamps
remain intact.

## Before you start

Use two preserved multistream imports in the same project. Each needs a recorded
event channel and one or two scalar measurement channels whose declared clock
and epoch match that event channel. The first profile requires matching reviewed
participant and session identities and consistent source origin across both
recordings. Resolve missing or conflicting identities through source curation;
an alignment name or explanation does not establish identity.

Use **linked stream review** when channels already share a supported declared
clock. Use the alignment flow when two independently recorded clocks need an
explicit reviewed relationship. This profile does not span clock resets.

## Create an alignment

1. Open **Data library**, choose the original source recording and expand
   **Align another recording**. Choose the reference recording from its catalog.
   The reference supplies the review coordinate. A single available import is
   selected automatically; import history remains available.
2. Select the recorded event channel and one or two measurement channels on each
   side. Choose **Load recorded events**. Search and page original events when
   necessary; selected rows remain identifiable across overlapping pages.
3. Choose corresponding start and end events. Each option shows the original
   row and timestamp. Repeated labels can refer to different occurrences; Brohn
   does not select a correspondence merely because the text matches.
4. Add independent event checks if you have them, explain why the occurrences
   correspond and confirm your review. Choose **Preview alignment**. Check the
   supported span and any signed check residuals. The defining pair determines
   the map; independent checks do not silently refit it.
5. Name the alignment and choose **Save and review**. Brohn saves a version,
   prepares the full supported original-measurement window and automatically
   prepares its overview. No additional chart-configuration step is needed.

## Read the overview and original rows

All lanes share the displayed review time window. Each signal has its own named
unit and value scale. Similar vertical heights across two lanes do not imply
equal amplitudes. The overview reads the complete selected exports, including
observations beyond the first numerical page. For larger signals it preserves
actual first, minimum, maximum and last observations within display bins.
Separate continuity runs are never joined across original gaps or identity
changes. Connections guide the eye; they are not interpolated measurements.

Recorded events appear as individual marks, or as labelled event counts in time
bins when there are more than 2,000 selected events. Unavailable values and rows
without an original observed time are reported explicitly, without invented
positions. **Numerical overview and exact time labels** provides accessible
counts, original ranges and exact time fractions alongside the chart.

Window start is included and window end is excluded. Bounds use exact decimal
reference-relative seconds. Apply an edited window to prepare its measurements.
Editing bounds immediately disables the previous window's download links.
The numerical table displays 100 rows at a time. At this implementation stage,
changing the table page retains a separately identified window result; its
overview still covers all selected observations. It does not rerun scientific
analysis. Reopening the exact same saved window reuses its saved overview.

The four original exports remain usable while an overview waits, fails or is
cancelled. Retry the overview independently if needed:

- **All selected original rows:** every selected value, original identity and
  timestamp, plus exact review coordinates.
- **All unplaced source rows:** original rows without observed time; they have
  no asserted window membership.
- **Complete segment evidence:** original continuity and gap evidence.
- **Mapping and window evidence:** exact selections, mapping and source binding.

**Complete overview evidence** separately downloads the saved chart artifact,
its reduction counts, exact ranges and original-row references.

## Save, revise and reopen

Use **Saved alignments**, **Alignment versions** and **Saved measurement windows**
to reopen exact historical results. Catalogs provide search and bounded paging.
Reopening checks today's access and the preserved source files. A successful
result can be reopened after its original producer's login has expired, provided
the current reader is authorized.

To change a map, open its source recording and choose **Revise event pairs as a
new version**. Select and preview the revised original events before saving.
The previous map version and its results remain available. Saving the same
unchanged accepted draft twice does not intentionally create another version.

Close alignment when finished. Its session-bound downloads expire when the
view closes; reopening produces fresh links. A restart can reopen saved maps,
windows and plots without repeating their preparation or underlying analyses.

## Meaning and current limits

The named profile is `reviewed-two-event-affine/0.1.0-draft`. It defines a
positive affine relationship inside the two reviewed anchor events. It does not
establish physical synchronization, detection accuracy or a timing error bound;
timing uncertainty remains unknown. Do not interpret zero defining-event
residuals as validation. Scientific methods must explicitly support a qualified
mapping before using it for ERP, event responses or cross-signal inference.

The current flow supports two original recordings, one event channel and one or
two scalar measurement channels per recording. Continuous playback, automatic
event correspondence, reset-spanning maps, resampling and arbitrary channel-count
review remain separate work. The native resource seals in this release are
qualified for the configured Windows installation; wider operating-system and
deployment qualification remains open.
