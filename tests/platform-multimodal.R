source("R/platform-participant-equipment.R") # Registered optional new-draft policy.
for (name in c("platform-core", "platform-store", "platform-publication", "platform-library", "platform-delivery", "platform-analysis", "platform-multimodal")) source(paste0("R/", name, ".R"), encoding = "UTF-8")
for (name in c("questionnaire-artifacts", "questionnaire-artifact-storage")) source(paste0("R/platform-", name, ".R"), encoding = "UTF-8")
local({
  checks <- 0L
  check <- function(name, value) { if (!isTRUE(value)) stop(paste("FAILED:", name)); checks <<- checks+1L }
  rejects <- function(expr) inherits(tryCatch({ force(expr); NULL }, error = function(e) e), "error")
  near <- function(a, b) brohn_number(a) && abs(a-b) < 1e-8
  root <- tempfile("brohn-multimodal-test-"); dir.create(root); root <- normalizePath(root, winslash = "/")
  store <- brohn_open_store(file.path(root, "workspace"))
  on.exit({
    brohn_close_store(store)
    actual <- normalizePath(root, winslash = "/", mustWork = FALSE)
    stopifnot(startsWith(actual, paste0(normalizePath(tempdir(), winslash = "/"), "/")), startsWith(basename(actual), "brohn-multimodal-test-"))
    unlink(actual, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  brohn_initialise_library(store)
  design <- brohn_new_design("Independent multimodal oracle", id = "multimodal-oracle")
  for (i in 1:2) design$stimuli[[i]]$aois <- list(list(id = paste0("logo-", i), label = "Logo", x = 0, y = 0, width = .5, height = 1))
  invisible(brohn_put_entity(store, "study", design$id, design))
  hash <- brohn_hash(design)
  sessions <- list(list(person = "P1", session = "S1", gaze = 10, rating = 1), list(person = "P1", session = "S2", gaze = 30, rating = 3),
    list(person = "P2", session = "S1", gaze = 25, rating = 1), list(person = "P3", session = "S1", gaze = 45, rating = NULL))
  gaze <- list(); ratings <- list(); crosswalk <- list()
  for (visit in sessions) {
    for (modality in c("gaze", "rating", "eeg")) crosswalk[[length(crosswalk)+1L]] <- list(report_id = paste0("report-", modality),
      source_participant_id = paste0(modality, "-", visit$person), source_session_id = paste0(modality, "-", visit$session),
      participant_id = visit$person, session_id = visit$session)
    for (condition in c("a", "b")) {
      share <- if (condition == "a") 20 else 20+visit$gaze
      identity <- list(participant_id = paste0("gaze-", visit$person), session_id = paste0("gaze-", visit$session),
        condition_id = paste0("condition-", condition), stimulus_id = paste0("stimulus-", condition), exposure_id = paste(visit$session, condition, sep = "-"), aoi_id = paste0("logo-", if (condition == "a") 1 else 2), aoi_label = "Logo")
      gaze[[length(gaze)+1L]] <- c(identity, list(valid_ms = 1000, inside_ms = 10*share, valid_share_percent = share,
        denominator = "valid gaze interval time; off-stimulus observations retained"))
      identity$participant_id <- paste0("rating-", visit$person); identity$session_id <- paste0("rating-", visit$session)
      value <- if (condition == "a") 3 else if (is.null(visit$rating)) NULL else 3+visit$rating
      ratings[[length(ratings)+1L]] <- c(identity[!names(identity) %in% c("aoi_id", "aoi_label")], list(question_id = "q-liking", prompt = "Liking",
        value = value, missing_reason = if (is.null(value)) "optional_omission" else NULL))
    }
  }
  make_report <- function(id, analysis, project = "default") {
    body <- list(schema_version = "brohn-report/1.0.0", id = id, title = id, study_id = design$id, dataset_id = paste0("dataset-", id),
      origin = "sample", status = "Available", analysis = analysis, provenance = list(design = design, design_hash = hash, source = list(hash = brohn_hash(id))))
    brohn_put_entity(store, "report", id, body, project_id = project)
  }
  gaze_report <- make_report("report-gaze", list(kind = "gaze", observations = gaze, features = list(),
    quality = list(participant_count = 3), parameters = list(method = "aoi-valid-gaze-time-share/0.1.0-draft", coordinate_space = "stimulus_normalized")))
  rating_report <- make_report("report-rating", list(kind = "questionnaire", observations = ratings, features = list(), quality = list(response_count = 8),
    parameters = list(method = "typed-explicit-responses/1.0.0-draft")))
  physiology <- list(); support <- list(); parameters <- list()
  for (person in c("P1", "P2", "P3")) for (condition in c("a", "b")) {
    recording <- paste(person, condition, sep = "-")
    identity <- list(recording_id = recording, segment_id = paste0(recording, "-segment"), channel = "Cz",
      group = list(participant_id = paste0("eeg-", person), session_id = "eeg-S1", condition_id = paste0("condition-", condition), exposure_id = paste("S1", condition, sep = "-")))
    value <- if (person == "P3") NULL else if (condition == "a") 10 else if (person == "P1") 12 else 14
    physiology[[length(physiology)+1L]] <- c(identity, list(name = "alpha_absolute_power", value = value, unit = "uV^2", scope = "recording"))
    support[[length(support)+1L]] <- c(identity, list(status = if (is.null(value)) "unavailable" else "computed", retained_duration_s = if (is.null(value)) 0 else 10))
    parameters[[recording]] <- list(recipe = "eeg-welch-channel/1.0", window_s = 2, psd_unit = "V^2/Hz")
  }
  eeg_report <- make_report("report-eeg", list(kind = "eeg", features = physiology, observations = list(), recordings = support,
    quality = list(usable = TRUE), status = "partial", parameters = parameters))
  selected <- list("report-gaze", "report-rating", "report-eeg", "report-eda-missing")
  contrast <- function(id, report, modality, metric, outcome, unit) list(id = id, report_ids = list(report), modality = modality, metric = metric,
    outcome_id = outcome, unit = unit, control_id = "condition-a", test_id = "condition-b")
  contrasts <- list(contrast("gaze", "report-gaze", "gaze", "valid_gaze_share", "Logo", "percentage points"),
    contrast("liking", "report-rating", "questionnaire", "explicit_rating", "q-liking", "rating points"),
    contrast("eeg", "report-eeg", "eeg", "alpha_absolute_power", "Cz", "uV^2"),
    contrast("eda", "report-eda-missing", "eda", "tonic_mean", "EDA", "uS"))
  prepare <- function(reports = selected, walk = crosswalk, comparisons = contrasts) brohn_prepare_multimodal(store, design$id, reports, walk, comparisons,
    origin = "sample", multiplicity = list(method = "holm", alpha = .05), identity_source = "Independent synthetic crosswalk; source labels deliberately differ by modality.")
  frozen <- prepare(); input <- brohn_multimodal_input(store, frozen); report <- brohn_analyse_multimodal(input); a <- report$analysis
  get <- function(analysis, id) Filter(function(c) c$id == id, analysis$contrasts)[[1]]
  check("three usable modalities survive an absent selected report", a$quality$available_report_count == 3 && a$recordings[[4]]$status == "missing")
  check("gaze uses equal people rather than raw session rows", near(get(a, "gaze")$estimate, 30) && !near(get(a, "gaze")$estimate, 27.5) && get(a, "gaze")$participant_count == 3 && get(a, "gaze")$paired_session_count == 4)
  check("missing rating keeps its own two-person denominator", near(get(a, "liking")$estimate, 1.5) && get(a, "liking")$participant_count == 2 && get(a, "liking")$paired_session_count == 3)
  check("physiology uses only computed declared-group support", near(get(a, "eeg")$estimate, 3) && get(a, "eeg")$participant_count == 2 && get(a, "eeg")$paired_session_count == 2)
  check("missing modality is unavailable rather than zero", is.null(get(a, "eda")$estimate) && get(a, "eda")$participant_count == 0 && get(a, "eda")$status == "unavailable")
  # Independent closed-form Student distributions: df=2 tail 1-t/sqrt(t^2+2),
  # df=1 two-sided tail 1-2 atan(t)/pi. Gaze person differences are 20,25,45.
  p_gaze <- 1-sqrt(54/61); p_two_people <- 1-2*atan(3)/pi
  check("paired inference matches independent t-distribution oracle", near(get(a, "gaze")$p_value, p_gaze) && near(get(a, "liking")$p_value, p_two_people) && near(get(a, "eeg")$p_value, p_two_people))
  adjusted_gaze <- min(1, 4*p_gaze); adjusted_other <- min(1, max(4*p_gaze, 3*p_two_people))
  check("Holm includes unavailable hypothesis in four-test family", near(get(a, "gaze")$p_adjusted, adjusted_gaze) && near(get(a, "eeg")$p_adjusted, adjusted_other) &&
    get(a, "eda")$multiplicity$family_size == 4 && get(a, "eda")$multiplicity$available_tests == 3 && is.null(get(a, "eda")$p_adjusted))
  q975_df2 <- sqrt(2*.95^2/(1-.95^2))
  check("confidence interval uses equal-person variance and explicit unadjusted scope", near(get(a, "gaze")$interval95$lower, 30-q975_df2*sqrt(175/3)) && grepl("Unadjusted", get(a, "gaze")$interval95$method))
  check("every observation retains source report row hash and eligibility", all(vapply(a$observations, function(r) nchar(r$source_report_hash) == 64 && nchar(r$source_row_hash) == 64 &&
    brohn_number(r$source_row, 1, integer = TRUE) && is.logical(r$eligible), logical(1))))
  check("rating omission remains typed missing and never zero", any(vapply(a$observations, function(r) r$modality == "questionnaire" && is.null(r$value) && !r$eligible, logical(1))))
  check("no cross-modal complete-case filter or composite score", identical(a$quality$cross_modal_complete_case_filter, FALSE) && !any(grepl("composite|engagement", vapply(a$features, `[[`, character(1), "metric"))))
  no_link <- brohn_analyse_multimodal(brohn_multimodal_input(store, prepare(walk = list())))$analysis
  check("matching source labels never create automatic people links", no_link$quality$eligible_observation_count == 0 && all(vapply(no_link$contrasts, function(c) c$participant_count == 0, logical(1))))
  just_gaze <- Filter(function(c) c$report_id == "report-gaze", crosswalk)
  gaze_only_links <- brohn_analyse_multimodal(brohn_multimodal_input(store, prepare(walk = just_gaze)))$analysis
  check("unlinked other measures cannot delete eligible gaze people", get(gaze_only_links, "gaze")$participant_count == 3 && near(get(gaze_only_links, "gaze")$estimate, 30) && get(gaze_only_links, "liking")$participant_count == 0)
  altered <- input; altered$sources[[3]]$body$analysis$features[[1]]$value <- 999
  failed_eeg <- brohn_analyse_multimodal(altered)$analysis
  check("changed pinned EEG report is isolated as integrity issue", failed_eeg$recordings[[3]]$status == "integrity_issue" && get(failed_eeg, "eeg")$participant_count == 0 && get(failed_eeg, "gaze")$participant_count == 3 && get(failed_eeg, "liking")$participant_count == 2)
  check("unavailable changed report remains in multiplicity family", get(failed_eeg, "gaze")$multiplicity$family_size == 4)
  catalog <- brohn_multimodal_catalog(store, design$id, selected, "sample")
  check("catalog exposes readable measures and unconfirmed identity proposals", length(catalog$metrics) == 3 && length(catalog$identities) > 0 && all(vapply(catalog$identities, function(i) identical(i$confirmed, FALSE), logical(1))))
  check("catalog identity proposals cannot be mistaken for reviewed crosswalk", rejects(prepare(walk = catalog$identities)))
  duplicated <- c(crosswalk, crosswalk[1])
  check("duplicate source-person mappings rejected", rejects(prepare(walk = duplicated)))
  bad <- contrasts; bad[[1]]$unit <- "unknown_unit"
  wrong_units <- brohn_analyse_multimodal(brohn_multimodal_input(store, prepare(comparisons = bad)))$analysis
  check("unknown units cannot silently match a known measure", get(wrong_units, "gaze")$participant_count == 0 && get(wrong_units, "liking")$participant_count == 2)
  check("duplicate declared hypotheses rejected", rejects(prepare(comparisons = c(contrasts, contrasts[1]))))
  # A newer report revision or later appearance of a missing report cannot alter
  # the already selected result. Existing revisions remain immutable in the store.
  revised <- gaze_report$body; revised$title <- "New report revision"; revised$analysis$observations[[2]]$valid_share_percent <- 90; revised$analysis$observations[[2]]$inside_ms <- 900
  invisible(brohn_put_entity(store, "report", gaze_report$id, revised, expected_revision = gaze_report$revision))
  pinned <- brohn_analyse_multimodal(brohn_multimodal_input(store, frozen))$analysis
  check("queued synthesis never swaps in a newer report revision", near(get(pinned, "gaze")$estimate, 30) && pinned$recordings[[1]]$revision == 1)
  missing_now <- make_report("report-eda-missing", list(kind = "eda", status = "failed", quality = list(usable = FALSE), features = list()))
  still_missing <- brohn_multimodal_input(store, frozen)
  check("report appearing after freeze remains missing for that request", still_missing$sources[[4]]$status == "missing")
  newest <- prepare()
  failed <- brohn_multimodal_input(store, newest)
  check("explicitly selected failed report has concrete unavailable status", failed$sources[[4]]$status == "unavailable")
  # Historical design remains selectable after the current study draft changes.
  changed <- design; changed$title <- "Later draft"
  invisible(brohn_put_entity(store, "study", design$id, changed, expected_revision = 1))
  historical <- prepare()
  check("historical synthesis retains the source report design version", historical$design_hash == hash && historical$design$title == design$title)
  other <- rating_report$body; other$id <- "report-other-project"
  invisible(brohn_put_entity(store, "project", "other-project", list(id = "other-project", title = "Other")))
  invisible(brohn_put_entity(store, "report", other$id, other, project_id = "other-project"))
  check("existing cross-project report is rejected before exposing status", rejects(brohn_multimodal_catalog(store, design$id, list(other$id), "sample")))
  other <- rating_report$body; other$id <- "report-other-origin"; other$origin <- "pilot"
  invisible(brohn_put_entity(store, "report", other$id, other))
  check("mixed source origins rejected", rejects(brohn_multimodal_catalog(store, design$id, list("report-rating", other$id), "sample")))
  other <- rating_report$body; other$id <- "report-other-design"; other$provenance$design <- changed; other$provenance$design_hash <- brohn_hash(changed)
  invisible(brohn_put_entity(store, "report", other$id, other))
  check("mixed frozen design versions rejected", rejects(brohn_multimodal_catalog(store, design$id, list("report-rating", other$id), "sample")))
  # Model a source definition change without allowing invalid body hashes to hide
  # the semantic conflict; two valid declared source reports are then selected.
  second_gaze <- gaze_report$body; second_gaze$id <- "report-gaze-different-recipe"
  second_gaze$analysis$parameters$method <- "brohn-adjacent-ray-ivt/0.1.0-draft"
  second_gaze$analysis$observations <- lapply(second_gaze$analysis$observations, function(r) {r$exposure_id <- paste0(r$exposure_id, "-second"); r})
  invisible(brohn_put_entity(store, "report", second_gaze$id, second_gaze))
  extra_walk <- lapply(just_gaze, function(w) {w$report_id <- second_gaze$id; w})
  new_contrast <- contrasts[[1]]; new_contrast$report_ids <- list("report-gaze", second_gaze$id)
  definitions <- brohn_analyse_multimodal(brohn_multimodal_input(store, prepare(reports = list("report-gaze", second_gaze$id), walk = c(just_gaze, extra_walk), comparisons = list(new_contrast))))$analysis
  check("incompatible gaze definitions cannot be silently pooled", definitions$contrasts[[1]]$reason == "source_measure_definitions_disagree")
  duplicate_report <- gaze_report$body; duplicate_report$id <- "report-gaze-repeated"
  invisible(brohn_put_entity(store, "report", duplicate_report$id, duplicate_report))
  duplicate_walk <- lapply(just_gaze, function(w) {w$report_id <- duplicate_report$id; w})
  new_contrast$report_ids <- list("report-gaze", duplicate_report$id)
  duplicates <- brohn_analyse_multimodal(brohn_multimodal_input(store, prepare(reports = new_contrast$report_ids, walk = c(just_gaze, duplicate_walk), comparisons = list(new_contrast))))$analysis
  check("duplicate observations across selected reports are not extra trials", duplicates$contrasts[[1]]$reason == "duplicate_or_ambiguous_observation_identity")
  one_person_walk <- Filter(function(c) c$participant_id == "P1", crosswalk)
  one_person <- brohn_analyse_multimodal(brohn_multimodal_input(store, prepare(walk = one_person_walk)))$analysis
  check("one person retains estimate but no inferential interval or p-value", get(one_person, "liking")$participant_count == 1 && near(get(one_person, "liking")$estimate, 2) && is.null(get(one_person, "liking")$interval95) && is.null(get(one_person, "liking")$p_value))
  constant <- rating_report$body; constant$id <- "report-rating-constant"
  constant$analysis$observations <- lapply(constant$analysis$observations, function(r) {r$value <- if (r$condition_id == "condition-a") 3 else 4; r$missing_reason <- NULL; r})
  invisible(brohn_put_entity(store, "report", constant$id, constant))
  constant_walk <- lapply(Filter(function(w) w$report_id == "report-rating", crosswalk), function(w) {w$report_id <- constant$id; w})
  constant_contrast <- contrasts[[2]]; constant_contrast$report_ids <- list(constant$id)
  constant_result <- brohn_analyse_multimodal(brohn_multimodal_input(store, prepare(reports = list(constant$id), walk = constant_walk, comparisons = list(constant_contrast))))$analysis$contrasts[[1]]
  check("zero between-person variance does not invent perfect significance", near(constant_result$estimate, 1) && constant_result$participant_count == 3 &&
    is.null(constant_result$p_value) && is.null(constant_result$interval95) && constant_result$reason == "zero_or_negligible_between_person_variance")
  object <- brohn_store_object(store, bytes = charToRaw("original synthetic report object"), media_type = "application/json")
  corrupted <- eeg_report$body; corrupted$id <- "report-eeg-object-corrupt"; corrupted$result_object <- object
  invisible(brohn_put_entity(store, "report", corrupted$id, corrupted))
  object_path <- brohn_object_path(store, object$hash)
  stopifnot(startsWith(normalizePath(object_path, winslash = "/"), paste0(root, "/")))
  Sys.chmod(object_path, mode = "0666"); writeBin(charToRaw("corrupt synthetic report object"), object_path)
  corrupted_walk <- lapply(crosswalk, function(w) {if (w$report_id == "report-eeg") w$report_id <- corrupted$id; w})
  corrupted_contrasts <- contrasts; corrupted_contrasts[[3]]$report_ids <- list(corrupted$id)
  corrupted_selection <- selected; corrupted_selection[[3]] <- corrupted$id
  corrupted_result <- brohn_analyse_multimodal(brohn_multimodal_input(store, prepare(reports = corrupted_selection, walk = corrupted_walk, comparisons = corrupted_contrasts)))$analysis
  check("corrupt immutable result object excludes only its source measure", corrupted_result$recordings[[3]]$status == "integrity_issue" && get(corrupted_result, "eeg")$participant_count == 0 && get(corrupted_result, "liking")$participant_count == 2)
  check("contrast explains unavailable selected source reports", length(get(corrupted_result, "eeg")$unavailable_sources) == 1 && get(corrupted_result, "eeg")$unavailable_sources[[1]]$source_report_id == corrupted$id)
  revised_aois <- design; revised_aois$title <- "Reviewed regions"; revised_aois$description <- "Post-collection curation"
  revised_aois$tags <- list("reviewed"); revised_aois$archived <- TRUE; revised_aois$stimuli[[1]]$aois[[1]]$width <- .4
  measurement_hash <- brohn_measurement_design_hash(design)
  check("explicit measurement projection excludes only harmless metadata and AOIs", identical(measurement_hash, brohn_measurement_design_hash(revised_aois)) && !identical(brohn_hash(design), brohn_hash(revised_aois)))
  changes <- list(
    function(d) {d$stimuli[[1]]$content <- "Different participant stimulus"; d},
    function(d) {d$stimuli[[1]]$duration_ms <- d$stimuli[[1]]$duration_ms+100; d},
    function(d) {d$questions[[1]]$prompt <- "A different question"; d},
    function(d) {d$conditions[[1]]$role <- "test"; d$conditions[[2]]$role <- "control"; d},
    function(d) {d$seed <- d$seed+1; d})
  check("execution content timing questions roles and allocation remain hashed", all(vapply(changes, function(change) !identical(measurement_hash, brohn_measurement_design_hash(change(design))), logical(1))))
  aoi_report <- gaze_report$body; aoi_report$id <- "report-gaze-reviewed-aois"
  aoi_report$provenance$design <- revised_aois; aoi_report$provenance$design_hash <- brohn_hash(revised_aois)
  invisible(brohn_put_entity(store, "report", aoi_report$id, aoi_report))
  compatibility_selection <- list(aoi_report$id, "report-rating")
  compatibility_walk <- lapply(Filter(function(w) w$report_id %in% c("report-gaze", "report-rating"), crosswalk), function(w) {if (w$report_id == "report-gaze") w$report_id <- aoi_report$id; w})
  compatibility_contrasts <- contrasts[1:2]; compatibility_contrasts[[1]]$report_ids <- list(aoi_report$id)
  check("default policy still refuses mixing AOI design revisions", rejects(brohn_prepare_multimodal(store, design$id, compatibility_selection, compatibility_walk, compatibility_contrasts, "sample", identity_source = "Reviewed links")))
  compatibility <- brohn_prepare_multimodal(store, design$id, compatibility_selection, compatibility_walk, compatibility_contrasts, "sample",
    identity_source = "Reviewed links and post-collection AOI curation", design_policy = "measurement_compatible_aoi_revision")
  compatible_result <- brohn_analyse_multimodal(brohn_multimodal_input(store, compatibility))$analysis
  check("explicit compatible AOI revision retains collected ratings", near(get(compatible_result, "gaze")$estimate, 30) && near(get(compatible_result, "liking")$estimate, 1.5))
  source_gaze <- Filter(function(r) r$modality == "gaze", compatible_result$observations)[[1]]
  source_rating <- Filter(function(r) r$modality == "questionnaire", compatible_result$observations)[[1]]
  check("compatible synthesis retains each full source hash and actual AOIs", identical(source_gaze$source_design_hash, brohn_hash(revised_aois)) &&
    identical(source_rating$source_design_hash, hash) && source_gaze$definition$aoi_map[[1]]$aois[[1]]$width == .4)
  mixed_versions_contrast <- contrasts[[1]]; mixed_versions_contrast$report_ids <- list("report-gaze", aoi_report$id)
  mixed_versions_walk <- c(just_gaze, Filter(function(w) w$report_id == aoi_report$id, compatibility_walk))
  mixed_versions <- brohn_prepare_multimodal(store, design$id, mixed_versions_contrast$report_ids, mixed_versions_walk, list(mixed_versions_contrast), "sample",
    identity_source = "Reviewed links", design_policy = "measurement_compatible_aoi_revision")
  mixed_result <- brohn_analyse_multimodal(brohn_multimodal_input(store, mixed_versions))$analysis$contrasts[[1]]
  check("compatible design policy cannot pool two AOI definitions", mixed_result$reason == "source_measure_definitions_disagree")
  bad_projection <- compatibility; bad_projection$measurement_design_hash <- paste(rep("0",64),collapse="")
  check("projection hash tampering cannot enable a broader design match", rejects(brohn_multimodal_input(store, bad_projection)))
  job <- brohn_queue_multimodal(store, design$id, selected, crosswalk, contrasts, "sample", identity_source = "Reviewed fictional crosswalk")
  again <- brohn_queue_multimodal(store, design$id, selected, crosswalk, contrasts, "sample", identity_source = "Reviewed fictional crosswalk")
  check("identical reviewed synthesis queues idempotently", identical(job$id, again$id) && job$operation == "analyse_multimodal")
  for (module in c("platform-methods", "platform-delivery", "platform-jobs")) source(paste0("R/", module, ".R"), encoding = "UTF-8")
  claim <- brohn_claim_job(store, "multimodal-qa", lease_seconds = 60)
  brohn_process_job(store, claim, timeout_seconds = 60)
  finished <- brohn_get_job(store, job$id)
  if (!identical(finished$status, "succeeded")) stop(paste("Multimodal saved-job failure:", brohn_json(finished$error)))
  saved <- brohn_get_entity(store, "report", finished$result$report_id)
  check("actual fenced child publishes multimodal report with independent amended estimate", saved$body$analysis$kind == "multimodal" && near(get(saved$body$analysis, "gaze")$estimate, 40))
  check("saved multimodal receipt verifies immutable result and crosswalk provenance", identical(saved$body$result_object$hash, finished$result$output_hash) &&
    identical(digest::digest(file = brohn_object_path(store, finished$result$output_hash), algo = "sha256"), finished$result$output_hash) &&
    identical(saved$body$provenance$crosswalk_hash, brohn_hash(crosswalk)))
  saved_hash <- brohn_hash(frozen)
  brohn_close_store(store); store <- brohn_open_store(file.path(root, "workspace"))
  after_restart <- brohn_analyse_multimodal(brohn_multimodal_input(store, frozen))$analysis
  check("frozen selection and independent results survive restart", identical(brohn_hash(frozen), saved_hash) && near(get(after_restart, "gaze")$estimate, 30))
  check("synthesis JSON preserves finite values and typed missingness", is.list(brohn_parse(brohn_json(report))))
  cat(sprintf("PASS: %d frozen multimodal, identity, independent inference and missing-modality checks\n", checks))
})
