# Portable PNG bytes belong to the draft; uploads never retain a local file path.
stimulus_asset_limits <- function() {
  list(bytes = 5 * 1024^2, side = 4096, pixels = 8000000)
}

stimulus_png_header <- function(bytes) {
  a <- record_assert; limits <- stimulus_asset_limits()
  a(is.raw(bytes) && length(bytes) >= 33L, "PNG: truncated header")
  a(identical(bytes[1:8], as.raw(c(137, 80, 78, 71, 13, 10, 26, 10))),
    "PNG: invalid signature")
  uint32 <- function(x) sum(as.numeric(x) * c(16777216, 65536, 256, 1))
  a(uint32(bytes[9:12]) == 13 && identical(bytes[13:16], charToRaw("IHDR")),
    "PNG: invalid IHDR header")
  dimensions <- c(width = uint32(bytes[17:20]), height = uint32(bytes[21:24]))
  a(all(dimensions >= 1 & dimensions <= limits$side) &&
      prod(dimensions) <= limits$pixels,
    "PNG: dimensions exceed 4096 per side or 8 million pixels")
  dimensions
}

stimulus_png_decode <- function(bytes) {
  dimensions <- stimulus_png_header(bytes)
  decoded <- withCallingHandlers(png::readPNG(bytes, native = TRUE),
    warning = function(w) stop("PNG: ", conditionMessage(w), call. = FALSE))
  record_assert(length(dim(decoded)) == 2L &&
    all(dim(decoded) == dimensions[c("height", "width")]), "PNG: decoded dimensions differ")
  invisible(dimensions)
}

stimulus_base64 <- function(bytes) {
  gsub("[\r\n]", "", jsonlite::base64_enc(bytes))
}

new_png_asset <- function(path, stimulus_id) {
  a <- record_assert; limits <- stimulus_asset_limits()
  a(scalar_text(path) && file.exists(path) && !dir.exists(path), "PNG: choose a readable file")
  a(scalar_text(stimulus_id), "PNG: stimulus ID required")
  size <- file.info(path)$size
  a(!is.na(size) && size >= 33 && size <= limits$bytes, "PNG: file must be at most 5 MiB")
  connection <- file(path, open = "rb")
  on.exit(close(connection), add = TRUE)
  stimulus_png_header(readBin(connection, "raw", n = 33L))
  seek(connection, where = 0, origin = "start")
  bytes <- readBin(connection, "raw", n = limits$bytes + 1L)
  a(length(bytes) == size && length(bytes) <= limits$bytes, "PNG: file changed while reading")
  dimensions <- stimulus_png_decode(bytes)
  list(stimulus_id = stimulus_id, media_type = "image/png",
       sha256 = digest::digest(bytes, algo = "sha256", serialize = FALSE),
       width = unname(dimensions["width"]), height = unname(dimensions["height"]),
       data_base64 = stimulus_base64(bytes))
}

validate_stimulus_assets <- function(assets, stimulus_ids) {
  tryCatch({
    a <- record_assert; limits <- stimulus_asset_limits()
    a(record_array(assets) && length(assets) <= length(stimulus_ids),
      "stimulus assets: unnamed array with at most one PNG per stimulus required")
    seen <- character()
    for (asset in assets) {
      a(record_fields(asset, c("stimulus_id", "media_type", "sha256", "width", "height", "data_base64")),
        "stimulus asset: fields")
      a(text_choice(asset$stimulus_id, stimulus_ids), "stimulus asset: unknown stimulus ID")
      a(!asset$stimulus_id %in% seen, "stimulus asset: duplicate stimulus ID")
      seen <- c(seen, asset$stimulus_id)
      a(identical(asset$media_type, "image/png"), "stimulus asset: only image/png is supported")
      a(positive_integer(asset$width) && positive_integer(asset$height) &&
          asset$width <= limits$side && asset$height <= limits$side &&
          asset$width * asset$height <= limits$pixels, "stimulus asset: invalid dimensions")
      a(scalar_text(asset$sha256) && grepl("^[0-9a-f]{64}$", asset$sha256),
        "stimulus asset: lowercase SHA-256 required")
      encoded <- asset$data_base64
      a(is.character(encoded) && length(encoded) == 1L && !is.na(encoded),
        "stimulus asset: base64 string required")
      encoded_size <- nchar(encoded, type = "bytes")
      a(encoded_size >= 44 && encoded_size <= 4 * ceiling(limits$bytes / 3) &&
          encoded_size %% 4 == 0, "stimulus asset: base64 size exceeds 5 MiB or is malformed")
      a(grepl("^[A-Za-z0-9+/]*={0,2}$", encoded), "stimulus asset: malformed base64")
      # Inspect the 33-byte header before decoding the bounded full byte payload.
      dimensions <- stimulus_png_header(jsonlite::base64_dec(substr(encoded, 1, 44)))
      a(all(dimensions == c(asset$width, asset$height)), "stimulus asset: dimensions do not match PNG")
      bytes <- jsonlite::base64_dec(encoded)
      a(length(bytes) <= limits$bytes, "stimulus asset: PNG exceeds 5 MiB")
      a(identical(stimulus_base64(bytes), encoded), "stimulus asset: noncanonical base64")
      a(identical(digest::digest(bytes, algo = "sha256", serialize = FALSE), asset$sha256),
        "stimulus asset: SHA-256 mismatch")
      stimulus_png_decode(bytes)
    }
    character()
  }, error = function(e) conditionMessage(e))
}

set_stimulus_asset <- function(bundle, asset) {
  a <- record_assert
  a(!length(validate_bundle(bundle)), "Open a valid draft first.")
  a(!length(bundle$events) && !length(bundle$streams) && !length(bundle$clocks),
    "This bundle contains recording metadata. Create a new study to change images.")
  a(bundle$session$mode %in% c("sample", "preview"), "Only sample and preview drafts can be edited here.")
  errors <- validate_stimulus_assets(list(asset), bundle$study$stimulus_ids)
  a(!length(errors), paste(errors, collapse = "; "))
  assets <- bundle$study$stimulus_assets
  if (is.null(assets)) assets <- list()
  index <- which(vapply(assets, function(x) identical(x$stimulus_id, asset$stimulus_id), logical(1)))
  if (length(index) && identical(assets[[index]], asset)) return(bundle)
  if (!length(index)) index <- length(assets) + 1L
  assets[[index]] <- asset
  bundle$study$stimulus_assets <- assets
  if ("aois" %in% names(bundle$study)) {
    bundle$study$aois <- Filter(function(region) !identical(region$stimulus_id, asset$stimulus_id), bundle$study$aois)
  }
  bundle$study$revision <- bundle$study$revision + 1
  bundle$session$study_revision <- bundle$study$revision
  errors <- validate_bundle(bundle)
  a(!length(errors), paste(errors, collapse = "; "))
  bundle
}
