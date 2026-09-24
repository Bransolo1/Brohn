# Read-only authority regression on a completed original-fixture browser store.
args<-commandArgs(trailingOnly=TRUE)
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
config<-brohn_read_json_file(file.path(args[[1L]],"fixture.json"))
local({
  store<-brohn_open_store(config$workspace);on.exit(brohn_close_store(store),add=TRUE)
  checks<-character();check<-function(label,ok){stopifnot(isTRUE(ok));checks<<-c(checks,label)}
  rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
  reviews<-brohn_list_entities(store,"linked_review");stopifnot(length(reviews)>0)
  saved<-Filter(function(r)r$body$result$selected_rows==78,reviews)[[1L]];request<-saved$body$request
  before<-brohn_hash(list(brohn_list_entities(store,"dataset"),brohn_list_entities(store,"stream"),reviews,brohn_list_jobs(store)))
  input<-brohn_linked_review_input(store,list(request=request))
  check("Every pinned canonical sample/evidence source passes its object integrity check",length(input$source_objects)==6L)
  for(field in c("samples","evidence")) {
    bad<-request;bad$tracks[[1L]][[field]]$hash<-bad$tracks[[2L]][[field]]$hash
    check(paste("Substituted",field,"artifact cannot replace the manifest reference"),rejects(brohn_linked_review_input(store,list(request=bad))))
  }
  bad<-request;bad$tracks[[1L]]$clock$id<-"other-clock"
  check("Request cannot substitute its declared source clock",rejects(brohn_linked_review_input(store,list(request=bad))))
  bad<-request;bad$tracks[[1L]]$origin<-"live"
  check("Sample origin cannot become live",rejects(brohn_linked_review_input(store,list(request=bad))))
  bad<-request;bad$project_id<-"foreign-project"
  check("Foreign project cannot open pinned source references",rejects(brohn_linked_review_input(store,list(request=bad))))
  selected<-lapply(request$tracks,function(t)list(stream_id=t$stream$id,channel_id=t$channel_id))
  check("Duplicate channel selection is refused",rejects(brohn_prepare_linked_review(store,request$dataset_id,request$imported$id,list(selected[[1]],selected[[1]]),request$selection,request$project_id)))
  bad<-request$selection;bad$confirmed<-FALSE
  check("Source-clock review is required",rejects(brohn_prepare_linked_review(store,request$dataset_id,request$imported$id,selected,bad,request$project_id)))
  bad<-request$selection;bad$clock_rationale<-""
  check("Clock declaration explanation cannot be empty",rejects(brohn_prepare_linked_review(store,request$dataset_id,request$imported$id,selected,bad,request$project_id)))
  check("Saved review refuses unrelated dataset navigation",rejects(brohn_linked_review_record(store,saved$id,"unrelated",request$project_id)))
  bad<-saved$body$result;bad$selected_rows<-79
  check("Publication checks reconcile all track and CSV support",rejects(brohn_validate_linked_review(bad,input)))
  bad<-saved$body$result;bad$selection$end_s<-"5"
  check("Publication refuses a substituted window",rejects(brohn_validate_linked_review(bad,input)))
  check("Read-only checks preserve every dataset, stream, linked view and job",identical(before,brohn_hash(list(brohn_list_entities(store,"dataset"),brohn_list_entities(store,"stream"),brohn_list_entities(store,"linked_review"),brohn_list_jobs(store)))))
  brohn_write_json_file(list(passed=TRUE,checks=as.list(checks),workspace=config$workspace,saved_review_id=saved$id),args[[2L]])
  cat(length(checks),"linked source authority checks passed\n")
})
