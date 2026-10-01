# Inactive, private server-instance composition. No loader or route activation.
.brohn_pvcp_time <- function() unname(proc.time()[["elapsed"]])
.brohn_pvcp_generation <- function() {
  code <- environment(.brohn_participant_view_context_pool)
  name <- ".brohn_participant_view_server_generation"
  .brohn_pvds_require(environmentIsLocked(code) && exists(name, code, inherits = FALSE) &&
    bindingIsLocked(name, code) && !bindingIsActive(name, code),
    "A sealed server validation generation is required.", "server_generation", 503L)
  registration <- get(name, code, inherits = FALSE)
  .brohn_pvds_require(is.function(registration), "Invalid server generation registration.", "server_generation", 503L)
  g <- registration()
  fields <- c("schema", "generation_hash", "code_environment")
  .brohn_pvds_require(is.environment(g) && is.null(attributes(g)) &&
    identical(parent.env(g), emptyenv()) && environmentIsLocked(g) &&
    setequal(ls(g, all.names = TRUE), fields) &&
    all(vapply(fields, bindingIsLocked, logical(1), env = g)) &&
    !any(vapply(fields, bindingIsActive, logical(1), env = g)),
    "Invalid server generation registration.", "server_generation", 503L)
  .brohn_pvds_require(identical(g$schema, "participant-context-server-generation/0.1") &&
    .brohn_pvds_hash(g$generation_hash) && is.null(attributes(g$generation_hash)) &&
    identical(g$code_environment, code) &&
    all(vapply(ls(code, all.names = TRUE), bindingIsLocked, logical(1), env = code)) &&
    !any(vapply(ls(code, all.names = TRUE), bindingIsActive, logical(1), env = code)),
    "The registered generation is not this sealed server implementation.", "server_generation", 503L)
  g
}

.brohn_pvcp_proof <- function(s) {
  # Authorization is performed by run_snapshot on every request. No credential
  # hash, ACK, status, equipment permission or replay result is retained here.
  run <- .brohn_pvds_run_pin(s$run)
  run <- run[setdiff(names(run), "run_credential")]
  release <- .brohn_pvds_release_pin(s$metadata)
  release <- release[setdiff(names(release), "release_credential")]
  list(bodies = s$bodies, presentation = s$presentation, receipt = s$receipt,
    release = release, run = run)
}

.brohn_pvcp_shape <- function(env) list(parent = parent.env(env), attributes = attributes(env),
  names = ls(env, all.names = TRUE), locked = environmentIsLocked(env),
  bindings = vapply(ls(env, all.names = TRUE), bindingIsLocked, logical(1), env = env),
  active = vapply(ls(env, all.names = TRUE), bindingIsActive, logical(1), env = env))

