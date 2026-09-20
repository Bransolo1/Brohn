# Independently defined asymmetric volume + derivative flow; no device claim.
source("R/platform-load.R"); brohn_load(ui = TRUE)
local({
  checks <- 0L
  check <- function(name, value) {if (!isTRUE(value)) stop("Respiration QA failed: ", name, call. = FALSE); checks <<- checks+1L}
  rejects <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  root <- tempfile("brohn-respiration-qa-"); dir.create(root); root <- normalizePath(root, winslash = "/")
  store <- brohn_open_store(file.path(root, "workspace")); brohn_initialise_library(store)
  on.exit({brohn_close_store(store); actual <- normalizePath(root, winslash = "/", mustWork = FALSE)
    stopifnot(startsWith(tolower(actual), paste0(tolower(normalizePath(tempdir(), winslash = "/")), "/")), grepl("^brohn-respiration-qa-", basename(actual)))
    unlink(actual, recursive = TRUE, force = TRUE)}, add = TRUE)
  fs <- 50; time <- (0:5999)/fs; phase <- time %% 5
  volume <- ifelse(phase < 2, (1-cos(pi*phase/2))/2, (1+cos(pi*(phase-2)/3))/2)
  flow <- ifelse(phase < 2, pi/4*sin(pi*phase/2), -pi/6*sin(pi*(phase-2)/3))
  stream <- function(id, values, unit) list(id = id, name = id, type = "Respiration", kind = "signal", source_id = paste0(id,"-generator"), uid = paste0(id,"-uid"),
    clock = list(id = "original-clock", unit = "ms", kind = "device", representation = "decimal_string"), nominal_srate = fs,
    identity = list(participant_id = "synthetic-person", session_id = "synthetic-visit"),
    channels = list(list(id = "resp", label = id, type = "Respiration", unit = unit, value_type = "float64")),
    samples = lapply(seq_along(time), function(i) list(timestamp = as.character((i-1)*20), values = list(values[[i]]))))
  source <- file.path(root, "original-volume-and-flow.json")
  brohn_write_json_file(list(schema = "brohn-stream-bundle/1.0", origin = "sample", streams = list(
    stream("negative-volume", -volume, "L"), stream("airflow", flow, "L/s"))), source)
  original <- brohn_ingest_dataset(store, source, "Original respiratory construction", modality = "multimodal", origin = "sample")
  original <- brohn_curate_dataset(store, original$id, list(origin_statement = "Independent mathematical volume rises for 2 seconds, falls for 3; saved with inverted sign. Analytic derivative separately retained. No device.", clock_policy = "preserve_only"), original$revision)
  run_job <- function(job) {
    force(job); claim <- brohn_claim_job(store, "respiration-qa", lease_seconds = 120)
    stopifnot(claim$id == job$id)
    brohn_process_job(store, claim, timeout_seconds = 120)
    done <- brohn_get_job(store, job$id)
    if (done$status != "succeeded") stop("Actual supervised job failed: ", brohn_json(done$error), call. = FALSE)
    done
  }
  imported <- run_job(brohn_queue_multistream(store, original$id))
  streams <- brohn_streams(store, import_id = imported$result$import_id)
  volumetric <- Filter(function(s) identical(s$body$manifest$channels[[1]]$unit,"L"), streams)[[1]]
  airflow <- Filter(function(s) identical(s$body$manifest$channels[[1]]$unit,"L/s"), streams)[[1]]
  selection <- list(schema = "brohn-stream-selection/1.0", channel_ids = list("resp"), modality = "respiration", unit = "L", sampling_rate = fs,
    participant_id = NULL, session_id = NULL, origin_statement = "Independent inverted volume construction; no device.", unit_rationale = "Analytic volume declared in L.",
    confirm_source_units = TRUE, confirm_boundaries = TRUE, run_analysis = TRUE)
  check("old untyped automatic selection requires review", rejects(brohn_validate_stream_selection(volumetric$body,selection)))
  declaration <- list(source_quantity = "lung_volume", polarity = "negative_inspiration", mapping_source = "Analytic volume increases during the specified 2-second inspiration; source is its negative in L.")
  selection$respiration <- declaration
  check("explicit source quantity and polarity accepted", !rejects(brohn_validate_stream_selection(volumetric$body,selection)))
  wrong <- selection; wrong$respiration$source_quantity <- "belt_displacement"
  check("quantity and calibrated unit must agree", rejects(brohn_validate_stream_selection(volumetric$body,wrong)))
  ui_job <- NULL
  ui_server <- function(input, output, session) {
    state <- shiny::reactiveValues(page = "dataset", dataset_id = original$id, error = NULL)
    attempt <- function(fn) {state$error <- NULL; tryCatch(fn(),error=function(e){state$error <- conditionMessage(e);NULL})}
    api <- brohn_install_stream_curation_ui(input,output,session,store,state,attempt,function(text)NULL,function()NULL,function(fn)fn())
  }
  shiny::testServer(ui_server, {
    session$setInputs(multistream_stream_id = volumetric$id,open_stream_curation = list(stream_id=volumetric$id,revision=volumetric$revision,hash=brohn_hash(volumetric$body)))
    context <- api$context()
    session$setInputs(stream_curation_form=context$id,stream_curation_channels="resp",stream_curation_modality="respiration",stream_curation_unit="L",
      stream_curation_unit_rationale=selection$unit_rationale,stream_curation_origin=selection$origin_statement,stream_curation_participant="",stream_curation_session="",
      stream_curation_units_confirmed=TRUE,stream_curation_boundaries_confirmed=TRUE,stream_curation_run_analysis=TRUE)
    session$setInputs(save_stream_curation=list(editor_id=context$id))
    check("actual researcher action cannot infer missing quantity and polarity",!is.null(state$error) && !is.null(api$context()))
    session$setInputs(stream_curation_respiration_quantity=declaration$source_quantity,stream_curation_respiration_polarity=declaration$polarity,stream_curation_respiration_source=declaration$mapping_source)
    session$setInputs(save_stream_curation=list(editor_id=context$id))
    check("actual controls queue reviewed respiration",is.null(state$error) && is.null(api$context()))
    ui_job <<- Filter(function(j)j$operation=="extract_stream" && j$status=="queued",brohn_list_jobs(store))[[1]]
  })
  check("queued source declaration exactly matches reviewed evidence",identical(brohn_hash(ui_job$request$selection$respiration),brohn_hash(declaration)))
  curated <- run_job(ui_job)
  dataset <- brohn_get_entity(store,"dataset",curated$result$dataset_id)
  check("new dataset freezes versioned displacement profile and direction",dataset$body$metadata$parameters$recipe=="respiration-displacement-khodadad/1.0" &&
    identical(dataset$body$metadata$parameters$polarity,"negative_inspiration") && !is.null(curated$result$analysis_job_id))
  completed <- run_job(brohn_get_job(store,curated$result$analysis_job_id))
  report <- brohn_get_entity(store,"report",completed$result$report_id)
  metric <- function(name) Filter(function(f)identical(f$name,name),report$body$analysis$features)[[1]]$value
  check("actual automatic worker estimates independent 12 breaths/min",abs(metric("respiration_rate")-12)<.03)
  check("actual inverted volume retains independent 2s inspiration and 3s expiration",abs(metric("inspiration_duration")-2)<.08 && abs(metric("expiration_duration")-3)<.08)
  check("report discloses normalization and source evidence",grepl("negative_inspiration",brohn_json(report$body),fixed=TRUE) && grepl(declaration$mapping_source,brohn_json(report$body),fixed=TRUE))
  prepared <- brohn_read_table(brohn_object_path(store,dataset$body$source$hash),"csv")
  check("every curated volume value retains its original negative sign",max(abs(as.numeric(prepared$value_resp)+volume))<1e-12)
  old <- dataset$body; old$metadata$parameters <- list(recipe="respiration-khodadad-cycles/1.0",edge_exclusion_s=5)
  check("new queue validation cannot silently rerun historical recipe",rejects(brohn_validate_dataset_mapping(old)))
  saved_hash <- brohn_hash(report$body)
  raw_selection <- selection; raw_selection$unit <- "L/s"; raw_selection$run_analysis <- FALSE; raw_selection$respiration <- NULL
  raw_selection$unit_rationale <- "Analytic volume derivative recorded in L/s; preserve raw flow, no phase analysis."
  automatic_flow <- raw_selection; automatic_flow$run_analysis <- TRUE; automatic_flow$respiration <- declaration
  check("automatic flow cannot masquerade as volume",rejects(brohn_queue_stream_curation(store,airflow$id,automatic_flow)))
  retained <- run_job(brohn_queue_stream_curation(store,airflow$id,raw_selection))
  raw_dataset <- brohn_get_entity(store,"dataset",retained$result$dataset_id)
  raw_values <- brohn_read_table(brohn_object_path(store,raw_dataset$body$source$hash),"csv")
  check("flow remains completely available without an analysis claim",is.null(retained$result$analysis_job_id) && raw_dataset$body$status=="needs_mapping" && nrow(raw_values)==length(flow) && max(abs(as.numeric(raw_values$value_resp)-flow))<1e-12)
  check("flow cannot later queue the displacement recipe",rejects(brohn_queue_dataset(store,raw_dataset$id)))
  check("original complete source bytes remain immutable",identical(digest::digest(file=brohn_object_path(store,original$body$source$hash),algo="sha256"),original$body$source$hash))
  html <- as.character(brohn_respiration_settings_ui())
  check("mapping fields make explicit review visible without positive default",all(vapply(c("Choose from source documentation","Confirm the direction","Airflow peaks","source"),function(x)grepl(x,html,fixed=TRUE),logical(1))))
  inputs <- list(map_origin="original",map_values="value_resp",map_unit="L",map_time="brohn_time_s",map_time_unit="s",map_sampling_rate=fs,
    map_respiration_quantity=declaration$source_quantity,map_respiration_polarity=declaration$polarity,map_respiration_source=declaration$mapping_source)
  mapping <- brohn_dataset_base_mapping(inputs,dataset$body)
  check("direct CSV controls also freeze explicit recipe and source declaration",identical(mapping$parameters$polarity,"negative_inspiration") && identical(mapping$parameters$recipe,"respiration-displacement-khodadad/1.0"))
  brohn_close_store(store); store <- brohn_open_store(file.path(root,"workspace"))
  check("saved report survives reopening without rescoring",identical(brohn_hash(brohn_get_entity(store,"report",report$id)$body),saved_hash))
  cat(sprintf("PASS: %d respiration assertions (actual UI, preserved flow, automatic publication, independent asymmetric phase oracle, immutable report)\n",checks))
})
