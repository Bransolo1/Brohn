# Stimulus versions and controls

Use **Add version** to create another editable stimulus in the same study while
keeping the original. This guide describes the focused authoring feature; the
[current release status](../../STATUS.md) records its availability and accepted
checks. Version-set and between-participant assignment remain planned.

## Add a version

1. Open the study's **Plan** and find the source under **Stimuli**. Check its
   current material, viewing duration and areas.
2. Choose **Add version**. Give **Version name** a useful name, such as “Shelf —
   revised price label”. The dialog starts from the current saved Plan, including
   edits captured when it opens.
3. Under **Compare this version as**, keep **A separate condition** or select an
   existing condition. For a separate condition, choose its role below.
4. Choose **Add version** to save the copy. It appears as another stimulus in
   Plan; the original remains. **Cancel** abandons the copy, but does not undo
   earlier Plan edits already saved when the dialog opened.
5. Edit the new stimulus's material, name, duration and areas as needed. Choose
   **Save** after your edits and check the saved revision. Review order and
   planned comparisons before releasing the revised study.

If the study changes while the dialog is open, reopen **Add version** from the
current Plan. A stale dialog cannot overwrite a newer saved revision.

## Choose a condition deliberately

The role describes your intended comparison; it does not create an analysis or
establish that the material is a valid control.

| Choice | Use in the study |
| --- | --- |
| **Test** | Material or manipulation you intend to evaluate. This is the new-condition default, which you can change. |
| **Control** | Your chosen reference for a specified comparison. You can have several control conditions. |
| **Neutral comparator** | A comparator you intend to treat as neutral in this design; the label does not establish physiological neutrality. |
| **Other** | A condition with another stated purpose. Explain that purpose in the research question/design notes. |
| **Existing condition** | Group the version with stimuli already assigned to that condition. No new condition is created. |

The separate-condition default helps avoid accidental pooling. It is not a rule
that every version scientifically requires its own condition. For example,
“Original package” and “Revised package” can have separate conditions when their
difference is the intended comparison. Assigning both to “Test packages” can
combine their exposures in current condition-level gaze summaries.

Under **Decide what the analysis should answer**, choose **Set analysis plan**
or **Edit analysis plan** after adding a version. A new condition or a
Control role does not automatically add a contrast or generate all pairwise
tests. Current paired comparisons require appropriate within-person support;
gaze comparisons match the declared AOI label across the selected conditions.
Use a label for the same intended region only after checking both images.

## Check exposure and order

The ordinary protocol schedules **every listed stimulus once per run**, including
all added versions and controls. Adding a version does not assign A to one group
and B to another. An interrupted or incomplete session is not proof that every
scheduled exposure occurred.

Under **Order and participant flow**, **Fixed** keeps the listed order,
**Counterbalanced rotation** rotates it across allocations, and **Randomized per
allocation** shuffles it. Two-stimulus rotation gives AB/BA across allocations;
it does not create a four-exposure ABBA sequence or guarantee general carryover
balance. Registered task blocks and MaxDiff have their own presentation rules.

A **control stimulus** is material the participant sees. **Baseline before each
stimulus** and the **Fixation cue** are separate timing settings. They do not
start a sensor or prove that a recording contains a usable physiological
baseline. Choose durations for the actual task and method; starter values are
operational defaults. See the [study-control appraisal](../methods/evidence-2026-10-01/study-control/APPRAISAL.md).

## Materials, areas and saved designs

The copy initially retains the exact asset, content, alternative text, duration
and area coordinates. It receives new stimulus and area IDs. Review the copied
areas before using them: attaching a different PNG clears that stimulus's old
areas, while reattaching identical image bytes preserves them. Switching to text
also clears image areas. Define appropriate areas again after replacing an
image. These actions on the copy do not replace the original stimulus's asset.

**Export design** creates a `.brohn-study.zip` containing the supported saved
design and its materials. Use **Import a portable design** on Studies to create
a separate study, with new live identities and retained source lineage. Existing
export/import compatibility checks still apply. This is a design package, not
a participant-data or whole-workspace backup; use the
[backup workflow](BACKUP-AND-RESTORE.md) for that purpose. Existing releases and
participant protocols retain their saved materials; later draft changes require
a new release to reach new collection.

## Evidence and remaining scope

For shelf/packaging comparisons, state which properties you intend to vary and
which context you are holding constant, including position, facings, price and
instructions. Chandon and colleagues studied these design factors in projected
shelf displays; Zuschke's product-choice studies retain distinct order and
starting conditions. Neither supplies a universal preset or validates Brohn's
copying feature. [Chandon et al., 2009](https://doi.org/10.1509/jmkg.73.6.1);
[Zuschke, 2023](https://doi.org/10.1002/bdm.2320). The
[source companion](../research/EYE-TRACKING-FLEXIBILITY-SOURCES.md) records the
selected-text reading depths, shared-data limits and consumer/device transfer.

The [flexibility matrix and queue](../research/EYE-TRACKING-FLEXIBILITY.md)
separate this authoring feature from planned variant sets, one-version-per-person
assignment, mixed allocation, semantic AOI matching and shelf-layout tools.
This guide adds no scientific qualification. It was checked against focused
source `021a3f927bee1f8feb726c1902335fe7430956c19275b993521d44d1c2e69251`;
the source-bound 36 domain/portable and 28 controller checks are distinct from
the actual connected researcher journey recorded in release QA.
