# Actual disposable SQLite catalogue and original local authority; deliberately
# minimal synthetic saved reports do not claim native scientific qualification.
args<-commandArgs(TRUE);stopifnot(length(args)==3L)
root<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE)
folder<-args[[2L]];stopifnot(!file.exists(folder));dir.create(folder,recursive=TRUE)
folder<-normalizePath(folder,winslash="/",mustWork=TRUE)
loader<-normalizePath(args[[3L]],winslash="/",mustWork=TRUE)
setwd(loader);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
source(file.path(root,"R","platform-report-package-source-catalog.R"),encoding="UTF-8")
source(file.path(root,"R","platform-report-package-views.R"),encoding="UTF-8")
checks<-list();observations<-list();failure<-NULL
check<-function(ok,label){checks[[length(checks)+1L]]<<-list(label=label,passed=isTRUE(ok));if(!isTRUE(ok))stop(label,call.=FALSE)}
refuse<-function(fn,label){condition<-tryCatch({fn();NULL},error=conditionMessage);observations[[label]]<<-condition;check(is.character(condition)&&length(condition)==1L,label)}
store<-brohn_open_store(file.path(folder,"workspace"))
tryCatch({
 brohn_initialise_library(store)
 a<-brohn_create_study(store,"Catalogue study A");b<-brohn_create_study(store,"Catalogue study B")
 make<-function(id,study,title=id,origin="synthetic-catalogue")brohn_put_entity(store,"report",id,
  list(id=id,study_id=study$id,title=title,origin=origin,analysis=list(kind="unsupported-catalogue-fixture")))
 originals<-lapply(c("saved-a","saved-b","saved-c"),function(id)make(id,a))
 foreign<-make("saved-foreign",b)
 original_choice<-brohn_report_package_report_choice;calls<-0L
 brohn_report_package_report_choice<-function(store,report_ref){calls<<-calls+1L;original_choice(store,report_ref)}
 first<-brohn_report_package_choice_descriptors(store,a$id,"default",limit=2L)
 second<-brohn_report_package_choice_descriptors(store,a$id,"default",cursor=first$next_cursor,limit=2L)
 actual<-c(first$reports,second$reports)
 check(calls==0L&&length(actual)==3L&&!anyDuplicated(vapply(actual,function(x)x$ref$id,character(1))),"Two catalogue pages contain each authorised head once without complete source admission")
 check(setequal(vapply(actual,function(x)x$ref$id,character(1)),vapply(originals,`[[`,character(1),"id")),"Other-study reports are excluded by original catalogue scope")
 check(all(vapply(actual,function(x)identical(x$availability,"unchecked")&&is.null(x$adapters)&&is.null(x$kind),logical(1)))&&!length(first$recommended_refs),"Descriptors do not claim scientific type, adapters, source validity or automatic selection")
 for(row in actual){original<-Filter(function(r)identical(r$id,row$ref$id),originals)[[1L]]
  check(.brohn_rpk_same(row$ref,.brohn_rpk_ref(original)),paste("Exact retained version/hash",original$id))}
 refuse(function()brohn_report_package_choice_descriptors(store,b$id,"default",first$next_cursor,2L),"A cursor from another study is refused")
 refuse(function()brohn_report_package_choice_descriptors(store,a$id,"default",limit=101L),"An unbounded page request is refused")
 old<-.brohn_rpk_ref(originals[[1L]])
 bad<-old;bad$body_hash<-paste(rep("0",64L),collapse="")
 refuse(function()brohn_report_package_admit_catalog_choice(store,bad,a$id,"default"),"A changed body hash cannot reach full source admission")
 refuse(function()brohn_report_package_admit_catalog_choice(store,old,b$id,"default"),"A same-project source from another study cannot reach full source admission")
 check(calls==0L,"Ref/hash/study rejection precedes the complete original reader")
 # Observe the genuine complete reader's disposition of a deliberately incomplete
 # fixture. It may reject or return an unsupported row, but never supply adapters.
 admitted<-tryCatch(brohn_report_package_admit_catalog_choice(store,old,a$id,"default"),error=function(e){observations$original_reader_refusal<<-conditionMessage(e);NULL})
 check(calls==1L&&(is.null(admitted)||length(admitted$adapters)==0L),"Add actually invokes the original complete source reader and cannot make incomplete synthetic evidence usable")
 new_body<-originals[[1L]]$body;new_body$study_id<-b$id;new_body$title<-"New head in study B"
 new_head<-brohn_put_entity(store,"report",old$id,new_body,expected_revision=old$revision)
 historical<-.brohn_rpk_choice_descriptor(store,old,a$id,"default")
 check(.brohn_rpk_same(historical$ref,old)&&identical(historical$title,originals[[1L]]$body$title),"An explicitly selected historical version stays exact after a newer head changes study")
 fresh<-brohn_report_package_choice_descriptors(store,a$id,"default")
 check(!old$id%in%vapply(fresh$reports,function(x)x$ref$id,character(1)),"New head listing does not silently substitute historical findings into the old study")
 absent<-make("label-absent",a,title=NULL,origin=NULL)
 descriptor<-.brohn_rpk_choice_descriptor(store,.brohn_rpk_ref(absent),a$id,"default")
 check(identical(descriptor$title,absent$id)&&identical(descriptor$origin,"saved"),"Absent optional catalogue labels use plain saved-result fallbacks")
 for(bad_title in list(list(text="not a text scalar"),23,strrep("x",513L))){
  id<-paste0("label-invalid-",length(observations));record<-make(id,a,title=bad_title)
  refuse(function().brohn_rpk_choice_descriptor(store,.brohn_rpk_ref(record),a$id,"default"),paste("Malformed or overlong label refused",id))
 }
 mixed<-brohn_report_package_choice_descriptors(store,a$id,"default")
 unavailable<-Filter(function(x)identical(x$availability,"unavailable"),mixed$reports)
 check(length(unavailable)==3L&&any(vapply(mixed$reports,function(x)identical(x$availability,"unchecked"),logical(1))),
  "Malformed labels become bounded unavailable rows without hiding other authorised findings")
 check(all(vapply(unavailable,function(x)identical(x$title,x$ref$id)&&brohn_text(x$reason,256),logical(1))),
  "Unavailable label rows retain exact refs and safe bounded text")
 for(row in unavailable)refuse(function()brohn_report_package_admit_catalog_choice(store,row$ref,a$id,"default"),paste("Unavailable row cannot gain source admission",row$ref$id))
 escaped<-make("label-escaped",a,title="<script>not markup</script>")
 descriptor<-.brohn_rpk_choice_descriptor(store,.brohn_rpk_ref(escaped),a$id,"default")
 html<-as.character(brohn_report_package_sources_ui(list(reports=list(descriptor),next_cursor=NULL),list()))
 check(!grepl("<script>",html,fixed=TRUE)&&grepl("&lt;script&gt;",html,fixed=TRUE),"Authorised catalogue text is escaped as text, not executable markup")
 # Controlled read-gap seam on this disposable catalogue only: ordinary entity
 # publication moves the current entity to another project during complete read.
 # This checks the second actual catalogue/authority fence, not scientific output.
 brohn_put_entity(store,"project","other",list(id="other",title="Other",archived=FALSE),project_id="other")
 movable<-make("scope-moves-during-read",a);movable_ref<-.brohn_rpk_ref(movable)
 brohn_report_package_report_choice<-function(s,report_ref){
  brohn_put_entity(s,"report",movable$id,movable$body,expected_revision=1L,project_id="other")
  list(ref=report_ref,adapters=list("gaze-context"))}
 refuse(function()brohn_report_package_admit_catalog_choice(store,movable_ref,a$id,"default"),"A current project change during the full read fails the second exact scope fence")
 brohn_report_package_report_choice<-original_choice
 project<-brohn_get_entity(store,"project","default");body<-project$body;body$archived<-TRUE
 brohn_put_entity(store,"project","default",body,expected_revision=project$revision)
 refuse(function()brohn_report_package_choice_descriptors(store,a$id,"default"),"Archived project authority cannot disclose catalogue labels")
 check(DBI::dbGetQuery(store$con,"SELECT count(*) AS n FROM jobs")$n[[1L]]==0L,"Catalogue and controlled admission never queue processing")
},error=function(e){failure<<-conditionMessage(e)})
cleanup_error<-tryCatch({brohn_close_store(store);NULL},error=conditionMessage)
brohn_write_json_file(list(passed=is.null(failure)&&is.null(cleanup_error),failure=failure,cleanup_error=cleanup_error,checks=checks,observations=observations,
 scenarios=list(list(label="Disposable authorised catalogue and exact source admission",passed=is.null(failure)&&is.null(cleanup_error),failure=failure,cleanup_error=cleanup_error)),
 source_hashes=setNames(lapply(c("platform-report-package-source-catalog.R","platform-report-package-views.R","platform-report-package-server.R"),function(f)digest::digest(file=file.path(root,"R",f),algo="sha256")),c("catalog","views","server")),
 scope="Actual SQLite entity catalogue and original local authority with minimal synthetic report bodies; one explicit controlled full-read seam. No genuine biosignal/scientific reader, hosted login, report preparation, worker or browser qualification."),file.path(folder,"results.json"))
if(!is.null(failure)||!is.null(cleanup_error))quit(status=1L)
