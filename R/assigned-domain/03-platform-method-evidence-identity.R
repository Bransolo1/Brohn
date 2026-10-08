# Implementation provenance only. No stores, participant scores or qualification.
.brohn_mei_need <- function(ok, message) if (!isTRUE(ok)) stop(message, call. = FALSE)
.brohn_mei_order <- function(x) x[order(x, method = "radix")]
.brohn_mei_plain <- function(x) {
  a <- attributes(x)
  .brohn_mei_need(is.null(a) || (typeof(x) == "list" && identical(names(a), "names")), "Implementation values need plain JSON types.")
}
.brohn_mei_fields <- function(x, fields, label) {
  .brohn_mei_plain(x)
  .brohn_mei_need(typeof(x) == "list" && !is.null(names(x)) && !anyNA(names(x)) &&
    !anyDuplicated(names(x)) && setequal(names(x), fields), paste(label, "has unsupported or missing fields."))
}
.brohn_mei_array <- function(x) typeof(x) == "list" && is.null(attributes(x))
.brohn_mei_token <- function(x, maximum = 200L, pattern = "^[A-Za-z0-9._/+:-]+$") {
  is.null(attributes(x)) && typeof(x) == "character" && length(x) == 1L && !is.na(x) &&
    isTRUE(validUTF8(x)) && nchar(x, type = "bytes") <= maximum && grepl(pattern, x)
}
.brohn_mei_sha <- function(x) .brohn_mei_token(x, 64L, "^[0-9a-f]{64}$")
.brohn_mei_integer <- function(x, maximum) is.null(attributes(x)) && typeof(x) %in% c("integer", "double") &&
  length(x) == 1L && !is.na(x) && is.finite(x) && x >= 1 && x <= maximum && x == floor(x)
.brohn_mei_paths <- function() c("R/platform-core.R", "R/platform-store.R", "R/platform-methods.R",
  "R/platform-gnat.R", "R/platform-sciat-window.R", "R/platform-method-evidence.R",
  "R/platform-method-evidence-binding.R", "R/platform-method-evidence-ancestry.R",
  "R/platform-load.R", "R/platform-method-evidence-identity.R")
.brohn_mei_codecs <- function() list(protocol = "brohn-protocol-json/0.1", store = "brohn-store-json/0.1")

# Closed fields contain only safe ASCII tokens and positive whole numbers.
# No current JSON-library formatting participates in historical manifest hashes.
.brohn_mei_encode <- function(x) {
  .brohn_mei_plain(x)
  if (typeof(x) == "list") {
    n <- names(x)
    if (is.null(n)) return(paste0("[", paste(vapply(x, .brohn_mei_encode, character(1)), collapse = ","), "]"))
    .brohn_mei_need(!anyNA(n) && !anyDuplicated(n) && all(grepl("^[a-z][a-z0-9_]*$", n)), "Noncanonical implementation object key.")
    o <- order(n, method = "radix")
    return(paste0("{", paste(paste0('"', n[o], '":', vapply(x[o], .brohn_mei_encode, character(1))), collapse = ","), "}"))
  }
  if (.brohn_mei_token(x, 1000L)) return(paste0('"', x, '"'))
  .brohn_mei_need(.brohn_mei_integer(x, 16 * 1024^2), "Noncanonical implementation scalar.")
  sprintf("%.0f", x)
}
.brohn_mei_runtime_validate <- function(x) {
  .brohn_mei_fields(x, c("r_version", "platform", "endian", "jsonlite", "digest"), "Implementation runtime")
  version <- "^[0-9]+([.][0-9]+)+([-+][A-Za-z0-9.]+)?$"
  .brohn_mei_need(all(vapply(x[c("r_version", "jsonlite", "digest")], .brohn_mei_token, logical(1), maximum = 100L, pattern = version)) &&
    .brohn_mei_token(x$platform, 200L, "^[A-Za-z0-9._+-]+$") &&
    .brohn_mei_token(x$endian, 6L) && x$endian %in% c("little", "big"), "Implementation runtime declarations are invalid.")
  invisible(TRUE)
}
brohn_method_evidence_manifest_validate <- function(manifest) {
  x <- manifest
  .brohn_mei_fields(x, c("schema", "closure", "resolver", "codecs", "load_order", "sources", "runtime"), "Implementation manifest")
  .brohn_mei_need(identical(x$schema, "brohn-method-evidence-implementation/0.1") &&
    identical(x$closure, "brohn-task-evidence-closure/0.1") &&
    identical(x$resolver, "brohn-task-evidence-resolver/0.1"), "Unsupported implementation schema, closure or resolver.")
  .brohn_mei_fields(x$codecs, c("protocol", "store"), "Implementation codecs")
  .brohn_mei_need(identical(x$codecs$protocol, .brohn_mei_codecs()$protocol) &&
    identical(x$codecs$store, .brohn_mei_codecs()$store), "Unsupported implementation codec IDs.")
  paths <- .brohn_mei_paths()
  .brohn_mei_need(.brohn_mei_array(x$load_order) && identical(x$load_order, as.list(paths)), "Implementation load order differs from its closed closure.")
  .brohn_mei_need(.brohn_mei_array(x$sources) && length(x$sources) == length(paths), "Implementation needs its complete source closure.")
  names <- vapply(x$sources, function(s) {
    .brohn_mei_fields(s, c("path", "bytes", "sha256"), "Implementation source")
    .brohn_mei_need(.brohn_mei_token(s$path, 200L) && .brohn_mei_integer(s$bytes, 4 * 1024^2) && .brohn_mei_sha(s$sha256), "Implementation source path, bytes or SHA256 is invalid.")
    s$path
  }, character(1))
  .brohn_mei_need(identical(names, .brohn_mei_order(paths)), "Implementation source inventory needs the unique sorted allowlist.")
  .brohn_mei_need(sum(vapply(x$sources, function(s) s$bytes, numeric(1))) <= 16 * 1024^2, "Implementation source closure exceeds 16 MiB.")
  .brohn_mei_runtime_validate(x$runtime)
  .brohn_mei_need(nchar(.brohn_mei_encode(x), type = "bytes") <= 64 * 1024, "Implementation manifest exceeds 64 KiB.")
  invisible(manifest)
}
brohn_method_evidence_manifest_hash <- function(manifest) {
  brohn_method_evidence_manifest_validate(manifest)
  digest::digest(charToRaw(paste0("brohn-method-evidence-implementation/0.1\n", .brohn_mei_encode(manifest))), algo = "sha256", serialize = FALSE)
}
.brohn_mei_ref <- function(manifest) list(schema = "brohn-method-evidence-resolver-implementation/0.1",
  resolver = manifest$resolver, source_manifest_sha256 = brohn_method_evidence_manifest_hash(manifest))
