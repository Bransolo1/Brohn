# Explicit installed application composition. This is not triggered by import,
# opening a saved design or a participant-provided profile selection.
brohn_initialize_assigned_delivery <- function(store) {
  .brohn_assigned_runtime_installed()
  brohn_register_assigned_derivation()
  brohn_initialize_participant_view_store(store)
  brohn_initialize_participant_view_receiving(store)
  .brohn_camera_schema(store)
  invisible(TRUE)
}

.brohn_assigned_document_policy <- function() paste(
  "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline';",
  "img-src 'self' data: blob:; media-src 'self' blob:; connect-src 'self';",
  "font-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'")

# Local cross-port researcher links are document navigations, not participant API
# authorization. Admit only this installed assigned document; preserve the exact
# request, original runner verification and every legacy/API origin boundary.
.brohn_assigned_document_entry <- function(store, req, installed) {
  if (!is.null(store$hosted_profile) || !identical(req$REQUEST_METHOD, "GET") ||
      !identical(req$HTTP_SEC_FETCH_SITE, "same-site") ||
      !identical(req$HTTP_SEC_FETCH_MODE, "navigate") ||
      !identical(req$HTTP_SEC_FETCH_DEST, "document")) return(NULL)
  path <- req$PATH_INFO
  invitation <- .brohn_pvh_text(path) && path %in% c("/participant", "/participant/")
  document <- .brohn_pvh_text(path) && grepl(
    "^/api/runtime/[a-f0-9]{64}/[a-f0-9]{64}/participant/index\\.html\\z", path, perl = TRUE)
  if (!invitation && !document) return(NULL)
  tryCatch({
    host <- brohn_default(req$HTTP_HOST, paste0("127.0.0.1:", brohn_default(req$SERVER_PORT, "3840")))
    .brohn_delivery_require(.brohn_pvh_text(host) &&
      grepl("^(127\\.0\\.0\\.1|localhost)(:[0-9]{1,5})?\\z", host, perl = TRUE),
      "This service accepts loopback hosts only.", 403L, "host")
    origin <- req$HTTP_ORIGIN
    .brohn_delivery_require(is.null(origin) || identical(origin, "") || identical(origin, paste0("http://", host)),
      "Requests from another browser origin are not accepted.", 403L, "origin")
    declared <- req$CONTENT_LENGTH
    .brohn_delivery_require((is.null(declared) || identical(declared, "0")) &&
      is.null(req$HTTP_TRANSFER_ENCODING), "Study document requests cannot contain a body.", 400L, "request_body")
    input <- req$rook.input
    .brohn_delivery_require(!is.null(input) && is.function(input$read),
      "Study document request body is unavailable.", 400L, "request_body")
    body <- input$read(1L)
    .brohn_delivery_require(is.raw(body) && is.null(attributes(body)) && length(body) == 0L,
      "Study document requests cannot contain a body.", 400L, "request_body")
    token <- .brohn_runner_query_identity(brohn_default(req$QUERY_STRING, ""), required = TRUE)
    if (document) {
      parts <- strsplit(sub("^/", "", path), "/", fixed = TRUE)[[1L]]
      .brohn_runner_require(identical(parts[[3L]], token),
        "Study link and installed participant interface do not match.", 404L)
    }
    # Metadata binds the original credential, workspace, source revision and
    # explicit release registration. Reading the immutable runtime additionally
    # checks its exact manifest and original publication audit. No enrollment,
    # session, current-response or resource permission is created by this read.
    row <- .brohn_delivery_deployment_row(store, token = token)
    .brohn_runner_require(nrow(row) == 1L, "Study link was not found.", 404L)
    runtime <- brohn_runner_assets_read(store, row$id[[1L]])
    # A retained legacy release stays on its original route, including the
    # original same-site refusal. This exception cannot serve legacy code.
    if (!identical(runtime$status, "pinned") ||
        !identical(runtime$manifest$schema, .brohn_assigned_runtime_profile)) return(NULL)
    metadata <- .brohn_pvds_release_meta(store, token = token)
    .brohn_runner_require(identical(metadata$registration, installed$registration) &&
      (!document || identical(parts[[4L]], installed$registration$runtime_manifest_hash)),
      "This release requires its installed participant interface.", 404L)
    .brohn_runner_require(identical(runtime$status, "pinned") &&
      identical(runtime$manifest_hash, installed$prepared$hash) &&
      .brohn_ph_equal(runtime$manifest, installed$prepared$manifest),
      "This release requires its original participant interface.", 404L)
    response <- brohn_runner_route(store, req)
    .brohn_runner_require(!is.null(response) &&
      identical(response$status, if (invitation) 302L else 200L) &&
      identical(response$headers[["Content-Type"]], "text/html; charset=utf-8"),
      "The original participant document is unavailable.", 503L)
    if (document) response$headers[["Content-Security-Policy"]] <- .brohn_assigned_document_policy()
    response
  }, error = function(e) {
    if (inherits(e, "brohn_delivery_error"))
      return(.brohn_delivery_response(e$status, list(error = list(code = e$code, message = conditionMessage(e)))))
    .brohn_delivery_response(500L, list(error = list(code = "document_unavailable",
      message = "The study page could not be opened. Please retry or contact your researcher.")))
  })
}

brohn_assigned_delivery_app <- function(store, legacy_static_root = "www/participant") {
  installed <- .brohn_assigned_runtime_installed()
  .brohn_pvr_identity(list(renderer_identity = .brohn_pvds_renderer(installed$registration)))
  assigned <- .brohn_assigned_view_http_app(store)
  legacy <- brohn_delivery_app(store, legacy_static_root)
  is_assigned <- function(req) is.character(req$PATH_INFO) && length(req$PATH_INFO) == 1L &&
    !is.na(req$PATH_INFO) && startsWith(req$PATH_INFO, "/api/view/")
  list(onHeaders = function(req) {
    if (is_assigned(req)) return(assigned$onHeaders(req))
    if (is.function(legacy$onHeaders)) return(legacy$onHeaders(req))
    NULL
  }, call = function(req) {
    if (is_assigned(req)) return(assigned$call(req))
    navigation <- .brohn_assigned_document_entry(store, req, installed)
    if (!is.null(navigation)) return(navigation)
    # The existing application performs original origin/hosted-edge validation,
    # exact token/manifest membership, source-object verification and GET rules.
    # Change only the successful HTML of this exact registered distribution.
    response <- legacy$call(req)
    path <- brohn_default(req$PATH_INFO, "")
    document <- paste0("^/api/runtime/[a-f0-9]{64}/", installed$registration$runtime_manifest_hash,
      "/participant/index\\.html$")
    if (identical(req$REQUEST_METHOD, "GET") && identical(response$status, 200L) &&
        grepl(document, path) && identical(response$headers[["Content-Type"]], "text/html; charset=utf-8"))
      response$headers[["Content-Security-Policy"]] <- .brohn_assigned_document_policy()
    response
  })
}

# Researcher startup retains the original hosted context and action boundary.
# This only prepares workspace tables and app-owned implementation metadata;
# it never starts a participant session or borrows participant authorization.
brohn_initialize_assigned_researcher <- function(store) {
  .brohn_store_ready(store)
  .brohn_delivery_require(!isTRUE(store$hosted_participant),
    "Only a researcher can initialize the study workspace.", 403L, "unauthorized")
  brohn_hosted_require_session(store)
  brohn_initialize_assigned_delivery(store)
}
