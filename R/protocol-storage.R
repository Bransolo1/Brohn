# Snapshots are never replaced. Re-saving identical content is an idempotent read.
read_protocol <- function(path, max_bytes = draft_size_limit) {
  record_assert(scalar_text(path) && file.exists(path) && !dir.exists(path), "Choose a saved protocol file.")
  record_assert(positive_integer(max_bytes) && max_bytes <= draft_size_limit, "Protocol size limit must be at most 16 MiB.")
  connection <- file(path, "rb")
  on.exit(close(connection), add = TRUE)
  bytes <- readBin(connection, "raw", n = max_bytes + 1)
  record_assert(length(bytes) > 0 && length(bytes) <= max_bytes, "Protocol file is empty or exceeds the size limit.")
  record_assert(!any(bytes == as.raw(0)), "Protocol must not contain NUL bytes.")
  text <- rawToChar(bytes)
  Encoding(text) <- "UTF-8"
  record_assert(!is.na(iconv(text, from = "UTF-8", to = "UTF-8", sub = NA)), "Protocol must contain valid UTF-8.")
  protocol_from_json(text)
}

save_protocol <- function(protocol, path) {
  text <- protocol_to_json(protocol, pretty = TRUE)
  record_assert(nchar(enc2utf8(text), type = "bytes") <= draft_size_limit, "Protocol exceeds 16 MiB.")
  record_assert(scalar_text(path) && dir.exists(dirname(path)), "Choose an existing protocol folder.")
  path <- file.path(normalizePath(dirname(path), winslash = "/", mustWork = TRUE), basename(path))
  lock <- paste0(path, ".lock")
  record_assert(dir.create(lock, showWarnings = FALSE), "Another save holds the protocol lock. Retry after it finishes.")
  on.exit(unlink(lock, recursive = TRUE), add = TRUE)
  if (file.exists(path)) {
    previous <- read_protocol(path)
    record_assert(identical(protocol_to_json(previous), protocol_to_json(protocol)),
      "A different protocol already exists here. Saved snapshots cannot be replaced.")
    return(invisible(path))
  }
  .atomic_draft_replace(text, path)
  invisible(path)
}

save_draft_protocol <- function(bundle, draft_path) {
  protocol <- create_protocol(bundle)
  directory <- paste0(draft_path, ".protocols")
  if (!dir.exists(directory)) record_assert(dir.create(directory), "Could not create the protocol folder.")
  path <- file.path(directory, paste0(protocol$content_sha256, ".json"))
  save_protocol(protocol, path)
  protocol
}

open_draft_protocol <- function(bundle, draft_path) {
  if (is.null(draft_path) || !dir.exists(paste0(draft_path, ".protocols")) ||
      length(bundle$study$stimulus_assets) != 2) return(NULL)
  current <- create_protocol(bundle)
  path <- file.path(paste0(draft_path, ".protocols"), paste0(current$content_sha256, ".json"))
  if (!file.exists(path)) return(NULL)
  saved <- read_protocol(path)
  record_assert(identical(saved$content_sha256, current$content_sha256), "Saved protocol does not match this draft.")
  saved
}

protocol_snapshot_ui <- function(bundle, protocol) {
  shiny::div(class = "panel", shiny::span(class = "eyebrow", "PROTOCOL SNAPSHOT"),
    shiny::h2("Keep a fixed copy of this plan."),
    shiny::p("Save the images, controls, questions and planned sequence together. Later draft edits leave this copy unchanged."),
    if (!is.null(protocol)) shiny::tagList(
      shiny::p(shiny::strong(paste("Snapshot saved for study revision", protocol$study$revision))),
      shiny::downloadButton("export_protocol", "Export protocol snapshot", icon = NULL, class = "btn-outline-primary"),
      shiny::tags$details(shiny::tags$summary("Snapshot contents"),
        shiny::p(paste(length(protocol$registry$trials), "planned trials;", length(protocol$registry$exposures),
          "stimulus exposures;", length(protocol$registry$epochs), "viewing/question phases.")),
        shiny::p("Snapshot reference: ", shiny::tags$code(substr(protocol$content_sha256, 1, 12))))) else
      if (length(bundle$study$stimulus_assets) == 2)
        shiny::actionButton("save_protocol_snapshot", "Save protocol snapshot", class = "btn-primary") else
          shiny::p("Add both images in Plan before saving a complete presentation snapshot."),
    shiny::p(class = "muted", "This preserves the intended protocol. It does not start a session, assign participants, certify the method or record observed timing."))
}