.brohn_pvcp_graph <- function(context, proof, code, maximum = 128 * 1024^2) {
  # A conservative eligibility charge, not process RSS. Ordinary aliases may be
  # charged repeatedly. Environments are identity-deduplicated and all bindings
  # are traversed; object.size(environment) alone is never used as an estimate.
  bytes <- 0; nodes <- 0; seen <- list(); shapes <- list()
  fail <- function() stop("context graph is ineligible", call. = FALSE)
  add <- function(n) { bytes <<- bytes + n; if (!is.finite(bytes) || bytes > maximum) fail() }
  tryCatch({
    brohn_assert_participant_view_context(context)
    if (!is.null(attributes(context))) fail()
    frame <- environment(context$binding)
    if (!is.environment(frame) || !identical(parent.env(frame), code) || !is.null(attributes(frame))) fail()
    methods <- c("binding", "step", "question", "task", "choice", "occurrence", "resource", "policy")
    if (!all(vapply(methods, function(n) identical(environment(get(n, context)), frame), logical(1)))) fail()
    allowed_frame <- c("protocol", "source_protocol_hash", "view_document", "map_document", "view", "map", "design",
      "revision", "occurrences", "r", "p", methods, "result", "values", "name")
    if (!all(ls(frame, all.names = TRUE) %in% allowed_frame)) fail()
    revision <- context$revision_context
    allowed <- list(context, frame)
    if (!is.null(revision)) {
      if (!is.environment(revision) || !identical(parent.env(revision), emptyenv()) ||
        !environmentIsLocked(revision) ||
        !identical(attributes(revision), list(class = "brohn_questionnaire_revision_context"))) fail()
      allowed[[3L]] <- revision
    }
    walk_attributes <- function(x, depth) {
      attrs <- attributes(x)
      if (is.null(attrs)) return(invisible(NULL))
      # attributes() synthesizes a named list. Its own "names" metadata is not
      # part of x's retained graph: charge that container/name overhead directly
      # and recursively inspect only the actual retained attribute VALUES.
      nodes <<- nodes + 2L
      if (nodes > 2000000 || depth + 1L > 128L) fail()
      add(128 + 16 * length(attrs) + 128 + as.numeric(utils::object.size(names(attrs))))
      for (value in attrs) walk(value, depth + 1L)
      invisible(NULL)
    }
    walk <- function(x, depth = 0L) {
      nodes <<- nodes + 1
      if (nodes > 2000000 || depth > 128L) fail()
      if (is.environment(x)) {
        if (identical(x, code) || identical(x, emptyenv())) return(invisible(NULL))
        if (!any(vapply(allowed, identical, logical(1), y = x))) fail()
        if (any(vapply(seen, identical, logical(1), y = x))) return(invisible(NULL))
        seen[[length(seen) + 1L]] <<- x
        shape <- .brohn_pvcp_shape(x)
        if (any(shape$active)) fail()
        if (!identical(x, frame) && (!shape$locked || !all(shape$bindings))) fail()
        shapes[[length(shapes) + 1L]] <<- shape
        # Charge frame/binding/promise overhead in addition to complete values.
        add(4096 + 1024 * length(shape$names))
        walk_attributes(x, depth)
        for (n in shape$names) walk(get(n, x, inherits = FALSE), depth + 1L)
        walk(parent.env(x), depth + 1L)
      } else if (is.function(x)) {
        if (typeof(x) != "closure" || !identical(environment(x), frame) || !is.null(attributes(x))) fail()
        add(1024 + as.numeric(utils::object.size(x)))
        walk(environment(x), depth + 1L)
      } else if (typeof(x) == "list") {
        if (is.object(x)) fail()
        add(128 + 16 * length(x))
        walk_attributes(x, depth)
        for (v in x) walk(v, depth + 1L)
      } else if (is.null(x) || typeof(x) %in% c("logical", "integer", "double", "character", "raw")) {
        if (is.object(x)) fail()
        add(128 + as.numeric(utils::object.size(x)))
        # Atomic attributes can contain references; do not ignore them.
        walk_attributes(x, depth)
      } else fail()
      invisible(NULL)
    }
    walk(list(context = context, proof = proof))
    # Bounded bookkeeping: at most three known environments, their shape
    # snapshots, entry key and vectors. Include this retention in the charge.
    if (length(seen) > 3L || any(vapply(shapes, function(s) length(s$names) > 64L, logical(1)))) fail()
    add(65536)
    list(eligible = TRUE, bytes = bytes, nodes = nodes, environments = seen, shapes = shapes)
  }, error = function(c) list(eligible = FALSE, bytes = bytes, nodes = nodes))
}

.brohn_pvcp_shapes_current <- function(graph) {
  isTRUE(graph$eligible) && length(graph$environments) == length(graph$shapes) &&
    all(vapply(seq_along(graph$environments), function(i)
      identical(.brohn_pvcp_shape(graph$environments[[i]]), graph$shapes[[i]]), logical(1)))
}

.brohn_pvcp_plain_result <- function(x, depth = 0L) {
  # A trusted coordinator may return bytes/plain documents, never a borrowed
  # environment/closure/handle. This is not a new JSON/schema admission API.
  if (depth > 128L || is.object(x)) return(FALSE)
  attrs <- attributes(x)
  if (!is.null(attrs) && !all(vapply(attrs, .brohn_pvcp_plain_result, logical(1), depth = depth + 1L))) return(FALSE)
  if (typeof(x) == "list") return(all(vapply(x, .brohn_pvcp_plain_result, logical(1), depth = depth + 1L)))
  is.null(x) || typeof(x) %in% c("logical", "integer", "double", "character", "raw")
}

