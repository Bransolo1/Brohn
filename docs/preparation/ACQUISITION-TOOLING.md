# Brohn acquisition, interchange and extended neuroscience preparation

Prepared 2026-09-08. **27/27 targeted checks pass** in a new isolated Python 3.12.10
environment. These are runnable synthetic acquisition, numerical and file-format
references. No physical device, camera, participant dataset or paid API was used.
Application dependencies and the existing methods environment were unchanged.

## Installed and exercised

| Package | Pinned version | Actual preparation evidence | Build use |
| --- | --- | --- | --- |
| BrainFlow | 5.22.2 | Synthetic board: samples, finite EEG rows, ordered clock, inserted marker, session release | Selected-device acquisition adapter with a bounded ring buffer |
| pylsl | 1.18.2 | Machine-scope loopback: values, original timestamp, correction API, provenance | Local multimodal transport and explicit clock mapping |
| pyxdf | 1.17.5 | Generated XDF numeric stream: values, timestamps, unit/provenance | XDF importer preserving clock evidence and original file |
| PyArrow | 25.0.1 | Parquet exact int64 values above 2^53, schema/units, null/validity | Immutable typed chunks and cross-language transport |
| DuckDB | 1.5.5 | Parameterized range/aggregate queries; 64 MB, one thread, external access disabled | Bounded review windows and report aggregates |
| MNE / MNE-BIDS / pybv | 1.12.1 / 0.19.0 / 0.8.1 | Synthetic EEG to BIDS/BrainVision and back, including event identity | Neuroscience import/export adapter |
| MNE-Connectivity | 0.9.0 | Coherence = 1 for identical synthetic channels | Named connectivity recipes after montage/reference/QC selection |
| snirf | 0.8.0 | Synthetic SNIRF structure validation; intensity, wavelengths, geometry and units roundtrip | fNIRS file validation/import preparation |
| MNE-NIRS | 0.7.3 | Independent OD arithmetic; Hb conversion smoke; shared-signal short-channel regression; known OLS coefficients | fNIRS preprocessing, nuisance regression and GLM recipes |

The [script](../../scripts/readiness/acquisition-reference.py) creates its own
synthetic artifacts outside the repository. [Aggregate results](acquisition-results.json)
include the script hash, versions, settings, check classifications and limitations.
No method or recorder is enabled in Brohn by this preparation.

