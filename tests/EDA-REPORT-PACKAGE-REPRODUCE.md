# Reproduce the pure EDA report checks

Use the installed R library and the pinned methods Python environment described
in `EDA-DISPLAY-REPRODUCE.md`. Use absolute paths for `REPO` and the evidence
directories below. Every output directory must be fresh and outside the source
checkout. No participant data, stored workspace, model, archive or executable is
included with these tests.

Generate original synthetic scientific results and actual saved preparations
using the separately qualified source tests:

```text
Rscript REPO/tests/eda-display-primitives.R REPO PRIMITIVES
Rscript REPO/tests/eda-display-originals.R REPO ORIGINALS
Rscript REPO/tests/eda-display-workers.R REPO ORIGINALS PREPARED
PYTHON -B REPO/tests/eda-report-python-pure.py REPO PYTHON_CHECKS --r-vectors PRIMITIVES/results.json
PYTHON -B REPO/tests/eda-report-index-lifetime.py REPO ORIGINALS INDEX_CHECKS
Rscript REPO/tests/eda-report-package-pure.R REPO ORIGINALS PREPARED RENDERED
PYTHON -B REPO/tests/verify-eda-report-download.py --bundle RENDERED/original-bundle.json --zip RENDERED/render/report.brohn-report.zip --html RENDERED/render/report.html --output ORACLE
PYTHON -B REPO/tests/eda-report-oracle-refusals.py RENDERED/original-bundle.json RENDERED/render/report.brohn-report.zip NEGATIVE_ORACLE
```

The original and preparation stages create jobs in their own fresh stores. The
Python and pure renderer stages read only their explicit files. They do not open
a study store, run a scientific worker, replay a study or fit an EDA model. Input
generated elsewhere may be used only with its actual original and preparation
provenance retained; a handwritten model is not evidence of native preparation.

The Python checks independently encode scalar typed-hash examples, compare actual
R transport vectors, retain signed zero, refuse unsafe numeric tokens, and check
complete selected counts at the sample, candidate and support-run limits. These
count boundaries use explicitly synthetic rows. They are not a capacity test or
the genuine long-recording recovery fixture.

The index-lifetime test uses the generated original continuous streams. It checks
one exclusive writer per table, complete flush/close before read access, cleanup
after normal completion and cleanup after an injected original-verifier error.
The real filesystem is used. The separate actual worker test is still required
to establish behavior under the native supervisor and its resource monitor.

The pure R test consumes the generator's event and continuous sources and the
worker's exact `*-prepared.json` / `*-evidence.json` outputs. It renders the full
default report, then checks mismatched artifact identity, reordered streams,
duplicate graph nodes and nonexistent numerical pages are refused. Its selection
and graph are external test fixtures, so this establishes pure assembly rather
than store authority. Scientific job/scoring/replay entry points fail fast in
this phase. Keyboard and print rules are checked as markup; this does
not replace actual browser, keyboard or PDF inspection.

The independent Python oracle imports no Brohn code. It compares every original
scientific value, null, type and array position, checks registered alias joins,
verifies every full typed NDJSON row and CSV record, and compares SVG coordinates
and marker membership with the saved display models. It verifies static HTML and
the deterministic ZIP inventory, hashes, CRC and metadata. Supported source
families are saved EDA, questionnaire and paired multimodal findings. This script
does not claim full task/choice adapter coverage; their own independent oracles
remain applicable.

The negative oracle changes copied scientific values, drops a full feature,
coerces a Boolean to a number, adds an unknown field, changes a prepared point,
and replaces a typed source row. Each copy has an independently valid updated
ZIP inventory. All six must still be refused by the scientific/row comparison;
the original bundle, data and archive remain untouched.
When supplied a paired multimodal fixture with distinct people, three additional
cases test merged visit aliases, a wrong parent namespace and a broken reviewed
crosswalk link. They require the separately generated paired-source fixture and
are not claimed by the compact event/continuous originals generator.

For actual worker or browser exports, pass the separately preserved, verified
original source bundle and the **downloaded** ZIP/HTML to the same oracle. Its
`--compare-zip PRIOR_ZIP` option checks complete companion conservation between
figure selections from the same renderer implementation. It allows only
source-equivalent distribution section-ordinal relocation with identical bytes,
roles and multiplicity. Do not use this comparison across a changed renderer.

Whole processed streams remain separate from reduced representative figure
points. Saved raw previews do not constitute a complete raw waveform. No check
here establishes physical synchronization, emotion/construct validity, detector
validity, hosted authorization or whole-platform readiness. In particular,
conserving a saved flatline flag and tiny saved candidates does not establish that
those candidates are physiological responses.

Current-reader revocation, acquisition/curation lineage, related-parent closure,
zero-figure packages, focused-window worker recovery, cancellation and actual
desktop/mobile/A4 output have separate, source-bound integration receipts.
