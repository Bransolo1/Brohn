source("R/platform-load.R", encoding = "UTF-8"); brohn_load()
local({
  checks <- 0L
  check <- function(label, value) {if (!isTRUE(value)) stop(paste("Interval QA:", label), call. = FALSE); checks <<- checks+1L}
  rejects <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  parent <- Sys.getenv("BROHN_TEST_EVIDENCE", "../../work/test-runs")
  dir.create(parent, recursive = TRUE, showWarnings = FALSE)
  root <- tempfile("brohn-signal-intervals-", tmpdir = parent); dir.create(root); root <- normalizePath(root, winslash = "/")
  store <- brohn_open_store(file.path(root, "workspace")); brohn_initialise_library(store)
  on.exit(brohn_close_store(store), add = TRUE)
  script <- paste("import importlib.util,json,sys; from pathlib import Path",
    "s=importlib.util.spec_from_file_location('fixture','tests/workers/signal_windows.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)",
    "p=m.Windows();p.root=Path(sys.argv[1]);p.builder=m.fixtures.Preview();p.builder.root=p.root;request=p.request()",
    "(p.root/'source.json').write_text(json.dumps(request),encoding='utf-8')", sep="\n")
  processx::run(brohn_python_profile("eda"), c("-c", script, root), windows_hide_window = TRUE)
  fixture <- brohn_read_json_file(file.path(root,"source.json")); a <- fixture$artifact
  object <- brohn_store_object(store, path = a$path, media_type = "application/x-ndjson")
  report_id <- brohn_id("report")
  report <- brohn_put_entity(store, "report", report_id, list(id = report_id, title = "Independent original interval fixture", origin = "sample",
    analysis = list(artifacts = list(c(list(kind = a$kind), object, a[c("schema","tables","rows","provenance_sha256","complete")])), artifact_verification = fixture$verification_receipt)))
  original_hash <- brohn_hash(report$body)
  run <- function(job, kind) {
    force(job); claimed <- brohn_claim_job(store,"interval-qa",lease_seconds=90)
    stopifnot(identical(claimed$id,job$id)); brohn_process_job(store,claimed,timeout_seconds=90)
    finished <- brohn_get_job(store,job$id)
    if (!identical(finished$status,"succeeded")) stop(brohn_json(finished$error))
    brohn_get_entity(store,kind,finished$result[[if(kind=="signal_view")"signal_view_id"else"signal_windows_id"]])
  }
  catalog <- run(brohn_queue_signal_view(store,report_id,"physiology-series"),"signal_view")
  annotations <- brohn_create_signal_annotations(store,catalog$id,"segment-1","Before and during")
  check("annotation creation pins exact source and project without analysis", annotations$revision == 1L && !length(annotations$body$intervals) &&
    identical(annotations$body$artifact_hash,a$sha256) && identical(annotations$body$report_hash,original_hash))
  check("empty annotations cannot queue summaries", rejects(brohn_queue_signal_windows(store,annotations$id,1L,brohn_hash(annotations$body),list("measure"))))
  check("unavailable table cannot be silently substituted", rejects(brohn_create_signal_annotations(store,catalog$id,"invented","Wrong source")))
  first <- brohn_save_signal_interval(store,annotations$id,1L,"Before","baseline",0,3,"Independent 2,4,6")
  first_id <- first$body$intervals[[1L]]$id
  second <- brohn_save_signal_interval(store,annotations$id,2L,"During","task",3,6,"Independent 8,10,12")
  check("two independent intervals retain half-open boundaries", second$revision == 3L && length(second$body$intervals)==2 &&
    identical(second$body$boundary,"start inclusive, end exclusive"))
  check("stale revision cannot overwrite current intervals", rejects(brohn_save_signal_interval(store,annotations$id,1L,"Lost edit","",0,1)))
  check("reversed or zero-width intervals cannot be saved", rejects(brohn_save_signal_interval(store,annotations$id,3L,"Bad","",5,2)) &&
    rejects(brohn_save_signal_interval(store,annotations$id,3L,"Bad","",2,2)))
  check("unknown measure and forged annotation hash fail before queueing", rejects(brohn_queue_signal_windows(store,annotations$id,3L,brohn_hash(second$body),list("invented"))) &&
    rejects(brohn_queue_signal_windows(store,annotations$id,3L,paste(rep("a",64),collapse=""),list("measure"))))
  job <- brohn_queue_signal_windows(store,annotations$id,3L,brohn_hash(second$body),list("measure"))
  check("identical annotation source and settings reuse the same job", identical(job$id,brohn_queue_signal_windows(store,annotations$id,3L,brohn_hash(second$body),list("measure"))$id))
  saved <- run(job,"signal_windows"); rows <- saved$body$summary$summaries
  check("real R and Python worker gives independent before/during means", identical(vapply(rows,`[[`,numeric(1),"mean"),c(4,10)))
  check("adjacent boundary and sample standard deviations match independent oracle", all(vapply(rows,`[[`,numeric(1),"eligible_rows")==3) &&
    all(vapply(rows,`[[`,numeric(1),"standard_deviation_sample")==2) && rows[[1L]]$last_time_s==2 && rows[[2L]]$first_time_s==3)
  check("summary retains exact clock, source and annotation version", identical(saved$body$annotation_source$hash,brohn_hash(second$body)) &&
    saved$body$annotation_source$revision==3L && identical(saved$body$summary$table$coordinates$source_time_origin,"99999999999999999"))
  check("summary carries recipe and actual worker code identity", all(c("R/platform-signal-annotations.R","scripts/workers/signal_windows.py","scripts/workers/physiology_artifacts.py") %in% names(saved$body$processing$code_hashes)) &&
    identical(saved$body$summary$parameters$interpolation,FALSE))
  check("publication is guarded and produces a preserved complete object", identical(saved$body$result_object$hash,digest::digest(file=brohn_object_path(store,saved$body$result_object$hash),algo="sha256")))
  edited <- brohn_save_signal_interval(store,annotations$id,3L,"Before corrected","baseline",0,2,"Independent 2,4",first_id)
  check("editing creates a revision and keeps original saved intervals accessible", edited$revision==4L &&
    brohn_signal_annotations(store,annotations$id,3L)$body$intervals[[1L]]$end_s==3)
  check("earlier derived summaries remain immutable after interval edit", identical(brohn_hash(brohn_get_entity(store,"signal_windows",saved$id)$body),brohn_hash(saved$body)))
  removed <- brohn_remove_signal_interval(store,annotations$id,4L,first_id)
  check("removal retains recoverable history rather than changing old versions", removed$revision==5L && length(removed$body$intervals)==1 &&
    length(brohn_signal_annotations(store,annotations$id,4L)$body$intervals)==2)
  new_job <- brohn_queue_signal_windows(store,annotations$id,5L,brohn_hash(removed$body),list("measure"))
  claim <- brohn_claim_job(store,"interval-qa",lease_seconds=90); stopifnot(identical(claim$id,new_job$id))
  input <- brohn_signal_windows_input(store,claim); scratch <- file.path(root,"fence"); dir.create(scratch)
  result <- list(report=brohn_analyse_signal_windows(input,scratch),code_identity=list())
  out <- file.path(scratch,"output.json"); brohn_write_json_file(result,out)
  changed <- input; changed$annotation_source$hash <- original_hash
  check("substituted annotation input cannot publish", rejects(brohn_publish_signal_windows(store,result,scratch,claim,changed,out)))
  brohn_cancel_job(store,claim$id)
  check("cancelled parent cannot publish partial or stale summary", rejects(brohn_publish_signal_windows(store,result,scratch,claim,input,out)) &&
    length(brohn_list_entities(store,"signal_windows"))==1L)
  project <- brohn_project(store,"default"); archived <- project$body; archived$archived <- TRUE
  brohn_put_entity(store,"project","default",archived,expected_revision=project$revision)
  check("archived project revokes annotation read/edit access", rejects(brohn_signal_annotations(store,annotations$id)) &&
    rejects(brohn_save_signal_interval(store,annotations$id,5L,"No access","",0,1)))
  brohn_put_entity(store,"project","default",project$body,expected_revision=project$revision+1L)
  check("original report and processed bytes remain unchanged", identical(brohn_hash(brohn_get_entity(store,"report",report_id)$body),original_hash) &&
    identical(digest::digest(file=brohn_object_path(store,a$sha256),algo="sha256"),a$sha256))
  brohn_close_store(store); store <- brohn_open_store(file.path(root,"workspace"))
  check("restart reopens exact annotation history and complete summary", brohn_signal_annotations(store,annotations$id,3L)$revision==3L &&
    brohn_get_entity(store,"signal_windows",saved$id)$body$summary$summaries[[2L]]$mean==10)
  brohn_write_json_file(list(passed=TRUE,checks=checks,root=root,report_id=report_id,annotations_id=annotations$id,summary_id=saved$id),file.path(root,"results.json"))
  cat("Signal annotations:",checks,"checks passed. Evidence:",root,"\n")
})
