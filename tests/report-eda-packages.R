# Actual source/preparation/publication gate on a copy of generated originals.
# Rscript this-file <checkout> <extended-originals> <fresh-external-evidence> [all|sources|paired|mixed]
args<-commandArgs(TRUE);stopifnot(length(args)%in%c(3L,4L))
repo<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE)
original<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
future_path<-function(x)file.path(normalizePath(dirname(x),winslash="/",mustWork=TRUE),basename(x))
inside<-function(x,parent){if(.Platform$OS.type=="windows"){x<-tolower(x);parent<-tolower(parent)};identical(x,parent)||startsWith(x,paste0(parent,"/"))}
out<-future_path(args[[3L]]);group<-if(length(args)==4L)args[[4L]]else"all"
stopifnot(!file.exists(out),!inside(out,original),!inside(out,repo),group%in%c("all","sources","paired","mixed"))
prior<-jsonlite::fromJSON(file.path(original,"results.json"),simplifyVector=FALSE)
stopifnot(isTRUE(prior$passed),identical(prior$schema,"brohn-eda-extended-original-corpus/0.1"),
 (!file.exists(file.path(original,"workspace","catalog.sqlite-wal"))||file.info(file.path(original,"workspace","catalog.sqlite-wal"))$size==0))
stopifnot(dir.create(out),file.copy(file.path(original,"workspace"),out,recursive=TRUE,copy.mode=TRUE,copy.date=TRUE))
for(name in list.files(original,pattern="-report[.]json$"))stopifnot(file.copy(file.path(original,name),file.path(out,name)),
 identical(digest::digest(file=file.path(original,name),algo="sha256"),digest::digest(file=file.path(out,name),algo="sha256")))