.brohn_participant_view_context_pool <- function(store) {
  .brohn_pvds_ready(store)
  generation <- .brohn_pvcp_generation(); code <- generation$code_environment
  con <- store$con; root <- normalizePath(store$root, winslash = "/", mustWork = TRUE); workspace <- store$workspace_id
  entries <- list(); closed <- FALSE; busy <- FALSE; reason <- NULL; borrowed <- NULL
  hits <- 0L; misses <- 0L; fallbacks <- 0L; evictions <- 0L
  maximum_entries <- 2L; maximum_bytes <- 128 * 1024^2; idle_seconds <- 300
  retire <- function(why) { entries <<- list(); closed <<- TRUE; reason <<- why; invisible(NULL) }
  live <- function() {
    if (closed) return(FALSE)
    same <- tryCatch(DBI::dbIsValid(con) && identical(con, store$con) && identical(workspace, store$workspace_id) &&
      identical(root, normalizePath(store$root, winslash = "/", mustWork = TRUE)) &&
      identical(.brohn_pvcp_generation(), generation), error = function(c) FALSE)
    if (!isTRUE(same)) { retire("store_or_generation_changed"); return(FALSE) }
    TRUE
  }
  expire <- function(now) {
    if (!length(entries)) return(invisible(NULL))
    keep <- vapply(entries, function(x) now >= x$used && now - x$used < idle_seconds, logical(1))
    evictions <<- evictions + sum(!keep); entries <<- entries[keep]; invisible(NULL)
  }
  charged <- function() {
    n <- sum(vapply(entries, function(x) x$graph$bytes, numeric(1)))
    if (!is.null(borrowed) && !any(vapply(entries, function(x) identical(x$context, borrowed$context), logical(1))))
      n <- n + borrowed$bytes
    n
  }
  with_open <- function(public_run_id, access_token, fn) {
    .brohn_pvds_require(live(), "This server context pool is closed or replaced.", "server_generation", 503L)
    .brohn_pvds_require(!busy && is.function(fn), "Only one owned context operation may run at a time.", "context_operation")
    .brohn_pvds_require(.brohn_pvc_key(public_run_id, "pvu") && brohn_text(access_token, 128L),
      "Run access is required.", "unauthorized", 401L)
    busy <<- TRUE; handle <- NULL; success <- FALSE
    on.exit({
      if (!is.null(handle)) handle$close()
      if (!success) entries <<- list()
      borrowed <<- NULL
      busy <<- FALSE
      if (live()) expire(.brohn_pvcp_time())
    }, add = TRUE)
    expire(.brohn_pvcp_time())
    # Never consult an entry until the actual current credential, hosted policy,
    # source/runtime registration, size/type and complete raw snapshot checks run.
    s <- .brohn_pvds_run_snapshot(store, public_run_id, access_token)
    .brohn_pvds_run_integrity(s)
    proof <- .brohn_pvcp_proof(s)
    index <- which(vapply(entries, function(x) identical(x$public_run_id, public_run_id), logical(1)))
    entry <- if (length(index)) entries[[index[[1L]]]] else NULL
    reuse <- !is.null(entry) && identical(entry$proof, proof) && .brohn_pvcp_shapes_current(entry$graph)
    if (!is.null(entry) && !reuse) {
      entries <<- entries[-index]; evictions <<- evictions + 1L
      entry <- NULL # Do not retain an uncharged evicted context in this frame.
    }
    context <- if (reuse) { hits <<- hits + 1L; entry$context } else {
      misses <<- misses + 1L; .brohn_pvds_admit(s, store)
    }
    # This is the unchanged real handle; its constructor performs a second fresh
    # source/authority fence after a cold admission or warm proof match.
    handle <- .brohn_pvds_handle(store, s, context, access_token, "existing")
    .brohn_pvds_require(live(), "Server generation changed during source admission.", "server_generation", 503L)
    if (reuse) {
      entries[[index[[1L]]]]$used <<- .brohn_pvcp_time()
      borrowed <<- list(context = context, bytes = entry$graph$bytes)
    } else {
      graph <- .brohn_pvcp_graph(context, proof, code, maximum_bytes)
      if (isTRUE(graph$eligible)) {
        while (length(entries) >= maximum_entries || (length(entries) && charged() + graph$bytes > maximum_bytes)) {
          oldest <- which.min(vapply(entries, function(x) x$used, numeric(1)))
          entries <<- entries[-oldest]; evictions <<- evictions + 1L
        }
        entries[[length(entries) + 1L]] <<- list(public_run_id = public_run_id, context = context,
          proof = proof, graph = graph, used = .brohn_pvcp_time())
        borrowed <<- list(context = context, bytes = graph$bytes)
      } else fallbacks <<- fallbacks + 1L
    }
    result <- fn(handle)
    .brohn_pvds_require(.brohn_pvcp_plain_result(result), "An operation cannot return a borrowed context or handle.", "context_escape")
    handle$current()
    .brohn_pvds_require(live(), "Server generation changed during the operation.", "server_generation", 503L)
    success <- TRUE
    result
  }
  result <- new.env(parent = emptyenv())
  result$with_open <- with_open
  result$close <- function() { retire("closed"); invisible(TRUE) }
  result$stats <- function() {
    if (live() && !busy) expire(.brohn_pvcp_time())
    list(schema = "participant-context-pool-stats/0.1", closed = closed, reason = reason,
      entries = length(entries), retained_charge_bytes = charged(), active_operation = busy,
      hits = hits, misses = misses, fallbacks = fallbacks, evictions = evictions)
  }
  lockEnvironment(result, bindings = TRUE)
  result
}
