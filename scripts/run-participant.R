# Run from the repository root. This local profile never binds a public address.
args <- commandArgs(trailingOnly = TRUE)
argument <- function(name, default = NULL) {
  index <- match(name, args)
  if (is.na(index)) return(default)
  if (index == length(args)) stop("Missing value for ", name)
  args[[index + 1L]]
}
root <- argument("--root", Sys.getenv("BROHN_WORKSPACE", unset = Sys.getenv("BROHN_DATA_DIR", unset = "")))
if (!nzchar(root)) stop("Choose the workspace with --root PATH or BROHN_WORKSPACE.")
port <- suppressWarnings(as.integer(argument("--port", "3840")))
if (is.na(port) || port < 1024L || port > 65535L) stop("Participant port must be from 1024 to 65535.")
# The launcher supplies the selected library. Do not override it with a local
# development cache: every service must use the installation being checked.
# Use the same domain module closure as the researcher. A separate hand-written
# validator list can release a design successfully then reject it at enrollment.
# Loading domain functions does not expose researcher routes in the HTTP app.
source("R/platform-load.R", encoding = "UTF-8")
brohn_load(ui = FALSE)
local({
  store <- brohn_open_store(root)
  on.exit(brohn_close_store(store), add = TRUE)
  app <- brohn_delivery_app(store, static_root = argument("--static-root", "www/participant"))
  cat(sprintf("Brohn participant service: http://127.0.0.1:%d/participant/\n", port))
  flush.console()
  httpuv::runServer("127.0.0.1", port, app)
})
