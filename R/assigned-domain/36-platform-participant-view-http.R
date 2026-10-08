# Exact assigned-participant HTTP boundary. Inactive until the complete router is joined.
# The Rook/httpuv stream is already buffered. These bounds limit admission into R;
# the deployment's ingress must separately bound the incoming upload.
.brohn_pvh_text <- function(x) {
  typeof(x) == "character" && is.null(attributes(x)) && length(x) == 1L &&
    !is.na(x) && validUTF8(x)
}

.brohn_pvh_headers <- function(req) {
  type <- req$CONTENT_TYPE
  .brohn_delivery_require(.brohn_pvh_text(type) &&
    grepl('^[ \t]*application/json[ \t]*(;[ \t]*charset[ \t]*=[ \t]*(utf-8|"utf-8")[ \t]*)?\\z',
      tolower(type), perl = TRUE),
    "Use application/json with UTF-8 for participant requests.", 415L, "content_type")
  encoding <- req$HTTP_CONTENT_ENCODING
  .brohn_delivery_require(is.null(encoding) || (.brohn_pvh_text(encoding) &&
    grepl("^[ \t]*identity[ \t]*\\z", tolower(encoding), perl = TRUE)),
    "Compressed participant requests are not supported.", 415L, "content_encoding")
  declared <- req$CONTENT_LENGTH
  if (is.null(declared)) return(NULL)
  .brohn_delivery_require(.brohn_pvh_text(declared) &&
    grepl("^[0-9]+\\z", declared, perl = TRUE) && nchar(declared, type = "bytes") <= 20L,
    "Request Content-Length must be a decimal byte count.", 400L, "request_length")
  size <- suppressWarnings(as.numeric(declared))
  .brohn_delivery_require(is.finite(size) && size >= 1 && size <= 4 * 1024^2,
    "Request body is empty or exceeds 4 MiB.", 413L, "request_limit")
  size
}

.brohn_participant_view_request_bytes <- function(req) {
  declared <- .brohn_pvh_headers(req)
  input <- req$rook.input
  .brohn_delivery_require(!is.null(input) && is.function(input$read),
    "Participant request body is unavailable.", 400L, "request_body")
  # httpuv's Rook InputStream reads raw bytes from its completed body connection.
  # Never convert a character body, parse JSON or reconstruct its spelling here.
  raw <- input$read(4 * 1024^2 + 1L)
  .brohn_delivery_require(typeof(raw) == "raw" && is.null(attributes(raw)),
    "Participant requests require actual raw body bytes.", 400L, "request_body")
  .brohn_delivery_require(length(raw) >= 1L && length(raw) <= 4 * 1024^2,
    "Request body is empty or exceeds 4 MiB.", 413L, "request_limit")
  .brohn_delivery_require(is.null(declared) || length(raw) == declared,
    "Request body length differs from Content-Length.", 400L, "request_length")
  raw
}

.brohn_participant_view_document_response <- function(document) {
  # The coordinator has already admitted/encoded this document. Check the exact
  # retained descriptor before returning raw bytes; no parse/reserialization.
  .brohn_delivery_require(typeof(document) == "list" &&
    identical(attributes(document), list(names = names(document))) &&
    length(document) == 4L && !anyDuplicated(names(document)) &&
    setequal(names(document), c("codec", "json", "bytes", "sha256")),
    "Participant response document is unavailable.", 500L, "response_document")
  .brohn_delivery_require(identical(document$codec, "brohn-participant-json-bytes/0.1") &&
    .brohn_pvh_text(document$json) && .brohn_pvh_text(document$sha256) &&
    grepl("^[a-f0-9]{64}\\z", document$sha256, perl = TRUE) &&
    typeof(document$bytes) %in% c("integer", "double") &&
    is.null(attributes(document$bytes)) && length(document$bytes) == 1L &&
    is.finite(document$bytes) && document$bytes >= 1 && document$bytes <= 4 * 1024^2,
    "Participant response descriptor is invalid.", 500L, "response_document")
  raw <- charToRaw(enc2utf8(document$json))
  .brohn_delivery_require(length(raw) == document$bytes &&
    identical(digest::digest(raw, algo = "sha256", serialize = FALSE), document$sha256),
    "Participant response bytes differ from the saved descriptor.", 500L, "response_document")
  .brohn_delivery_response(body = raw)
}
