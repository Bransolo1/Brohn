# Local service recovery

The connected launcher starts the researcher interface, participant service and
analysis worker against one durable workspace. It checks owned child processes
every two seconds and replaces an unexpectedly exited child. The first replacement
is immediate; failed replacements use increasing delays capped at 60 seconds.
Healthy operation resets the failure count after 30 seconds.

Each runtime and child generation has separate diagnostic logs. Restart events
are appended to a diagnostic JSONL file outside participant observations. The
researcher interface shows a temporary collection or processing notice while the
affected service is unavailable. Stored designs, source files, event receipts and
queued jobs remain in the same workspace.

A compatible participant service already running for this workspace can be reused.
The launcher does not own, terminate or replace that external process. A conflicting
service belonging to another workspace is refused. Stopping this launcher cancels
future restart callbacks and stops only its owned children.

`tests/platform-runtime.R` passes 51 checks using real isolated child processes and
free loopback ports. Evidence includes a killed worker followed by a completed
checked gaze analysis, participant restart with the same workspace identity,
failed-launch backoff, external-service preservation, distinct logs, and an actual
researcher/participant launcher start and normal shutdown. Backoff tests inject
tick times to exercise the 60-second cap without sleeping for a minute.

This detects unexpected process exits. Worker readiness currently means process
liveness; an alive but hung process is not automatically restarted. Recovery of a
job interrupted mid-analysis uses the existing lease expiry and publication fence.
The restart checks do not establish physical device reconnection or uninterrupted
recording during a service failure.
