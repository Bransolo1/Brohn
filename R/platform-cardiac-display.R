# Saved cardiac display requests. This candidate is not registered in the app.
# Time bounds reuse the existing exact-decimal transport, never signal analysis.
.brohn_cdd_profile <- "saved-cardiac-display/0.1"
.brohn_cdd_policy <- "cardiac-readable-pages/0.1"
.brohn_cdd_request_bytes <- 2 * 1024^2
.brohn_cdd_explicit_pages <- 20000L

.brohn_cdd_request_limit <- function(resource, measured, maximum, request_hash) {
  brohn_require(.brohn_rpk_hash(request_hash), "A display refusal needs its exact input identity.")
  refusal <- list(schema="brohn-cardiac-report-refusal/0.1",
    reason_code=paste0(resource, "_limit"), stage="metadata",
    source_ref=NULL, cell_key=NULL, resource=resource, measured=measured,
    maximum=maximum, recovery_scope="fewer_figures",
    blocked_request_hash=request_hash, message="Choose fewer explicit display pages.")
  stop(structure(list(message=refusal$message, call=NULL, refusal=refusal),
    class=c("brohn_cardiac_refusal", "error", "condition")))
}

.brohn_cdd_page_policy <- function(value, label="Saved display pages") {
  brohn_fields(value, c("mode", "numbers"), label=label)
  brohn_require(brohn_text(value$mode, 20) && value$mode %in% c("first", "all", "selected") &&
    brohn_array(value$numbers) && length(value$numbers) <= .brohn_cdd_explicit_pages,
    "Choose a bounded first, all or explicit page selection.")
  brohn_require(identical(value$mode == "selected", length(value$numbers) > 0L),
    "Only an explicit page selection can contain page numbers.")
  brohn_require(all(vapply(value$numbers, function(n) brohn_number(n, 1, 2^53-1, TRUE), logical(1))),
    "Page numbers must be positive exact integers, not text or booleans.")
  numbers <- vapply(value$numbers, as.double, numeric(1))
  brohn_require(!anyDuplicated(numbers), "Select each display page once.")
  list(mode=value$mode, numbers=as.list(sort(numbers)))
}

.brohn_cdd_figure_cells <- function(value) {
  brohn_fields(value, c("scope", "keys"), label="Cardiac figure cells")
  brohn_require(brohn_text(value$scope, 30) && value$scope %in%
      c("first_chapter", "all_cells", "exact_cells", "no_cells") &&
      brohn_array(value$keys) && length(value$keys) <= 2000L,
    "Choose a bounded cardiac figure chapter or exact cell selection.")
  brohn_require(identical(value$scope == "exact_cells", length(value$keys) > 0L),
    "Only an exact cell selection can contain cell keys.")
  brohn_require(all(vapply(value$keys, .brohn_rpk_hash, logical(1))),
    "Choose complete original cardiac cell keys.")
  keys <- vapply(value$keys, identity, character(1))
  brohn_require(!anyDuplicated(keys), "Select each cardiac figure cell once.")
  list(scope=value$scope, keys=as.list(sort(keys, method="radix")))
}

