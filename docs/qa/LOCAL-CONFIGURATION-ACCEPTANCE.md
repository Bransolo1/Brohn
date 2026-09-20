# Saved local installation — 20 September 2026

`scripts/configure-local.ps1` validates the chosen R library, Windows publication
guard/Python and portable-design Python, then saves a bounded, data-only JSON
configuration. Optional named scientific profiles must pass their own existing
doctor checks when supplied. Failed checks never replace a saved installation.
`run-local.ps1` reads that configuration, retains explicit command-line overrides
and offers `-CheckOnly` without opening research storage or starting services.

The actual prepared Windows runtime passed 38 assertions in
`tests/local-configuration.ps1`, including real dependency checks, failed
replacement with an empty library, exact prior-file preservation, relative paths
with spaces/Unicode, unknown schema/profile/field rejection and environment
restoration. The fixture directory is
`C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-configuration-check-6755751991fc4a9faf74faf0e7e0ada1`.

Initial execution exposed a real PowerShell/.NET distinction between restoring
an unset variable and assigning an empty string. Both configuration and launcher
now preserve null using `NullString`; the corrected 38-check run passed. The
additional filename checks reject non-JSON destinations and existing directories
before any readiness or write operation.

This is saved-configuration and readiness evidence on the existing prepared
installation. A fully provisioned clean-machine installer, integrated launch on
that clean machine and physical-device qualification remain separate gates.