.brohn_mei_required <- function(wrapper) {
  # Independent public validation; no caller-supplied skip flag.
  brohn_method_evidence_envelope_validate(wrapper)
  refs <- c(list(wrapper$current$implementation_ref), lapply(wrapper$ancestry$nodes, function(n) n$current$implementation_ref))
  .brohn_mei_need(all(vapply(refs, function(r) identical(r$resolver, "brohn-task-evidence-resolver/0.1"), logical(1))), "Unsupported referenced implementation resolver.")
  .brohn_mei_order(unique(vapply(refs, function(r) r$source_manifest_sha256, character(1))))
}
brohn_method_evidence_inventory_validate <- function(inventory, wrapper) {
  .brohn_mei_fields(inventory, c("schema", "entries"), "Implementation inventory")
  .brohn_mei_need(identical(inventory$schema, "brohn-method-evidence-implementations/0.1") &&
    .brohn_mei_array(inventory$entries) && length(inventory$entries) >= 1L && length(inventory$entries) <= 256L, "Unsupported or oversized implementation inventory.")
  hashes <- vapply(inventory$entries, function(entry) {
    .brohn_mei_fields(entry, c("sha256", "manifest"), "Implementation inventory entry")
    .brohn_mei_need(.brohn_mei_sha(entry$sha256) && identical(entry$sha256, brohn_method_evidence_manifest_hash(entry$manifest)), "Retained implementation manifest hash mismatch.")
    entry$sha256
  }, character(1))
  .brohn_mei_need(!anyDuplicated(hashes) && identical(hashes, .brohn_mei_order(hashes)), "Saved implementation entries need unique canonical order.")
  .brohn_mei_need(identical(hashes, .brohn_mei_required(wrapper)), "Implementation inventory has missing or unreferenced manifests.")
  .brohn_mei_need(nchar(.brohn_mei_encode(inventory), type = "bytes") <= 16 * 1024^2, "Implementation inventory exceeds 16 MiB.")
  invisible(inventory)
}
brohn_method_evidence_inventory <- function(manifests, wrapper) {
  .brohn_mei_need(.brohn_mei_array(manifests) && length(manifests) >= 1L && length(manifests) <= 256L, "Supply a bounded manifest array.")
  hashes <- vapply(manifests, brohn_method_evidence_manifest_hash, character(1))
  for (h in unique(hashes)) {
    copies <- manifests[hashes == h]
    .brohn_mei_need(length(unique(vapply(copies, .brohn_mei_encode, character(1)))) == 1L, "Conflicting implementation values share a hash.")
  }
  order <- order(hashes, method = "radix"); order <- order[!duplicated(hashes[order])]
  result <- list(schema = "brohn-method-evidence-implementations/0.1",
    entries = lapply(order, function(i) list(sha256 = hashes[[i]], manifest = manifests[[i]])))
  brohn_method_evidence_inventory_validate(result, wrapper)
  result
}

.brohn_mei_runtime <- function() list(r_version = as.character(getRversion()), platform = R.version$platform,
  endian = .Platform$endian, jsonlite = as.character(utils::packageVersion("jsonlite")), digest = as.character(utils::packageVersion("digest")))
