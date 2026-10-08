# Inactive pure assignment algorithms. No compiler, enrollment or delivery hook.
.brohn_vas_decimal <- function(x) sprintf("%.0f", x)
.brohn_vas_policy <- function(design) {
  a <- design$stimulus_assignment
  list(schema = "brohn-assignment-policy/0.1", seed = .brohn_vas_decimal(design$seed),
    allocation = a$allocation, presentation = a$presentation, order = design$order,
    stimuli = as.list(brohn_ids(design$stimuli)),
    sets = lapply(a$sets, function(s) list(id = s$id, concept_id = s$concept_id, selection = s$selection,
      members = lapply(s$members, `[[`, "stimulus_id"))),
    arms = lapply(a$arms, function(x) list(id = x$id, choices = x$choices)))
}
.brohn_vas_rank <- function(messages, ids) {
  ranks <- vapply(messages, brohn_hash, character(1))
  order(ranks, ids, method = "radix")
}
.brohn_vas_arm_rank <- function(a, policy_hash, index, block = FALSE) {
  ids <- brohn_ids(a$arms)
  messages <- lapply(ids, function(id) if (block) list(schema = "brohn-arm-block/0.1",
    policy_hash = policy_hash, block = .brohn_vas_decimal(index), arm_id = id) else
    list(schema = "brohn-arm-draw/0.1", policy_hash = policy_hash,
      allocation_index = .brohn_vas_decimal(index), arm_id = id))
  .brohn_vas_rank(messages, ids)
}
.brohn_vas_receipt <- function(design, allocation_index) {
  a <- design$stimulus_assignment
  policy_hash <- brohn_hash(.brohn_vas_policy(design))
  block <- slot <- arm <- NULL
  if (identical(a$allocation, "blocked-arm-sha256/0.1")) {
    block <- floor((allocation_index - 1) / length(a$arms))
    slot <- (allocation_index - 1) %% length(a$arms)
    arm <- a$arms[[.brohn_vas_arm_rank(a, policy_hash, block, TRUE)[[slot + 1L]]]]
  } else if (identical(a$allocation, "arm-sha256/0.1")) {
    arm <- a$arms[[.brohn_vas_arm_rank(a, policy_hash, allocation_index)[[1L]]]]
  }
  selection <- .brohn_vad_selected(design, arm)
  realized <- selection$selected
  if (length(realized) && identical(design$order, "counterbalanced")) {
    start <- ((allocation_index - 1) %% length(realized)) + 1L
    realized <- c(realized, realized)[seq.int(start, length.out = length(realized))]
  } else if (length(realized) && identical(design$order, "randomized")) {
    messages <- lapply(realized, function(id) list(schema = "brohn-selected-order/0.1", policy_hash = policy_hash,
      allocation_index = .brohn_vas_decimal(allocation_index), stimulus_id = id))
    realized <- realized[.brohn_vas_rank(messages, realized)]
  }
  list(schema = "brohn-run-stimulus-assignment/0.1", policy_hash = policy_hash,
    design_hash = brohn_hash(design), allocation = a$allocation,
    allocation_index = .brohn_vas_decimal(allocation_index), arm_id = if (is.null(arm)) NULL else arm$id,
    block = if (is.null(block)) NULL else .brohn_vas_decimal(block), slot = if (is.null(slot)) NULL else .brohn_vas_decimal(slot),
    sets = selection$sets, always_stimulus_ids = as.list(selection$always),
    selected_stimulus_ids = as.list(selection$selected), realized_stimulus_order = as.list(realized))
}

brohn_stimulus_assignment <- function(design, allocation_index) {
  brohn_validate_variant_design(design)
  brohn_require(brohn_number(allocation_index, 1, 1e9, TRUE) && is.null(attributes(allocation_index)),
    "Allocation index must be an exact unclassed integer from 1 to 1,000,000,000.")
  .brohn_vas_receipt(design, allocation_index)
}

brohn_validate_stimulus_assignment <- function(design, receipt) {
  # A pure receipt check only: not a saved-protocol/current-authority reader.
  brohn_validate_variant_design(design)
  .brohn_vad_domain(receipt)
  brohn_fields(receipt, c("schema", "policy_hash", "design_hash", "allocation", "allocation_index", "arm_id",
    "block", "slot", "sets", "always_stimulus_ids", "selected_stimulus_ids", "realized_stimulus_order"), label = "Assignment receipt")
  text <- receipt$allocation_index
  brohn_require(brohn_text(text, 10) && grepl("^[1-9][0-9]{0,9}$", text) && as.numeric(text) <= 1e9,
    "Receipt allocation index must be a canonical decimal string from 1 to 1,000,000,000.")
  expected <- .brohn_vas_receipt(design, as.numeric(text))
  brohn_require(identical(brohn_json(receipt), brohn_json(expected)), "Assignment receipt differs from its full design, frozen index or algorithm.")
  invisible(receipt)
}

brohn_variant_cartesian_count <- function(member_counts) {
  brohn_require(is.numeric(member_counts) && is.null(attributes(member_counts)) && length(member_counts) <= 250L &&
    !anyNA(member_counts) && all(is.finite(member_counts)) && all(member_counts >= 2 & member_counts <= 500 & member_counts == floor(member_counts)),
    "Cartesian counts require up to 250 bounded whole member counts.")
  count <- 1
  for (n in member_counts) {
    brohn_require(count <= floor(500 / n), "Cartesian allocation exceeds 500 arms; choose an explicit bounded arm table.")
    count <- count * n
  }
  # A design without show-one sets needs no arms.
  if (!length(member_counts)) 0 else count
}

brohn_variant_arm_counts <- function(design, quota) {
  brohn_validate_variant_design(design)
  brohn_require(brohn_number(quota, 0, 1e9, TRUE) && is.null(attributes(quota)), "Quota must be a whole started-run count from 0 to 1,000,000,000.")
  a <- design$stimulus_assignment
  brohn_require(a$allocation %in% c("all/0.1", "blocked-arm-sha256/0.1"),
    "Pseudorandom arm allocation has no exact bounded quota-count preview; use a bounded index page.")
  if (!length(a$arms)) return(list(schema = "brohn-arm-quota-preview/0.1", quota = .brohn_vas_decimal(quota), arms = list()))
  counts <- rep(floor(quota / length(a$arms)), length(a$arms))
  remainder <- quota %% length(a$arms)
  if (remainder) {
    ranks <- .brohn_vas_arm_rank(a, brohn_hash(.brohn_vas_policy(design)), floor(quota / length(a$arms)), TRUE)
    counts[ranks[seq_len(remainder)]] <- counts[ranks[seq_len(remainder)]] + 1
  }
  list(schema = "brohn-arm-quota-preview/0.1", quota = .brohn_vas_decimal(quota),
    arms = lapply(seq_along(a$arms), function(i) list(arm_id = a$arms[[i]]$id, started_runs = .brohn_vas_decimal(counts[[i]]))))
}
