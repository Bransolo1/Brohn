args <- commandArgs(trailingOnly = TRUE)
arg <- function(name, default = NULL) {i <- match(name, args); if (is.na(i)) return(default); if (i == length(args)) stop("Missing ", name); args[[i+1L]]}
root <- arg("--root", Sys.getenv("BROHN_WORKSPACE", ""))
if (!nzchar(root)) stop("Choose --root PATH for the worker workspace.")
source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = FALSE)
publication<-brohn_publication_readiness()
brohn_require(isTRUE(publication$ready),paste("Report publication is not ready.",publication$message,publication$action))
local({
  store <- brohn_open_store(root); on.exit(brohn_close_store(store), add = TRUE)
  worker <- brohn_id("worker"); cat("Brohn analysis worker ready\n"); flush.console()
  repeat {
    job <- brohn_claim_job(store, worker, 60)
    if (!is.null(job)) brohn_process_job(store, job) else Sys.sleep(.5)
    if ("--once" %in% args) break
  }
})
