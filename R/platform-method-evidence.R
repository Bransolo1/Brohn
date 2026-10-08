# Read-only academic evidence metadata. Never a science/admission/authority gate.
.brohn_me_need <- function(ok, message) if (!isTRUE(ok)) stop(message, call. = FALSE)
.brohn_me_text <- function(x, maximum = 12000L) typeof(x) == "character" && length(x) == 1L &&
  !is.na(x) && nzchar(trimws(x)) && nchar(x, type = "bytes") <= maximum && isTRUE(validUTF8(x))
.brohn_me_array <- function(x) typeof(x) == "list" && is.null(names(x))
.brohn_me_fields <- function(x, keys, label) {
  .brohn_me_need(typeof(x) == "list" && !is.null(names(x)) && !anyDuplicated(enc2utf8(names(x))) &&
    setequal(names(x), keys), paste(label, "requires exactly:", paste(keys, collapse = ", ")))
}
.brohn_me_strings <- function(x, minimum = 1L, maximum = 100L, unique = FALSE) {
  .brohn_me_need(.brohn_me_array(x) && length(x) >= minimum && length(x) <= maximum &&
    all(vapply(x, .brohn_me_text, logical(1))), "Expected a bounded array of nonempty UTF-8 strings.")
  if (unique) .brohn_me_need(!anyDuplicated(unlist(x, use.names = FALSE)), "Repeated array identities are not allowed.")
}
.brohn_me_date <- function(x) .brohn_me_text(x, 10L) && grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", x) &&
  !is.na(as.Date(x, format = "%Y-%m-%d")) && identical(format(as.Date(x), "%Y-%m-%d"), x)
.brohn_me_sha <- function(x) .brohn_me_text(x, 64L) && grepl("^[0-9a-f]{64}$", x)
.brohn_me_id <- function(x) .brohn_me_text(x, 160L) && grepl("^[a-z][a-z0-9._-]*$", x)
.brohn_me_enum <- function(x, values) .brohn_me_text(x, 160L) && x %in% values
.brohn_me_url <- function(x) .brohn_me_text(x, 2000L) && grepl("^https://[A-Za-z0-9.-]+(/[^[:space:]]*)?$", x)
.brohn_me_publication_id <- function(x) .brohn_me_text(x, 500L) &&
  grepl("^(doi:10\\.[0-9]{4,9}/[-._;()/a-z0-9:]+|pmid:[1-9][0-9]*)$", x)
.brohn_me_tree <- function(x, depth = 0L) {
  .brohn_me_need(depth < 32L, "Evidence tree exceeds its depth bound.")
  if (is.null(x)) return(invisible(TRUE))
  attrs <- attributes(x)
  .brohn_me_need(is.null(attrs) || (typeof(x) == "list" && identical(names(attrs), "names")),
    "Evidence values must be plain JSON values without classes or attributes.")
  if (typeof(x) == "list") {
    .brohn_me_need(length(x) <= 20000L, "Evidence collection exceeds its bound.")
    if (!is.null(names(x))) .brohn_me_need(!anyNA(names(x)) && all(nzchar(names(x))) &&
      all(validUTF8(names(x))) && !anyDuplicated(enc2utf8(names(x))), "Evidence object keys must be unique UTF-8 text.")
    for (item in x) .brohn_me_tree(item, depth + 1L)
    return(invisible(TRUE))
  }
  .brohn_me_need(length(x) == 1L && !is.na(x), "Evidence scalars cannot be vectors or missing values.")
  .brohn_me_need(typeof(x) %in% c("character", "logical", "integer", "double"), "Unsupported evidence value type.")
  if (typeof(x) == "character") .brohn_me_need(validUTF8(x) && nchar(x, type = "bytes") <= 2L*1024L*1024L, "Invalid or excessive UTF-8 text.")
  if (typeof(x) %in% c("integer", "double")) .brohn_me_need(is.finite(x), "Evidence numbers must be finite.")
  invisible(TRUE)
}