BrainFlow supplies a synthetic board specifically for development and a playback
board for recorded streams. Its API exposes channel maps, sample rate, ring-buffer
reads and marker insertion. Playback of a recording is a later adapter check;
this run exercised the synthetic board only. Per-board/preset channel mappings
must remain explicit. A common API does not make all channels share one unit or
one supported sampling configuration. [Supported boards](https://brainflow.readthedocs.io/en/stable/SupportedBoards.html),
[API](https://brainflow.readthedocs.io/en/stable/UserAPI.html).

## Reproduce the preparation

From the repository root, in PowerShell:

```powershell
$acquisitionPython = '../../work/tooling/acquisition-venv/Scripts/python.exe'
& $acquisitionPython -m pip install -r scripts/readiness/requirements-acquisition.txt
& $acquisitionPython -m pip check
& $acquisitionPython scripts/readiness/acquisition-reference.py `
  --work-dir '../../work/tooling/acquisition-venv/reference-data' `
  --output docs/preparation/acquisition-results.json
```

For a fresh machine, create that virtual environment with Python 3.12 before the
commands. The [54-package freeze](../../scripts/readiness/requirements-acquisition.txt)
records the tested resolved versions. `pip check` returned **No broken requirements
found**. The freeze is a version lock, not a wheel-hash lock or a cross-platform
restore qualification. Native Windows wheels/libraries were exercised here.

Installation came from the public PyPI packages and their bundled native libraries;
no separate vendor SDK, model weight or external EEG corpus was downloaded.
The newer `snirf` distribution follows the
current BUNPC installation/import instructions; the obsolete `pysnirf2` 0.7.3
distribution was removed from this isolated environment. MNE-NIRS resolved
scikit-learn 1.8.0 because Nilearn 0.14.1 excludes 1.9.0. Preserve the freeze rather
than independently upgrading these dependencies. [BUNPC package](https://github.com/BUNPC/pysnirf2),
[MNE-NIRS project](https://github.com/mne-tools/mne-nirs).

## Clock and stream contract for the master architecture

The following are Brohn implementation requirements inferred from the transport
APIs and existing timestamp contract:

1. Each stream manifest needs modality, channel labels/types, original units,
   scale/offset, sample representation, nominal/observed rate, adapter/version,
   device/preset identity, source ID, origin, raw-file hash and sequence numbers.
   Keep unit conversion as a separately versioned transform.
2. Store original source timestamps with clock ID, epoch/type, unit, integer or
   floating representation, resolution and wrap/reset segments. Keep receive
   timestamps separately. A local monotonic clock is not UTC; converting seconds
   to integer nanoseconds does not create nanosecond accuracy.
3. Keep the clock-mapping observations: source/master clock IDs, sampled offsets,
   uncertainty/round-trip evidence, drift fit, valid interval, reset boundaries,
   mapping version and processing flags. Preserve raw timestamps before correction
   or dejitter. Never silently synchronize a stream twice.
4. Stimulus presentation, response input, question onset/answer, video frames and
   device markers need their own events linked to protocol/trial/exposure IDs.
   A requested stimulus time and a measured onset time are separate fields.
5. In the collector, freeze the approved stream selection, show readiness, acquire
   bounded chunks, append sequence/checksum records, detect gaps/overflow, flush on
   stop, and release handles. Persist crash/restart boundaries; do not bridge them
   by interpolation. UI disconnection must not silently terminate the local writer.

LSL timestamps originate in a monotonic local clock; its correction API maps clock
domains. XDF importers can apply recorded synchronization evidence after collection.
This probe explicitly used `proc_none`; its XDF fixture disabled synchronization
and dejitter so raw values could be compared exactly. Real clock-offset/reset
fixtures remain a separate importer test. [LSL synchronization](https://labstreaminglayer.readthedocs.io/info/time_synchronization.html),
[XDF format](https://github.com/sccn/xdf/wiki/Specifications).

The loopback used a random source ID and random session, with
`ResolveScope=machine`; it selected only the newly created synthetic outlet.
Initial direct `outlet.get_info()` connection timed out because it lacked the
resolved network address on this platform. Resolving that exact source ID fixed
the connection. General device discovery was not performed. Session IDs help
separate streams but are not authentication. [LSL configuration](https://labstreaminglayer.readthedocs.io/info/lslapicfg.html).

## Columnar boundary and R integration

Use Arrow/Parquet for typed sample chunks; keep method manifests and portable
report metadata in JSON. The fixture preserved `9007199254740993` exactly as an
int64, together with channel `V`, clock `ns`, null value and an independent validity
flag. Large source ticks are decimal strings at the JSON/browser boundary. The
R adapter must preserve integer64 storage or decimal strings; it must never coerce
these ticks through an R double or JavaScript number. R-to-Python-to-R interchange
still needs its own execution check; this probe establishes the Python side.
[Arrow timestamp representation](https://arrow.apache.org/docs/python/timestamps.html),
[Parquet API](https://arrow.apache.org/docs/python/parquet.html).

DuckDB queried an explicitly registered four-row Arrow object with parameterized
time bounds and a row limit. This confirms integer/missingness behaviour, not
throughput. Production jobs need memory/time/output limits, cancellation and an
allowlisted data-path service; UI-supplied SQL/file paths are not the API.
Partition study/session/stream chunks and load only the needed channels/time
windows. [DuckDB Python ingestion](https://www.duckdb.org/docs/current/clients/python/data_ingestion).

## Neuroscience adoption details

The BIDS/BrainVision roundtrip retained 300 samples, 100 Hz, two EEG channels and
the synthetic control event. Maximum voltage error was approximately
`1.72e-13 V`, consistent with the chosen float export. MNE uses volts at this
boundary. External BIDS validation and manufacturer-file fixtures remain to add.
[MNE-BIDS usage](https://mne.tools/mne-bids/stable/use.html),
[pybv writer](https://pybv.readthedocs.io/en/stable/generated/pybv.write_brainvision.html).

Connectivity preparation exercised Fourier coherence across ten synthetic epochs,
8-12 Hz. Recipes must name the estimator and averaging axis, reference/montage,
frequency bands, epochs, edge pairs and statistical unit. Coherence/PLV/wPLI are
different outputs; none should be relabelled causal influence or generic engagement.
[MNE-Connectivity example](https://mne.tools/mne-connectivity/stable/auto_examples/compare_connectivity_over_time_over_trial.html).

fNIRS preparation verified `-log(I / mean(I))`, exercised modified Beer-Lambert
conversion with explicit `ppf=6`, and recovered known OLS coefficients. The PPF
and OLS settings are fixture choices, not universal study defaults. Store wavelengths,
source/detector positions and units, separation, short-channel mapping, motion masks,
intensity QC, pathlength assumptions and HbO/HbR units. Each study recipe must state
the haemodynamic basis, event durations, drift/confound columns, noise model and
contrast. [MNE-NIRS API](https://mne.tools/mne-nirs/stable/api.html).

Source inspection of MNE-NIRS 0.7.3 found that `short_channel_regression` chooses
the nearest short channel by geometry without checking wavelength, and channels
exactly equal to `max_dist` fall into neither distance group. Its synthetic fixture
intentionally used identical short signals. Brohn must use explicit compatible
regressor selection, defined distance boundaries and nonzero/valid regressor checks;
do not expose a blind "automatic correction" wrapper. Joint GLM nuisance regressors
are another supported route. This is an integration decision, not a finding that
short-channel correction is invalid.

## Distribution and remaining build work

Installed metadata identifies PyArrow as Apache-2.0; pyxdf as BSD-2-Clause;
MNE-BIDS/MNE-NIRS as BSD-3-Clause; pylsl/DuckDB as MIT. BrainFlow's installed
license is MIT. `snirf` has conflicting metadata (MIT classifier, GPLv3 license
field); its shipped LICENSE is GPLv3. Record it as GPLv3 pending any maintainer
clarification, and preserve a separate optional dependency declaration.
[SNIRF license](https://github.com/BUNPC/pysnirf2/blob/main/LICENSE),
[BrainFlow license](https://github.com/brainflow-dev/brainflow/blob/master/LICENSE).

The large build can now implement the recorder/import/worker interfaces against
these pinned APIs and examples. Remaining concrete checks are R interoperability,
recording recovery and bounds, real-file import profiles, multi-clock recordings,
external BIDS validation and named live-device configurations. No existing
scientific library has to be rewritten to implement these routes.
