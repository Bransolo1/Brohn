for(module in c("platform-core","platform-store","platform-publication","platform-methods","platform-library","platform-analysis","platform-jobs","platform-headers",
  "platform-shell","platform-data-views","platform-headers-views","platform-app")) source(paste0("R/",module,".R"),encoding="UTF-8")
for (module in c("questionnaire-artifacts", "questionnaire-artifact-storage")) source(paste0("R/platform-",module,".R"),encoding="UTF-8")
local({
  checks <- 0L
  check <- function(name,value) {if(!isTRUE(value)) stop(paste("Native-header QA failed:",name),call.=FALSE); checks <<- checks+1L}
  rejected <- function(expr) inherits(try(force(expr),silent=TRUE),"try-error")
  root <- tempfile("brohn-header-qa-"); dir.create(root); root <- normalizePath(root,winslash="/")
  store <- brohn_open_store(file.path(root,"workspace")); brohn_initialise_library(store)
  on.exit({brohn_close_store(store); actual <- normalizePath(root,winslash="/",mustWork=FALSE)
    stopifnot(startsWith(tolower(actual),paste0(tolower(normalizePath(tempdir(),winslash="/")),"/")),grepl("^brohn-header-qa-",basename(actual)))
    unlink(actual,recursive=TRUE,force=TRUE)},add=TRUE)
  fixture <- paste("import importlib.util,sys; from pathlib import Path",
    "spec=importlib.util.spec_from_file_location('original_headers','tests/workers/headers.py'); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)",
    "root=Path(sys.argv[1]); (root/'original.edf').write_bytes(m.edf_fixture()); (root/'other.edf').write_bytes(m.edf_fixture(mixed=False)); (root/'truncated.edf').write_bytes(m.edf_fixture()[:-1])",sep="\n")
  processx::run(brohn_python_profile("eeg"),c("-c",fixture,root),timeout=30,cleanup_tree=TRUE,windows_hide_window=TRUE)
  raw <- brohn_ingest_dataset(store,file.path(root,"original.edf"),"Original header fixture",modality="eeg",origin="sample")
  job <- brohn_queue_header_inspection(store,raw$id)
  check("inspection queues before scientific mapping",job$operation=="inspect_header" && raw$body$status=="needs_mapping")
  check("identical header request deduplicates",identical(job$id,brohn_queue_header_inspection(store,raw$id)$id))
  latest <- raw; latest$body$title <- "Later source label"; latest <- brohn_put_entity(store,"dataset",raw$id,latest$body,raw$revision,raw$project_id)
  claim <- brohn_claim_job(store,"header-qa",lease_seconds=60)
  brohn_process_job(store,claim,timeout_seconds=60)
  done <- brohn_get_job(store,job$id)
  if(done$status!="succeeded") stop(paste("Actual native-header job failed:",brohn_json(done$error)),call.=FALSE)
  inspection <- brohn_get_entity(store,"header_inspection",done$result$header_id)
  check("supervised Python creates an immutable header entity",!is.null(inspection) && inspection$body$inspection$header$channel_count==2L)
  check("header pins original source revision without changing later label",inspection$body$dataset_revision==raw$revision &&
    brohn_get_entity(store,"dataset",raw$id)$body$title=="Later source label")
  check("source-only header can be reused across later metadata revisions",brohn_header_for_dataset(store,latest)$id==inspection$id)
  check("recorded mixed native rates survive R roundtrip",identical(vapply(inspection$body$inspection$header$channels,`[[`,numeric(1),"sampling_rate_hz"),c(100,50)))
  check("patient header text is absent from the inspection",!grepl("PRIVATE",brohn_json(inspection$body),fixed=TRUE))
  check("header is not a scientific report",length(brohn_list_entities(store,"report"))==0L && is.null(done$result$report_id))
  check("both worker and R adapter identities are pinned",all(c("scripts/workers/headers.py","R/platform-headers.R") %in% names(inspection$body$processing$code_hashes)))
  defaults <- brohn_header_mapping_defaults(inspection,"Cz")
  exact_names <- c("Cz, reference", "[Original]", "Pz")
  check("channel text roundtrip preserves commas and brackets without splitting names", identical(brohn_parse_native_channel_input(brohn_native_channel_input_text(exact_names)),exact_names))
  check("ordinary manual channel input remains readable", identical(brohn_parse_native_channel_input("Cz, Pz"),c("Cz","Pz")) && identical(brohn_native_channel_input_text(c("Cz","Pz")),"Cz, Pz"))
  check("invalid structured channel input is rejected",rejected(brohn_parse_native_channel_input('["Cz",4]')) && rejected(brohn_parse_native_channel_input('["Cz","Cz"]')))
  check("explicit channel defaults retain exact name/rate/native policy",identical(defaults$value_columns,list("Cz")) && defaults$sampling_rate==100 && defaults$unit=="native" && defaults$requires_confirmation)
  check("mixed-rate selection cannot silently trigger MNE resampling",rejected(brohn_header_mapping_defaults(inspection,c("Cz","ECG"))))
  check("unknown channel cannot populate mapping",rejected(brohn_header_mapping_defaults(inspection,"invented")))
  uncalibrated <- inspection; uncalibrated$body$inspection$header$channels[[1]]$source_unit <- NULL
  check("unknown EDF unit is not converted into a voltage claim",rejected(brohn_header_mapping_defaults(uncalibrated,"Cz")))
  artifact <- file.path(root,"download.json"); brohn_copy_object_download(store,inspection$body$result_object$hash,artifact)
  check("published header remains downloadable after owned bulk scratch cleanup",file.access(artifact,2)==0 &&
    !length(list.files(file.path(store$root,"scratch"),pattern="\\.object-pending$",recursive=TRUE)) &&
    !length(list.files(file.path(store$root,"scratch"),pattern=paste0("^",job$id,"-"))) && !length(ls(.brohn_publication_handles)) &&
    brohn_read_json_file(artifact)$header_inspection$source_hash==raw$body$source$hash)
  corrupt <- brohn_ingest_dataset(store,file.path(root,"truncated.edf"),"Original corrupt header fixture",modality="eeg",origin="sample")
  corrupt_job <- brohn_queue_header_inspection(store,corrupt$id)
  brohn_process_job(store,brohn_claim_job(store,"header-qa",lease_seconds=60),timeout_seconds=60)
  check("truncated recording has an actionable failure and no partial header",brohn_get_job(store,corrupt_job$id)$status=="failed" &&
    grepl("truncated",brohn_get_job(store,corrupt_job$id)$error$message,fixed=TRUE) && !length(brohn_header_inspections(store,corrupt$id)))
  fence_job <- brohn_queue_header_inspection(store,raw$id,force=TRUE)
  fence <- brohn_claim_job(store,"header-qa",lease_seconds=60); input <- brohn_header_input(store,fence)
  scratch <- file.path(store$root,"scratch","original-header-fence"); dir.create(scratch)
  output <- list(code_identity=list(),report=brohn_analyse_header(input,scratch)); output_path <- file.path(scratch,"output.json"); brohn_write_json_file(output,output_path)
  wrong <- input; wrong$dataset$title <- "Different input"
  before <- DBI::dbGetQuery(store$con,"SELECT COUNT(*) AS n FROM objects")$n
  check("publication rejects substituted dataset body",rejected(brohn_publish_header_inspection(store,output,scratch,fence,wrong,output_path)))
  stale <- fence; stale$token <- "original-stale-token"
  check("publication rejects stale attempt fence",rejected(brohn_publish_header_inspection(store,output,scratch,stale,input,output_path)))
  invisible(brohn_cancel_job(store,fence_job$id))
  check("cancelled inspection cannot publish valid output",rejected(brohn_publish_header_inspection(store,output,scratch,fence,input,output_path)) &&
    DBI::dbGetQuery(store$con,"SELECT COUNT(*) AS n FROM objects")$n==before)
  other <- brohn_ingest_dataset(store,file.path(root,"other.edf"),"Other original recording",modality="eeg",origin="sample")
  server <- function(input,output,session) {
    state <- shiny::reactiveValues(page="dataset",dataset_id=raw$id,refresh=0L,error=NULL,status=NULL)
    sent <- new.env(parent=emptyenv()); session$sendInputMessage <- function(inputId,message) sent[[inputId]] <- message
    attempt <- function(fn) {state$error <- NULL; tryCatch(fn(),error=function(e) {state$error <- conditionMessage(e); NULL})}
    refresh <- function() state$refresh <- state$refresh+1L
    message <- function(value) state$status <- value
    brohn_install_header_server(input,output,session,store,state,attempt,refresh,message,function(fn) fn())
  }
  shiny::testServer(server,{
    session$flushReact()
    check("Shiny header preview shows actual channel names and rate differences",grepl("Cz",output$native_header_review$html,fixed=TRUE) &&
      grepl("no single native sampling rate",output$native_header_review$html,fixed=TRUE))
    check("rendering metadata does not automatically fill the mapping",length(ls(sent))==0L)
    session$setInputs(native_header_form_identity=paste(raw$id,inspection$id,inspection$body$source_hash,sep=":"),native_header_channels="Cz",apply_native_header=1L)
    check("only explicit confirmation updates native channel/unit/rate controls",is.null(state$error) && sent$map_native_values$value=="Cz" && sent$map_unit$value=="native" && sent$map_sampling_rate$value==100)
    download <- output$native_header_download
    check("actual Shiny header download serves immutable source inspection",file.access(download,2)==0 && digest::digest(file=download,algo="sha256")==inspection$body$result_object$hash)
    session$setInputs(native_header_channels=c("Cz","ECG"),apply_native_header=2L)
    check("UI refuses mixed-rate selection with clear guidance",grepl("different native rates",state$error,fixed=TRUE))
    state$dataset_id <- other$id; state$refresh <- state$refresh+1L; session$flushReact()
    previous <- as.list(sent)
    session$setInputs(apply_native_header=3L)
    check("navigation cannot apply an earlier recording header",identical(previous,as.list(sent)) && grepl("previous header belongs to another source",state$error,fixed=TRUE))
    session$setInputs(inspect_native_header=list(dataset_id=raw$id,revision=raw$revision,source_hash=raw$body$source$hash))
    check("inspection action rejects stale source commands",grepl("source changed",state$error,fixed=TRUE))
    session$setInputs(inspect_native_header=list(dataset_id=other$id,revision=other$revision,source_hash=other$body$source$hash))
    check("actual header action queues selected source without remapping it",is.null(state$error) && grepl("Header inspection queued",state$status,fixed=TRUE) &&
      brohn_get_entity(store,"dataset",other$id)$body$status=="needs_mapping")
  })
  cat(sprintf("PASS: %d native header assertions (actual R/Python supervisor, immutable publication, Shiny confirmation and download, fencing)\n",checks))
})
