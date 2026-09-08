# Actual R supervisor -> Python interchange -> immutable stream catalog journeys.
source("R/platform-load.R");brohn_load(ui=TRUE)
local({
  checks <- 0L
  check <- function(name, ok) {if (!isTRUE(ok)) stop(paste("Interchange QA failed:", name), call. = FALSE); checks <<- checks+1L}
  rejected <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  root <- tempfile("brohn-interchange-qa-"); dir.create(root); root <- normalizePath(root, winslash = "/")
  store <- brohn_open_store(file.path(root, "workspace"))
  on.exit({
    brohn_close_store(store)
    actual <- normalizePath(root, winslash = "/", mustWork = FALSE)
    stopifnot(startsWith(tolower(actual), paste0(tolower(normalizePath(tempdir(), winslash = "/")), "/")), grepl("^brohn-interchange-qa-", basename(actual)))
    unlink(actual, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  brohn_initialise_library(store)
  fixture <- paste(
    "import importlib.util,json,sys,copy; from pathlib import Path",
    "spec=importlib.util.spec_from_file_location('original_fixture','tests/workers/interchange.py'); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)",
    "root=Path(sys.argv[1]); (root/'original.xdf').write_bytes(m.xdf_fixture()); bundle=m.bundle_fixture()",
    "empty=copy.deepcopy(bundle['streams'][1]); empty['id']='empty'; empty['name']='Declared empty stream'; empty['samples']=[]; bundle['streams'].append(empty)",
    "(root/'original-bundle.json').write_text(json.dumps(bundle)); (root/'corrupt.xdf').write_bytes(m.xdf_fixture()[:-2])", sep = "\n")
  processx::run(brohn_python_profile("interchange"), c("-c", fixture, root), timeout = 30000, windows_hide_window = TRUE)
  mapping <- list(origin_statement = "Original generated multistream fixture; no physical device or person.", clock_policy = "preserve_only")
  original <- brohn_ingest_dataset(store, file.path(root, "original.xdf"), "Original XDF streams", modality = "multimodal", origin = "sample")
  check("raw source requires explicit declaration", rejected(brohn_queue_multistream(store, original$id)))
  accepted <- brohn_curate_dataset(store, original$id, mapping, original$revision)
  job <- brohn_queue_multistream(store, accepted$id)
  check("normalization queues dedicated operation", job$operation == "normalise_dataset")
  check("same source revision deduplicates queue", identical(job$id, brohn_queue_multistream(store, accepted$id)$id))
  amended <- mapping; amended$origin_statement <- "Later source-note amendment"
  later <- brohn_curate_dataset(store, accepted$id, amended, accepted$revision)
  claim <- brohn_claim_job(store, "interchange-qa", lease_seconds = 60)
  brohn_process_job(store, claim, timeout_seconds = 60)
  done <- brohn_get_job(store, job$id)
  if (done$status != "succeeded") stop(paste("Actual XDF job failed:", brohn_json(done$error)), call. = FALSE)
  imported <- brohn_stream_import(store, done$result$import_id)
  streams <- brohn_streams(store, import_id = imported$id)
  check("actual R/Python child publishes three ordered stream entities", length(streams)==3L &&
    identical(vapply(streams, function(x) x$body$source_stream_id, character(1)), c("xdf-7", "xdf-2", "xdf-9")))
  check("raw dataset version remains pinned after note amendment", imported$body$dataset_revision==accepted$revision &&
    identical(imported$body$dataset_hash, brohn_hash(accepted$body)) && brohn_get_entity(store,"dataset",accepted$id)$revision==later$revision)
  check("raw original and normalized children preserve source identity", identical(imported$body$source$hash, original$body$source$hash) &&
    all(vapply(streams, function(x) identical(x$body$source_hash, original$body$source$hash), logical(1))))
  check("no generic scientific report is fabricated", length(brohn_list_entities(store,"report"))==0L && is.null(done$result$report_id))
  check("complete stream/sample counts and mapping status are explicit", imported$body$stream_count==3L && imported$body$sample_count==12L &&
    imported$body$status=="needs_mapping" && isTRUE(imported$body$manifest$quality$complete_source_samples_retained))
  eeg <- streams[[1]]; events <- streams[[2]]; counter <- streams[[3]]
  check("channel unit and original UID survive catalog reload", eeg$body$manifest$channels[[1]]$unit=="uV" && eeg$body$manifest$uid=="original-uid-7")
  check("unknown channel unit is retained without guessed calibration", is.null(counter$body$manifest$channels[[1]]$unit) && isTRUE(counter$body$manifest$quality$requires_mapping))
  check("marker stream remains distinct from analogue stream", events$body$manifest$kind=="markers" && eeg$body$manifest$kind=="signal")
  check("normalized streams remain unreviewed", all(vapply(streams,function(x) x$body$review_status=="unreviewed",logical(1))))
  read_stream <- function(record) lapply(readLines(brohn_stream_artifact_path(store,record$id,"stream_samples_jsonl"),warn=FALSE), brohn_parse)
  rows <- read_stream(eeg)
  check("original timestamps remain ordered through reversal", identical(vapply(rows, `[[`, character(1), "source_timestamp"), c("10.0","10.125","10.25","11.0","5.0","5.125")))
  check("nonfinite source missingness survives without zero imputation", is.null(rows[[4]]$values$channel_1) && rows[[4]]$value_states$channel_1=="nan")
  check("int64 values beyond 2^53 remain exact strings", identical(vapply(read_stream(counter),function(x) x$values$channel_1,character(1)),c("9007199254740993","-9007199254740993")))
  check("empty marker text and coincident marker order survive", identical(vapply(read_stream(events),function(x) x$values$channel_1,character(1)),c("control","","test","restart")))
  evidence_path <- brohn_stream_artifact_path(store,eeg$id,"stream_evidence_jsonl")
  evidence <- lapply(readLines(evidence_path,warn=FALSE),brohn_parse)
  offsets <- Filter(function(x) x$type=="clock_offset",evidence)
  check("all recorded offsets remain downloadable and unapplied", length(offsets)==3L && offsets[[3]]$offset_s=="6.0" && identical(offsets[[3]]$applied,FALSE))
  check("full artifacts survive supervised scratch cleanup", file.exists(evidence_path) && !length(setdiff(list.dirs(file.path(store$root,"scratch"),recursive=FALSE,full.names=FALSE),"publication")))
  check("stream import uses parent-owned staged publication",identical(imported$body$processing$publication$mode,"staged-windows-parent-read-seal/1.0"))
  download <- file.path(root,"stream-download.csv")
  brohn_download_stream_artifact(store,counter$id,"stream_samples_csv",download)
  handle <- brohn_stream_artifact(store,counter$id,"stream_samples_csv")
  check("transfer copy preserves bytes and is writable for HTTP delivery", file.access(download,2)==0 && identical(digest::digest(file=download,algo="sha256"),handle$hash))
  downloaded <- brohn_read_json_file(brohn_object_path(store,imported$body$result_object$hash))
  check("download manifest replaces every scratch path with immutable handles", !grepl("/scratch/|\\\"path\\\"",brohn_json(downloaded)) &&
    all(vapply(downloaded$stream_import$manifest$artifacts,function(x) nchar(x$hash)==64 && is.null(x$path),logical(1))))
  check("bootstrap identity pins R and Python implementations", all(c("R/platform-interchange.R","scripts/workers/interchange.py","scripts/analysis-worker.R") %in% names(imported$body$processing$code_hashes)))
  check("import histories reopen through catalog APIs", length(brohn_stream_imports(store,dataset_id=accepted$id))==1L && length(brohn_streams(store,dataset_id=accepted$id))==3L)
  stable_hash <- brohn_hash(imported$body)

  bundle <- brohn_ingest_dataset(store,file.path(root,"original-bundle.json"),"Original declared bundle",modality="multimodal",origin="live")
  bundle <- brohn_curate_dataset(store,bundle$id,mapping,bundle$revision)
  bundle_job <- brohn_queue_multistream(store,bundle$id)
  bundle_claim <- brohn_claim_job(store,"interchange-qa",lease_seconds=60)
  brohn_process_job(store,bundle_claim,timeout_seconds=60)
  bundle_done <- brohn_get_job(store,bundle_job$id)
  if(bundle_done$status!="succeeded") stop(paste("Actual bundle job failed:",brohn_json(bundle_done$error)),call.=FALSE)
  bundle_import <- brohn_stream_import(store,bundle_done$result$import_id)
  bundle_streams <- brohn_streams(store,import_id=bundle_import$id)
  check("stream source provenance cannot be upgraded to live", bundle_import$body$origin=="mixed" &&
    all(vapply(bundle_streams,function(x) x$body$origin=="sample",logical(1))) && bundle_import$body$raw_origin=="live")
  first <- read_stream(bundle_streams[[1]])
  check("large nanosecond timestamps and elapsed arithmetic survive R catalog", first[[1]]$source_timestamp=="9007199254740993" && first[[2]]$time_since_segment_start_s=="0.100000000")
  check("separate participant identities survive stream normalization", first[[1]]$identity$participant_id=="p1" && first[[4]]$identity$participant_id=="p2" && first[[1]]$segment_id!=first[[4]]$segment_id)
  marker <- read_stream(bundle_streams[[2]])
  check("typed false and zero remain distinct values", identical(marker[[1]]$values$answer,FALSE) && marker[[1]]$values$condition==0)
  empty <- bundle_streams[[3]]; empty_path <- brohn_stream_artifact_path(store,empty$id,"stream_samples_jsonl")
  check("zero-sample stream preserves empty canonical object plus metadata", empty$body$manifest$sample_count==0 && file.info(empty_path)$size==0 && length(read_stream(empty))==0L &&
    file.info(brohn_stream_artifact_path(store,empty$id,"stream_evidence_jsonl"))$size>0)
  check("first import remains immutable after second import", identical(stable_hash,brohn_hash(brohn_stream_import(store,imported$id)$body)))

  # Corrupt raw input must fail before any child stream publication.
  corrupt <- brohn_ingest_dataset(store,file.path(root,"corrupt.xdf"),"Original deliberately truncated fixture",modality="multimodal",origin="sample")
  corrupt <- brohn_curate_dataset(store,corrupt$id,mapping,corrupt$revision)
  corrupt_job <- brohn_queue_multistream(store,corrupt$id)
  corrupt_claim <- brohn_claim_job(store,"interchange-qa",lease_seconds=60)
  before_streams <- length(brohn_list_entities(store,"stream")); before_imports <- length(brohn_list_entities(store,"stream_import"))
  brohn_process_job(store,corrupt_claim,timeout_seconds=60)
  check("corrupt source publishes neither partial streams nor import manifest", brohn_get_job(store,corrupt_job$id)$status=="failed" &&
    length(brohn_list_entities(store,"stream"))==before_streams && length(brohn_list_entities(store,"stream_import"))==before_imports)
  check("failed source bytes remain available", identical(digest::digest(file=brohn_object_path(store,corrupt$body$source$hash),algo="sha256"),corrupt$body$source$hash))
  bad_request <- job$request; bad_request$source_hash <- paste(rep("0",64),collapse="")
  wrong <- brohn_enqueue_job(store,"normalise_dataset",bad_request,"original-wrong-source")
  wrong_claim <- brohn_claim_job(store,"interchange-qa",lease_seconds=60)
  brohn_process_job(store,wrong_claim,timeout_seconds=30)
  check("pinned request/source mismatch fails closed", brohn_get_job(store,wrong$id)$status=="failed" && length(brohn_list_entities(store,"stream"))==before_streams)

  fence_job <- brohn_queue_multistream(store,accepted$id,revision=accepted$revision,force=TRUE)
  fence <- brohn_claim_job(store,"interchange-qa",lease_seconds=60)
  input <- brohn_interchange_input(store,fence)
  scratch <- file.path(store$root,"scratch","original-fence-fixture"); dir.create(scratch)
  worker_report <- brohn_analyse_interchange(input,scratch)
  result <- worker_report$interchange
  before_objects <- DBI::dbGetQuery(store$con,"SELECT COUNT(*) AS n FROM objects")$n
  bad <- result
  bad$streams[[1]]$sample_count <- bad$streams[[1]]$sample_count+1
  bad$streams[[1]]$value_count <- bad$streams[[1]]$value_count+length(bad$streams[[1]]$channels)
  bad$quality$sample_count <- bad$quality$sample_count+1
  bad$quality$value_count <- bad$quality$value_count+length(bad$streams[[1]]$channels)
  check("canonical row-count mismatch cannot publish", rejected(brohn_promote_interchange_artifacts(store,bad,scratch,fence,input)) && DBI::dbGetQuery(store$con,"SELECT COUNT(*) AS n FROM objects")$n==before_objects)
  identity_paths<-c("R/platform-publication.R","R/platform-interchange.R","scripts/workers/publication.py","src/publication_guard.c")
  staged_output<-list(schema="brohn-analysis-output/1.0",report=worker_report,code_identity=setNames(lapply(identity_paths,function(path)digest::digest(file=path,algo="sha256")),identity_paths))
  staged_output$report$interchange<-bad;staged_path<-file.path(scratch,"original-malformed-result.json");brohn_write_json_file(staged_output,staged_path)
  check("sealed semantic row mismatch rejects all staged metadata",rejected(brohn_publish_stream_import(store,staged_output,scratch,fence,input,staged_path)) &&
    DBI::dbGetQuery(store$con,"SELECT COUNT(*) AS n FROM objects")$n==before_objects)
  altered_input <- input; altered_input$dataset$title <- "Wrong pinned body"
  check("publication cannot substitute a different dataset body", rejected(brohn_promote_interchange_artifacts(store,result,scratch,fence,altered_input)))
  check("external artifact path is rejected", rejected(brohn_interchange_checked_path(store,file.path(root,"original.xdf"),scratch)))
  bad_token <- fence; bad_token$token <- "stale-original-token"
  check("stale attempt token cannot promote artifacts", rejected(brohn_promote_interchange_artifacts(store,result,scratch,bad_token,input)))
  invisible(brohn_cancel_job(store,fence_job$id))
  check("cancelled fence cannot promote correct bytes", rejected(brohn_promote_interchange_artifacts(store,result,scratch,fence,input)) && DBI::dbGetQuery(store$con,"SELECT COUNT(*) AS n FROM objects")$n==before_objects)
  check("failed attempts preserve catalog integrity", identical(DBI::dbGetQuery(store$con,"PRAGMA integrity_check")[[1]],"ok") && nrow(DBI::dbGetQuery(store$con,"PRAGMA foreign_key_check"))==0)
  for(module in c("platform-shell", "platform-data-views", "platform-interchange-views", "platform-app")) source(paste0("R/",module,".R"),local=TRUE)
  html <- as.character(brohn_dataset_detail_ui(store, accepted$id))
  check("multistream page has its own preservation action and no scientific analysis action", grepl("accept_multistream",html,fixed=TRUE) &&
    !grepl("accept_dataset",html,fixed=TRUE) && grepl("map_preserve_clocks",html,fixed=TRUE))
  hostile <- eeg; hostile$body$title <- "<script>window.original=1</script>"
  check("source titles render as escaped text", !grepl("<script>",as.character(brohn_interchange_stream_ui(hostile)),fixed=TRUE))
  ui_server <- function(input,output,session) {
    state <- shiny::reactiveValues(page="dataset",dataset_id=accepted$id,refresh=0L,error=NULL,status=NULL)
    attempt <- function(fn) {state$error <- NULL; tryCatch(fn(),error=function(e) {state$error <- conditionMessage(e); NULL})}
    refresh <- function() state$refresh <- state$refresh+1L
    message <- function(value) state$status <- value
    brohn_install_interchange_server(input,output,session,store,state,attempt,refresh,message,function(fn) fn())
  }
  shiny::testServer(ui_server, {
    session$flushReact()
    check("Shiny catalog renders saved source counts and origin", grepl("3 streams",output$multistream_catalog$html,fixed=TRUE) && grepl("sample",output$multistream_catalog$html,fixed=TRUE))
    session$setInputs(multistream_import_id=imported$id,multistream_stream_id=counter$id)
    check("selected stream exposes exact integer preview and unit gap", grepl("9007199254740993",output$multistream_stream_detail$html,fixed=TRUE) &&
      grepl("No unit was declared",output$multistream_stream_detail$html,fixed=TRUE))
    csv_download <- output$multistream_csv
    check("actual Shiny download handler delivers the complete selected CSV", file.exists(csv_download) && file.access(csv_download,2)==0 &&
      identical(digest::digest(file=csv_download,algo="sha256"),brohn_stream_artifact(store,counter$id,"stream_samples_csv")$hash))
    canonical_download <- output$multistream_jsonl
    check("actual Shiny canonical download retains all selected rows", length(readLines(canonical_download,warn=FALSE))==counter$body$manifest$sample_count)
    check("actual Shiny recording evidence and manifest downloads resolve immutable objects", file.exists(output$multistream_container) &&
      identical(brohn_read_json_file(output$multistream_manifest)$stream_import$source$hash,original$body$source$hash))
    session$setInputs(multistream_form_identity=paste(accepted$id,later$revision,sep=":"),map_origin="Original fixture reviewed in the source declaration UI.",
      map_preserve_clocks=FALSE,map_study="",accept_multistream=1L)
    check("UI confirmation requires explicit original-clock policy", grepl("Confirm the original-clock",state$error,fixed=TRUE))
    session$setInputs(map_preserve_clocks=TRUE,accept_multistream=2L)
    check("actual UI action saves source notes and queues stream preservation", is.null(state$error) &&
      grepl("preservation queued",state$status,fixed=TRUE) && brohn_get_entity(store,"dataset",accepted$id)$body$metadata$origin_statement=="Original fixture reviewed in the source declaration UI.")
    session$setInputs(accept_multistream=3L)
    check("stale source form cannot confirm a newer revision", grepl("source changed",state$error,fixed=TRUE))
    state$dataset_id <- bundle$id; state$refresh <- state$refresh+1L
    session$flushReact()
    check("navigation cannot keep another recording selected", identical(digest::digest(file=output$multistream_jsonl,algo="sha256"),
      brohn_stream_artifact(store,bundle_streams[[1]]$id,"stream_samples_jsonl")$hash))
  })
  cat(sprintf("PASS: %d interchange assertions (actual supervised XDF/bundle import, immutable downloads, Shiny flow, corruption and fences)\n",checks))
})