brohn_method_evidence_validate <- function(registry) {
  .brohn_me_tree(registry)
  .brohn_me_fields(registry, c("schema", "registry_id", "revision", "created_on", "audit_ref", "coverage", "sources", "claims"), "Evidence registry")
  .brohn_me_need(identical(registry$schema, "brohn-method-evidence/0.1") && .brohn_me_id(registry$registry_id) &&
    .brohn_me_text(registry$revision, 100L) && .brohn_me_date(registry$created_on), "Unsupported registry identity or date.")
  .brohn_me_fields(registry$audit_ref, c("path", "sha256"), "Audit reference")
  .brohn_me_need(.brohn_me_text(registry$audit_ref$path) && .brohn_me_sha(registry$audit_ref$sha256), "Audit reference needs its exact fingerprint.")
  .brohn_me_fields(registry$coverage, c("status", "exhaustive", "qualification_supported", "omitted_scope"), "Coverage")
  .brohn_me_need(identical(registry$coverage$status, "partial_option_inventory") && identical(registry$coverage$exhaustive, FALSE) &&
    identical(registry$coverage$qualification_supported, FALSE), "This schema cannot claim exhaustive coverage or qualification.")
  .brohn_me_strings(registry$coverage$omitted_scope)
  .brohn_me_need(.brohn_me_array(registry$sources) && length(registry$sources) >= 2L && length(registry$sources) <= 1000L,
    "Registry needs a bounded source array.")
  for (s in registry$sources) {
    .brohn_me_fields(s, c("id", "publication_id", "title", "authors", "year", "url", "kind", "verification"), "Academic source")
    .brohn_me_need(.brohn_me_id(s$id) && .brohn_me_publication_id(s$publication_id) &&
      .brohn_me_text(s$title) && .brohn_me_text(s$authors) && .brohn_me_url(s$url), "Academic source identity is incomplete.")
    .brohn_me_need(typeof(s$year) %in% c("double", "integer") && s$year == floor(s$year) && s$year >= 1800 && s$year <= 2100,
      "Invalid publication year.")
    .brohn_me_need(.brohn_me_enum(s$kind, c("consensus", "primary_methods", "primary_experiment", "methods_guidance", "review")),
      "Software/vendor documentation is not an academic source type in this registry.")
    v <- s$verification
    .brohn_me_fields(v, c("state", "checked_on", "record_url", "provenance", "limits"), "Source verification")
    .brohn_me_need(identical(v$state, "bibliographic_verified") && .brohn_me_date(v$checked_on) && .brohn_me_url(v$record_url) &&
      .brohn_me_text(v$provenance) && .brohn_me_text(v$limits), "Source bibliographic verification must retain scope and provenance.")
  }
  ids <- vapply(registry$sources, `[[`, character(1), "id")
  publications <- tolower(vapply(registry$sources, `[[`, character(1), "publication_id"))
  urls <- tolower(sub("/$", "", vapply(registry$sources, `[[`, character(1), "url")))
  .brohn_me_need(!anyDuplicated(ids) && !anyDuplicated(publications) && !anyDuplicated(urls),
    "Declared canonical publication IDs and source URLs must be distinct; aliases are not additional sources.")
  .brohn_me_need(.brohn_me_array(registry$claims) && length(registry$claims) >= 1L && length(registry$claims) <= 2000L, "Registry needs a bounded claim array.")
  bindings <- character()
  for (c in registry$claims) {
    .brohn_me_fields(c, c("id", "method_refs", "binding", "claim", "context", "review", "evidence", "independence", "gaps", "release_gate"), "Evidence claim")
    .brohn_me_need(.brohn_me_id(c$id), "Claim needs a stable identity.")
    .brohn_me_strings(c$method_refs, maximum = 20L, unique = TRUE)
    .brohn_me_need(all(grepl("^[a-z][a-z0-9._-]*/[0-9]+\\.[0-9]+([.][0-9]+)?(-[a-z0-9.-]+)?$", unlist(c$method_refs))),
      "Evidence lookup requires exact versioned method references.")
    b <- c$binding
    .brohn_me_fields(b, c("kind", "input_scope", "option_path", "current_value", "current_value_role", "admission", "implementation"), "Option binding")
    .brohn_me_need(.brohn_me_enum(b$kind, c("option", "template_field")) && .brohn_me_text(b$input_scope, 200L) &&
      .brohn_me_text(b$option_path, 500L) && grepl("^/[^[:space:]]+$", b$option_path) && .brohn_me_text(b$admission), "Option needs an exact scope/path and admission description.")
    .brohn_me_need(.brohn_me_enum(b$current_value_role, c("computational_default", "fixed_recipe_value", "researcher_required", "starter_default")),
      "A current setting cannot masquerade as an academically recommended value.")
    if (b$current_value_role == "researcher_required") .brohn_me_need(is.null(b$current_value), "Required researcher settings have no invented default.")
    i <- b$implementation
    .brohn_me_fields(i, c("path", "sha256", "line", "symbol"), "Implementation pointer")
    .brohn_me_need(.brohn_me_text(i$path, 500L) && !grepl("(^/|^[A-Za-z]:|\\\\|(^|/)\\.\\.(/|$))", i$path) &&
      .brohn_me_sha(i$sha256) && typeof(i$line) %in% c("double", "integer") && i$line >= 1 && i$line == floor(i$line) && .brohn_me_text(i$symbol, 200L),
      "Implementation pointer requires a repository-relative path, exact hash and location.")
    binding <- paste(unlist(c$method_refs), b$input_scope, b$option_path, sep = "\n")
    .brohn_me_need(!any(binding %in% bindings), "An exact method/option binding is duplicated.")
    bindings <- c(bindings, binding)
    .brohn_me_fields(c$claim, c("title", "statement", "observed_quantity", "estimand", "consumer_question", "nonclaims"), "Scoped claim")
    for (key in setdiff(names(c$claim), "nonclaims")) .brohn_me_need(.brohn_me_text(c$claim[[key]]), paste("Claim needs", key))
    .brohn_me_strings(c$claim$nonclaims)
    .brohn_me_fields(c$context, c("population", "task", "device", "setting", "prerequisites"), "Claim context")
    for (key in setdiff(names(c$context), "prerequisites")) .brohn_me_need(.brohn_me_text(c$context[[key]]), paste("Context needs", key))
    .brohn_me_strings(c$context$prerequisites)
    r <- c$review
    .brohn_me_fields(r, c("state", "reviewed_on", "reviewer", "applicability", "next_review_trigger"), "Review state")
    .brohn_me_need(.brohn_me_enum(r$state, c("discovered", "screened", "full_text_reviewed", "applicability_reviewed", "disputed", "superseded")) &&
      .brohn_me_date(r$reviewed_on) && .brohn_me_text(r$reviewer) && .brohn_me_text(r$next_review_trigger),
      "Unsupported review state; this schema cannot represent scientific qualification.")
    .brohn_me_need(.brohn_me_enum(r$applicability, c("unresolved", "reviewed_with_limits", "disputed", "superseded")), "Unsupported applicability status.")
    if (r$state == "applicability_reviewed") .brohn_me_need(r$applicability == "reviewed_with_limits", "Applicability review must remain bounded.")
    if (r$state %in% c("discovered", "screened", "full_text_reviewed")) .brohn_me_need(r$applicability == "unresolved", "Review depth does not automatically resolve applicability.")
    .brohn_me_need(.brohn_me_array(c$evidence) && length(c$evidence) >= 2L && length(c$evidence) <= 30L,
      "Each recorded claim needs at least two distinct academic links for bibliography completeness, not approval.")
    for (e in c$evidence) {
      .brohn_me_fields(e, c("source_id", "role", "locator", "depth", "contribution", "limits"), "Claim-to-source link")
      .brohn_me_need(.brohn_me_id(e$source_id) && e$source_id %in% ids && .brohn_me_enum(e$role, c("measurement_guidance", "measurement_limitations", "method_contrast", "method_specification", "method_evaluation", "method_comparison", "consumer_example", "design_guidance")),
        "Claim refers to an unknown source or evidence role.")
      .brohn_me_need(.brohn_me_enum(e$depth, c("abstract_screened", "selected_sections_screened", "full_text_reviewed")) &&
        .brohn_me_text(e$locator) && .brohn_me_text(e$contribution) && .brohn_me_text(e$limits), "Evidence link must retain supporting-text depth, locator and limits.")
    }
    .brohn_me_need(!anyDuplicated(vapply(c$evidence, `[[`, character(1), "source_id")), "Two links to one source do not complete a bibliography.")
    if (r$state %in% c("full_text_reviewed", "applicability_reviewed"))
      .brohn_me_need(all(vapply(c$evidence, function(e) identical(e$depth, "full_text_reviewed"), logical(1))), "A review state cannot overstate supporting-text depth.")
    .brohn_me_fields(c$independence, c("status", "detail"), "Independence")
    .brohn_me_need(.brohn_me_enum(c$independence$status, c("not_assessed", "overlap_identified", "independent_teams_screened")) &&
      .brohn_me_text(c$independence$detail), "Distinct source count cannot stand in for independent corroboration.")
    .brohn_me_strings(c$gaps)
    .brohn_me_fields(c$release_gate, c("scientific_change_requires_new_recipe", "reference_tests"), "Scientific release gate")
    .brohn_me_need(identical(c$release_gate$scientific_change_requires_new_recipe, TRUE), "Changed science requires a new recipe.")
    .brohn_me_strings(c$release_gate$reference_tests)
  }
  .brohn_me_need(!anyDuplicated(vapply(registry$claims, `[[`, character(1), "id")), "Claim identities must be unique.")
  invisible(registry)
}

