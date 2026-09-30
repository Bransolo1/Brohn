# Bounded cold service startup

30 September 2026. Windows startup, supervisor and recording-recovery checks
have passed on the joined candidate. Final researcher entry/history checks are
reported separately in the exact-constant EDA acceptance record.

Two actual cold starts failed because the previous acquisition readiness loop
allowed only thirty 100 ms polling sleeps. The child was still starting and its
logs were empty when it was terminated. Separately starting the same original
manager enabled the earlier history test; that workaround did not qualify the
integrated startup path.

Participant and acquisition startup now use an elapsed 15-second deadline with
at most 100 ms between probes. A response arriving after the deadline is refused.
The existing probes still verify the correct workspace and process identity.
An in-flight probe or OS scheduling can delay when the timeout is reported; the
helper never resets its deadline or waits without a bound. Successful timings
and specific failure states are recorded. Errors identify child exit or timeout,
the last readiness result, an available exit code and the owned diagnostic log.

The analysis worker starts after both services are ready. A failed launch first
uses the existing exact-manager stop/flush/archive path, bounded to 20 seconds,
then terminates and waits up to five seconds for each remaining owned child.
Compatible external services are not adopted or stopped. A child dying after a
ready probe must have a freshly verified replacement before its ownership is
released; acquisition also requires a different process ID.

## Executed evidence

| Phase | Checked behavior |
|---|---|
| Focused startup | 27 real-process checks: four-second readiness, early exit, wrong workspace, late response, genuine fresh boot, external service reuse, foreign port protection, stale-probe/death race and worker-launch exception after acquisition readiness. The latter exits the exact manager gracefully with a stop control and exit code zero. No recording was active in that focused fault case. |
| Full runtime on joined03 | The unchanged `tests/platform-runtime.R` passed 74 checks in 94.31 seconds. It covers actual worker recovery, manager failure with an active synthetic recording, the actual Shiny entry point, shutdown/flush/archive and restart. |
| Acquisition ownership on joined03 | The unchanged `tests/platform-acquisition-service.R` passed 22 checks, including exact process stop authorization and real Windows sharing-state refusals. |
| Final joined03 browser | 31 initial and 11 cold saved-result checks include two normal complete startups without a prestarted manager. Exact current/old downloads and saved state survive; see the separate [EDA phase record](EDA-CONSTANT-SIGNAL-ACCEPTANCE.md). |
| Preservation and cleanup | All 1,415 joined source files remained exact. No test-owned processes or listeners remained on the five observed ports. Stores were isolated and user port 3838 was not used. |

The focused fresh boot measured 7.43 seconds overall, including participant and
acquisition waits of 2.46 and 2.42 seconds. These are observed test durations,
not installation-wide performance promises. The full-suite acceptance SHA256 is
`f2bb0abdf82caada8ab71d5281d00033d51ef93e8a6da2b032dca30ce386ef47`;
its evidence manifest is
`0b735ea7686972857c4f65835e3b0cd4c80fe4e0d7c12e637f34fadef524c8cf`.
The exact runtime module SHA256 is
`e7f04de5e7dc50b91c88043dbe9fe8594595178e778ed8dd0882e24e9c474401`.

Independent review found the stale-ready and worker-launch cleanup cases before
the final focused run. Both were corrected and tested. An initial full-suite
runner used a private R environment incompatible with its global fixture
functions; the external runner was corrected without changing the suite or
application. Failed attempts and archived test logs remain retained.

Run from the repository root using the installed, configured native R/Python
environment and publication guard. Replace the placeholders with absolute paths;
the focused output directory must not exist:

```text
Rscript --vanilla tests/runtime-startup-readiness.R REPO FRESH_OUTPUT
Rscript --vanilla tests/platform-runtime.R
Rscript --vanilla tests/platform-acquisition-service.R
```

The latter suites own dynamically selected ports and validated temporary stores.
Do not point them at participant workspaces. Their original cleanup is retained;
the qualification runner archived only their owned temporary trees before that
cleanup. Broader installation, physical-device, recording-load and scientific
qualification remain separate.
