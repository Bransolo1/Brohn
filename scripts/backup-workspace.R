# Local administrative command; run from the repository root. All destinations
# must be absent and have an existing parent. Backups contain private research data.
args <- commandArgs(trailingOnly = TRUE)
if (!length(args) || !args[[1]] %in% c("backup", "verify", "restore", "resume"))
  stop("Usage: backup-workspace.R backup|verify|restore|resume --root PATH --backup PATH --destination PATH")
operation <- args[[1]]
argument <- function(name) {
  index <- match(name, args)
  if (is.na(index) || index == length(args)) stop("Missing required argument ", name)
  args[[index + 1L]]
}
source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = FALSE)
result <- local({
  if (operation == "verify") {
    checked <- brohn_verify_backup(argument("--backup"))
    return(list(path = checked$path, verified = checked$verified, backup_id = checked$manifest$id,
      object_count = checked$object_count, total_bytes = checked$total_bytes))
  }
  if (operation == "restore") return(brohn_restore_workspace(argument("--backup"), argument("--destination")))
  store <- brohn_open_store(argument("--root"))
  on.exit(brohn_close_store(store), add = TRUE)
  if (operation == "backup") brohn_backup_workspace(store, argument("--destination")) else brohn_resume_workspace(store)
})
cat(.brohn_store_json(result), "\n")
