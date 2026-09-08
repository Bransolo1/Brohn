source("R/platform-load.R"); brohn_load()
local({
  checks <- 0L
  check <- function(name, value) {if (!isTRUE(value)) stop("Camera UI QA failed: ", name, call. = FALSE); checks <<- checks+1L}
  rejects <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  root <- tempfile("brohn-camera-ui-qa-"); dir.create(root); root <- normalizePath(root, winslash = "/")
  store <- brohn_open_store(file.path(root, "workspace")); brohn_initialise_library(store)
  on.exit({brohn_close_store(store); actual <- normalizePath(root, winslash = "/", mustWork = FALSE)
    stopifnot(startsWith(tolower(actual), paste0(tolower(normalizePath(tempdir(), winslash = "/")), "/")), grepl("^brohn-camera-ui-qa-", basename(actual)))
    unlink(actual, recursive = TRUE, force = TRUE)}, add = TRUE)
  initial <- brohn_create_study(store, "Original camera authoring fixture", "survey")
  original <- initial$body; info <- brohn_question("Original camera UI information fixture", "information", "before"); info$required <- FALSE
  original$questions <- list(info); initial <- brohn_save_study(store, original, initial$revision)
  policy <- list(schema = "brohn-camera-policy/1.0", required = TRUE, audio = TRUE,
    consent_text = "Original fixture: camera and microphone recording is used for this study.",
    retention_text = "Original fixture: only the local researcher can access recordings; delete after this test.",
    width = 320, height = 240, frame_rate = 12, max_duration_s = 120, max_bytes = 8*1024^2, analysis_profile = "none")
  editor_server <- function(input, output, session) {
    current <- new.env(parent = emptyenv()); current$study <- initial
    state <- shiny::reactiveValues(page = "study", error = NULL, status = NULL)
    current$pending <- NULL
    attempt <- function(fn) {state$error <- NULL; tryCatch(fn(), error = function(e) {state$error <- conditionMessage(e); NULL})}
    update_study <- function(d) current$study <- brohn_save_study(store, d, current$study$revision)
    capture <- function() {if (!is.null(current$pending)) {d <- current$study$body; d$description <- current$pending; update_study(d); current$pending <- NULL}; invisible(NULL)}
    message <- function(text) state$status <- text
    api <- brohn_install_camera_plan_ui(input, output, session, current, state, capture, attempt, update_study, message)
  }
  shiny::testServer(editor_server, {
    session$setInputs(edit_camera_policy = initial$id)
    context <- api$context()
    check("Plan opens an identified editable camera draft", !is.null(context$id) && identical(context$study_id, initial$id))
    session$setInputs(camera_policy_form = context$id, camera_policy_enabled = TRUE,
      camera_policy_required = TRUE, camera_policy_audio = TRUE, camera_policy_consent = policy$consent_text,
      camera_policy_retention = "", camera_policy_width = 320, camera_policy_height = 240,
      camera_policy_rate = 12, camera_policy_duration = 120, camera_policy_size = 8, camera_policy_analysis = "none")
    session$setInputs(save_camera_policy = list(editor_id = context$id))
    check("blank participant retention information prevents a saved revision", !is.null(state$error) && current$study$revision == initial$revision && is.null(current$study$body$camera))
    session$setInputs(camera_policy_retention = policy$retention_text, camera_policy_size = 129)
    session$setInputs(save_camera_policy = list(editor_id = context$id))
    check("UI save enforces the actual bounded recording policy", !is.null(state$error) && current$study$revision == initial$revision)
    session$setInputs(camera_policy_size = 8, camera_policy_audio = "false")
    session$setInputs(save_camera_policy = list(editor_id = context$id))
    check("unbound checkbox strings cannot become microphone permission", !is.null(state$error) && current$study$revision == initial$revision)
    session$setInputs(camera_policy_audio = TRUE)
    session$setInputs(save_camera_policy = list(editor_id = context$id))
    check("one Save persists exact required audio profile and limits", is.null(state$error) && current$study$revision == initial$revision+1L && identical(brohn_hash(current$study$body$camera), brohn_hash(policy)))
    check("saved camera policy is the compiler's frozen participant policy", identical(brohn_hash(brohn_compile(current$study$body)$design$camera), brohn_hash(policy)))
    retained <- current$study
    session$setInputs(edit_camera_policy = initial$id); context <- api$context()
    session$setInputs(camera_policy_form = context$id, camera_policy_enabled = FALSE)
    session$setInputs(cancel_camera_policy = list(editor_id = context$id))
    check("Cancel discards disabled policy without a revision", is.null(api$context()) && identical(current$study$body, retained$body) && current$study$revision == retained$revision)
    session$setInputs(save_camera_policy = list(editor_id = context$id))
    check("late Save after Cancel cannot remove the saved policy", !is.null(state$error) && identical(current$study$body, retained$body))
    session$setInputs(edit_camera_policy = initial$id); newer <- api$context()
    session$setInputs(cancel_camera_policy = list(editor_id = context$id))
    check("old Cancel cannot close a later camera editor", !is.null(state$error) && identical(api$context()$id, newer$id))
    session$setInputs(camera_policy_form = context$id, save_camera_policy = list(editor_id = newer$id))
    check("stale form fields cannot publish into a later editor", !is.null(state$error) && current$study$revision == retained$revision)
    session$setInputs(camera_policy_form = newer$id)
    current$pending <- "A pending underlying Plan edit flushed while recording settings were open."
    session$setInputs(save_camera_policy = list(editor_id = newer$id))
    check("flushing underlying Plan edits invalidates a stale camera draft", grepl("study changed", state$error, fixed = TRUE) && current$study$body$description == "A pending underlying Plan edit flushed while recording settings were open." && identical(brohn_hash(current$study$body$camera), brohn_hash(policy)))
    session$setInputs(edit_camera_policy = initial$id); context <- api$context()
    session$setInputs(camera_policy_form = context$id, camera_policy_enabled = FALSE)
    before_disable <- current$study
    session$setInputs(save_camera_policy = list(editor_id = context$id))
    check("explicit disable removes only the current optional policy", is.null(state$error) && is.null(current$study$body$camera) && current$study$revision == before_disable$revision+1L && current$study$body$description == before_disable$body$description)
    check("historical design still retains required camera consent and bounds", identical(brohn_hash(brohn_study(store, initial$id, before_disable$revision)$body$camera), brohn_hash(policy)))
    session$setInputs(edit_camera_policy = initial$id); context <- api$context()
    session$setInputs(camera_policy_form = context$id, camera_policy_enabled = TRUE, camera_policy_required = FALSE, camera_policy_audio = FALSE,
      camera_policy_analysis = "face_geometry_v1", camera_policy_size = 1025/1024^2)
    session$setInputs(save_camera_policy = list(editor_id = context$id))
    check("optional geometry policy and exact imported byte limits survive UI units", is.null(state$error) && identical(current$study$body$camera$required, FALSE) && identical(current$study$body$camera$audio, FALSE) && current$study$body$camera$analysis_profile == "face_geometry_v1" && current$study$body$camera$max_bytes == 1025)
    session$setInputs(edit_camera_policy = initial$id); context <- api$context()
    session$setInputs(camera_policy_form = context$id, camera_policy_enabled = FALSE)
    current$study <- brohn_archive_study(store, initial$id, TRUE, current$study$revision)
    session$setInputs(save_camera_policy = list(editor_id = context$id))
    check("archiving while an editor is open blocks its late save", !is.null(state$error) && !is.null(current$study$body$camera))
    session$setInputs(edit_camera_policy = initial$id)
    check("archived study cannot open a new camera setup", !is.null(state$error))
    current$study <- NULL; state$page <- "studies"
    session$setInputs(edit_camera_policy = initial$id)
    check("stale setup command after navigation has an actionable error", grepl("Choose an editable study", state$error, fixed = TRUE))
  })
  saved <- brohn_study(store, initial$id)
  cloned <- brohn_clone_study(store, saved$id)
  template <- brohn_save_template(store, saved$id); reused <- brohn_use_template(store, template$id)
  check("clone preserves camera policy with new study identity", cloned$id != saved$id && identical(brohn_hash(cloned$body$camera), brohn_hash(saved$body$camera)))
  check("saved reusable design preserves the exact camera agreement", identical(brohn_hash(reused$body$camera), brohn_hash(saved$body$camera)))
  portable <- file.path(root, "camera-ui.brohn-study.zip"); brohn_export_design(store, cloned$id, portable)
  imported <- brohn_import_design(store, portable, title = "Original camera portable fixture")
  check("export and reupload retain UI-authored camera policy", identical(brohn_hash(imported$body$camera), brohn_hash(saved$body$camera)))
  plan <- as.character(brohn_camera_plan_ui(cloned$body))
  check("Plan shows optional audio status and bounded automatic processing", grepl("continue without recording", plan, fixed = TRUE) && grepl("microphone is disabled", plan, fixed = TRUE) && grepl("Supported recordings from completed sessions", plan, fixed = TRUE))

  # Original typed object fixtures prove display and download ownership. They do
  # not assert these intentionally tiny bytes are a decodable camera recording.
  kinds <- c("camera-recording", "camera-observations", "camera-decoded-frames", "camera-manifest")
  payloads <- list(charToRaw("Original unplayable camera source fixture"), charToRaw('{"original_callback_ms":"2000"}\n'),
    charToRaw('{"original_frames":[{"pts":0}]}'), charToRaw('{"original_retention":"fixture only"}'))
  artifacts <- lapply(seq_along(kinds), function(i) c(list(kind = kinds[[i]], complete = TRUE), brohn_store_object(store, bytes = payloads[[i]], media_type = if (i == 1) "video/webm" else if (i == 2) "application/x-ndjson" else "application/json")))
  source <- artifacts[[1]][c("hash", "size", "media_type")]; source$format <- "webm"; source$filename <- "original-ui-fixture.webm"
  body <- list(id = "dataset-camera-ui-original", schema_version = "brohn-dataset/1.0.0", modality = "video", title = "Original camera artifact fixture",
    origin = "sample", status = "needs_mapping", source = source, source_provenance = list(acquisition = "browser_camera", capture_id = "camera-ui-original",
      run_id = "run-ui-original", participant_id = "ORIGINAL-UI-FIXTURE", design_hash = brohn_hash(saved$body), protocol_hash = brohn_hash(brohn_compile(saved$body)),
      recording_outcome = "interrupted", container_complete_declared = FALSE, decoder = list(supported = FALSE, decoded = FALSE, reason = "Original unplayable UI fixture"),
      artifacts = artifacts, capture_policy = saved$body$camera))
  dataset <- brohn_put_entity(store, "dataset", body$id, body, project_id = "default")
  requests <- lapply(artifacts, function(a) list(dataset_id = dataset$id, revision = dataset$revision, source_hash = dataset$body$source$hash, kind = a$kind, hash = a$hash))
  html <- as.character(brohn_camera_dataset_ui(store, dataset))
  check("Data lists all four preserved camera evidence artifact types", all(vapply(c("Original camera recording (WebM)", "Chunk clocks and frame callbacks (JSONL)", "Decoded frames and native timestamps (JSON)", "Capture and transfer manifest (JSON)"), grepl, logical(1), x = html, fixed = TRUE)))
  check("partial unsupported source is not presented as complete or aligned", grepl("partial recording", html, fixed = TRUE) && grepl("may not play", html, fixed = TRUE) && grepl("do not establish encoded-frame alignment", html, fixed = TRUE))
  hostile <- dataset; hostile$body$source_provenance$participant_id <- '<script>alert("original")</script>'
  check("camera source identity is escaped in researcher markup", !grepl("<script>", as.character(brohn_camera_dataset_ui(store, hostile)), fixed = TRUE))
  for (i in seq_along(requests)) {
    a <- brohn_camera_dataset_artifact(store, requests[[i]], dataset$id)
    destination <- file.path(root, paste0(kinds[[i]], ".download")); brohn_copy_object_download(store, a$hash, destination)
    check(paste("download retains full immutable bytes:", kinds[[i]]), identical(readBin(destination, "raw", n = file.info(destination)$size), payloads[[i]]) && file.access(destination, 2) == 0L)
  }
  wrong <- requests[[1]]; wrong$hash <- artifacts[[2]]$hash
  check("same-dataset artifact substitution is rejected", rejects(brohn_camera_dataset_artifact(store, wrong, dataset$id)))
  check("foreign dataset download selection is rejected", rejects(brohn_camera_dataset_artifact(store, requests[[1]], "dataset-other")))
  wrong <- requests[[1]]; wrong$path <- "arbitrary.webm"
  check("artifact requests cannot introduce filesystem paths", rejects(brohn_camera_dataset_artifact(store, wrong, dataset$id)))
  artifact_server <- function(input, output, session) {
    state <- shiny::reactiveValues(page = "dataset", dataset_id = dataset$id)
    api <- brohn_install_camera_artifact_ui(input, output, session, store, state, function(fn) fn())
  }
  shiny::testServer(artifact_server, {
    session$setInputs(camera_dataset_artifact = brohn_json(requests[[4]]))
    check("actual Shiny download selector resolves the registered manifest", identical(api$selected()$hash, artifacts[[4]]$hash))
    state$page <- "studies"
    check("stale download after leaving Data is rejected", rejects(api$selected()))
    state$page <- "dataset"; state$dataset_id <- "dataset-other"
    check("stale download after changing datasets is rejected", rejects(api$selected()))
  })
  updated <- dataset$body; updated$notes <- "Original curation revision"
  brohn_put_entity(store, "dataset", dataset$id, updated, dataset$revision, "default")
  check("curation revision invalidates the previous artifact selection", rejects(brohn_camera_dataset_artifact(store, requests[[1]], dataset$id)))

  # Real frozen participant runs exercise the Sessions camera decision surface.
  counter <- 0L; uuid <- function() {counter <<- counter+1L; paste0("00000000-0000-4000-8000-", sprintf("%012d", counter))}
  d <- brohn_new_design("Original Sessions camera fixture", "survey"); p <- policy; p$required <- FALSE; p$audio <- FALSE; d$camera <- p; d$questions <- list(info)
  study <- brohn_put_entity(store, "study", d$id, d, project_id = "default")
  deployment <- brohn_publish(store, study$id, origin = "sample", quota = 10)
  start <- .brohn_delivery_start(store, deployment$token, list(consented = TRUE, participant_alias = "ORIGINAL-CAMERA-UI", client_id = uuid(), operation_id = uuid()))
  run <- brohn_run(store, start$run_id)
  check("a missing camera decision is visible in Sessions", grepl("Awaiting camera decision", as.character(brohn_camera_session_ui(store, run)), fixed = TRUE))
  declined <- list(capture_id = paste0("camera-", uuid()), consented = FALSE,
    clock = list(id = "browser-monotonic", unit = "ms", value = "1000", instance_id = "original-ui-page", time_origin_ms = "1700000000000"),
    mime_type = NULL, settings = NULL, reason = "participant_declined", operation_id = uuid())
  .brohn_camera_start(store, run$id, start$access_token, declined)
  decision <- as.character(brohn_camera_session_ui(store, run))
  check("Sessions displays explicit optional decline without inventing source bytes", grepl("Declined", decision, fixed = TRUE) && grepl("recording was optional", decision, fixed = TRUE) && !grepl("Open camera dataset", decision, fixed = TRUE))
  no_camera <- run; no_camera$protocol$design$camera <- NULL
  check("ordinary historical sessions stay separate from camera requests", grepl("Not requested", as.character(brohn_camera_session_ui(store, no_camera)), fixed = TRUE))
  check("integrated Sessions table has a labelled Camera column", grepl('scope="col">Camera', as.character(brohn_sessions_ui(store, study$id)), fixed = TRUE))
  cat(sprintf("PASS: %d camera researcher UI assertions (real Shiny draft/save/cancel, portable policy, immutable artifact ownership, frozen run decisions)\n", checks))
})
