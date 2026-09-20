source("R/platform-participant-equipment.R") # Registered optional new-draft policy.
# Independent library durability and legacy migration failure-recovery checks.
.libPaths(c(normalizePath("../../work/r-library-brohn", winslash = "/", mustWork = FALSE), .libPaths()))
for (module in c("study", "comparison", "presentation", "records", "json", "storage", "assets", "aois", "drafts",
                 "platform-core", "platform-store", "platform-delivery", "platform-catalog", "platform-library")) source(paste0("R/", module, ".R"))
local({
  directory <- tempfile("brohn-library-storage-"); dir.create(directory)
  cleanup_root <- normalizePath(directory, winslash = "/")
  store <- brohn_open_store(file.path(directory, "workspace"))
  on.exit({
    brohn_close_store(store)
    stopifnot(identical(normalizePath(directory, winslash = "/"), cleanup_root),
      startsWith(cleanup_root, paste0(normalizePath(tempdir(), winslash = "/"), "/")))
    Sys.chmod(list.files(directory, recursive = TRUE, full.names = TRUE, all.files = TRUE), "0666")
    unlink(directory, recursive = TRUE)
  }, add = TRUE)
  count <- 0L
  check <- function(name, value) { if (!isTRUE(value)) stop("FAIL: ", name); count <<- count+1L }
  rejects <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  brohn_initialise_library(store); brohn_initialise_library(store)
  check("default project initialization is idempotent", brohn_get_entity(store, "project", "default")$revision == 1L)
  sample <- brohn_sample_study(store)
  check("sample design stores complete assets and AOI bindings", length(sample$body$stimuli) == 2L &&
    all(vapply(sample$body$stimuli, function(s) !is.null(s$asset) && length(s$aois) == 1L &&
      identical(s$aois[[1]]$asset_hash, s$asset$hash), logical(1))))
  check("attached asset retains actual validated dimensions", sample$body$stimuli[[1]]$asset$width == 800 &&
    sample$body$stimuli[[1]]$asset$height == 600)
  .brohn_delivery_schema(store)
  release <- brohn_publish(store, sample$id)
  check("open release blocks archiving", rejects(brohn_archive_study(store, sample$id)) && !brohn_study(store, sample$id)$body$archived)
  brohn_deployment_state(store, release$id, "closed")
  archived <- brohn_archive_study(store, sample$id)
  check("archive applies only after recruitment closes", archived$body$archived && rejects(brohn_publish(store, sample$id)))
  changed_archive <- archived$body; changed_archive$title <- "Accidental archive overwrite"
  check("archived source rejects ordinary edits", rejects(brohn_save_study(store, changed_archive, archived$revision)) &&
    brohn_study(store, sample$id)$body$title == archived$body$title)
  restored <- brohn_archive_study(store, sample$id, FALSE)
  check("restore does not reopen historical release", !restored$body$archived && brohn_deployment(store, release$id)$status == "closed")
  before_count <- length(brohn_studies(store, archived = NULL))
  DBI::dbExecute(store$con, paste("CREATE TRIGGER fail_sample_save BEFORE INSERT ON entity_versions",
    "WHEN NEW.kind='study' AND NEW.revision=2 BEGIN SELECT RAISE(ABORT,'injected sample failure'); END"))
  check("sample assembly failure surfaces", rejects(brohn_sample_study(store, "Will fail")))
  DBI::dbExecute(store$con, "DROP TRIGGER fail_sample_save")
  check("failed sample leaves no partial study", length(brohn_studies(store, archived = NULL)) == before_count)
  csv <- file.path(directory, "observations.csv")
  writeLines(c("tick,value,quality", "9007199254740993,0,valid", "9007199254740994,,missing"), csv)
  dataset <- brohn_ingest_dataset(store, csv, "Synthetic observations", metadata = list(unit = "uS"), origin = "sample")
  check("dataset import preserves precision and explicit missing text", identical(dataset$body$preview[[1]]$tick, "9007199254740993") &&
    identical(dataset$body$preview[[1]]$value, "0") && identical(dataset$body$preview[[2]]$value, ""))
  check("unmapped dataset is not labelled analysis-ready", identical(dataset$body$status, "needs_mapping") && identical(dataset$body$origin, "sample"))
  failure_csv <- file.path(directory, "failure.csv"); writeLines(c("x,y", "2,3"), failure_csv)
  failure_hash <- digest::digest(file = failure_csv, algo = "sha256")
  DBI::dbExecute(store$con, paste("CREATE TRIGGER fail_dataset_save BEFORE INSERT ON entity_versions",
    "WHEN NEW.kind='dataset' BEGIN SELECT RAISE(ABORT,'injected dataset failure'); END"))
  check("dataset catalog failure surfaces", rejects(brohn_ingest_dataset(store, failure_csv, "Will fail")))
  DBI::dbExecute(store$con, "DROP TRIGGER fail_dataset_save")
  check("failed dataset also rolls back new object registration", length(brohn_list_entities(store, "dataset")) == 1L &&
    inherits(tryCatch(brohn_object_path(store, failure_hash), error = function(e) e), "brohn_store_not_found"))
  legacy <- file.path(directory, "legacy"); dir.create(legacy)
  bundle <- create_draft("sample")
  legacy_path <- file.path(legacy, "original.json")
  save_bundle(bundle, legacy_path)
  dir.create(paste0(legacy_path, ".analyses"))
  writeLines('{"legacy_report":"preserved raw evidence"}', file.path(paste0(legacy_path, ".analyses"), "report.json"))
  original_hash <- digest::digest(file = legacy_path, algo = "sha256")
  DBI::dbExecute(store$con, paste("CREATE TRIGGER fail_migration_marker BEFORE INSERT ON entity_versions",
    "WHEN NEW.kind='migration' BEGIN SELECT RAISE(ABORT,'injected migration failure'); END"))
  failed <- brohn_import_legacy(store, legacy)[[1]]
  DBI::dbExecute(store$con, "DROP TRIGGER fail_migration_marker")
  check("legacy migration failure leaves no untracked clone", failed$status == "failed" &&
    length(brohn_studies(store, archived = NULL)) == before_count && length(brohn_list_entities(store, "migration")) == 0L)
  imported <- brohn_import_legacy(store, legacy)[[1]]
  if (imported$status != "imported") stop(imported$reason)
  check("legacy migration preserves design and historical artifact membership", imported$preserved_artifacts == 2L &&
    length(brohn_study(store, imported$study_id)$body$stimuli[[1]]$aois) == 1L)
  marker <- brohn_get_entity(store, "migration", paste0("legacy-", original_hash))
  draft_artifact <- Filter(function(a) a$type == "draft", marker$body$artifacts)[[1]]
  check("legacy fingerprint identifies the exact retained source bytes", identical(marker$body$source_hash, original_hash) &&
    identical(draft_artifact$object$hash, original_hash) && identical(digest::digest(file =
      brohn_object_path(store, draft_artifact$object$hash), algo = "sha256"), original_hash))
  again <- brohn_import_legacy(store, legacy)[[1]]
  check("legacy migration retries do not clone again", again$status == "already_imported" && identical(again$study_id, imported$study_id))
  check("legacy original remains untouched", identical(digest::digest(file = legacy_path, algo = "sha256"), original_hash))
  cat(sprintf("PASS: %d library durability checks (archive, datasets, sample assembly, exact legacy snapshot, rollback)\n", count))
})
