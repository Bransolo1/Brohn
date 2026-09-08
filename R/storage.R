# Local JSON persistence. Same-directory rename is the commit point; never delete
# an existing draft to make room. This does not promise power-loss durability.
draft_size_limit <- 16 * 1024 * 1024

draft_fingerprint <- function(path) {
  if (!file.exists(path) || dir.exists(path)) return(NULL)
  value <- unname(tools::md5sum(path))
  record_assert(!is.na(value), "Could not read the saved draft fingerprint.")
  value
}

read_bundle <- function(path, max_bytes = draft_size_limit) {
  record_assert(scalar_text(path), "Choose a draft JSON file to open.")
  record_assert(positive_integer(max_bytes) && max_bytes <= draft_size_limit,
                "The draft size limit must be between 1 byte and 16 MB.")
  record_assert(file.exists(path) && !dir.exists(path), "The draft file was not found.")
  tryCatch({
    con <- file(path, open = "rb")
    on.exit(close(con), add = TRUE)
    raw <- readBin(con, "raw", n = max_bytes + 1)
    record_assert(length(raw) <= max_bytes, "The draft exceeds the size limit (maximum 16 MB).")
    record_assert(length(raw) > 0, "The draft file is empty.")
    text <- rawToChar(raw)
    Encoding(text) <- "UTF-8"
    record_assert(!is.na(iconv(text, from = "UTF-8", to = "UTF-8")), "The draft must contain valid UTF-8 text.")
    bundle_from_json(text)
  }, error = function(e) stop(paste("Could not open this draft:", conditionMessage(e)), call. = FALSE))
}

.write_draft_bytes <- function(text, path) {
  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(charToRaw(enc2utf8(text)), con)
  flush(con)
}

.atomic_draft_replace <- function(text, path, write_fn = .write_draft_bytes,
                                   rename_fn = file.rename) {
  temporary <- tempfile(pattern = ".draft-", tmpdir = dirname(path), fileext = ".tmp")
  on.exit(unlink(temporary), add = TRUE)
  write_fn(text, temporary)
  record_assert(isTRUE(suppressWarnings(rename_fn(temporary, path))),
                "Could not replace the draft. The previous file has been kept; check folder permissions and retry.")
  invisible(path)
}

save_bundle <- function(x, path, overwrite = FALSE, expected_fingerprint = NULL) {
  text <- bundle_to_json(x, pretty = TRUE) # Invalid data never reaches the file.
  record_assert(nchar(enc2utf8(text), type = "bytes") <= draft_size_limit, "The draft exceeds 16 MB.")
  record_assert(scalar_text(path), "Choose a draft file location.")
  record_assert(is.logical(overwrite) && length(overwrite) == 1L && !is.na(overwrite), "overwrite must be TRUE or FALSE.")
  record_assert(is.null(expected_fingerprint) || scalar_text(expected_fingerprint), "Invalid saved-draft fingerprint.")
  record_assert(dir.exists(dirname(path)), "The destination folder does not exist.")
  path <- file.path(normalizePath(dirname(path), winslash = "/", mustWork = TRUE), basename(path))
  record_assert(!dir.exists(path), "Choose a file, not a folder.")
  lock <- paste0(path, ".lock")
  record_assert(dir.create(lock, showWarnings = FALSE),
                "This draft is locked by another save. Retry when it finishes; after a crash, inspect the lock before removing it.")
  on.exit(unlink(lock, recursive = TRUE), add = TRUE)
  exists <- file.exists(path)
  record_assert(!exists || overwrite, "A draft already exists here. Explicit overwrite is required.")
  if (!is.null(expected_fingerprint)) {
    record_assert(identical(draft_fingerprint(path), expected_fingerprint),
                  "This draft changed since you opened it. Reopen it before saving to avoid losing changes.")
  }
  if (exists) {
    previous <- read_bundle(path)
    record_assert(identical(previous$study$id, x$study$id) &&
                    identical(previous$session$id, x$session$id) &&
                    identical(previous$session$mode, x$session$mode),
                  "This file belongs to another study, run or origin. Save to a new file.")
  }
  .atomic_draft_replace(text, path)
  invisible(list(path = path, fingerprint = draft_fingerprint(path)))
}
