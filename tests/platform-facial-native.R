# Optional installed-provider integration: actual R dispatch, not store publication.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==1L)
folder<-normalizePath(args[[1]],winslash="/",mustWork=FALSE);stopifnot(!dir.exists(folder));dir.create(folder,recursive=TRUE)
reference<-normalizePath("../../work/test-runs/brohn-facial-native-20260924-01",winslash="/",mustWork=TRUE)
video<-file.path(reference,"authored-vfr-face-reference.mkv");original_hash<-digest::digest(file=video,algo="sha256")
stopifnot(original_hash=="251248e52a49b17a258e59ce31b27b5a05ff0bdc39f116e355c1959a09f0bf6c")
source_files<-c("R/platform-facial-expression.R","R/platform-vision.R","scripts/workers/facial_expression.py","scripts/workers/vision.py","scripts/readiness/facial-models.json","scripts/readiness/facial-runtime.json","scripts/readiness/requirements-facial-au.txt")
identity<-stats::setNames(lapply(source_files,function(f)digest::digest(file=f,algo="sha256")),source_files)
input<-list(operation="analyse_dataset",source_path=video,dataset=list(modality="video",source=list(hash=original_hash,size=as.numeric(file.info(video)$size),format="mkv"),
  metadata=list(profile=.brohn_facial_profile,origin_statement="Existing composed licensed six-frame VFR software fixture; no participant capture.",consent_statement="Existing Apache2 upstream media; local software agreement testing only.",start_s="0",frame_stride=1L,max_support_gap_s=.25)))
result<-brohn_run_vision(input,folder);checks<-character();check<-function(label,value){stopifnot(isTRUE(value));checks<<-c(checks,label);cat("PASS",label,"\n")}
check("Actual existing R video dispatch selects the separate native facial provider",brohn_facial_supported(result)&&result$engine$version=="2.0.0")
prior<-brohn_read_json_file(file.path(reference,"result.json"))
check("All27 native summaries and complete coverage equal independently checked reference output",.brohn_facial_same(result$features,prior$features)&&.brohn_facial_same(result$quality,prior$quality))
check("Both complete native artifacts remain exact byte matches",identical(vapply(result$artifacts,`[[`,character(1),"sha256"),vapply(prior$artifacts,`[[`,character(1),"sha256")))
check("Exact permission statement and configured native provider remain in effective settings",identical(result$parameters$consent_statement,input$dataset$metadata$consent_statement)&&brohn_is_facial_profile(result$parameters))
check("Native R processing preserves original bytes and selected source identities",identical(original_hash,digest::digest(file=video,algo="sha256"))&&all(vapply(source_files,function(f)identical(identity[[f]],digest::digest(file=f,algo="sha256")),logical(1))))
brohn_write_json_file(list(passed=TRUE,checks=as.list(checks),source_hash=original_hash,code_hashes=identity,artifact_hashes=lapply(result$artifacts,function(x)x[c("kind","sha256","bytes")]),scope="Actual R->native adapter and complete value checks; guarded store publication and UI are separate browser evidence."),file.path(folder,"results.json"))
