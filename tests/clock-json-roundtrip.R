# Real R/Python JSON interoperability using Brohn's installed canonical encoder.
args<-commandArgs(trailingOnly=TRUE)
stopifnot(length(args)==2L,file.exists(args[[1L]]),!file.exists(args[[2L]]))
source("R/platform-core.R",encoding="UTF-8")
value<-jsonlite::fromJSON(args[[1L]],simplifyVector=FALSE)
writeLines(enc2utf8(brohn_json(value)),args[[2L]],useBytes=TRUE)
