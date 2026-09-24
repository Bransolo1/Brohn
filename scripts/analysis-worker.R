args <- commandArgs(trailingOnly = TRUE)
arg <- function(name) {i <- match(name, args); if (is.na(i) || i == length(args)) stop("Missing ", name); args[[i+1L]]}
sources <- paste0("R/", c("platform-core", "platform-question-materials", "platform-welcome", "platform-store", "platform-publication", "platform-methods", "platform-delivery", "platform-analysis", "platform-gaze", "platform-vision", "platform-neural", "platform-multimodal", "platform-jobs"), ".R")
for (optional in c("R/platform-analysis-plan.R", "R/platform-eda-events.R", "R/platform-headers.R", "R/platform-physiology-artifacts.R", "R/platform-signal.R", "R/platform-task-delivery.R", "R/platform-backup.R", "R/platform-interchange.R")) if (file.exists(optional)) sources <- c(sources, optional)
if (file.exists("R/platform-capture.R")) sources <- c(sources, "R/platform-capture.R")
sources <- c(sources, "R/platform-participant-equipment.R")
sources <- c(sources, "R/platform-peripheral.R", "R/platform-peripheral-synthesis.R")
sources <- c(sources, "R/platform-ingestion.R")
if (file.exists("R/platform-scales.R")) sources <- c(sources, "R/platform-scales.R")
sources <- c(sources, "R/platform-question-sections.R")
sources <- c(sources, "R/platform-question-revision.R", "R/platform-question-revision-delivery.R")
sources <- c(sources, "R/platform-run-evidence.R", "R/platform-questionnaire-artifacts.R", "R/platform-questionnaire-artifact-storage.R")
sources <- c(sources, "R/platform-questionnaire-index.R", "R/platform-questionnaire-explorer.R")
sources <- c(sources, "R/platform-explicit-distributions.R")
sources <- c(sources, "R/platform-vision-explorer.R", "R/platform-vision-frame.R")
sources <- c(sources, "R/platform-signal-values.R")
sources <- c(sources, "R/platform-gaze-traces.R", "R/platform-gaze-retention.R", "R/platform-gaze-trace-views.R", "R/platform-gaze-trace-jobs.R")
sources <- c(sources, "R/platform-signal-annotations.R", "R/platform-signal-reuse.R", "R/platform-cardiac-review.R")
sources <- c(sources, "R/platform-task-import.R", "R/platform-task-import-storage.R")
sources <- c(sources, "R/platform-task-cohort.R", "R/platform-task-cohort-storage.R")
if (file.exists("R/platform-scale-comparisons.R")) sources <- c(sources, "R/platform-scale-comparisons.R")
if (file.exists("R/platform-maxdiff.R")) sources <- c(sources, "R/platform-maxdiff.R", "R/platform-maxdiff-platform.R", "R/platform-maxdiff-import.R")
hash_sources <- function(paths) setNames(lapply(paths, function(p) digest::digest(file = p, algo = "sha256")), paths)
identity <- hash_sources(c("scripts/analysis-worker.R", sources))
for (path in sources) source(path, encoding = "UTF-8")
input <- brohn_read_json_file(arg("--request"))
if (identical(input$operation,"answer_session")) {
  identity <- c(identity, hash_sources("R/platform-answer-session.R"))
  source("R/platform-answer-session.R", encoding="UTF-8")
}
if (input$operation %in% c("audio_tracks","audio_extract") || !is.null(input$derived_audio_lineage) || !is.null(input$binding$extraction_lineage)) {
  identity <- c(identity, hash_sources("R/platform-audio-extraction.R"))
  source("R/platform-audio-extraction.R", encoding="UTF-8")
}
if (identical(input$operation, "audio_review")) {
  identity <- c(identity, hash_sources("R/platform-audio-review.R"))
  source("R/platform-audio-review.R", encoding = "UTF-8")
}
if (identical(input$operation, "eda_review")) {
  identity <- c(identity, hash_sources("R/platform-eda-review.R"))
  source("R/platform-eda-review.R", encoding="UTF-8")
}
if (identical(input$operation,"respiration_review")) {
  identity <- c(identity, hash_sources("R/platform-respiration-review.R"))
  source("R/platform-respiration-review.R", encoding="UTF-8")
}
if (identical(input$operation,"emg_review")) {
  identity <- c(identity, hash_sources("R/platform-emg-review.R"))
  source("R/platform-emg-review.R", encoding="UTF-8")
}
if (identical(input$operation,"eda_continuous_review")) {
  identity <- c(identity, hash_sources("R/platform-eda-continuous-review.R"))
  source("R/platform-eda-continuous-review.R", encoding="UTF-8")
}
if (identical(input$operation, "analyse_resolved_run")) {
  identity <- c(identity, hash_sources("R/platform-session-resolution.R"))
  source("R/platform-session-resolution.R", encoding = "UTF-8")
}
if (identical(input$operation, "linked_review")) {
  identity <- c(identity, hash_sources("R/platform-linked-review.R"))
  source("R/platform-linked-review.R", encoding = "UTF-8")
}
if (!is.null(input$run_evidence)) input <- brohn_read_run_evidence_input(input, arg("--scratch"))
if (identical(input$operation, "extract_stream")) {
  identity <- c(identity, hash_sources("R/platform-stream-curation.R"))
  source("R/platform-stream-curation.R", encoding = "UTF-8")
}
native_sources <- if (identical(input$operation, "segment_aoi") || identical(input$dataset$modality, "video")) "scripts/workers/vision.py" else
  if (input$operation %in% c("audio_tracks","audio_extract")) "scripts/workers/audio_extract.py" else
  if (identical(input$operation, "audio_review")) "scripts/workers/audio_review.py" else
  if (identical(input$operation, "eda_review")) c("scripts/workers/eda_review.py", "scripts/workers/physiology_artifacts.py") else
  if (identical(input$operation, "respiration_review")) c("scripts/workers/respiration_review.py", "scripts/workers/physiology_artifacts.py") else
  if (identical(input$operation, "emg_review")) c("scripts/workers/emg_review.py", "scripts/workers/physiology_artifacts.py") else
  if (identical(input$operation, "eda_continuous_review")) c("scripts/workers/eda_continuous_review.py", "scripts/workers/physiology_artifacts.py") else
  if (identical(input$operation, "linked_review")) c("scripts/workers/linked_review.py", "scripts/workers/stream_extract.py") else
  if (identical(input$operation, "vision_index")) "scripts/workers/vision_explorer.py" else
  if (identical(input$operation, "vision_frame")) c("scripts/workers/vision_frame.py", "scripts/workers/vision.py", "scripts/workers/vision_explorer.py") else
  if (brohn_gaze_retention_enabled(input) || input$operation %in% c("gaze_trace_catalog", "gaze_trace_preview")) c("scripts/workers/gaze_trace.py", "scripts/workers/physiology_artifacts.py") else
  if (identical(input$operation, "ingest_source")) "scripts/workers/ingestion_snapshot.py" else
  if (identical(input$operation, "extract_stream")) "scripts/workers/stream_extract.py" else
  if (input$operation %in% c("normalise_dataset", "import_multistream")) "scripts/workers/interchange.py" else
  if (input$operation %in% c("signal_values_page", "signal_values_export")) c("scripts/workers/signal_values.py", "scripts/workers/signal_preview.py", "scripts/workers/physiology_artifacts.py") else
  if (input$operation %in% c("signal_catalog", "signal_preview")) c("scripts/workers/signal_preview.py", "scripts/workers/physiology_artifacts.py") else
  if (identical(input$operation, "summarize_signal_windows")) c("scripts/workers/signal_windows.py", "scripts/workers/signal_preview.py", "scripts/workers/physiology_artifacts.py") else
  if (input$operation %in% c("preview_cardiac_review", "reanalyse_cardiac")) c("scripts/workers/cardiac_review.py", "scripts/workers/physiology.py", "scripts/workers/signal_preview.py", "scripts/workers/physiology_artifacts.py") else
  if (identical(input$operation, "inspect_header")) "scripts/workers/headers.py" else
  if (identical(input$operation, "analyse_dataset") && input$dataset$modality %in% c("temperature", "movement")) c("scripts/workers/peripheral.py", "scripts/workers/physiology_artifacts.py") else
  if (identical(input$operation, "analyse_dataset") && !input$dataset$modality %in% c("gaze", "prepared_gaze", "questionnaire", "maxdiff", "implicit")) {
    c("scripts/workers/physiology.py", "scripts/workers/physiology_artifacts.py", if (identical(input$dataset$modality, "eeg") && brohn_neural_is_epoch(input$dataset$metadata)) "scripts/workers/neural.py",
      if (identical(input$dataset$modality, "eeg")) "scripts/workers/headers.py",
      if (identical(input$dataset$modality, "eda") && brohn_eda_events_is_event(input$dataset$metadata)) "scripts/workers/eda_events.py")
  } else character()
identity <- c(identity, hash_sources(unique(c(native_sources, "scripts/workers/publication.py", "src/publication_guard.c"))))
result <- brohn_analyse_input(input, arg("--scratch"))
result <- brohn_pack_questionnaire_report(result, arg("--scratch"))
brohn_require(identical(identity, hash_sources(names(identity))), "Analysis implementation changed while this job was running. Retry with a stable installation; the source is preserved.")
brohn_write_json_file(list(schema = "brohn-analysis-output/1.0", code_identity = identity, report = result), arg("--output"))
