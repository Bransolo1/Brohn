# Inactive raw request decoder. A successful result is data, never authority.
.brohn_prb_require <- function(ok, message) {
  if (!isTRUE(ok)) stop(message, call. = FALSE)
  invisible(NULL)
}

.brohn_prb_limit <- function(x, upper) {
  typeof(x) %in% c("integer", "double") && is.null(attributes(x)) &&
    length(x) == 1L && !is.na(x) && is.finite(x) && x >= 1 && x <= upper && x == floor(x)
}

# This pass recognizes JSON grammar and bounds before jsonlite materializes a
# tree. It neither constructs values nor changes number/string spellings.
.brohn_prb_scan <- function(raw, maximum_nodes) {
  b <- as.integer(raw); n <- length(b); i <- 1L; nodes <- 0L
  special <- which(b < 32L | b == 34L | b == 92L); at <- 1L
  peek <- function() if (i <= n) b[[i]] else -1L
  whitespace <- function() {
    while (i <= n && b[[i]] %in% c(9L, 10L, 13L, 32L)) i <<- i + 1L
  }
  hex4 <- function(start) {
    .brohn_prb_require(start + 3L <= n, "Received JSON has an incomplete Unicode escape.")
    x <- b[seq.int(start, start + 3L)]
    value <- ifelse(x >= 48L & x <= 57L, x - 48L,
      ifelse(x >= 65L & x <= 70L, x - 55L, ifelse(x >= 97L & x <= 102L, x - 87L, -1L)))
    .brohn_prb_require(all(value >= 0L), "Received JSON has an invalid Unicode escape.")
    sum(value * c(4096L, 256L, 16L, 1L))
  }
  string <- function() {
    .brohn_prb_require(peek() == 34L, "Received JSON requires a quoted string.")
    i <<- i + 1L
    repeat {
      while (at <= length(special) && special[[at]] < i) at <<- at + 1L
      .brohn_prb_require(at <= length(special), "Received JSON has an unterminated string.")
      i <<- special[[at]]; ch <- b[[i]]; at <<- at + 1L
      if (ch == 34L) { i <<- i + 1L; return(invisible(NULL)) }
      .brohn_prb_require(ch == 92L, "Received JSON has an unescaped control character.")
      .brohn_prb_require(i + 1L <= n, "Received JSON has an incomplete string escape.")
      escaped <- b[[i + 1L]]
      if (escaped %in% c(34L, 92L, 47L, 98L, 102L, 110L, 114L, 116L)) {
        i <<- i + 2L
      } else {
        .brohn_prb_require(escaped == 117L, "Received JSON has an invalid string escape.")
        code <- hex4(i + 2L)
        .brohn_prb_require(code != 0L, "Received JSON cannot contain an embedded NUL escape.")
        if (code >= 55296L && code <= 56319L) {
          .brohn_prb_require(i + 11L <= n && b[[i + 6L]] == 92L && b[[i + 7L]] == 117L,
            "Received JSON has an unpaired high surrogate escape.")
          low <- hex4(i + 8L)
          .brohn_prb_require(low >= 56320L && low <= 57343L,
            "Received JSON has an invalid surrogate escape pair.")
          i <<- i + 12L
        } else {
          .brohn_prb_require(code < 56320L || code > 57343L,
            "Received JSON has an unpaired low surrogate escape.")
          i <<- i + 6L
        }
      }
    }
  }
  number <- function() {
    start <- i
    if (peek() == 45L) i <<- i + 1L
    ch <- peek()
    .brohn_prb_require(ch >= 48L && ch <= 57L, "Received JSON has an invalid number.")
    if (ch == 48L) {
      i <<- i + 1L
      .brohn_prb_require(peek() < 48L || peek() > 57L, "Received JSON numbers cannot have leading zeroes.")
    } else {
      while (peek() >= 48L && peek() <= 57L) i <<- i + 1L
    }
    if (peek() == 46L) {
      i <<- i + 1L
      .brohn_prb_require(peek() >= 48L && peek() <= 57L, "Received JSON requires digits after a decimal point.")
      while (peek() >= 48L && peek() <= 57L) i <<- i + 1L
    }
    if (peek() %in% c(69L, 101L)) {
      i <<- i + 1L
      if (peek() %in% c(43L, 45L)) i <<- i + 1L
      .brohn_prb_require(peek() >= 48L && peek() <= 57L, "Received JSON requires exponent digits.")
      while (peek() >= 48L && peek() <= 57L) i <<- i + 1L
    }
    # jsonlite's integer branch loses the sign of this one spelling. The
    # qualified client emits -0.0. Refuse the whole request, never repair it.
    .brohn_prb_require(!(i - start == 2L && b[[start]] == 45L && b[[start + 1L]] == 48L),
      "Received request codec 0.1 refuses bare -0; use the producer spelling -0.0.")
  }
  literal <- function(token) {
    end <- i + length(token) - 1L
    .brohn_prb_require(end <= n && identical(b[seq.int(i, end)], token), "Received JSON has an invalid literal.")
    i <<- end + 1L
  }
  value <- function(depth = 0L) {
    nodes <<- nodes + 1L
    .brohn_prb_require(depth < 64L && nodes <= maximum_nodes, "Received JSON exceeds its traversal limit.")
    whitespace(); ch <- peek()
    if (ch == 34L) { string(); return(invisible(NULL)) }
    # A delimiter proves this unsigned one-digit number is complete. Keep
    # all other spellings and every later container/root check unchanged.
    if (ch >= 48L && ch <= 57L &&
        (i == n || b[[i + 1L]] %in% c(9L, 10L, 13L, 32L, 44L, 93L, 125L))) {
      i <<- i + 1L; return(invisible(NULL))
    }
    if (ch == 45L || (ch >= 48L && ch <= 57L)) { number(); return(invisible(NULL)) }
    if (ch == 110L) { literal(c(110L, 117L, 108L, 108L)); return(invisible(NULL)) }
    if (ch == 116L) { literal(c(116L, 114L, 117L, 101L)); return(invisible(NULL)) }
    if (ch == 102L) { literal(c(102L, 97L, 108L, 115L, 101L)); return(invisible(NULL)) }
    .brohn_prb_require(ch %in% c(91L, 123L), "Received JSON requires exactly one valid JSON value.")
    object <- ch == 123L; close <- if (object) 125L else 93L
    i <<- i + 1L; whitespace()
    if (peek() == close) { i <<- i + 1L; return(invisible(NULL)) }
    repeat {
      if (object) {
        string(); whitespace()
        .brohn_prb_require(peek() == 58L, "Received JSON object key requires a colon.")
        i <<- i + 1L
      }
      value(depth + 1L); whitespace()
      if (peek() == close) { i <<- i + 1L; break }
      .brohn_prb_require(peek() == 44L, "Received JSON container requires a comma or matching close.")
      i <<- i + 1L; whitespace()
    }
    invisible(NULL)
  }
  value(); whitespace()
  .brohn_prb_require(i == n + 1L, "Received JSON has trailing bytes after its value.")
  nodes
}

