# Independent fNIRS conversion checks

20 September 2026. `tests/reference/fnirs_phantom.py` passes seven actual Python
CLI cases: five successful conversions and two deliberate refusals. Evidence is
retained in `C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-fnirs-phantom-04`.
These are original software signals, not recordings from tissue or equipment.

The oracle transcribes the 760/850 nm oxy/deoxyhaemoglobin coefficients directly
from [OMLC's table](https://omlc.org/spectra/hemoglobin/summary.html). It reads
native HDF5 samples independently, calculates segment arithmetic means with
`math.fsum`, takes the logarithmic intensity ratio and solves the two simultaneous
equations by a scalar determinant. It does not call MNE preprocessing, its
absorption loader or a matrix solver for expected values. The source table
defines coefficients in inverse centimetres per molar; the oracle explicitly
converts declared millimetres, partial pathlength factors and micromolar output.

The installed MNE1.12.1 recipe uses the rounded logarithmic conversion2.303.
The oracle declares that same numerical convention. Its factor differs from
exact ln(10) by approximately0.0180%; agreement tests the named recipe rather
than silently asserting exact-log physical calibration. MNE's documented
[Beer-Lambert interface](https://mne.tools/stable/generated/mne.preprocessing.nirs.beer_lambert_law.html)
supports wavelength-specific partial pathlength factors. Package versions and
both Brohn worker hashes are saved in `acceptance.json`.

Successful cases use unequal wavelength factors6/5, doubled source-detector
distance, doubled factors, reversed native channel ordering and ten consecutive
nonpositive source samples. All6,980 complete haemoglobin rows, their optical
density companions, original source indices and times are checked. Channel
identity, rather than positional table ID, determines pairing. The invalid span
splits independent segments; each segment receives its own declared intensity
reference. Mean, sample standard deviation and range features also agree.
Worst absolute haemoglobin difference is1.63e-14 micromolar, below the frozen
1e-10 absolute/relative tolerance. Original SNIRF hashes remain unchanged.
Missing pathlength factors and zero geometry produce explicit errors.

Earlier retained harness failures in runs01-03 were corrected before acceptance:
parameters are nested per recording; native binary64 cadence reconstruction
needs a scale-aware four-epsilon time tolerance; reversed input channels require
identity-based comparison. No production method changed to make these checks
pass. The final time tolerance is6.21e-14 seconds over the70-second fixture.

This establishes bounded conversion arithmetic and source retention. It does
not validate scalp coupling, motion correction, experimental baseline contrasts,
an event GLM, neural interpretation, device calibration or human usability.
`tests/reference/fnirs_saved_review.R` additionally passes **18 checks and eight
actual supervised jobs** over the unequal-factor and invalid-gap cases. Native
SNIRF intake/mapping, automatic feature equality, complete channel/segment
catalogs, saved haemoglobin figures, full selected CSVs and reopen all pass.
The same original hashes and sample origin are preserved. Evidence is in
`C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-fnirs-saved-01`.
The actual researcher browser journey remains separate work.
