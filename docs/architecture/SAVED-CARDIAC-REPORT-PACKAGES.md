# Saved cardiac report packages

Development-checkpoint contract, 9 October 2026. Saved ECG/PPG report packaging is implemented and has the scoped native evidence in [QA acceptance](../qa/CARDIAC-EVIDENCE-ACCEPTANCE.md). The complete cardiac researcher-browser and cold-reopen journey remains open. This contract supersedes the implementation-status assumptions in the dated [earlier plan](SAVED-CARDIAC-REPORT-NEXT.md), without changing that historical record.

## Saved findings to a shareable package

The existing **Prepare report** workflow selects supported saved findings, retains the researcher's contents choices, queues missing descriptive views and assembles standalone HTML plus an evidence ZIP. It does not repeat detection, filtering, interpolation, spectral estimation or scientific scoring. Supported cardiac sources can accompany admitted gaze, task, choice, EDA and explicit-response findings.

Admission uses the exact producer, method version, schema, source references and required collections. A modality label is insufficient. Selected child results retain required parent, import/mapping and supported exclusion-review evidence. Required parents need not add duplicate figures. Unknown required collections or unsupported ancestry refuse explicitly.

The cardiac profile is `controlled-gaze-explicit-task-choice-eda-cardiac-paired/0.2`; the new noncardiac profile is `controlled-gaze-explicit-task-choice-eda-paired/0.3`. Their narrowly admitted raw-gaze projection preserves original candidate fields and definitions. It neither redetects fixations nor relabels angular path as endpoint saccade amplitude. Historical profiles and downloaded bytes retain their original contracts.

## Evidence and presentation

Detected ECG RR is not confirmed normal-to-normal HRV. PPG PRV remains distinct. Excluded intervals, unavailable outcomes and their reasons retain their original support. Separate runs and gaps are not pooled into new interval sequences or spectra. No new cardiac-to-liking estimator or emotional/clinical interpretation is introduced.

Display windows, waveform components, chapter choices and optional figures change presentation, not the complete included numerical evidence. Typed artifacts retain the lossless record; declared CSV companions export all included rows. Complete analytical evidence is not an automatic bundle of every original raw recording. Original input files remain separate source downloads.

Preparation saves an intent and uses ordinary queued work. Duplicate requests reuse eligible work; cancellation respects shared ownership and prevents cancelled publication. Failed work and already-attached cancelled attempts retain explicit Retry. History opens the original choices/artifacts; editing makes a draft and preparing makes a new intent. Original artifacts are never silently rewritten.

## Qualification boundaries

Inherited combined19 checks cover actual concurrent public Save/Continue, native preparation, complete saved-reader calls and independent archive conservation. They do not qualify the final cardiac browser journey, physiological accuracy, physical devices or broad workload capacity. A measured saved-history open took **80.342 seconds**; responsiveness remains a defect. The separately tested later reader optimization is not included merely by citing its receipt.

[Researcher guidance](../operations/SHARE-SAVED-CARDIAC-FINDINGS.md) explains sharing. [Current method guidance](../research/METHOD-EVIDENCE-RUNTIME.md) describes screened references; it does not imply automatic citation snapshots in every result.