brohn_normalize_cardiac_display_request <- function(request=NULL) {
  if (is.null(request)) return(list(schema="brohn-cardiac-display-request/0.1",
    policy=.brohn_cdd_policy, figure_cells=list(scope="first_chapter", keys=list()),
    cell_overrides=list()))
  brohn_fields(request, c("schema", "policy", "figure_cells", "cell_overrides"),
    label="Cardiac saved-display request")
  brohn_require(identical(request$schema, "brohn-cardiac-display-request/0.1") &&
      identical(request$policy, .brohn_cdd_policy) && brohn_array(request$cell_overrides) &&
      length(request$cell_overrides) <= 2000L,
    "Choose the registered, bounded cardiac display policy.")
  figures <- .brohn_cdd_figure_cells(request$figure_cells)
  fields <- c("waveform_windows", "marker_pages", "interval_pages", "numerical_pages")
  total_pages <- 0L
  overrides <- lapply(request$cell_overrides, function(x) {
    brohn_fields(x, c("cell_key", "time_focus", fields), label="Cardiac cell display choices")
    brohn_require(.brohn_rpk_hash(x$cell_key), "Choose an exact original cardiac cell key.")
    focus <- NULL
    if (!is.null(x$time_focus)) {
      brohn_fields(x$time_focus, c("start_s", "end_s"), label="Exact cardiac time focus")
      start <- .brohn_edd_decimal_parts(x$time_focus$start_s)$canonical
      end <- .brohn_edd_decimal_parts(x$time_focus$end_s)$canonical
      brohn_require(brohn_eda_decimal_compare(start, end) < 0L,
        "The cardiac source-window end must follow its start.")
      focus <- list(start_s=start, end_s=end)
    }
    policies <- stats::setNames(lapply(fields, function(k) .brohn_cdd_page_policy(x[[k]])), fields)
    total_pages <<- total_pages + sum(vapply(policies, function(v) length(v$numbers), integer(1)))
    if (!is.null(focus) && identical(policies$waveform_windows$mode, "selected"))
      brohn_require(identical(policies$waveform_windows$numbers, list(1)),
        "An explicit time focus has exactly one waveform window.")
    c(list(cell_key=x$cell_key, time_focus=focus), policies)
  })
  keys <- vapply(overrides, `[[`, character(1), "cell_key")
  brohn_require(!anyDuplicated(keys), "A cardiac cell can have only one display override.")
  normalized <- list(schema=request$schema, policy=request$policy,
    figure_cells=figures, cell_overrides=overrides[order(keys, method="radix")])
  # The public text entry point below applies the raw byte bound before parsing.
  # This structured entry point receives already parsed application records; the
  # normalized byte and aggregate-selection bounds still apply before queueing.
  text <- brohn_json(normalized)
  bytes <- nchar(enc2utf8(text), type="bytes")
  hash <- digest::digest(charToRaw(enc2utf8(text)), algo="sha256", serialize=FALSE)
  if (bytes > .brohn_cdd_request_bytes)
    .brohn_cdd_request_limit("display_request_bytes", bytes, .brohn_cdd_request_bytes, hash)
  if (total_pages > .brohn_cdd_explicit_pages)
    .brohn_cdd_request_limit("display_page_selection_count", total_pages, .brohn_cdd_explicit_pages, hash)
  normalized
}

brohn_parse_cardiac_display_request <- function(text) {
  brohn_require(is.character(text) && length(text) == 1L && !is.na(text) &&
    !is.na(iconv(text, from="", to="UTF-8", sub=NA)), "Provide one valid UTF-8 display request.")
  bytes <- nchar(enc2utf8(text), type="bytes")
  if (bytes > .brohn_cdd_request_bytes) {
    hash <- digest::digest(charToRaw(enc2utf8(text)), algo="sha256", serialize=FALSE)
    .brohn_cdd_request_limit("display_request_bytes", bytes, .brohn_cdd_request_bytes, hash)
  }
  brohn_normalize_cardiac_display_request(brohn_parse(text, .brohn_cdd_request_bytes))
}

.brohn_cdd_cell_defaults <- function(key) {
  brohn_require(.brohn_rpk_hash(key), "Choose an exact original cardiac cell key.")
  page <- function(mode) list(mode=mode, numbers=list())
  list(cell_key=key, time_focus=NULL, waveform_windows=page("first"),
    marker_pages=page("all"), interval_pages=page("first"), numerical_pages=page("first"))
}

brohn_normalize_cardiac_figure_chapters <- function(value=NULL) {
  if (is.null(value)) value <- list(schema="brohn-cardiac-figure-chapters/0.1",
    cells_per_chapter=10, chapters=list(mode="first", numbers=list()))
  brohn_fields(value, c("schema", "cells_per_chapter", "chapters"), label="Cardiac report chapters")
  brohn_require(identical(value$schema, "brohn-cardiac-figure-chapters/0.1") &&
    brohn_number(value$cells_per_chapter, 10, 10, TRUE), "Choose the registered ten-cell chapter policy.")
  list(schema=value$schema, cells_per_chapter=10,
    chapters=.brohn_cdd_page_policy(value$chapters, "Cardiac figure chapters"))
}
