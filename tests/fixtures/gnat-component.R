# Original complete protocol fixture; no participant session or scientific result.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==1L)
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
source("R/platform-gnat.R",encoding="UTF-8")
folder<-args[[1L]];dir.create(folder,recursive=TRUE,showWarnings=FALSE)
folder<-normalizePath(folder,winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-gnat-"),!file.exists(file.path(folder,"compiled.json")))
compiled<-brohn_gnat_compile(brohn_gnat_new(id="gnat-reference"),1L)
brohn_gnat_validate_compiled(compiled)
brohn_write_json_file(compiled,file.path(folder,"compiled.json"))
brohn_write_json_file(list(kind="Original synthetic component fixture",trial_count=384L,sequence_hash=compiled$sequence_hash,
  procedure_hash=compiled$procedure_hash,domain_sha256=digest::digest(file="R/platform-gnat.R",algo="sha256")),file.path(folder,"fixture.json"))
cat(folder,"\n")