.brohn_me_parse <- function(text) {
  .brohn_me_need(.brohn_me_text(text, 2L*1024L*1024L) && !startsWith(text, "\ufeff"), "Evidence JSON needs bounded UTF-8 without a BOM.")
  x <- tryCatch(jsonlite::fromJSON(text, simplifyVector = FALSE), error = function(e) stop("Evidence JSON cannot be parsed.", call. = FALSE))
  brohn_method_evidence_validate(x)
  x
}
.brohn_me_hash <- function(text) digest::digest(charToRaw(text), algo = "sha256", serialize = FALSE)
.brohn_me_ref <- function(registry, text) list(registry_id = registry$registry_id, revision = registry$revision, sha256 = .brohn_me_hash(text))
brohn_method_evidence_read <- function(path, expected_sha256 = NULL) {
  .brohn_me_need(.brohn_me_text(path, 4096L) && file.exists(path) && !isTRUE(file.info(path)$isdir), "Evidence registry file is unavailable.")
  if (!is.null(expected_sha256)) .brohn_me_need(.brohn_me_sha(expected_sha256), "Expected registry hash must be exact SHA-256.")
  con <- file(path, "rb"); on.exit(close(con), add = TRUE)
  bytes <- readBin(con, "raw", n = 2L*1024L*1024L + 1L)
  .brohn_me_need(length(bytes) > 0L && length(bytes) <= 2L*1024L*1024L && !any(bytes == as.raw(0)), "Evidence file is empty, too large or contains NUL.")
  text <- rawToChar(bytes); Encoding(text) <- "UTF-8"
  .brohn_me_need(validUTF8(text), "Evidence file contains invalid UTF-8.")
  hash <- digest::digest(bytes, algo = "sha256", serialize = FALSE)
  .brohn_me_need(is.null(expected_sha256) || identical(hash, expected_sha256), "Evidence registry bytes differ from the requested revision.")
  registry <- .brohn_me_parse(text)
  list(registry = registry, ref = .brohn_me_ref(registry, text), text = text)
}
brohn_method_evidence_find <- function(registry, method_ref, option_path = NULL) {
  brohn_method_evidence_validate(registry)
  .brohn_me_need(.brohn_me_text(method_ref, 200L) && (is.null(option_path) || .brohn_me_text(option_path, 500L)), "Choose an exact method and optional option path.")
  Filter(function(c) method_ref %in% unlist(c$method_refs) && (is.null(option_path) || identical(c$binding$option_path, option_path)), registry$claims)
}
brohn_method_evidence_card <- function(registry, claim_id) {
  brohn_method_evidence_validate(registry)
  .brohn_me_need(.brohn_me_id(claim_id), "Choose an exact claim identity.")
  found <- Filter(function(c) identical(c$id, claim_id), registry$claims)
  .brohn_me_need(length(found) == 1L, "This exact claim is not catalogued; no family evidence was substituted.")
  c <- found[[1L]]
  labels <- c(discovered = "Evidence identified; review pending", screened = "Sources screened; option review pending", full_text_reviewed = "Supporting text reviewed; applicability pending", applicability_reviewed = "Applicability reviewed with limits; no qualification", disputed = "Evidence disputed", superseded = "Historical evidence revision")
  source_cards <- lapply(c$evidence, function(e) {
    s <- registry$sources[[match(e$source_id, vapply(registry$sources, `[[`, character(1), "id"))]]
    list(source = s, role = e$role, locator = e$locator, depth = e$depth, contribution = e$contribution, limits = e$limits)
  })
  list(schema = "brohn-method-evidence-card/0.1", claim_id = c$id, method_refs = c$method_refs, binding = c$binding,
    title = c$claim$title, question = c$claim$consumer_question, observed_quantity = c$claim$observed_quantity,
    statement = c$claim$statement, estimand = c$claim$estimand, nonclaims = c$claim$nonclaims,
    evidence_label = unname(labels[[c$review$state]]), review = c$review, context = c$context,
    bibliography = list(distinct_publications = length(source_cards), completeness = "At least two distinct academic publications are linked; this is bibliography completeness only."),
    qualification = "not_supported_by_this_schema", independence = c$independence, gaps = c$gaps, sources = source_cards)
}
brohn_method_evidence_snapshot <- function(path, expected_sha256, claim_ids) {
  .brohn_me_need(.brohn_me_sha(expected_sha256), "Freezing evidence requires its exact registry hash.")
  .brohn_me_strings(claim_ids, maximum = 2000L, unique = TRUE)
  x <- brohn_method_evidence_read(path, expected_sha256)
  .brohn_me_need(all(unlist(claim_ids) %in% vapply(x$registry$claims, `[[`, character(1), "id")), "Snapshot requested an unknown claim.")
  list(schema = "brohn-method-evidence-snapshot/0.1", registry_ref = x$ref, selected_claim_ids = claim_ids, registry_text = x$text)
}
brohn_method_evidence_cards <- function(registry, method_ref, option_path = NULL) {
  found <- brohn_method_evidence_find(registry, method_ref, option_path)
  list(schema = "brohn-method-evidence-cards/0.1", status = if (length(found)) "catalogued" else "not_catalogued",
    method_ref = method_ref, option_path = option_path,
    evidence_label = if (length(found)) "Partial option evidence; no scientific qualification" else "No option evidence is catalogued for this exact method version.",
    cards = lapply(found, function(c) brohn_method_evidence_card(registry, c$id)), coverage = registry$coverage)
}
brohn_method_evidence_reopen <- function(snapshot) {
  .brohn_me_tree(snapshot)
  .brohn_me_fields(snapshot, c("schema", "registry_ref", "selected_claim_ids", "registry_text"), "Historical evidence snapshot")
  .brohn_me_need(identical(snapshot$schema, "brohn-method-evidence-snapshot/0.1"), "Unsupported evidence snapshot.")
  .brohn_me_fields(snapshot$registry_ref, c("registry_id", "revision", "sha256"), "Historical registry reference")
  .brohn_me_need(.brohn_me_sha(snapshot$registry_ref$sha256), "Historical registry reference needs an exact hash.")
  .brohn_me_strings(snapshot$selected_claim_ids, maximum = 2000L, unique = TRUE)
  registry <- .brohn_me_parse(snapshot$registry_text)
  .brohn_me_need(identical(.brohn_me_ref(registry, snapshot$registry_text), snapshot$registry_ref), "Historical evidence bytes or identity changed.")
  ids <- vapply(registry$claims, `[[`, character(1), "id")
  .brohn_me_need(all(unlist(snapshot$selected_claim_ids) %in% ids), "Historical evidence selection contains an unknown claim.")
  claims <- lapply(snapshot$selected_claim_ids, function(id) registry$claims[[match(id, ids)]])
  source_ids <- unique(unlist(lapply(claims, function(c) lapply(c$evidence, `[[`, "source_id"))))
  list(registry_ref = snapshot$registry_ref, claims = claims,
    sources = Filter(function(s) s$id %in% source_ids, registry$sources), coverage = registry$coverage)
}