config<-list(checkout=repo,out=out,scenario_group=group,original=original)
jsonlite::write_json(config,file.path(out,"config.json"),auto_unbox=TRUE,pretty=TRUE)
setwd(config$checkout); source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = FALSE)
source("R/platform-report-package-views.R", encoding = "UTF-8")
local({
  out <- config$out; store <- brohn_open_store(file.path(out, "workspace"))
  checks <- list(); packages <- list(); timings <- list(); failure <- NULL; passed <- FALSE
  group <- brohn_default(config$scenario_group, "all"); stopifnot(group %in% c("all", "sources", "paired", "mixed"))
  check <- function(label, value) {
    if (!isTRUE(value)) stop(label, call. = FALSE)
    checks[[length(checks) + 1L]] <<- label; cat("PASS", label, "\n")
  }
  reject <- function(expr) inherits(tryCatch({force(expr); NULL}, error = function(e) e), "error")
  rows <- function(table) if (DBI::dbExistsTable(store$con, table))
    DBI::dbGetQuery(store$con, paste0("SELECT * FROM ", table, " ORDER BY rowid")) else NULL
  before_jobs <- rows("jobs"); before_versions <- rows("entity_versions")
  before_runs <- rows("delivery_runs"); before_events <- rows("delivery_events")
  before_objects <- rows("objects")
  on.exit({
    for (job in brohn_list_jobs(store, limit = 1000L)) if (job$status %in% c("queued", "running")) brohn_cancel_job(store, job$id)
    brohn_write_json_file(list(schema = "brohn-integrated-eda-package-checks/0.1", passed = passed,
      scenario_group = group, checks = checks, failure = failure, packages = packages, timings = timings,
      scope = "Copied genuine synthetic originals. Actual intent, dependency, source-guard, child and package publication APIs. Numerical conservation, scientific qualification, child cancellation, browser and cold restart remain separate gates."), file.path(out, "results.json"))
    brohn_close_store(store)
  }, add = TRUE)
  original <- function(key) brohn_read_json_file(file.path(out, paste0(key, "-report.json")))
  ref <- function(key) .brohn_rpk_ref(original(key))
  process <- function() {
    job <- brohn_claim_job(store, "integrated-eda-package-qa", lease_seconds = 60L)
    stopifnot(!is.null(job), job$operation %in% c("eda_display", "explicit_distributions", "report_package"))
    started <- Sys.time()
    brohn_process_job(store, job, timeout_seconds = 300)
    timings[[length(timings) + 1L]] <<- list(stage = "actual_worker", job_id = job$id, operation = job$operation, seconds = as.numeric(difftime(Sys.time(), started, units = "secs")))
    done <- brohn_get_job(store, job$id)
    if (done$status != "succeeded") stop("Actual ", job$operation, " failed: ", brohn_json(done$error))
    done
  }
  finish <- function(intent) {
    for (attempt in seq_len(10L)) {
      intent <- brohn_continue_report_package_intent(store, intent$intent_ref)
      if (intent$status == "waiting_for_display") {
        pending <- Filter(function(d) d$status %in% c("queued", "running"), intent$dependencies)
        stopifnot(length(pending) > 0L)
        for (dependency in pending) process()
      } else if (intent$status == "assembly_queued") {
        process()
        return(brohn_read_report_package_intent(store, intent$intent_ref$id, intent$request$project_id))
      } else stop("Unexpected preparation state: ", brohn_json(intent))
    }
    stop("Saved preparation did not settle.")
  }
  request <- function(keys) {
    refs <- lapply(keys, ref)
    choices <- lapply(refs, function(r) brohn_report_package_report_choice(store, r))
    list(schema = "brohn-report-package-intent-request/0.1", study_id = original(keys[[1L]])$body$study_id,
      project_id = refs[[1L]]$project_id, title = paste("Complete saved findings", paste(keys, collapse = ", ")),
      report_refs = refs, requested_sections = unname(.brohn_rpv_default_sections(choices)),
      contents_policy = list(profile = "complete-findings/0.1", audience = "research_team", identifier_mode = "package_aliases",
        stimulus_images = "excluded_by_choice", complete_selected_numerical_evidence = TRUE,
        include_original_evidence = FALSE, include_raw_recordings = FALSE),
      limits_profile = "controlled-task-choice-eda-report-package/0.1",
      renderer_profile = "controlled-gaze-explicit-task-choice-eda-paired/0.1", eda_display_requests = list())
  }
  export <- function(key, intent) {
    started <- Sys.time()
    on.exit({timings[[length(timings) + 1L]] <<- list(stage = "open_export_and_current_reader_checks", package = key, seconds = as.numeric(difftime(Sys.time(), started, units = "secs")))}, add = TRUE)
    selection <- brohn_get_entity(store, "report_package_selection", intent$selection_ref$id, intent$selection_ref$revision)$body
    opened <- brohn_open_report_package_resources(store, intent$package_ref, intent$request$project_id)
    on.exit(brohn_release_report_package_resources(opened$handle), add = TRUE)
    current <- brohn_report_package_resources_current(store, opened$handle)
    destination <- file.path(out, key); stopifnot(dir.create(destination))
    producer <- brohn_get_job(store, opened$record$body$processing$job_id)
    sources <- .brohn_rpk_complete_sources(store, opened$handle$source_handle)
    bundle <- c(list(schema = "brohn-report-package-render-input/0.1", selection = selection), sources,
      list(implementation = producer$request$implementation, limits = producer$request$limits))
    brohn_eda_write_json_file(bundle, file.path(destination, "original-source-bundle.json"), maximum = 128 * 1024^2)
    artifact_refs <- list()
    for (kind in names(current$artifacts)) {
      artifact <- current$artifacts[[kind]]
      stopifnot(file.copy(artifact$path, file.path(destination, artifact$file), overwrite = FALSE))
      check(paste(key, kind, "retains published byte identity"),
        identical(digest::digest(file = file.path(destination, artifact$file), algo = "sha256"), artifact$hash))
      artifact_refs[[kind]] <- artifact[c("file", "hash", "bytes")]
    }
    eda <- Filter(function(x) x$adapter == "eda-display", selection$prepared_sources)
    check(paste(key, "retains complete EDA prerequisites"), length(eda) > 0L &&
      !anyDuplicated(vapply(eda, function(x) brohn_hash(x$source_report_ref), character(1))) &&
      all(vapply(eda, function(x) x$implementation_ref$profile == "saved-eda-display/0.1", logical(1))))
    # Fresh current-reader checks must reject revoked producer proof, even for
    # the already-open exact package. Roll back this test-only local mutation.
    display <- brohn_get_entity(store, "eda_display", eda[[1L]]$prepared_ref$id, eda[[1L]]$prepared_ref$revision)
    DBI::dbBegin(store$con)
    tryCatch({
      stopifnot(DBI::dbExecute(store$con, "UPDATE jobs SET status='failed' WHERE id=?", params = list(display$body$producer$job_id)) == 1L)
      check(paste(key, "fresh read refuses revoked EDA producer proof"), reject(brohn_report_package_resources_current(store, opened$handle)))
    }, finally = DBI::dbRollback(store$con))
    check(paste(key, "reopens after exact producer proof restoration"), !is.null(brohn_report_package_resources_current(store, opened$handle)))
    packages[[key]] <<- list(intent_ref = intent$intent_ref, selection_ref = intent$selection_ref,
      package_ref = intent$package_ref, prepared_sources = selection$prepared_sources, artifacts = artifact_refs)
    list(selection = selection, eda = eda, intent = intent)
  }
  run <- function(key, req) {
    count <- nrow(rows("jobs"))
    intent <- brohn_save_report_package_intent(store, paste0("eda-", key), req)
    check(paste(key, "saves before prerequisite work"), intent$status == "prepared" && nrow(rows("jobs")) == count)
    intent <- finish(intent)
    check(paste(key, "complete saved publication succeeds"), intent$status == "succeeded" && intent$next_action == "download")
    export(key, intent)
  }
  tryCatch({
    if (group %in% c("all", "sources")) {
      event <- run("event-default", request("event"))
      unavailable <- run("unavailable-default", request("unavailable"))
      cvxeda <- run("cvxeda-default", request("cvxeda"))
    }
    if (group %in% c("all", "paired")) {
    paired <- run("paired-only", request("paired"))
    check("paired-only has complete related EDA with no automatic EDA figures",
      length(paired$selection$related_eda_refs) == 1L && length(paired$eda) == 1L &&
      .brohn_rpk_same(paired$eda[[1L]]$source_report_ref, ref("controlled")) &&
      !any(vapply(paired$selection$sections, function(s) s$adapter %in% c("eda-events", "eda-continuous"), logical(1))))
    selected <- run("paired-with-parent", request(c("paired", "controlled")))
    check("selected and required parent has one exact EDA prerequisite",
      length(selected$eda) == 1L && length(selected$selection$related_eda_refs) == 0L &&
      .brohn_rpk_same(selected$eda[[1L]]$prepared_ref, paired$eda[[1L]]$prepared_ref))
    }
    if (group %in% c("all", "mixed")) {
    mixed <- run("continuous-liking-default", request(c("continuous", "liking")))
    no_figures <- request(c("continuous", "liking")); no_figures$requested_sections <- list()
    before <- nrow(rows("jobs")); hidden <- run("evidence-only", no_figures)
    check("zero figures retains complete EDA preparation and both original sources", length(hidden$selection$sections) == 0L &&
      nrow(rows("jobs")) == before + 1L && .brohn_rpk_same(hidden$eda, mixed$eda) &&
      .brohn_rpk_same(hidden$selection$report_refs, mixed$selection$report_refs))
    catalog <- brohn_eda_display_catalog(store, mixed$eda[[1L]]$prepared_ref, limit = 25L)
    cell <- Filter(function(x) isTRUE(x$focusable), catalog$items)[[1L]]
    focused_request <- request(c("continuous", "liking"))
    focused_request$eda_display_requests <- list(list(report_ref = ref("continuous"),
      display_request = list(schema = "brohn-eda-display-request/0.1", continuous_windows = list(
        list(key = cell$key, start_s = "10.000000000000000001", end_s = "20.000000000000000001")))))
    before <- nrow(rows("jobs")); focused <- run("continuous-focused", focused_request)
    check("changed exact window adds display and assembly only", nrow(rows("jobs")) == before + 2L &&
      !.brohn_rpk_same(focused$eda[[1L]]$prepared_ref, mixed$eda[[1L]]$prepared_ref))
    figure_request <- focused_request
    figure_request$requested_sections <- lapply(figure_request$requested_sections, function(s) {
      if (s$adapter == "eda-continuous") {s$selector <- list(scope = "exact_cells", keys = list(cell$key)); s$display$components <- list("tonic_us")}
      s
    })
    before <- nrow(rows("jobs")); figure_only <- run("continuous-figure-only", figure_request)
    check("figure-only edit retains exact window and all complete preparation", nrow(rows("jobs")) == before + 1L &&
      .brohn_rpk_same(figure_only$selection$prepared_sources, focused$selection$prepared_sources) &&
      .brohn_rpk_same(figure_only$selection$eda_display_requests, focused$selection$eda_display_requests))
    }
    after <- rows("jobs")
    check("all original jobs remain exact", identical(before_jobs, after[match(before_jobs$id, after$id), , drop = FALSE]))
    check("no new scientific operations ran", all(after$operation[!after$id %in% before_jobs$id] %in% c("eda_display", "explicit_distributions", "report_package")))
    after_versions <- rows("entity_versions")
    keys <- function(x) paste(x$kind, x$id, x$revision, sep = ":")
    check("all original entity versions remain exact", identical(before_versions, after_versions[match(keys(before_versions), keys(after_versions)), , drop = FALSE]))
    check("participant run and journal tables remain exact", identical(before_runs, rows("delivery_runs")) && identical(before_events, rows("delivery_events")))
    check("every original stored object remains exact", all(vapply(before_objects$hash,
      function(hash) identical(digest::digest(file = brohn_object_path(store, hash, FALSE), algo = "sha256"), hash), logical(1))))
    passed <- TRUE
  }, error = function(e) {failure <<- conditionMessage(e); stop(e)})
  cat(length(checks), "integrated EDA package checks passed\n")
})
