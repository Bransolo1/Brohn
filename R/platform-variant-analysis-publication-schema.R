# Source-owned required SQL definitions; see PUBLICATION-EXTRACTIONS.json.
.brohn_vra_publication_schema_admit <- function(pin) {
  required <- c(
    "CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)",
    "CREATE TABLE entities (kind TEXT NOT NULL, id TEXT NOT NULL, project_id TEXT NOT NULL, revision INTEGER NOT NULL CHECK(revision > 0), created_at TEXT NOT NULL, updated_at TEXT NOT NULL, PRIMARY KEY(kind,id))",
    "CREATE TABLE entity_versions (kind TEXT NOT NULL, id TEXT NOT NULL, revision INTEGER NOT NULL CHECK(revision > 0), project_id TEXT NOT NULL, body_json TEXT NOT NULL, body_hash TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, PRIMARY KEY(kind,id,revision), FOREIGN KEY(kind,id) REFERENCES entities(kind,id))",
    "CREATE TABLE jobs (id TEXT PRIMARY KEY, operation TEXT NOT NULL, request_json TEXT NOT NULL, request_hash TEXT NOT NULL, idempotency_key TEXT NOT NULL UNIQUE, status TEXT NOT NULL CHECK(status IN ('queued','running','succeeded','failed','cancelled')), attempt INTEGER NOT NULL DEFAULT 0, worker TEXT, token TEXT, lease_until REAL, result_json TEXT, error_json TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
    "CREATE TABLE audit_log (sequence INTEGER PRIMARY KEY AUTOINCREMENT, occurred_at TEXT NOT NULL, action TEXT NOT NULL, target TEXT NOT NULL, detail_json TEXT NOT NULL)",
    "CREATE TRIGGER versions_no_update BEFORE UPDATE ON entity_versions BEGIN SELECT RAISE(ABORT,'Entity revisions are immutable'); END",
    "CREATE TRIGGER versions_no_delete BEFORE DELETE ON entity_versions BEGIN SELECT RAISE(ABORT,'Entity revisions are immutable'); END",
    "CREATE TRIGGER audit_no_update BEFORE UPDATE ON audit_log BEGIN SELECT RAISE(ABORT,'Audit entries are immutable'); END",
    "CREATE TRIGGER audit_no_delete BEFORE DELETE ON audit_log BEGIN SELECT RAISE(ABORT,'Audit entries are immutable'); END",
    "CREATE TABLE delivery_deployments (id TEXT PRIMARY KEY, study_id TEXT NOT NULL, project_id TEXT NOT NULL, title TEXT NOT NULL, origin TEXT NOT NULL, status TEXT NOT NULL CHECK(status IN ('open','paused','closed')), quota INTEGER NOT NULL, alias_required INTEGER NOT NULL, design_revision INTEGER NOT NULL, design_json TEXT NOT NULL, design_hash TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
    "CREATE TABLE delivery_events (run_id TEXT NOT NULL, sequence INTEGER NOT NULL CHECK(sequence>0), event_id TEXT NOT NULL, event_json TEXT NOT NULL, event_hash TEXT NOT NULL, received_at TEXT NOT NULL, PRIMARY KEY(run_id,sequence), UNIQUE(run_id,event_id), FOREIGN KEY(run_id) REFERENCES delivery_runs(id))",
    "CREATE TRIGGER delivery_pinned_design BEFORE UPDATE OF study_id,project_id,origin,design_revision,design_json,design_hash ON delivery_deployments BEGIN SELECT RAISE(ABORT,'Released designs are immutable'); END",
    "CREATE TRIGGER delivery_pinned_run BEFORE UPDATE OF deployment_id,study_id,origin,client_id,protocol_json,protocol_hash,allocation_index ON delivery_runs BEGIN SELECT RAISE(ABORT,'Run protocols are immutable'); END",
    "CREATE TRIGGER delivery_terminal_run BEFORE UPDATE ON delivery_runs WHEN OLD.completion_status <> 'in_progress' BEGIN SELECT RAISE(ABORT,'Terminal run outcomes are immutable'); END",
    "CREATE TRIGGER delivery_events_no_update BEFORE UPDATE ON delivery_events BEGIN SELECT RAISE(ABORT,'Received events are immutable'); END",
    "CREATE TRIGGER delivery_events_no_delete BEFORE DELETE ON delivery_events BEGIN SELECT RAISE(ABORT,'Received events are immutable'); END"
  )
  for (statement in required) {
    pieces <- strsplit(statement, " ", fixed = TRUE)[[1L]]
    rows <- pin$main[pin$main$type == tolower(pieces[[2L]]) & pin$main$name == pieces[[3L]], , drop = FALSE]
    brohn_require(nrow(rows) == 1L && identical(rows$sql[[1L]], statement),
      "A source-owned variant publication table or immutability trigger changed.")
  }
  invisible(TRUE)
}
