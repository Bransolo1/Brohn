# Isolated team hosted profile

Bounded local software acceptance completed, 24 September 2026; see the [joined evidence and limitations](../qa/HOSTED-PROFILE-ACCEPTANCE.md). The first profile keeps one default project in one isolated workspace for one trusted researcher team. It does not provide a shared database with tenant ACLs, differentiated researcher roles, or a public production deployment. Follow the [scope audit](../qa/HOSTED-PROFILE-SCOPE-AUDIT.md) and current acceptance receipt before enabling remote recruitment.

## Deployment boundary

```text
researcher HTTPS origin -> Caddy -> oauth2-proxy / established OIDC -> loopback Shiny
participant HTTPS origin -> Caddy -> narrow loopback participant service
                                      |
                         original workspace + supervised native worker
```

Caddy overwrites the internal edge proof and removes client-supplied identity headers. oauth2-proxy verifies the configured issuer/client and group claim, then supplies the subject/group identity. Brohn checks the internal proof, exact origin, group and workspace binding before opening a researcher session. Tokens, cookies and the edge secret do not become research audit identities. The audit actor is the issuer, subject and profile ID.

All Brohn R services remain loopback-only. Service-account permissions and host/network isolation remain essential: loopback and a project name are not an ACL against a hostile process on the same host. Use a separate workspace, process set, service identity, filesystem access and edge policy per team. The profile refuses foreign current or historical project records. Native operator/worker connections remain trusted and do not acquire a fabricated researcher identity.

Authenticated researcher sessions have an absolute application lease of at most one hour, checked before every session HTTP resource dispatch, by commands/store operations/download handlers and by a two-second live-session check. Cached search/file responses and upload bodies are guarded before their handlers execute. The operator revocation file can reject a subject or all sessions established before a timestamp. External identity-provider changes are not claimed to propagate instantly to existing sessions. Sign-out closes the current page connection; other tabs remain subject to the same lease and revocation rules.

## Capability policy

Each newly published hosted release pins its enrollment deadline and material-access deadline in separate operational policy records. Admitted sessions receive their own upload deadline. Original protocols, responses, completion status and receipt history remain unchanged.

- Enrollment expiry prevents a new start. It does not shorten an already admitted upload interval.
- Release revocation stops entry and shared material access. An admitted participant can still upload retained responses until their own deadline; presentations needing revoked materials may no longer continue.
- Individual session revocation stops that session's uploads and server resume. It does not erase received data or claim receipt of browser-local data.
- Expired or revoked upload access stops participant capture, retains browser-local data and explains how to contact the researcher. It does not fabricate a participant ending.
- A restored workspace changes identity, pauses processing, closes releases and rotates access credentials. The old hosted profile is rejected. An operator must explicitly review and rebind the copy.

Remote researchers cannot import arbitrary server folders, select host backup destinations or resume a restored workspace. Those operations require the trusted host operator. Existing quota, request-body, recording and worker bounds remain distinct from HTTP rate limiting and production workload qualification.

## Operator configuration

First prepare the supported native Windows R/Python installation using [local installation](LOCAL-INSTALLATION.md). Prepare Caddy and oauth2-proxy from verified pinned official releases. `scripts/prepare-hosted-tooling.py` downloads the fixture lock outside the checkout, verifies each archive and extracts without modifying PATH, services, firewall or OS certificate trust. Its Keycloak/Temurin entries are for the local OIDC fixture, not a proposed production identity service.

Store the profile and secrets outside the checkout in an operator/service-account protected directory. The profile is JSON with schema `brohn-hosted-profile/1.0` and these exact fields:

