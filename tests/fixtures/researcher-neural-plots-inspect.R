# Read-only verification of this harness's already-saved reports and objects.
args <- commandArgs(trailingOnly = TRUE); stopifnot(length(args) == 3L)
source("R/platform-load.R"); brohn_load(ui = FALSE)
store <- brohn_open_store(args[[1L]])
local({
  on.exit(brohn_close_store(store), add = TRUE)
  downloaded <- brohn_read_json_file(args[[2L]])
  record <- brohn_get_entity(store, "report", downloaded$id)
  brohn_require(!is.null(record) && identical(brohn_hash(record$body), brohn_hash(downloaded)), "Downloaded report differs from the saved immutable record.")
  hashes <- list(source = record$body$provenance$source$hash, result = record$body$result_object$hash)
  verified <- lapply(hashes, function(hash) list(hash = hash,
    actual = digest::digest(file = brohn_object_path(store, hash), algo = "sha256", serialize = FALSE)))
  brohn_write_json_file(list(report_id = record$id, report_hash = brohn_hash(record$body), objects = verified), args[[3L]])
})
