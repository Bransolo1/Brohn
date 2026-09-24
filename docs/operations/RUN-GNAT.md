# Run a Go/No-Go association study

This guide describes Brohn's named single-target GNAT procedure. Its
[connected researcher acceptance](../qa/GNAT-RESEARCHER-ACCEPTANCE.md) covers
two full administrations, automatic reports, summary reimports, a reviewed
cohort, exact exports and restart. Read that record for the exercised software
scope and the separate physical-timing and scientific-validity limits.

## Design and rehearse

1. Create or open a study. In **Tasks**, choose the Go/No-Go procedure and
   select **Add procedure**.
2. Name the target, distractor context, positive category and negative category.
   Paste 2–64 distinct text exemplars per category, one per line. Replace the
   demonstration words with reviewed materials for your research question.
3. Record the comparison/control rationale, why the distractor context fits,
   material language and provenance/permission. Select **Researcher-supplied
   and reviewed** when appropriate. The language field documents your words;
   participant instructions are currently in English.
4. Add explicit liking or other questionnaires separately when the study needs
   them. Save the design. Templates, cloning and portable design ZIPs preserve
   the task and materials; they do not copy participant results into a new study.
5. Rehearse through a separately marked sample collection using the actual
   participant link. A material thumbnail does not rehearse the timed task.

Participants need a physical keyboard. They press Space when a word belongs to
either named Go category and withhold a response otherwise. Instructions are
self-paced. There are 384 trials: 80 category-training, 64 pairing-practice and
240 test trials. Test deadlines are 750 ms and 600 ms, analysed separately.
Practice runs once without an accuracy pass threshold. These rules belong to
this versioned procedure; the editor does not silently shorten it.

## Collect and inspect

Release the reviewed study from **Collect** and serve its participant link.
Consent, actual frozen assignment, input checks and received completion remain
part of the participant flow. Losing focus, hiding the page, reloading or a
failed durable write interrupts the timed administration; it is not silently
resumed as complete. Earlier received evidence remains available.

A supported completed administration queues an automatic report. The saved
report shows two separate target-positive contrasts and a table of counts,
sensitivity and response criterion for each pairing/deadline. Positive contrast
means greater Go/No-Go sensitivity in the target-positive pairing; Brohn does
not turn it into an individual preference category.

Explore the complete trial evidence or select test trials. Hits, misses, false
alarms and correct rejections remain distinct in the outcome figure. Only an
actual Space response has a response time: successful withholding is neither
zero milliseconds nor a missing observation. Numerical tables and complete
CSV/JSON exports accompany the plots.

## Reuse results without losing their meaning

For a summary reimport, retain both the complete native trial CSV and its frozen
protocol registry JSON. Select the original study/task in the import mapping,
attach that registry and review the matching column assignments and source
definitions. Unknown timing definitions preserve observations but do not
produce eligible scores. A declared summary remains a summary; it cannot
recreate the native keyboard or visibility journal.

For a cohort, review participant/session links and repeat handling before
combining reports. A native report and its imported copy must not become two
people. The two deadlines and all ten named dimensionless metrics retain their
own results. Saved reports, complete source exports and figures reopen from
history without rerunning the original administration.

The [procedure contract](../methods/GNAT-BROHN-PROCEDURE.md) specifies the exact
sampling, endpoint correction and scoring rules. This is a named Brohn
adaptation, with software replay/arithmetic evidence separate from physical
timing, material suitability and population reliability.
