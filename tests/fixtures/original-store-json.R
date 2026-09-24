# Frozen original encoder from e35db46; platform-store.R SHA256 0a4a4ee4361b887b2665f4a2105c48f505335975bdf2270d1496b8a951117238.
# Independent byte/error oracle. Never delegate its encoding to the optimized helper.
.brohn_reference_store_json <- function(body, maximum = 16 * 1024 * 1024) {
  encode <- function(x, depth = 0L) {
    .brohn_store_assert(depth <= 64L, "JSON nesting exceeds 64 levels.")
    if (is.null(x)) return("null")
    if (is.list(x) && !is.object(x)) {
      n <- names(x)
      if (!is.null(n)) {
        .brohn_store_assert(!anyNA(n) && all(nzchar(n)) && !anyDuplicated(n),
          "JSON object keys must be nonempty and unique.")
        order <- order(enc2utf8(n), method = "radix")
        entries <- vapply(order, function(i) paste0(encode(enc2utf8(n[[i]]), depth + 1L),
          ":", encode(x[[i]], depth + 1L)), character(1))
        return(paste0("{", paste(entries, collapse = ","), "}"))
      }
      return(paste0("[", paste(vapply(x, encode, character(1), depth = depth + 1L),
        collapse = ","), "]"))
    }
    force_array <- inherits(x, "AsIs")
    if (force_array) x <- unclass(x)
    .brohn_store_assert(!is.object(x) && is.null(dim(x)) && is.null(names(x)) &&
      (is.character(x) || is.logical(x) || is.numeric(x)), "Unsupported JSON value; use plain lists and scalars.")
    .brohn_store_assert(!anyNA(x) && (!is.numeric(x) || all(is.finite(x))),
      "JSON values cannot contain NA or non-finite numbers; use explicit NULL.")
    if (is.character(x)) .brohn_store_assert(!anyNA(iconv(x, from = "", to = "UTF-8")),
      "JSON text must be valid UTF-8.")
    if (length(x) != 1L || force_array) {
      return(paste0("[", paste(vapply(as.list(x), encode, character(1), depth = depth + 1L),
        collapse = ","), "]"))
    }
    # Match the protocol/report encoder's binary64 precision. jsonlite's NA
    # setting rounds to about fifteen significant digits in this pinned build.
    as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = 17))
  }
  value <- encode(body)
  .brohn_store_assert(nchar(value, type = "bytes") <= maximum,
    "JSON payload exceeds the catalog limit; store bulk data as objects.", "too_large")
  value
}