.brohn_mei_root <- function(root) {
  .brohn_mei_need(is.null(attributes(root)) && is.character(root) && length(root) == 1L && !is.na(root) &&
    validUTF8(root) && nchar(root, type = "bytes") <= 4096L && dir.exists(root), "Choose an installed source root.")
  link <- Sys.readlink(root)
  .brohn_mei_need(!is.na(link) && !nzchar(link), "Implementation root must not be a symbolic link.")
  normalizePath(root, winslash = "/", mustWork = TRUE)
}
.brohn_mei_file <- function(root, relative) {
  .brohn_mei_need(relative %in% .brohn_mei_paths(), "Source path is outside the implementation allowlist.")
  parts <- strsplit(relative, "/", fixed = TRUE)[[1L]]; path <- root
  fold <- function(x) if (.Platform$OS.type == "windows") tolower(x) else x
  for (part in parts) {
    path <- file.path(path, part); link <- Sys.readlink(path)
    .brohn_mei_need(file.exists(path) && !is.na(link) && !nzchar(link), "Implementation source is missing or linked.")
    resolved <- normalizePath(path, winslash = "/", mustWork = TRUE)
    .brohn_mei_need(startsWith(fold(resolved), paste0(sub("/+$", "", fold(root)), "/")), "Implementation source resolves outside its root.")
  }
  .brohn_mei_need(utils::file_test("-f", path) && !isTRUE(file.info(path)$isdir), "Implementation source must be a regular file.")
  size <- file.info(path)$size
  .brohn_mei_need(is.finite(size) && size >= 1 && size <= 4 * 1024^2, "Implementation source exceeds its byte bound.")
  con <- file(path, "rb"); on.exit(close(con), add = TRUE)
  bytes <- readBin(con, "raw", n = 4 * 1024^2 + 1L)
  .brohn_mei_need(length(bytes) == size && !any(bytes == as.raw(0)), "Implementation source changed size or contains NUL bytes.")
  text <- rawToChar(bytes); Encoding(text) <- "UTF-8"
  .brohn_mei_need(validUTF8(text), "Implementation source is not valid UTF-8.")
  list(bytes = bytes, text = text, entry = list(path = relative, bytes = as.numeric(length(bytes)),
    sha256 = digest::digest(bytes, algo = "sha256", serialize = FALSE)))
}
.brohn_mei_read <- function(root) {
  paths <- .brohn_mei_paths()
  captured <- lapply(paths, function(p) .brohn_mei_file(root, p))
  names(captured) <- paths
  sources <- lapply(captured[order(paths, method = "radix")], function(s) s$entry); names(sources) <- NULL
  manifest <- list(schema = "brohn-method-evidence-implementation/0.1", closure = "brohn-task-evidence-closure/0.1",
    resolver = "brohn-task-evidence-resolver/0.1", codecs = .brohn_mei_codecs(), load_order = as.list(paths), sources = sources, runtime = .brohn_mei_runtime())
  brohn_method_evidence_manifest_validate(manifest)
  list(manifest = manifest, captured = captured)
}
.brohn_mei_check <- function(state) {
  current <- .brohn_mei_read(state$root)$manifest
  .brohn_mei_need(identical(.brohn_mei_encode(current), .brohn_mei_encode(state$manifest)),
    "Implementation closure or runtime changed; reload coherently before a prospective write.")
  invisible(TRUE)
}
brohn_method_evidence_identity_load <- function(root) {
  root <- .brohn_mei_root(root)
  captured <- .brohn_mei_read(root)
  # Parse the complete closure before evaluating any captured source.
  parsed <- lapply(captured$captured, function(s) parse(text = s$text, keep.source = FALSE, encoding = "UTF-8"))
  imports <- new.env(parent = baseenv()); imports$setNames <- stats::setNames
  lockEnvironment(imports, bindings = TRUE)
  namespace <- new.env(parent = imports)
  for (expression in parsed) eval(expression, envir = namespace)
  .brohn_mei_need(exists("brohn_method_evidence_bind", envir = namespace, inherits = FALSE) &&
    exists("brohn_method_evidence_envelope_validate", envir = namespace, inherits = FALSE), "Captured implementation lacks its declared entry points.")
  namespace$brohn_method_evidence_manifest_validate(captured$manifest)
  lockEnvironment(namespace, bindings = TRUE)
  state <- new.env(parent = emptyenv())
  state$root <- root; state$manifest <- captured$manifest; state$ref <- namespace$.brohn_mei_ref(captured$manifest)
  state$namespace <- namespace; state$source_bytes <- lapply(captured$captured, function(s) s$bytes)
  lockEnvironment(state, bindings = TRUE)
  namespace$.brohn_mei_check(state)
  facade <- new.env(parent = emptyenv())
  facade$manifest <- function() state$manifest
  facade$implementation_ref <- function() state$ref
  facade$commit_check <- function() state$namespace$.brohn_mei_check(state)
  facade$bind <- function(blocks, context, registry_capture, captured_at, previous = NULL) {
    state$namespace$.brohn_mei_check(state)
    result <- state$namespace$brohn_method_evidence_bind(blocks, context, registry_capture, state$ref, captured_at, previous)
    state$namespace$.brohn_mei_check(state)
    result
  }
  lockEnvironment(facade, bindings = TRUE)
  # Lock the closure's bindings as well as the public methods/private namespace.
  lockEnvironment(environment(facade$bind), bindings = TRUE)
  facade
}
