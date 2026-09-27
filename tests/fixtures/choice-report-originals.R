# Original synthetic sources; actual delivery/import/scientific worker publication.
# No stored participant corpus and no estimator execution after this boundary.
brohn_choice_report_originals <- function(checkout,out,native_manifest) {
 oldwd<-getwd();on.exit(setwd(oldwd),add=TRUE);setwd(checkout)
 cfg<-list(checkout=checkout,out=out,native_manifest=native_manifest)
Sys.setenv(BROHN_PUBLICATION_NATIVE_MANIFEST=cfg$native_manifest)
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
# Reuse the original receiver fixture's complete task journal, adding declared
# choice responses. This is a synthetic protocol witness, not a browser/person.
fixture<-paste(readLines("tests/fixtures/original-task-journal.R",warn=FALSE,encoding="UTF-8"),collapse="\n")
fixture<-sub('events <- list(); state <- .brohn_delivery_initial_state(); time <- 0',
 'events <- list(); state <- .brohn_delivery_initial_state(); time <- 0; page <- "original-task-export-page"; resumed_once <- FALSE',fixture,fixed=TRUE)
fixture<-gsub('instance_id="original-task-export-page"','instance_id=page',fixture,fixed=TRUE)
fixture<-gsub('clock_instance_id="original-task-export-page"','clock_instance_id=page',fixture,fixed=TRUE)
fixture<-sub('} else if(step$type=="question") {',paste0('} else if(step$type=="maxdiff") {\n',
 '      resumed <- FALSE\n',
 '      if(!resumed_once){page <- "choice-resumed-page";time <- 20;if(length(equipment$required_codes))emit_equipment("keyboard",list(codes=equipment$required_codes,released=TRUE,focused=TRUE,visible=TRUE,last_input_ms=time));if(isTRUE(equipment$controls))emit_equipment("controls",list(activation="keyboard_or_assistive",trusted=TRUE,last_input_ms=time));send("step_started",step,list(resumed=TRUE),time);resumed<-TRUE;resumed_once<-TRUE}\n',
 '      pair <- list(c(1L,2L),c(1L,3L),c(2L,1L),c(2L,3L),c(3L,1L),c(3L,2L))[[as.integer(sub(".*set-","",step$choice$set_id))]]\n',
 '      value <- if(grepl("missing",step$choice$exercise_id,fixed=TRUE))NULL else list(best_id=paste0("item-",pair[[1L]]),worst_id=paste0("item-",pair[[2L]]))\n',
 '      send("response",step,list(value=value,response_time_ms=if(resumed)NULL else 50,active_segment_response_ms=50,resumed=resumed),time+50)\n',
 '    } else if(step$type=="question") {'),fixture,fixed=TRUE)
eval(parse(text=fixture),envir=environment())
local({
 out<-cfg$out;checks<-list();reports<-list();passed<-FALSE;failure<-NULL
 check<-function(name,value){if(!isTRUE(value))stop(name,call.=FALSE);checks[[length(checks)+1L]]<<-name;cat("PASS",name,"\n")}
 near<-function(x,y)length(x)==1L&&is.numeric(x)&&is.finite(x)&&abs(x-y)<1e-8
 ref<-function(r)list(kind="report",id=r$id,revision=r$revision,body_hash=brohn_hash(r$body),project_id=r$project_id)
 store<-brohn_open_store(file.path(out,"workspace"));brohn_initialise_library(store)
 on.exit({
   for(j in brohn_list_jobs(store))if(j$status %in% c("queued","running"))brohn_cancel_job(store,j$id)
   objects<-DBI::dbGetQuery(store$con,"SELECT * FROM objects")
   brohn_write_json_file(list(schema="brohn-choice-initial-original-corpus/0.1",passed=passed,checks=checks,failure=failure,
    reports=lapply(reports,ref),jobs=lapply(brohn_list_jobs(store),function(j)list(id=j$id,operation=j$operation,status=j$status,attempt=j$attempt,error=j$error,result=j$result)),
    objects=lapply(seq_len(nrow(objects)),function(i)as.list(objects[i,,drop=FALSE])),
    qualification="Genuine unchanged scientific workers over original synthetic receiver and CSV sources. No browser, human, device, display, package or new-estimator qualification."),file.path(out,"results.json"))
   brohn_close_store(store)
 },add=TRUE)
 tryCatch({
  runjob<-function(j){force(j);claim<-brohn_claim_job(store,"choice-original-corpus",lease_seconds=120L);stopifnot(!is.null(claim),identical(j$id,claim$id));brohn_process_job(store,claim,timeout_seconds=180L)
   done<-brohn_get_job(store,j$id);if(done$status!="succeeded")stop("Original scientific worker failed: ",brohn_json(done$error));r<-brohn_get_entity(store,"report",done$result$report_id);reports[[length(reports)+1L]]<<-r;r}
  exercise<-brohn_maxdiff_new(id="corpus-choice-fit");exercise$title<-"Original balanced three-feature choice";exercise$items<-head(exercise$items,3L)
  exercise$sets<-lapply(1:6,function(i)list(id=paste0("set-",i),item_ids=as.list(brohn_ids(exercise$items))))
  exercise$settings$set_order<-exercise$settings$item_order<-"fixed"
  countonly<-exercise;countonly$id<-"corpus-choice-counts";countonly$title<-"Original fitting not requested";countonly$settings$analysis$fit_aggregate<-FALSE
  missing<-exercise;missing$id<-"corpus-choice-missing";missing$title<-"Original optional missing pairs";missing$settings$required<-FALSE
  study<-brohn_create_study(store,"Original mixed task choice and liking", "blank");d<-study$body;d$instructions<-"";d$questionnaire_navigation<-NULL
  d$blocks<-list(brohn_task_new("rt-deary-liewald-choice/1.0",id="original-choice-rt"));d$maxdiff<-list(exercise,countonly,missing)
  d$questions<-lapply(c("liking","experience"),function(id){q<-brohn_question(paste("Original",id),"rating","end",paste0("original-",id));q$min<-0;q$max<-4;q$step<-1;q$options<-lapply(0:4,function(v)list(id=paste0("rating-",v),label=as.character(v),value=v));q})
  d$scales<-list(list(schema="brohn-questionnaire-scale/1.0",id="original-scale",label="Original reverse-keyed sum",version="1.0",source="Synthetic arithmetic only; not a construct-validity claim.",scope="end",
   items=lapply(seq_along(d$questions),function(i)list(question_id=d$questions[[i]]$id,reverse=i==2L,min=0,max=4)),scoring=list(aggregation="sum",missing="complete",minimum_answered=2,prorate=FALSE),conversion=NULL))
  study<-brohn_save_study(store,d,study$revision);release<-brohn_publish(store,study$id,"sample",alias_required=TRUE)
  start<-.brohn_delivery_start(store,release$token,list(consented=TRUE,participant_alias="001",client_id="choice-original-client",operation_id="choice-original-start"))
  protocol<-brohn_run(store,start$run_id)$protocol;events<-original_task_journal(protocol,function(t)if(!t$scored||t$trial_index==1L)list(outcome="correct",rt=500)else list(outcome="timeout"))
  for(first in seq.int(1L,length(events),100L)) .brohn_delivery_receive(store,start$run_id,start$access_token,list(events=events[first:min(first+99L,length(events))],operation_id=paste0("choice-original-events-",first)))
  .brohn_delivery_finish(store,start$run_id,start$access_token,list(outcome="completed",final_sequence=length(events),operation_id="choice-original-finish"))
  queued<-brohn_list_jobs(store,request_filters=list(run_id=start$run_id));stopifnot(length(queued)==1L);native<-runjob(queued[[1L]]);a<-native$body$analysis
  metrics<-a$task_scores[[1L]]$metrics;metric<-function(k)Filter(function(m)m$name==k,metrics)[[1L]]$value
  check("mixed native task/liking/scale original values",metric("correct_test_rt_mean")==500&&metric("test_omission_rate")==39/40&&is.null(metric("correct_test_rt_sd"))&&length(a$observations)==2L&&a$scales$observations[[1L]]$value==4)
  check("native source contains three complete distinct model states",length(a$choice_tasks)==3L&&a$choice_tasks[[1L]]$model$status=="estimated"&&a$choice_tasks[[2L]]$model$status=="not_requested"&&a$choice_tasks[[3L]]$model$status=="unavailable")
  fitted<-a$choice_tasks[[1L]]
  check("native balanced6 exact counts and symmetric fit",near(fitted$model$diagnostics$negative_log_likelihood,6*log(6))&&all(vapply(fitted$model$utilities,function(u)near(u$utility,0),logical(1)))&&all(vapply(fitted$items,function(i)i$best_count==2L&&i$worst_count==2L&&i$answered_exposures==6L&&i$exposure_adjusted_score==0,logical(1))))
  check("native resumed timing and missing support remain explicit",isTRUE(fitted$collection_evidence[[1L]]$resumed)&&is.null(fitted$collection_evidence[[1L]]$response_time_ms)&&fitted$collection_evidence[[1L]]$active_segment_response_ms==50&&a$choice_tasks[[3L]]$quality$missing_exposures==6L&&all(vapply(a$choice_tasks[[3L]]$items,function(i)is.null(i$exposure_adjusted_score),logical(1))))
  check("modern native original protocol/journal receipts retained",length(native$body$provenance$run_evidence$runs)==1L&&native$body$processing$publication$native_seal)
  brohn_write_json_file(native,file.path(out,"native-report.json"));brohn_write_json_file(events,file.path(out,"native-original-journal.json"));brohn_write_json_file(protocol,file.path(out,"native-original-protocol.json"))
  # Original character CSV is authored directly, then imported/scored once by a child.
  impstudy<-brohn_create_study(store,"Original imported explicit choices", "blank");impdesign<-impstudy$body;impdesign$maxdiff<-list(exercise);impstudy<-brohn_save_study(store,impdesign,impstudy$revision)
  pairs<-list(c(1L,2L),c(1L,3L),c(2L,1L),c(2L,3L),c(3L,1L),c(3L,2L))
  rows<-lapply(seq_along(pairs),function(i)list(person_code="0009",visit_code="00001",exposure_code=paste0("source-",i),design_hash=brohn_hash(exercise),set_id="set-1",item_order=brohn_json(exercise$sets[[1L]]$item_ids),presented="true",status="answered",best_id=paste0("item-",pairs[[i]][[1L]]),worst_id=paste0("item-",pairs[[i]][[2L]]),missing_reason="",participant_linkage="true",exercise_id=exercise$id,origin="sample",unmapped_lexeme="00009.12345678901234567890"))
  partial<-rows[[1L]];partial$exposure_code<-"source-partial";partial$status<-"missing";partial$worst_id<-"";partial$missing_reason<-"Original partial response"
  unpresented<-partial;unpresented$exposure_code<-"source-not-reached";unpresented$presented<-"false";unpresented$status<-"not_presented";unpresented$best_id<-"";unpresented$missing_reason<-"Original not reached"
  excluded<-rows[[1L]];excluded$exercise_id<-"other-exercise";excluded$person_code<-"";excluded$visit_code<-"0000007";excluded$unmapped_lexeme<-"-0.00000000000000000000017"
  rows<-c(rows,list(partial,unpresented,excluded));tab<-as.data.frame(do.call(rbind,lapply(rows,unlist)),stringsAsFactors=FALSE,check.names=FALSE)
  csv<-file.path(out,"original-maxdiff.csv");utils::write.csv(tab,csv,row.names=FALSE,na="",fileEncoding="UTF-8")
  metadata<-list(exercise_id=exercise$id,origin_statement="Original synthetic balanced pairs with partial, unpresented and excluded exercise rows; no physical participant data.",participant_column="person_code",session_column="visit_code",exposure_column="exposure_code",design_hash_column="design_hash",set_column="set_id",item_order_column="item_order",presented_column="presented",status_column="status",best_column="best_id",worst_column="worst_id",missing_reason_column="missing_reason",participant_linkage_column="participant_linkage",exercise_column="exercise_id",origin_column="origin")
  dataset<-brohn_ingest_dataset(store,csv,"Original choice CSV",modality="maxdiff",origin="sample");curated<-brohn_curate_dataset(store,dataset$id,metadata,dataset$revision,impstudy$id,impstudy$revision)
  imported<-runjob(brohn_queue_dataset(store,curated$id));a<-imported$body$analysis;fitted<-a$choice_tasks[[1L]]
  check("genuine import is explicit_choice with9 original rows and8 exposures",a$kind=="explicit_choice"&&a$parameters$schema=="brohn-maxdiff-csv-import/1.0"&&length(a$source_rows)==9L&&length(a$observations)==8L&&identical(brohn_hash(a$observations),brohn_hash(fitted$exposures)))
  check("import preserves leading zeros and excluded null/absent distinctions",a$observations[[1L]]$participant_id=="0009"&&a$observations[[1L]]$session_id=="00001"&&!a$source_rows[[9L]]$selected&&is.null(a$source_rows[[9L]]$response_id)&&!"mapped_cells" %in% names(a$source_rows[[9L]])&&a$source_rows[[1L]]$mapped_cells$person_code=="0009")
  check("import balanced counts fitted utilities and incomplete support",near(fitted$model$diagnostics$negative_log_likelihood,6*log(6))&&all(vapply(fitted$model$utilities,function(u)near(u$utility,0),logical(1)))&&all(vapply(fitted$items,function(i)i$best_count==2L&&i$worst_count==2L&&i$answered_exposures==6L&&i$missing_exposures==1L&&i$exposure_adjusted_score==0,logical(1)))&&a$quality$unpresented_exposures==1L)
  check("import has no invented native timing",!"collection_evidence" %in% names(fitted)&&!"collection_evidence_hash" %in% names(fitted)&&identical(brohn_hash(a$source_rows),a$source_rows_hash))
  brohn_write_json_file(imported,file.path(out,"import-report.json"));brohn_write_json_file(curated,file.path(out,"import-dataset.json"))
  brohn_write_json_file(list(native=list(correct_test_rt_mean=500,test_omission_numerator=39,test_omission_denominator=40,correct_test_rt_sd=NULL,explicit_values=list(0,0),scale_sum=4,choice_model_states=list("estimated","not_requested","unavailable"),choice_complete_pairs=6,each_item_best=2,each_item_worst=2,each_item_adjusted=0,utilities=list(0,0,0),negative_log_likelihood=6*log(6),resumed_response_ms=NULL,resumed_active_segment_ms=50),imported=list(source_rows=9,selected_rows=8,excluded_rows=1,complete_pairs=6,missing_pairs=1,unpresented=1,person_code="0009",visit_code="00001",raw_unmapped_lexeme="00009.12345678901234567890",excluded_lexeme="-0.00000000000000000000017",utilities=list(0,0,0),negative_log_likelihood=6*log(6))),file.path(out,"reference-witnesses.json"))
  for(r in reports){envelope<-brohn_read_json_file(brohn_object_path(store,r$body$result_object$hash,verify=TRUE));check(paste("complete original report body matches retained worker",r$id),identical(brohn_hash(envelope$report$analysis),brohn_hash(r$body$analysis)))}
  check("exactly2original scientific workers settled before export",length(brohn_list_jobs(store))==2L&&all(vapply(brohn_list_jobs(store),function(j)j$status=="succeeded"&&j$operation %in% c("analyse_run","analyse_dataset"),logical(1))))
  passed<-TRUE
 },error=function(e){failure<<-conditionMessage(e);stop(e)})
 cat("Initial choice source corpus:",length(checks),"checks passed\n")
})

 invisible(out)
}
