# Current configuration guidance only. Existing mapping and worker functions own
# defaults, null semantics and admission; this file never resolves their inputs.
brohn_method_evidence_config_ui <- function(method_ref, context = NULL, state = NULL) {
  shiny::div(class = "brohn-method-evidence-config",
    brohn_method_evidence_task_style(),
    if (!is.null(context)) shiny::p(class = "brohn-muted", context),
    brohn_method_evidence_task_ui(method_ref, state = state))
}

brohn_method_evidence_selector_ui <- function(input_id, method_refs, state = NULL) {
  stopifnot(is.character(input_id), length(input_id) == 1L,
    grepl("^[A-Za-z][A-Za-z0-9_]*$", input_id),
    is.character(method_refs), length(method_refs) > 0L,
    !anyNA(method_refs), !anyDuplicated(method_refs))
  # Conditions read the live selector. There is deliberately no saved/draft
  # fallback: the selector's original code, not guidance, chooses its default.
  input <- paste0("input.", input_id)
  quoted <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE))
  choices <- as.character(jsonlite::toJSON(unname(method_refs)))
  shiny::div(class = "brohn-method-evidence-selector", `data-evidence-input` = input_id,
    lapply(unname(method_refs), function(ref) shiny::conditionalPanel(
      paste(input, "===", quoted(ref)),
      brohn_method_evidence_config_ui(ref,
        "Guidance follows the selected procedure. Your chosen numerical settings still need review.", state))),
    shiny::conditionalPanel(paste0("!", input),
      shiny::p(class = "brohn-muted", "Choose a procedure to see its current academic guidance.")),
    shiny::conditionalPanel(paste0(input, " && ", choices, ".indexOf(", input, ") === -1"),
      shiny::p(class = "brohn-muted", "No academic guidance is linked here for this selected procedure version. Guidance from another version does not apply.")))
}

brohn_method_evidence_cardiac_mapping_ui <- function(modality, state = NULL) {
  stopifnot(modality %in% c("ecg", "ppg"))
  # Confirm mapping rebuilds ECG/PPG metadata without parameters. These exact
  # refs describe that current worker default, not an arbitrary saved mapping.
  ref <- if (modality == "ecg") "ecg-neurokit-detected-rr/1.0" else "ppg-elgendi-detected-prv/1.0"
  shiny::tagList(
    shiny::h3(if (modality == "ecg") "Detected ECG RR intervals" else "PPG pulse-rate variability (PRV)"),
    shiny::p(if (modality == "ecg")
      "Detected RR intervals are not confirmed normal-to-normal (NN) intervals." else
      "PRV describes detected pulse intervals; it is not ECG heart-rate variability."),
    brohn_method_evidence_config_ui(ref,
      "Current procedure used by Confirm mapping and analyse. This guidance does not describe a different saved mapping.", state))
}

brohn_method_evidence_mapping_actions_ui <- function() shiny::p(class = "brohn-muted",
  "Confirm mapping and analyse uses these controls. Run a new analysis uses the last confirmed mapping, including its saved procedure and settings.")
