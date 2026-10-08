# Inactive pure domain slice. No core override, loader registration or store IO.
.brohn_med_fields <- function(x) {
  .brohn_meb_domain(x)
  brohn_fields(x, c("schema_version", "id", "project_id", "title", "description", "template", "archived", "tags",
    "conditions", "stimuli", "questions", "order", "seed", "baseline_ms", "fixation_ms", "instructions", "consent",
    "debrief", "appearance", "measures", "methods", "blocks", "lineage", "method_evidence", "method_evidence_implementations"),
    optional = c("analysis_plan", "camera", "scales", "maxdiff", "questionnaire_sections", "questionnaire_navigation", "welcome", "participant_equipment"),
    label = "Evidence design")
  brohn_require(identical(x$schema_version, "brohn-design/1.1.0"), "This route requires an explicit evidence design1.1.")
  invisible(TRUE)
}
.brohn_med_operational <- function(x, publish = FALSE) {
  .brohn_med_fields(x)
  legacy <- x
  legacy$method_evidence <- legacy$method_evidence_implementations <- NULL
  legacy$schema_version <- "brohn-design/1.0.0"
  brohn_validate_design(legacy, publish = publish)
  invisible(legacy)
}
.brohn_med_codecs <- function(x) {
  .brohn_meb_domain(x)
  target <- brohn_method_evidence_tag(x)
  for (encode in list(brohn_json, .brohn_store_json)) {
    text <- encode(x)
    brohn_require(is.character(text) && length(text) == 1L && !is.na(text) && validUTF8(text) &&
      nchar(text, type = "bytes") <= 16 * 1024^2, "The complete evidence design exceeds the16 MiB codec limit.")
    decoded <- jsonlite::fromJSON(text, simplifyVector = FALSE)
    brohn_require(identical(target, brohn_method_evidence_tag(decoded)),
      "The complete evidence design does not survive its stored JSON codecs exactly.")
  }
  invisible(TRUE)
}
brohn_validate_evidence_design <- function(design, publish = FALSE) {
  brohn_require(is.logical(publish) && length(publish) == 1L && !is.na(publish), "Declare the design validation mode.")
  .brohn_med_operational(design, publish)
  brohn_method_evidence_inventory_validate(design$method_evidence_implementations, design$method_evidence)
  current <- design$method_evidence$current
  context <- brohn_method_evidence_untag(current$context)
  brohn_method_evidence_binding_matches(current, design$blocks, context)
  .brohn_med_codecs(design)
  invisible(design)
}
.brohn_med_identity <- function(identity) {
  fields <- c("manifest", "implementation_ref", "commit_check", "bind")
  brohn_require(is.environment(identity) && environmentIsLocked(identity) &&
    setequal(ls(identity, all.names = TRUE), fields) &&
    all(vapply(fields, function(n) bindingIsLocked(n, identity) && is.function(get(n, identity, inherits = FALSE)), logical(1))),
    "Prospective preparation needs the loader-owned identity facade, not request JSON.")
  manifest <- identity$manifest()
  brohn_method_evidence_manifest_validate(manifest)
  brohn_require(.brohn_meb_equal(identity$implementation_ref(), .brohn_mei_ref(manifest)), "Identity facade and manifest differ.")
  identity$commit_check()
  invisible(manifest)
}
.brohn_med_inventory <- function(wrapper, old, identity) {
  manifests <- if (is.null(old)) list() else lapply(old$entries, `[[`, "manifest")
  manifests <- c(manifests, list(identity$manifest()))
  required <- .brohn_mei_required(wrapper)
  manifests <- Filter(function(m) brohn_method_evidence_manifest_hash(m) %in% required, manifests)
  brohn_method_evidence_inventory(manifests, wrapper)
}
brohn_new_evidence_design <- function(identity, registry_capture, context, captured_at,
    title = "Untitled study", template = "comparison", id = brohn_id("study"), project_id = "default") {
  .brohn_med_identity(identity)
  design <- brohn_new_design(title, template, id, project_id)
  brohn_validate_design(design)
  current <- identity$bind(design$blocks, context, registry_capture, captured_at)
  design$schema_version <- "brohn-design/1.1.0"
  design$method_evidence <- brohn_method_evidence_envelope(current)
  design$method_evidence_implementations <- .brohn_med_inventory(design$method_evidence, NULL, identity)
  brohn_validate_evidence_design(design)
  identity$commit_check()
  design
}
.brohn_med_ref <- function(ref, design) {
  .brohn_meb_domain(ref)
  brohn_fields(ref, c("kind", "id", "project_id", "revision", "body_hash"), label = "Original study reference")
  brohn_require(identical(ref$kind, "study") && brohn_valid_id(ref$id) && brohn_valid_id(ref$project_id) &&
    brohn_number(ref$revision, 1, .Machine$integer.max, TRUE) && .brohn_mei_sha(ref$body_hash) &&
    identical(ref$id, design$id) && identical(ref$project_id, design$project_id), "Original reference does not match the supplied study identity.")
  invisible(TRUE)
}
brohn_prepare_evidence_design <- function(identity, original, expected_ref, draft, captured_at,
    context = NULL, registry_capture = NULL) {
  .brohn_med_identity(identity)
  brohn_validate_evidence_design(original)
  .brohn_med_ref(expected_ref, original)
  brohn_require(!isTRUE(original$archived), "Restore the study before preparing edits.")
  .brohn_med_operational(draft)
  brohn_require(identical(draft$id, original$id) && identical(draft$project_id, original$project_id) &&
    identical(draft$archived, original$archived), "Save preparation cannot move, archive or replace the study identity.")
  brohn_require(.brohn_meb_equal(draft$method_evidence, original$method_evidence) &&
    .brohn_meb_equal(draft$method_evidence_implementations, original$method_evidence_implementations),
    "Editable input cannot replace the saved evidence or inherited implementation inventory.")
  previous <- original$method_evidence$current
  if (is.null(context)) context <- brohn_method_evidence_untag(previous$context)
  if (is.null(registry_capture)) registry_capture <- previous$registry_capture
  old_registry <- .brohn_meb_registry(previous$registry_capture)
  proposed_registry <- .brohn_meb_registry(registry_capture)
  brohn_require(.brohn_meb_equal(old_registry$ref, proposed_registry$ref), "Ordinary Save must retain the exact saved registry pin.")
  current <- identity$bind(draft$blocks, context, registry_capture, captured_at, previous = previous)
  candidate <- draft
  candidate$method_evidence <- brohn_method_evidence_envelope_update(original$method_evidence, current)
  candidate$method_evidence_implementations <- .brohn_med_inventory(candidate$method_evidence, original$method_evidence_implementations, identity)
  brohn_validate_evidence_design(candidate)
  identity$commit_check()
  original_hash <- brohn_method_evidence_design_value_hash(original)
  candidate_hash <- brohn_method_evidence_design_value_hash(candidate)
  changed <- !identical(original_hash, candidate_hash)
  # In-process copied values only. Caller owns the actual authorized source read
  # and must run check_current on a fresh read within its later transaction.
  state <- new.env(parent = emptyenv())
  state$identity <- identity; state$original_hash <- original_hash
  state$expected_ref <- expected_ref; state$candidate <- candidate; state$changed <- changed
  lockEnvironment(state, bindings = TRUE)
  plan <- new.env(parent = emptyenv())
  plan$candidate <- function() state$candidate
  plan$expected_ref <- function() state$expected_ref
  plan$changed <- function() state$changed
  plan$check_current <- function(ref, design) {
    .brohn_med_ref(ref, design)
    brohn_require(.brohn_meb_equal(ref, state$expected_ref), "The study revision changed; prepare the save again.")
    brohn_validate_evidence_design(design)
    brohn_require(identical(brohn_method_evidence_design_value_hash(design), state$original_hash),
      "The original study value changed; prepare the save again.")
    state$identity$commit_check()
    invisible(TRUE)
  }
  lockEnvironment(plan, bindings = TRUE)
  lockEnvironment(environment(plan$check_current), bindings = TRUE)
  plan
}
