# Inactive assigned-only media response; no route or static path registration.
.brohn_pvres_snapshot <- function(source, snapshot, size) {
  input <- file(source, open = "rb")
  on.exit(close(input), add = TRUE)
  output <- file(snapshot, open = "wb")
  on.exit(close(output), add = TRUE)
  remaining <- size
  while (remaining > 0) {
    count <- min(1024^2, remaining)
    bytes <- readBin(input, what = "raw", n = count)
    .brohn_pvds_require(length(bytes) == count,
      "The assigned resource changed while it was copied.", "resource_integrity")
    writeBin(bytes, output)
    remaining <- remaining - count
  }
  .brohn_pvds_require(length(readBin(input, what = "raw", n = 1L)) == 0L,
    "The assigned resource exceeds its retained size.", "resource_integrity")
  invisible(TRUE)
}

.brohn_participant_view_resource_response <- function(store, public_run_id, access_token, resource_key) {
  handle <- brohn_open_participant_view(store, public_run_id, access_token)
  on.exit(handle$close(), add = TRUE)
  original <- handle$read()
  resource <- original$context$resource(resource_key)
  asset <- resource$source_descriptor
  .brohn_pvds_require(.brohn_delivery_media_allowed(asset$media_type),
    "This assigned resource has an unsupported media type.", "resource_type", 404L)
  # Containment/catalog checks precede a bounded copy. Authenticate the copied
  # bytes below; an initial hash-to-EOF would be unbounded if this file grew.
  source <- brohn_object_path(store, asset$hash, verify = FALSE)
  .brohn_pvds_require(identical(as.numeric(file.info(source)$size), as.numeric(asset$size)),
    "The stored resource differs from its assigned size.", "resource_integrity")

  # httpuv takes ownership of this per-response file. Snapshot before the final
  # authority check so delayed socket reads cannot select changed source bytes.
  # No raw material is hydrated into R memory or exposed through staticPaths.
  snapshot <- tempfile(pattern = "brohn-assigned-resource-")
  transferred <- FALSE
  on.exit(if (!transferred && file.exists(snapshot)) unlink(snapshot), add = TRUE)
  .brohn_pvres_snapshot(source, snapshot, asset$size)
  .brohn_pvds_require(identical(as.numeric(file.info(snapshot)$size), as.numeric(asset$size)) &&
    identical(digest::digest(file = snapshot, algo = "sha256"), asset$hash),
    "The assigned resource could not be prepared intact.", "resource_integrity")
  handle$current()
  response <- .brohn_delivery_response(body = list(file = snapshot, owned = TRUE), type = asset$media_type)
  response$headers[["Content-Length"]] <- sprintf("%.0f", asset$size)
  response$headers[["Accept-Ranges"]] <- "none"
  transferred <- TRUE
  response
}
