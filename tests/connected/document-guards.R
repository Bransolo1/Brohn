# Controlled R request-shape tests on genuinely published disposable releases.
# Actual HTTP body representation and anchor/redirect are covered by the browser.
brohn_test_document_guards <- function(installation, output) {
  dir.create(output); results <- list(passed = FALSE, checks = list()); store <- NULL
  write <- function() writeLines(jsonlite::toJSON(results, auto_unbox = TRUE,
    null = "null", pretty = TRUE, digits = NA), file.path(output, "RESULTS.json"), useBytes = TRUE)
  on.exit({if (!is.null(store) && DBI::dbIsValid(store$con)) DBI::dbDisconnect(store$con)
    results$store_closed <- is.null(store) || !DBI::dbIsValid(store$con); write()}, add = TRUE)
  check <- function(name, ok) {if (!isTRUE(ok)) stop(name, call. = FALSE); results$checks[[length(results$checks)+1L]] <<- name}
  tryCatch({
    e <- new.env(parent = .GlobalEnv)
    source("R/platform-load.R", local = e, encoding = "UTF-8"); e$brohn_load(envir = e, ui = FALSE)
    source("R/platform-assigned-delivery-load.R", local = e, encoding = "UTF-8"); e$brohn_load_assigned_delivery(e)
    store <- e$brohn_open_store(file.path(output, "workspace")); e$brohn_initialize_assigned_researcher(store)
    e$brohn_initialise_library(store)
    publish <- function(title, assigned) {
      entity <- e$brohn_create_study(store, title); design <- entity$body
      design$stimuli[[1L]]$content <- "Control"; design$stimuli[[2L]]$content <- "Packaging"
      design$measures <- list("questionnaire"); design$participant_equipment <- NULL
      design$questionnaire_navigation <- e$brohn_questionnaire_navigation()
      if (assigned) design <- e$brohn_group_stimuli(design,
        vapply(design$stimuli, `[[`, character(1), "id"), "All materials", selection = "all")
      saved <- e$brohn_save_study(store, design, entity$revision)
      e$brohn_release_study(store, saved$id, "sample", 1L, FALSE, saved$revision)
    }
    assigned <- publish("Document admission", TRUE); legacy <- publish("Legacy admission conservation", FALSE)
    runtime <- e$brohn_runner_assets_read(store, assigned$id); old <- e$brohn_runner_assets_read(store, legacy$id)
    app <- e$brohn_assigned_delivery_app(store); legacy_app <- e$brohn_delivery_app(store)
    empty <- function(bytes = raw()) list(read = function(n) bytes[seq_len(min(n, length(bytes)))])
    req <- list(REQUEST_METHOD = "GET", PATH_INFO = "/participant/", QUERY_STRING = paste0("token=", assigned$token),
      HTTP_HOST = "127.0.0.1:48011", HTTP_SEC_FETCH_SITE = "same-site", HTTP_SEC_FETCH_MODE = "navigate",
      HTTP_SEC_FETCH_DEST = "document", HTTP_SEC_FETCH_USER = "?1", rook.input = empty())
    changed <- function(...) {value <- req; edits <- list(...); value[names(edits)] <- edits; value}
    path <- paste0("/api/runtime/", assigned$token, "/", runtime$manifest_hash, "/participant/index.html")
    tables <- c("delivery_deployments", "delivery_runs", "delivery_events", "delivery_view_operations", "jobs", "audit_log")
    snapshot <- function() setNames(lapply(tables, function(name) DBI::dbGetQuery(store$con, paste("SELECT * FROM", name, "ORDER BY rowid"))), tables)
    original <- snapshot()
    first <- app$call(req); doc <- app$call(changed(PATH_INFO = path))
    check("assigned navigation yields original exact redirect", identical(first$status, 302L) &&
      identical(first$headers[["Location"]], paste0(path, "?token=", assigned$token)))
    member <- Filter(function(x) identical(x$path, "participant/index.html"), runtime$manifest$files)[[1L]]
    check("document body is the exact stored original with assigned CSP and no-store", identical(doc$status, 200L) &&
      identical(digest::digest(doc$body, algo = "sha256", serialize = FALSE), member$hash) && length(doc$body) == member$size &&
      identical(doc$headers[["Content-Security-Policy"]], e$.brohn_assigned_document_policy()) && identical(doc$headers[["Cache-Control"]], "no-store"))
    refuses <- function(label, request, status = 403L, code = "origin") {
      response <- app$call(request); value <- jsonlite::fromJSON(rawToChar(if (is.raw(response$body)) response$body else charToRaw(response$body)), simplifyVector = FALSE)
      check(label, identical(response$status, status) && identical(value$error$code, code))
    }
    for (dest in c("iframe", "empty", "script", "")) refuses(paste("unchanged destination refusal", dest), changed(HTTP_SEC_FETCH_DEST = dest))
    for (mode in c("cors", "no-cors", "same-origin")) refuses(paste("unchanged mode refusal", mode), changed(HTTP_SEC_FETCH_MODE = mode))
    refuses("missing mode refuses", changed(HTTP_SEC_FETCH_MODE = NULL))
    refuses("cross-site document refuses", changed(HTTP_SEC_FETCH_SITE = "cross-site"))
    for (method in c("POST", "PUT", "HEAD")) refuses(paste("non-GET refuses", method), changed(REQUEST_METHOD = method))
    refuses("same-site entry API fetch refuses", changed(PATH_INFO = paste0("/api/view/entry/", assigned$token), HTTP_SEC_FETCH_MODE = "cors", HTTP_SEC_FETCH_DEST = "empty"))
    refuses("same-site Start POST refuses", changed(PATH_INFO = paste0("/api/view/start/", assigned$token), REQUEST_METHOD = "POST", HTTP_SEC_FETCH_MODE = "cors", HTTP_SEC_FETCH_DEST = "empty"))
    refuses("same-site runtime module refuses", changed(PATH_INFO = sub("index.html$", "bootstrap.mjs", path)))
    refuses("foreign Host refuses", changed(HTTP_HOST = "example.org"), 403L, "host")
    refuses("cross-port Origin still refuses", changed(HTTP_ORIGIN = "http://127.0.0.1:48010"))
    refuses("foreign Origin refuses", changed(HTTP_ORIGIN = "https://example.org"))
    refuses("declared body refuses", changed(CONTENT_LENGTH = "1", rook.input = empty(charToRaw("x"))), 400L, "request_body")
    refuses("undeclared actual body refuses", changed(rook.input = empty(charToRaw("x"))), 400L, "request_body")
    refuses("transfer encoding refuses", changed(HTTP_TRANSFER_ENCODING = "chunked"), 400L, "request_body")
    refuses("malformed release identity refuses", changed(QUERY_STRING = "token=bad"), 400L, "runner_integrity")
    refuses("missing release identity refuses", changed(QUERY_STRING = ""), 400L, "runner_integrity")
    refuses("duplicate release identities refuse", changed(QUERY_STRING = paste0("token=", assigned$token, "&study=", assigned$token)), 400L, "runner_integrity")
    refuses("path/query identity mismatch refuses", changed(PATH_INFO = path, QUERY_STRING = paste0("token=", legacy$token)), 404L, "runner_integrity")
    refuses("wrong assigned manifest refuses", changed(PATH_INFO = sub(runtime$manifest_hash, paste(rep("0",64),collapse=""), path, fixed=TRUE)), 404L, "runner_integrity")
    legacy_request <- changed(QUERY_STRING = paste0("token=", legacy$token))
    check("valid legacy same-site invitation retains exact original refusal", identical(app$call(legacy_request), legacy_app$call(legacy_request)))
    legacy_request$PATH_INFO <- paste0("/api/runtime/", legacy$token, "/", old$manifest_hash, "/participant/index.html")
    check("valid legacy same-site document retains exact original refusal", identical(app$call(legacy_request), legacy_app$call(legacy_request)))
    legacy_request$HTTP_SEC_FETCH_SITE <- "none"
    check("legacy direct document retains exact original bytes and headers", identical(app$call(legacy_request), legacy_app$call(legacy_request)))
    direct <- changed(HTTP_SEC_FETCH_SITE = "none", PATH_INFO = path)
    check("assigned direct navigation remains admitted through original route", identical(app$call(direct)$body, doc$body))
    zero <- changed(CONTENT_LENGTH = "0", PATH_INFO = path)
    check("explicit empty body remains admitted", identical(app$call(zero)$body, doc$body))
    previous <- store$hosted_profile; store$hosted_profile <- list(test = TRUE)
    hosted <- tryCatch(e$.brohn_assigned_document_entry(store, req, e$.brohn_assigned_runtime_installed()), finally = {store$hosted_profile <- previous})
    check("hosted context never enters local document exception", is.null(hosted))
    asset_path <- e$brohn_object_path(store, member$hash, verify = TRUE); bytes <- readBin(asset_path,"raw",n=member$size)
    # Fault injection is limited to this newly created disposable guard store.
    # Original production objects deliberately have mode0444; retain and restore
    # their original mode and bytes even when the deliberate write/call fails.
    guard_root <- normalizePath(file.path(output, "workspace"), winslash="/", mustWork=TRUE)
    target <- normalizePath(asset_path, winslash="/", mustWork=TRUE)
    expected <- paste0(guard_root,"/objects/sha256/",substr(member$hash,1L,2L),"/",member$hash)
    check("fault target is exactly inside this fresh guard workspace", identical(target,expected) &&
      identical(normalizePath(store$root,winslash="/",mustWork=TRUE),guard_root) &&
      identical(digest::digest(bytes,algo="sha256",serialize=FALSE),member$hash))
    original_mode <- file.info(asset_path)$mode
    response <- (function() {
      writable <- FALSE; restore_bytes <- FALSE
      on.exit({
        if (writable) {
          tryCatch({if (restore_bytes) writeBin(bytes,asset_path)}, finally = {
            if (!isTRUE(Sys.chmod(asset_path,original_mode))) stop("Could not restore guard object's original mode.")
          })
        }
      }, add=TRUE)
      if (!isTRUE(Sys.chmod(asset_path,"0600"))) stop("Could not make test-owned guard object writable.")
      writable <- TRUE
      if (file.access(asset_path,2L)!=0L) stop("Guard object remains read-only; fault was not injected.")
      corrupt <- bytes; corrupt[[1L]] <- as.raw(bitwXor(as.integer(corrupt[[1L]]),1L))
      restore_bytes <- TRUE; writeBin(corrupt,asset_path)
      app$call(changed(PATH_INFO=path))
    })()
    check("fault injection restores original object bytes and mode", identical(file.info(asset_path)$mode,original_mode) &&
      identical(readBin(asset_path,"raw",n=member$size+1L),bytes))
    check("altered original document object is never served", response$status >= 400L && !identical(response$status, 200L))
    check("document reads and all refusals create no enrollment or changed source", identical(original, snapshot()) && nrow(original$delivery_runs)==0L && nrow(original$jobs)==0L)
    results$passed <- TRUE
  }, error = function(error) results$failure <<- list(message = conditionMessage(error),call=paste(deparse(conditionCall(error)),collapse=" ")))
  if (!results$passed) stop(results$failure$message, call.=FALSE)
  invisible(results)
}
