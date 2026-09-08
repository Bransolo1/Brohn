# Independent local acquisition manager; never part of a Shiny session.
args <- commandArgs(trailingOnly=TRUE)
argument <- function(name,default=NULL) {
  i <- match(name,args); if(is.na(i)) return(default)
  if(i==length(args)) stop("Missing ",name)
  args[[i+1L]]
}
root <- argument("--root",Sys.getenv("BROHN_WORKSPACE",""))
if(!nzchar(root)) stop("Choose --root PATH for the acquisition workspace.")
source("R/platform-load.R",encoding="UTF-8"); brohn_load(ui=FALSE)
if(!exists("brohn_acquisition_manager",mode="function")) source("R/platform-acquisition.R",encoding="UTF-8")
local({
  store <- brohn_open_store(root); on.exit(brohn_close_store(store),add=TRUE)
  manager <- brohn_acquisition_manager(store)
  # Register before the earlier close-store cleanup: final preservation needs
  # the catalog connection until every owned writer has stopped.
  on.exit(brohn_stop_acquisition_manager(store,manager),add=TRUE,after=FALSE)
  cat("Brohn acquisition manager ready\n"); flush.console()
  repeat {
    if(brohn_acquisition_stop_requested(store,manager)) break
    tryCatch(brohn_acquisition_tick(store,manager),error=function(e) {
      cat("Acquisition manager needs attention: ",conditionMessage(e),"\n",sep="",file=stderr())
    })
    if("--once" %in% args) break
    Sys.sleep(.25)
  }
})
