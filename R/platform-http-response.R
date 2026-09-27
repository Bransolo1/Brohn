# Full, identity-encoded saved-resource responses for Shiny's HTTP dispatcher.
# Authority and retained-file lifetime remain the caller's responsibility.
.brohn_http_stop <- function(message) {
  stop(structure(list(message = message, call = NULL),
    class = c("brohn_http_response_error", "error", "condition")))
}

.brohn_http_length <- function(value) {
  if (is.character(value) && length(value) == 1L && !is.na(value) &&
      grepl("^(0|[1-9][0-9]*)$", value) && nchar(value, type = "bytes") <= 16L) {
    value <- as.numeric(value)
  }
  if (!is.numeric(value) || length(value) != 1L || is.na(value) ||
      !is.finite(value) || value < 0 || value != trunc(value) || value > 2^53 - 1) {
    .brohn_http_stop("Response length must be an exact nonnegative byte count below 2^53.")
  }
  format(value, scientific = FALSE, trim = TRUE, decimal.mark = ".", digits = 22L)
}

`$<-.brohn_http_identity_headers` <- function(x, name, value) {
  if (identical(tolower(name), "content-length")) {
    value <- .brohn_http_length(value)
    name <- "Content-Length"
  }
  classes <- class(x)
  class(x) <- NULL
  x[[name]] <- value
  class(x) <- classes
  x
}

# A dedicated application S3 registry entry is necessary when the module is
# sourced privately: Shiny calls `$<-` after as.list(response$headers).
# This does not replace a base/Shiny function or alter formatting options.
registerS3method("$<-", "brohn_http_identity_headers",
  `$<-.brohn_http_identity_headers`, envir = asNamespace("base"))

brohn_http_identity_response <- function(response) {
  if (!inherits(response, "httpResponse") || !is.list(response) ||
      is.null(names(response)) || anyDuplicated(names(response)) ||
      !all(c("status", "content_type", "content") %in% names(response))) {
    .brohn_http_stop("Expected one complete Shiny httpResponse.")
  }
  status <- response$status
  if (!is.numeric(status) || length(status) != 1L || is.na(status) ||
      !is.finite(status) || status != trunc(status) || status < 200 || status > 599 ||
      status %in% c(204, 205, 206, 304)) {
    .brohn_http_stop("This finalizer requires a full representation with a body-capable status.")
  }
  text_scalar <- function(x) is.character(x) && length(x) == 1L && !is.na(x)
  type <- response$content_type
  if (!text_scalar(type) || !nzchar(type) || grepl("[[:cntrl:]]", type)) {
    .brohn_http_stop("Response media type must be a single nonempty header value.")
  }
  headers <- response$headers
  if (is.null(headers)) headers <- list()
  if (!is.list(headers) || (length(headers) &&
      (is.null(names(headers)) || anyNA(names(headers)) || any(!nzchar(names(headers))) ||
       anyDuplicated(tolower(names(headers))) ||
       any(!grepl("^[!#$%&'*+.^_`|~0-9A-Za-z-]+$", names(headers)))))) {
    .brohn_http_stop("Response headers must be a uniquely named list of valid header fields.")
  }
  # Strip only our own dispatch class before validating an idempotent call.
  if (is.object(headers) && !identical(class(headers), c("brohn_http_identity_headers", "list"))) {
    .brohn_http_stop("Unsupported response-header dispatch class.")
  }
  class(headers) <- NULL
  lower <- tolower(names(headers))
  for (i in seq_along(headers)) {
    if (lower[[i]] == "content-length") {
      invisible(.brohn_http_length(headers[[i]]))
    } else if (!text_scalar(headers[[i]]) || grepl("[[:cntrl:]]", headers[[i]])) {
      .brohn_http_stop("Response headers must contain scalar values without control characters.")
    }
  }
  if (any(lower %in% c("transfer-encoding", "content-range", "trailer")) ||
      ("content-encoding" %in% lower &&
       !identical(tolower(headers[[which(lower == "content-encoding")]]), "identity"))) {
    .brohn_http_stop("Encoded, transfer-coded and partial responses require a separate transport contract.")
  }
  if ("content-type" %in% lower) {
    i <- which(lower == "content-type")
    if (!identical(names(headers)[[i]], "Content-Type") || !identical(headers[[i]], type)) {
      .brohn_http_stop("Content-Type must agree exactly with the dispatcher media type.")
    }
  }
  content <- response$content
  if (is.raw(content) && !is.object(content) && is.null(dim(content))) {
    bytes <- length(content)
  } else if (text_scalar(content) && !is.object(content) && is.null(dim(content))) {
    # httpuv emits UTF-8. Refuse a character encoding conversion that would
    # change the byte count; do not rewrite the supplied representation.
    if (identical(Encoding(content), "bytes")) .brohn_http_stop("Byte-marked text must be supplied as raw content.")
    valid <- !is.na(iconv(content, from = "UTF-8", to = "UTF-8", sub = NA_character_))
    stable <- identical(charToRaw(content), charToRaw(enc2utf8(content)))
    if (!valid || !stable) .brohn_http_stop("Text content must already have byte-stable UTF-8 or ASCII encoding.")
    bytes <- nchar(content, type = "bytes")
  } else if (is.list(content) && !is.object(content) &&
      identical(sort(names(content)), c("file", "owned")) &&
      text_scalar(content$file) && nzchar(content$file) && identical(content$owned, FALSE)) {
    info <- file.info(content$file)
    if (nrow(info) != 1L || is.na(info$isdir) || info$isdir || is.na(info$size)) {
      .brohn_http_stop("Retained response file must exist and be a regular file.")
    }
    bytes <- info$size
  } else {
    .brohn_http_stop("Unsupported response content; use scalar text, raw bytes or a retained unowned file.")
  }
  length_header <- .brohn_http_length(bytes)
  if ("content-length" %in% lower &&
      !identical(.brohn_http_length(headers[[which(lower == "content-length")]]), length_header)) {
    .brohn_http_stop("Declared Content-Length differs from the complete representation.")
  }
  headers <- headers[!lower %in% c("content-length", "content-encoding")]
  headers[["Content-Encoding"]] <- "identity"
  headers[["Content-Length"]] <- length_header
  response$headers <- structure(headers, class = c("brohn_http_identity_headers", "list"))
  response
}