| Field | Required value |
| --- | --- |
| `id`, `mode` | Named profile; `isolated_team` for the intended remote profile. `local_oidc_fixture` is an explicitly labelled loopback test exception. |
| `workspace_root`, `workspace_id`, `project_id` | Existing absolute root and actual catalog workspace identity; project is `default`. Do not reuse a source workspace ID after restore. |
| `researcher_origin`, `participant_origin` | Different exact HTTPS origins, with no path, credentials, query, fragment or trailing slash. |
| `issuer` | Exact OIDC issuer. Production mode requires HTTPS. The local fixture permits only its loopback Keycloak realm URL over HTTP. |
| `allowed_groups` | Nonempty array of exact verified group-claim values. Configure the IdP client to issue that claim for `openid profile email`. |
| `edge_secret_file` | Absolute path to exactly 64 lowercase hexadecimal characters from 32 random bytes; no newline. Never print it or commit it. |
| `revocations_file` | Protected JSON `{"schema":"brohn-hosted-revocations/1.0","subjects":[],"not_before":0}`. Subjects belong to this configured issuer; `not_before` is Unix seconds. Replace atomically when updating. |
| `session_seconds` | 30–3,600 seconds. Choose and communicate the intended researcher session interval. |
| `enrollment_seconds` | 30 seconds–30 days, applied when a hosted release is published. |
| `upload_seconds`, `resource_seconds` | 30 seconds–7 days; resources must cover the upload interval. Material expiry is enrollment expiry plus resource interval. |
| `researcher_port`, `participant_port`, `oauth_port` | Three different internal ports from 1,024–65,535. R startup and workspace binding must match the profile. |

The OIDC client secret is a separate vendor-compatible file. The cookie secret is exactly 32 random raw bytes for the pinned proxy. The profile contains paths to secrets, not their contents. Configure the IdP callback as `<researcher_origin>/oauth2/callback`; allow only the intended group, use PKCE S256 and retain issuer/audience/nonce/TLS verification.

Generate new configuration without starting listeners:

```powershell
./scripts/configure-hosted.ps1 -ProfilePath 'C:/Brohn/hosted/profile.json' `
  -OutputDirectory 'C:/Brohn/hosted/config-v1' `
  -RscriptPath 'C:/Program Files/R/R-4.6.1/bin/Rscript.exe' `
  -LibraryPath 'C:/Brohn/local/r-library' -ClientId 'brohn-research' `
  -ClientSecretFile 'C:/Brohn/secrets/oidc-client' `
  -CookieSecretFile 'C:/Brohn/secrets/proxy-cookie'
```

The command validates the profile/workspace and writes `Caddyfile`, `oauth2-proxy.cfg` and a configuration-check receipt. It refuses to overwrite an earlier attempt. This receipt is configuration generation, not deployment acceptance. Before launch run the pinned vendors' `caddy validate --config ...` and `oauth2-proxy --config=... --config-test` with the edge secret supplied through the process environment. Do not print the environment or use a command line containing the secret itself.

Set `BROHN_HOSTED_PROFILE` to the absolute validated JSON path. `run-local.ps1` inherits it and supplies `BROHN_WORKSPACE`, `RESEARCH_PLATFORM_PORT` and `BROHN_PARTICIPANT_PORT` from its matching `-Workspace`, `-Port` and `-ParticipantPort` arguments. Use the same pinned library/publication settings as the local installation. `run-local.ps1` remains the R service supervisor; it does not start the public edge or manage external OIDC. The host operator must supervise Caddy/oauth2-proxy, restrict direct backend access, and arrange failure/restart monitoring. The generated configuration does not silently create system services.

## Local proof and deployment inputs

The actual local fixture uses Caddy2.11.4, oauth2-proxy7.15.4, Keycloak26.7.4 and Temurin25.0.4.1+1 from `tests/fixtures/hosted-oidc/vendor-lock.json`. Two HTTPS localhost origins, a separate loopback development issuer and a test-browser certificate exception exercise software without public DNS or an external tenant. The fixture never installs its local CA system-wide. Its source/binary identities, failed attempts and 12 joined browser assertion groups are retained separately from production evidence. The 31 direct policy, 26 wired handler/storage and 13 actual installed-Shiny dispatcher checks remain distinct evidence layers; five browser axe/overflow scans are clean.

Still required for a real destination: domain/DNS and certificate trust; external IdP registration/group policy; service-account/ACL and firewall configuration; request-rate/concurrency limits; capacity/disk monitoring; encrypted backup/retention policy; operational logs and alert routing. Capability-bearing paths, queries, cookies and authorization must be redacted from logs. The current generated edge does not enable request access logs. A monitoring integration must preserve that boundary.

No public deployment or real-participant collection is established merely by generating this profile or passing a local fixture.
