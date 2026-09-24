# Only bootstrap renv in the caller-selected library; never activate the project.
local({
args <- commandArgs(trailingOnly=TRUE)
if(length(args)!=3L)stop("Usage: bootstrap-dependencies.R bootstrap-library exact-renv-version exact-R-version")
if(as.character(getRversion())!=args[[3L]])stop("Install R ",args[[3L]]," before running Brohn setup.")
if(!grepl("^[0-9]+[.][0-9]+[.][0-9]+$",args[[2L]]))stop("Invalid pinned renv version")
dir.create(args[[1L]],recursive=TRUE,showWarnings=FALSE)
target<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE)
if(identical(target,normalizePath(.Library,winslash="/")))stop("Use a separate bootstrap library")
.libPaths(c(target,.Library),include.site=FALSE)
if(!dir.exists(file.path(target,"renv"))) {
  # Both URLs identify the requested version. A current-version source may not
  # yet be in CRAN's archive. Neither route substitutes the latest package.
  version<-args[[2L]];filename<-paste0("renv_",version,".tar.gz")
  urls<-c(paste0("https://cloud.r-project.org/src/contrib/Archive/renv/",filename),paste0("https://cloud.r-project.org/src/contrib/",filename))
  archive<-tempfile("brohn-renv-",fileext=".tar.gz");on.exit(unlink(archive),add=TRUE)
  downloaded<-FALSE
  for(url in urls) {
    status<-tryCatch(suppressWarnings(download.file(url,archive,mode="wb",quiet=TRUE)),error=function(e)1L)
    if(identical(status,0L)){downloaded<-TRUE;break}
  }
  if(!downloaded)stop("Could not download pinned renv ",version,". Check network access and retry; no application configuration was changed.")
  install.packages(archive,repos=NULL,type="source",lib=target,dependencies=FALSE,quiet=TRUE)
}
if(!requireNamespace("renv",quietly=TRUE,lib.loc=target)||as.character(packageVersion("renv",lib.loc=target))!=args[[2L]])
  stop("The selected bootstrap library does not contain pinned renv ",args[[2L]],". Choose a fresh Brohn installation directory.")
cat("Pinned renv bootstrap ready:",args[[2L]],"\n")
})
