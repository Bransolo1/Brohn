# Inactive, separately versioned wire JSON. Never substitutes a scientific hash.
brohn_participant_json_bytes <- function(value, maximum_bytes = 16 * 1024^2, maximum_nodes = 2000000L) {
  brohn_require(brohn_number(maximum_bytes, 1, 16 * 1024^2, TRUE) &&
    brohn_number(maximum_nodes, 1, 2000000L, TRUE), "Invalid participant JSON admission limit.")
  chunks <- list(); count <- 0L; total <- 0; nodes <- 0L
  emit <- function(text) {
    bytes <- nchar(text, type = "bytes"); total <<- total + bytes
    brohn_require(total <= maximum_bytes, "Participant JSON exceeds its stored byte limit.")
    count <<- count + 1L; chunks[[count]] <<- text
  }
  quote <- function(text) {
    brohn_require(.brohn_vad_text_encoding(text), "Participant JSON text must have valid original encoding.")
    brohn_require(nchar(enc2utf8(text), type = "bytes") + 2 <= maximum_bytes - total,
      "Participant JSON text exceeds its remaining byte limit.")
    as.character(jsonlite::toJSON(enc2utf8(text), auto_unbox = TRUE, null = "null", na = "null"))
  }
  number <- function(x) {
    if (x == 0 && is.infinite(1 / x) && 1 / x < 0) return("-0.0")
    text <- sprintf("%.17g", as.double(x))
    decimal <- Sys.localeconv()[["decimal_point"]]
    if (nzchar(decimal) && decimal != ".") text <- gsub(decimal, ".", text, fixed = TRUE)
    brohn_require(grepl("^-?(0|[1-9][0-9]*)([.][0-9]+)?([eE][+-]?[0-9]+)?$", text), "Participant JSON number could not be encoded exactly.")
    text
  }
  visit <- function(x, depth = 0L) {
    nodes <<- nodes + 1L
    brohn_require(nodes <= maximum_nodes && depth < 64L, "Participant JSON exceeds its traversal limit.")
    attrs <- attributes(x)
    brohn_require(is.null(attrs) || (typeof(x) == "list" && identical(names(attrs), "names")), "Participant JSON requires plain values.")
    if (is.null(x)) {emit("null"); return(invisible(NULL))}
    if (typeof(x) == "list") {
      keys <- names(x); object <- !is.null(keys)
      if (object) {
        brohn_require(!anyNA(keys) && all(nzchar(keys)) && .brohn_vad_text_encoding(keys) && !anyDuplicated(enc2utf8(keys)),
          "Participant JSON object keys must be valid, nonempty and unique.")
        brohn_require(sum(nchar(enc2utf8(keys), type = "bytes")) + 3 * length(keys) + 2 <= maximum_bytes - total,
          "Participant JSON object keys exceed its remaining byte limit.")
        # ASCII hexadecimal lexicographic order is exact UTF-8 byte order,
        # independent of the host collation locale.
        hex <- vapply(enc2utf8(keys), function(k) paste(format(charToRaw(k)), collapse = ""), character(1))
        order <- order(hex, method = "radix")
      } else order <- seq_along(x)
      emit(if (object) "{" else "[")
      for (position in seq_along(order)) {
        i <- order[[position]]
        if (position > 1L) emit(",")
        if (object) {emit(quote(keys[[i]])); emit(":")}
        visit(x[[i]], depth + 1L)
      }
      emit(if (object) "}" else "]"); return(invisible(NULL))
    }
    brohn_require(typeof(x) %in% c("character", "logical", "integer", "double") && length(x) == 1L && !is.na(x), "Participant JSON scalars must have one actual value.")
    if (is.character(x)) emit(quote(x)) else if (is.logical(x)) emit(if (x) "true" else "false") else {
      brohn_require(is.finite(x), "Participant JSON numbers must be finite."); emit(number(x))
    }
    invisible(NULL)
  }
  visit(value)
  json <- paste0(unlist(chunks, use.names = FALSE), collapse = "")
  Encoding(json) <- "UTF-8"
  bytes <- charToRaw(json)
  brohn_require(length(bytes) == total && validUTF8(json), "Participant JSON byte accounting differs.")
  list(codec = "brohn-participant-json-bytes/0.1", json = json, bytes = length(bytes),
    sha256 = digest::digest(bytes, algo = "sha256", serialize = FALSE))
}