.brohn_prb_domain <- function(value, maximum_nodes, expected_nodes) {
  nodes <- 0L
  visit <- function(x, depth = 0L) {
    nodes <<- nodes + 1L
    .brohn_prb_require(depth < 64L && nodes <= maximum_nodes, "Decoded request exceeds its traversal limit.")
    attrs <- attributes(x)
    .brohn_prb_require(is.null(attrs) || (typeof(x) == "list" && identical(names(attrs), "names")),
      "Decoded request requires plain JSON values.")
    if (is.null(x)) return(invisible(NULL))
    if (typeof(x) == "list") {
      keys <- names(x)
      if (!is.null(keys)) .brohn_prb_require(!anyNA(keys) && all(nzchar(keys)) && all(validUTF8(keys)) &&
        !anyDuplicated(enc2utf8(keys)), "Decoded request object keys must be nonempty and unique UTF-8 strings.")
      for (child in x) visit(child, depth + 1L)
      return(invisible(NULL))
    }
    .brohn_prb_require(typeof(x) %in% c("logical", "integer", "double", "character") && length(x) == 1L && !is.na(x),
      "Decoded request requires actual scalar JSON values.")
    if (typeof(x) %in% c("integer", "double")) .brohn_prb_require(is.finite(x), "Decoded request numbers must be finite.")
    if (is.character(x)) .brohn_prb_require(validUTF8(x), "Decoded request text must preserve valid UTF-8.")
    invisible(NULL)
  }
  visit(value)
  .brohn_prb_require(nodes == expected_nodes, "Decoded request node accounting differs from the original JSON.")
  invisible(NULL)
}

brohn_participant_received_bytes <- function(raw, maximum_bytes = 4 * 1024^2, maximum_nodes = 2000000L) {
  .brohn_prb_require(.brohn_prb_limit(maximum_bytes, 4 * 1024^2) && .brohn_prb_limit(maximum_nodes, 2000000L),
    "Invalid received request admission limit.")
  .brohn_prb_require(typeof(raw) == "raw" && is.null(attributes(raw)) && length(raw) >= 1L && length(raw) <= maximum_bytes,
    "Received request must be 1 to 4 MiB of actual unclassed raw bytes within the selected limit.")
  .brohn_prb_require(!any(raw == as.raw(0L)), "Received JSON cannot contain an embedded raw NUL byte.")
  text <- rawToChar(raw); Encoding(text) <- "UTF-8"
  .brohn_prb_require(validUTF8(text) && identical(charToRaw(text), raw), "Received JSON must have exact valid UTF-8 bytes.")
  nodes <- .brohn_prb_scan(raw, maximum_nodes)
  original_hash <- digest::digest(raw, algo = "sha256", serialize = FALSE)
  value <- withCallingHandlers(jsonlite::parse_json(text, simplifyVector = FALSE,
    simplifyDataFrame = FALSE, simplifyMatrix = FALSE, bigint_as_char = FALSE),
    warning = function(w) stop(paste("Received JSON parser warning:", conditionMessage(w)), call. = FALSE))
  .brohn_prb_domain(value, maximum_nodes, nodes)
  list(codec = "brohn-participant-request-json/0.1", raw = raw, bytes = length(raw), sha256 = original_hash, value = value)
}
