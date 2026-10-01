# Inactive API-only HTTP application. Not registered by the released loader.
# This does not supply the participant renderer or activate a delivery profile.
.brohn_pvroute_error <- function(error) {
  if (inherits(error, "brohn_delivery_error"))
    return(.brohn_delivery_response(error$status, list(error = list(code = error$code, message = conditionMessage(error)))))
  if (inherits(error, "brohn_store_error")) {
    if (identical(error$code, "busy")) {
      response <- .brohn_delivery_response(503L, list(error = list(code = "workspace_busy", retryable = TRUE,
        retry_after_seconds = 1L, message = "Your responses remain in this browser. The study is briefly busy; retry shortly.")))
      response$headers[["Retry-After"]] <- "1"
      return(response)
    }
    status <- if (error$code %in% c("revision_conflict", "idempotency_conflict")) 409L else
      if (identical(error$code, "too_large")) 413L else 500L
    return(.brohn_delivery_response(status, list(error = list(code = error$code,
      message = if (status == 500L) "The study could not safely save this request. Retry or contact your researcher." else conditionMessage(error)))))
  }
  # Legacy field/domain validators use simpleError. Never echo arbitrary error
  # messages: they may contain participant values, paths or SQL diagnostics.
  if (inherits(error, "simpleError"))
    return(.brohn_delivery_response(400L, list(error = list(code = "invalid_request",
      message = "This request could not be accepted. Keep your saved responses and contact your researcher if retrying does not resolve it."))))
  .brohn_delivery_response(500L, list(error = list(code = "internal",
    message = "The study could not safely process this request. Your local responses have not been deleted.")))
}

.brohn_pvroute_request <- function(store, req, headers_only = FALSE) {
  if (is.null(store$hosted_profile) || !brohn_hosted_participant_request(store, req)) .brohn_delivery_origin(req)
  path <- req$PATH_INFO; method <- req$REQUEST_METHOD
  .brohn_delivery_require(.brohn_pvh_text(path) && nchar(path, type = "bytes") <= 240L,
    "Route was not found.", 404L, "not_found")
  release <- grepl("^/api/view/(entry|welcome|start)/[a-f0-9]{64}\\z", path, perl = TRUE)
  run <- grepl(paste0("^/api/view/(current|events|questionnaire_state|camera_start|camera_chunk|camera_finish|finish)/",
    "pvu-[a-f0-9]{64}\\z"), path, perl = TRUE)
  resource <- grepl("^/api/view/resources/pvu-[a-f0-9]{64}/pvr-[a-f0-9]{64}\\z", path, perl = TRUE)
  .brohn_delivery_require(release || run || resource, "Route was not found.", 404L, "not_found")
  parts <- strsplit(path, "/", fixed = TRUE)[[1L]]
  operation <- parts[[4L]]; identity <- parts[[5L]]
  expected <- if (operation %in% c("entry", "welcome", "current", "resources")) "GET" else "POST"
  .brohn_delivery_require(identical(method, expected), "HTTP method is not supported for this route.", 405L, "method")
  # Do not let a body with no declared bound spill indefinitely into httpuv's
  # pre-Rook buffer. The browser sends finite string/Uint8Array request bodies.
  .brohn_delivery_require(is.null(req$HTTP_TRANSFER_ENCODING),
    "Streaming participant request bodies are not supported.", 400L, "request_encoding")
  if (identical(method, "POST")) {
    .brohn_delivery_require(!is.null(req$CONTENT_LENGTH),
      "A complete participant request needs Content-Length.", 411L, "request_length")
    .brohn_pvh_headers(req)
  } else {
    .brohn_delivery_require(is.null(req$CONTENT_LENGTH) || identical(req$CONTENT_LENGTH, "0"),
      "This read route does not accept a request body.", 400L, "request_length")
  }
  token <- NULL
  if (!release) {
    authorization <- req$HTTP_AUTHORIZATION
    .brohn_delivery_require(.brohn_pvh_text(authorization) &&
      grepl("^Bearer [a-f0-9]{64}\\z", authorization, perl = TRUE),
      "Run access is required.", 401L, "unauthorized")
    token <- substring(authorization, 8L)
  }
  if (headers_only) return(NULL)
  raw <- if (identical(method, "POST")) .brohn_participant_view_request_bytes(req) else NULL
  if (identical(operation, "welcome")) return(.brohn_participant_view_welcome_response(store, identity))
  if (identical(operation, "resources"))
    return(.brohn_participant_view_resource_response(store, identity, token, parts[[6L]]))
  document <- switch(operation,
    entry = .brohn_participant_view_entry_response(store, identity),
    start = .brohn_participant_view_start_response(store, identity, raw),
    current = .brohn_participant_view_current_response(store, identity, token),
    events = brohn_receive_participant_view_events(store, identity, token, raw),
    questionnaire_state = .brohn_participant_view_current_response(store, identity, token,
      questionnaire_request = brohn_participant_received_bytes(raw)$value),
    camera_start = .brohn_participant_view_camera_response(store, identity, token, "start", raw),
    camera_chunk = .brohn_participant_view_camera_response(store, identity, token, "chunk", raw),
    camera_finish = .brohn_participant_view_camera_response(store, identity, token, "finish", raw),
    finish = .brohn_participant_view_finish_response(store, identity, token, raw))
  .brohn_participant_view_document_response(document)
}

.brohn_participant_view_http_app <- function(store) {
  # Refuse partial wiring; neither a global fallback nor a client flag can turn
  # an incomplete registration into another profile's authorization path.
  required <- c(".brohn_participant_view_entry_response", ".brohn_participant_view_welcome_response",
    ".brohn_participant_view_start_response", ".brohn_participant_view_current_response",
    "brohn_receive_participant_view_events", ".brohn_participant_view_resource_response",
    ".brohn_participant_view_camera_response", ".brohn_participant_view_finish_response")
  .brohn_pvds_require(all(vapply(required, exists, logical(1),
    envir = environment(.brohn_participant_view_http_app), mode = "function", inherits = TRUE)),
    "The complete assigned participant HTTP implementation is unavailable.", "profile_unavailable", 503L)
  .brohn_pvds_tables(store)
  list(onHeaders = function(req) tryCatch(.brohn_pvroute_request(store, req, headers_only = TRUE), error = .brohn_pvroute_error),
    call = function(req) tryCatch(.brohn_pvroute_request(store, req), error = .brohn_pvroute_error))
}
