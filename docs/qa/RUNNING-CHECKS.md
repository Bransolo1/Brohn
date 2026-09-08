# Repeatable Brohn checks

Use the exact restored R library described in
[the installation guide](../operations/LOCAL-INSTALLATION.md). From the repository:

```powershell
Rscript --vanilla scripts/run-checks.R --list
Rscript --vanilla scripts/run-checks.R --test core --output C:/Brohn-QA/core-run-001
```

At the 8 September 2026 handoff, **full catalog suites are not a fresh-clone
portability guarantee**. Some `domain` checks reference external methods/gaze
libraries, generated fixtures and `../../work`; scientific and operations
checks can reference the original development Python or TinyCC paths. Inspect
the chosen script and adapt its isolated test configuration before running it.
The core check above is the initial smoke test. `npm run test:browser` exercises
the legacy prototype, not the connected researcher application. Historical
evidence paths outside the repository are recorded local artifacts, not files
included in this source distribution.

The runner checks the selected R installation, runs each registered script in its
own process, and keeps separate output/error logs plus `results.json`. Choose a
new directory outside the source checkout for each run. Without `--output`, a new
system temporary directory is used. A failed or timed-out child fails the selected
suite; it does not become a passing skip. Application code and selected test hashes
are retained; changing either during the run prevents a passing stable-checkout
claim. Tests run sequentially to avoid competing
local service/recording fixtures. Only the child's owned process tree is cleaned up.

`domain` checks core scientific/domain arithmetic, identities, questionnaires and
storage using original fixtures. `scientific` exercises native headers, neural and
EDA processing, vision and saved signal views against prepared profile runtimes.
`interchange` includes real archive and supervised
stream preparation tests. `operations` creates isolated test services and stores;
some operations and interchange checks require the prepared native/Python profiles
and are scoped to the documented Windows runtime. Consult each script and the
installation doctor before selecting those suites. No test selection installs
dependencies or uses a physical participant or device.

This is an explicit initial catalog, not every project test. Native-worker Python
checks and the saved-workspace researcher browser journeys are documented in
[RESEARCHER-QA.md](RESEARCHER-QA.md) and their method specifications. Those browser
journeys have their own fixture/deployment order and must run against the dedicated
QA workspace. They are intentionally not launched against whichever researcher
workspace happens to be open. A green selected suite only claims that named scope;
it does not imply complete product, human usability or live-device qualification.
