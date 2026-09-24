# Hosted profile scope audit

24 September 2026. Read-only source audit for PC15. **No hosted authentication, deployment or remote recruitment has been qualified by this audit.** The implementation proposal below is separate from existing local behavior. The source review and official tool documentation support preparing a complete local software proof without production tenant credentials.

## Current boundary

| Area | Observed source | Consequence for a remote profile |
| --- | --- | --- |
| Researcher identity | `R/platform-app.R:2` opens the store before any principal check. `R/platform-store.R:123` records actions without authenticated actor identity. | An authenticated edge and an explicit application session context must precede access. |
| Project namespace | `R/platform-library.R:16` checks existence/archive state. `R/platform-store.R:202` reads an entity by ID and `:239` makes project filtering optional. | These checks are not user authorization or tenant isolation. |
| Transport | `scripts/run-brohn.R:16` and `scripts/run-participant.R:26` bind loopback. `R/platform-delivery.R:589` accepts loopback hosts and matching HTTP origins only. | Keep R internal; introduce a separately configured HTTPS edge and exact public origins. Do not loosen the existing guard to arbitrary hosts. |
| Recruitment links | `R/platform-views.R:112` constructs a loopback URL and explicitly describes it as local. | Hosted links must come from validated profile configuration, never request headers. |
| Access capabilities | `R/platform-delivery.R:14` retains separate release/run credentials; starts reserve quota atomically and run uploads require a bearer capability. No expiry/revocation fields were found. | Reuse the existing opaque credentials and receipts; add enrollment and active-upload policies without confusing release closure with session revocation. |
| Data paths | `R/platform-app.R:482` imports a server folder; `:489` accepts a backup destination; `:497` resumes a restored workspace. | A remote researcher must not control arbitrary server paths or restore activation. Enforce this in handlers, not only hidden controls. |
| Health and logs | `R/platform-delivery.R:607` exposes workspace identity in local health. Release secrets occur in URL query/path; run secrets use Authorization. | Internal readiness can remain detailed. Public health and access logs must not expose identifiers or capabilities. |
| Restore | `R/platform-backup.R:268` assigns a new workspace ID, pauses execution, closes releases and rotates both credential families. | Preserve this safe base. Restored workspaces also need explicit rebinding to the hosted profile before access resumes. |
| Native worker publication | `R/platform-jobs.R` explicitly marks POSIX publication as a legacy transactional fallback without the qualified Windows native seal. | The first hosted profile should retain the tested Windows worker path. A Linux container is a separate qualification task. |

The current local boundary is intentional. Merely changing the listening address or putting the app behind HTTPS would leave the other requirements unresolved.

## Smallest complete deployment model

Use one isolated workspace containing one configured project per trusted research team, with all allowed members holding researcher authority. Separate workspace processes, service identities, data directories and edge policies are the initial project-isolation model. Do not advertise a shared multitenant database or role hierarchy. Reject extra project data in this profile and test foreign IDs and paths explicitly. Host administration and other processes with access to the service account remain trusted; loopback alone does not defend against a hostile local administrator.

The researcher origin routes every page, static resource, download and WebSocket upgrade through Caddy and oauth2-proxy before the internal Shiny service. Use established OIDC verification and group allowlisting. Record issuer plus subject as the stable identity; email is display information. Strip untrusted forwarding/identity headers at the edge and accept only the declared internal proxy path. The public participant origin routes only the narrow participant service and uses its existing scoped capabilities. It must never proxy researcher routes.

An authenticated WebSocket upgrade does not imply that an already-open Shiny session is revoked when a cookie expires. Define and exercise a bounded application session lease plus local operator revocation, including closing live sockets. Do not promise immediate propagation of an external identity-provider group change unless that behavior is actually implemented and measured.

Enrollment expiry and revocation must stop new starts and scoped material access according to an explicit policy. Existing admitted participants need a separately defined resume/upload window, with idempotent receipt retries. Revoking an individual run must not rewrite its outcome or erase preserved data. Restore keeps earlier capabilities invalid and processing paused until an operator reviews and rebinds the copy.

Bound body size, request frequency, concurrent uploads, job admission and disk use independently. Existing quotas and worker limits are useful but are not HTTP rate limits. Health/readiness needs actionable internal diagnostics and a minimal public response. Redact capability-bearing paths, queries, authorization and cookies from logs and evidence. Remote folder imports, backups and restore activation require server-side operator or confined-path policy.

## Candidate established components

oauth2-proxy documents OIDC discovery, group restrictions, PKCE S256, secret files, secure cookies, configuration validation and explicit trusted reverse proxies. Its published releases include Windows executables. Pin an exact release and verified vendor checksum during installation rather than relying on a mutable latest URL. [Configuration](https://oauth2-proxy.github.io/oauth2-proxy/configuration/overview/), [official releases](https://github.com/oauth2-proxy/oauth2-proxy/releases).

Caddy provides reverse proxying with WebSocket support and configurable request-header handling. It also supports automatic HTTPS, with distinct trust requirements for a local CA and a public certificate. A local fixture must not silently install trust system-wide. [Reverse proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy), [HTTPS](https://caddyserver.com/docs/automatic-https).

Keycloak publishes a ZIP-based Windows development route with realms, users and OIDC clients. This provides a real local identity-provider fixture without external tenant credentials; its development mode is not a production deployment profile. [Official ZIP quickstart](https://www.keycloak.org/getting-started/getting-started-zip).

These are proposed components, not installed or qualified by this read-only audit. The bounded follow-on implementation can download pinned vendor tooling outside the repository and retain version/hash receipts.

## Connected local acceptance before claiming software support

1. Start the actual edge, OIDC provider, proxy, Shiny app, participant service and supervised worker from a fresh isolated profile. Retain source and binary identities. No fake successful identity headers as the only authentication proof.
2. Anonymous and disallowed users cannot fetch researcher pages, downloads, session URLs or WebSocket upgrades. Allowed users complete actual OIDC login. Missing, forged, oversized or contradictory forwarded identity/origin headers fail closed.
3. Two isolated fixture projects reject cross-project study/report/object/job IDs and server filesystem paths. Restored workspace identity differs and the old profile cannot silently attach to it.
4. Author a control/candidate study, preview it, publish a correctly configured participant link, complete a separate participant browser session, receive automatic analysis, inspect/export results, close collection and reopen history after a real restart.
5. Exercise enrollment expiry, release revocation, admitted-session upload policy, individual revocation, exact receipt retries, quota races and bounded request failures. Expired/revoked state is comprehensible to the participant without changing original receipts.
6. Test authenticated browser logout, expired session, operator revocation and existing WebSocket closure. Measure and document the actual maximum revocation delay; test reconnect and stale download URLs.
7. Test 390px and keyboard flows, screen-reader labels, local TLS settings, redacted logs, unavailable IdP/proxy/worker, disk pressure and safe restore. Keep failed attempts. Do not count generated configuration as executed acceptance.

## Required external deployment inputs

Actual hosting destination and OS/service account; researcher and participant domains/DNS; production TLS/certificate policy and network/firewall rules; OIDC issuer/client registration, secret and allowlisted group policy; persistent storage/ACLs, encrypted backup/retention arrangements and operator alert destination. These remain named inputs even after local software acceptance. No public deployment, messages or real participant recruitment is authorized by this audit itself.

PC15 remains open until the intended profile and its connected acceptance are implemented. Production deployment evidence remains separate from local software proof.
