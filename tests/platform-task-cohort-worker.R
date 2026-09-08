# Actual supervised original CSV -> imported report -> frozen task cohort worker.
# Run only in a coordinated scientific-source freeze. No live device/participant.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
local({
  checks<-0L;passed<-FALSE;jobs<-list();reports<-list()
  check<-function(label,x){if(!isTRUE(x))stop("Task cohort worker: ",label,call.=FALSE);checks<<-checks+1L}
  rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
  metric<-function(analysis,name="correct_test_rt_mean")Filter(function(s)s$metric==name,analysis$summaries)[[1L]]
  parent<-normalizePath("../../work/test-runs",winslash="/",mustWork=TRUE)
  root<-file.path(parent,paste0("brohn-task-cohort-worker-",format(Sys.time(),"%Y%m%d-%H%M%S"),"-",substr(brohn_id("qa"),4L,11L)))
  stopifnot(!file.exists(root));dir.create(root);root<-normalizePath(root,winslash="/",mustWork=TRUE)
  stopifnot(startsWith(tolower(root),paste0(tolower(parent),"/")))
  store<-brohn_open_store(file.path(root,"workspace"));brohn_initialise_library(store)
  on.exit({
    for(j in brohn_list_jobs(store))if(j$status %in% c("queued","running"))brohn_cancel_job(store,j$id)
    brohn_write_json_file(list(schema="brohn-task-cohort-worker-evidence/1.0",passed=passed,checks=checks,root=root,
      jobs=lapply(brohn_list_jobs(store),function(j)list(id=j$id,operation=j$operation,status=j$status,attempt=j$attempt,error=j$error,result=j$result)),
      reports=lapply(reports,function(r)list(id=r$id,hash=brohn_hash(r$body),result_object=r$body$result_object)),
      qualification="Original synthetic CSV imports and actual isolated supervised cohort workers/publication. No native replay, physical timing, population inference, browser or hosted deployment qualification."),file.path(root,"evidence.json"))
    brohn_close_store(store)
  },add=TRUE)
  manifest<-brohn_read_json_file("tests/fixtures/task-import/manifest.json");f<-manifest$fixtures$choice
  registry_path<-file.path("tests/fixtures/task-import",f$registry);registry<-brohn_read_json_file(registry_path)
  source_table<-brohn_read_table(file.path("tests/fixtures/task-import",f$csv),"csv",20000L)
  design<-brohn_new_design("Original supervised task cohort","blank",brohn_id("study"));design$blocks<-list(registry$task)
  study<-brohn_put_entity(store,"study",design$id,design)
  create_rows<-function(person,session,value,one_error=FALSE,one_correct=FALSE) {
    x<-source_table;x[[f$metadata$participant_column]]<-person;x[[f$metadata$session_column]]<-session
    x[[f$metadata$attempt_column]]<-"original-attempt";x$first_response_ms<-x$final_correct_ms<-as.character(value)
    if(one_error) {
      trials<-Filter(function(t)t$type=="task_trial",registry$protocols[[1L]]$compiled$timeline)
      x$outcome[[9L]]<-"incorrect";x$first_correct[[9L]]<-"false"
      x$first_code[[9L]]<-setdiff(unlist(trials[[9L]]$allowed_codes),trials[[9L]]$correct_code)[[1L]]
      x$final_code[[9L]]<-x$final_correct_ms[[9L]]<-""
    }
    omitted<-if(one_correct)10:48 else if(one_error)12:48 else integer()
    if(length(omitted)) {
      x$outcome[omitted]<-"timeout";x$first_correct[omitted]<-"false"
      for(field in c("first_code","final_code","first_response_ms","final_correct_ms"))x[[field]][omitted]<-""
    }
    x
  }
  run_job<-function(job,success=TRUE) {
    force(job);claim<-brohn_claim_job(store,"original-task-cohort-worker-qa",lease_seconds=90L)
    stopifnot(!is.null(claim),identical(claim$id,job$id))
    brohn_process_job(store,claim,timeout_seconds=120)
    done<-brohn_get_job(store,job$id);jobs[[length(jobs)+1L]]<<-done
    if(success&&done$status!="succeeded")stop("Actual scientific child failed: ",brohn_json(done$error),call.=FALSE)
    if(success) {
      r<-brohn_get_entity(store,"report",done$result$report_id);reports[[length(reports)+1L]]<<-r
      return(list(job=done,report=r))
    }
    done
  }
  import_source<-function(rows,filename) {
    path<-file.path(root,filename)
    utils::write.table(rows,path,sep=",",quote=TRUE,row.names=FALSE,qmethod="double",fileEncoding="UTF-8",eol="\n")
    dataset<-brohn_ingest_dataset(store,path,paste("Original",filename),modality="implicit",origin="sample")
    reference<-brohn_stage_task_registry(store,registry_path,basename(registry_path),dataset$id,dataset$revision,study$id,study$revision,registry$task$id)
    metadata<-f$metadata;metadata$source_collection_id<-"original-supervised-collection";metadata$protocol_registry<-reference
    curated<-brohn_curate_dataset(store,dataset$id,metadata,dataset$revision,study$id,study$revision)
    run_job(brohn_queue_dataset(store,curated$id))
  }
  first<-import_source(rbind(create_rows("P","S1",1),create_rows("P","S2",1),create_rows("Q","S1",3,one_error=TRUE)),"original-repeats-and-third-error.csv")
  check("actual source worker saves three canonical administrations from144 original trials",length(first$report$body$analysis$task_attempts)==3L&&first$report$body$analysis$quality$source_row_count==144L)
  second<-import_source(create_rows("R","S1",500,one_correct=TRUE),"original-one-correct-39-timeouts.csv")
  partial<-second$report$body$analysis$task_attempts[[1L]]
  check("actual source worker preserves partial RT recipe and39of40",partial$score$status=="partial"&&Filter(function(m)m$name=="test_omission_rate",partial$score$metrics)[[1L]]$value==39/40&&is.null(Filter(function(m)m$name=="correct_test_rt_sd",partial$score$metrics)[[1L]]$value))
  prepare<-function(report_ids,choose=NULL,unlinked=FALSE) {
    c<-brohn_task_cohort_catalog(store,study$id,report_ids)
    chosen<-if(is.null(choose))c$attempts else Filter(choose,c$attempts)
    map<-brohn_task_cohort_identity_rows(chosen)
    if(!unlinked) {
      map$linkage_statement<-"Original fixture participant register and visits were explicitly reviewed."
      map$participants<-lapply(map$participants,function(p){p$person_id<-p$participant_id;p})
      map$sessions<-lapply(map$sessions,function(s){s$session_id<-s$source_session_id;s})
    }
    list(catalog=c,args=list(store=store,study_id=study$id,report_ids=report_ids,attempt_ids=lapply(chosen,`[[`,"id"),identity_map=map,
      repeat_policy="equal_attempts_within_session_then_equal_sessions_within_person",description=if(unlinked)"Explicit unlinked original cohort"else"Original reviewed repeated-person cohort",expected_selection_hash=c$selection_hash))
  }
  review<-prepare(list(first$report$id));queued<-do.call(brohn_queue_task_cohort,review$args)
  frozen_input<-brohn_job_input(store,queued)
  check("registered job input freezes source reports plus independent plan and map hashes",frozen_input$operation=="analyse_task_cohort"&&frozen_input$task_cohort$request$plan_hash==brohn_hash(queued$request$plan)&&frozen_input$task_cohort$request$identity_map_hash==brohn_hash(queued$request$identity_map))
  check("same exact reviewed selection deduplicates queued work",identical(queued$id,do.call(brohn_queue_task_cohort,review$args)$id))
  # Current report metadata and study-head edits occur after queueing; the worker
  # must still read its pinned original revision and source design.
  newer<-first$report$body;newer$title<-"Later independent source report title"
  brohn_put_entity(store,"report",first$report$id,newer,first$report$revision)
  changed<-study$body;changed$title<-"Later draft title";changed$archived<-TRUE
  brohn_put_entity(store,"study",study$id,changed,study$revision)
  saved<-run_job(queued);r<-saved$report;analysis<-r$body$analysis
  check("actual cohort gives mean2 with two people not administration mean5/3",metric(analysis)$mean==2&&metric(analysis)$contributing_person_count==2L&&metric(analysis)$selected_attempt_count==3L)
  check("actual worker uses source-recipe rates and preserves exact1/6",identical(metric(analysis,"test_first_response_error_rate")$mean,1/6)&&metric(analysis,"test_first_response_error_rate")$contributing_person_count==2)
  check("actual saved between-person SD uses two people",identical(metric(analysis)$between_person_sd,sqrt(2))&&length(analysis$contrasts)==0L&&!analysis$quality$inference_performed)
  check("later source and study heads never replace pinned report evidence",r$body$provenance$source_reports[[1L]]$revision==1L&&r$body$provenance$design$title==design$title&&r$body$provenance$design_hash==brohn_hash(design))
  code<-r$body$processing$code_hashes
  check("actual scientific child closure includes pure cohort and storage adapters",all(c("R/platform-task-cohort.R","R/platform-task-cohort-storage.R","R/platform-methods.R","scripts/analysis-worker.R") %in% names(code))&&all(vapply(names(code),function(p)identical(code[[p]],digest::digest(file=p,algo="sha256")),logical(1))))
  check("cohort uses guarded staged report publication",r$body$processing$publication$mode=="staged-windows-parent-read-seal/1.0"&&isTRUE(r$body$processing$publication$native_seal)&&r$body$result_object$hash==saved$job$result$output_hash)
  path<-brohn_object_path(store,r$body$result_object$hash,verify=TRUE);envelope<-brohn_read_json_file(path)
  check("published object hash and binary64 analysis match catalog exactly",digest::digest(file=path,algo="sha256")==r$body$result_object$hash&&identical(brohn_hash(envelope$report$analysis),brohn_hash(analysis))&&identical(metric(envelope$report$analysis,"test_first_response_error_rate")$mean,1/6))
  csv<-file.path(root,"cohort-outcomes.csv");brohn_export_task_cohort_csv(r$body,csv)
  table<-brohn_read_table(csv,"csv",20000L)
  check("outcome CSV retains exact machine1/6 and measure-specific N",identical(as.numeric(table$mean[table$metric=="test_first_response_error_rate"]),1/6)&&table$contributing_person_count[table$metric=="correct_test_rt_mean"]=="2")
  # The app's general download handler dispatches to this dedicated exporter.
  # Its button/route integration belongs to browser QA, not a changed contract
  # for the older generic observations CSV helper.
  for(level in c("per_person","per_session","attempt_metrics","membership")) {
    file<-file.path(root,paste0("cohort-",level,".csv"));brohn_export_task_cohort_csv(r$body,file,level)
    check(paste("complete",level,"CSV support export"),nrow(brohn_read_table(file,"csv",20000L))==length(analysis[[level]]))
  }
  json<-file.path(root,"cohort-full-report.json");brohn_write_json_file(r$body,json)
  html<-file.path(root,"cohort-report.html");brohn_export_report_html(r$body,html,store)
  check("full JSON and offline cohort report preserve explicit support",brohn_hash(brohn_read_json_file(json))==brohn_hash(r$body)&&grepl("Task cohort outcomes",paste(readLines(html,warn=FALSE),collapse="\n"),fixed=TRUE))
  review2<-prepare(list(first$report$id,second$report$id),function(a)a$participant_id %in% c("Q","R"))
  saved2<-run_job(do.call(brohn_queue_task_cohort,review2$args));a2<-saved2$report$body$analysis
  check("actual partial cohort uses both RTmeans but only supported within-attempt SD",metric(a2)$mean==251.5&&metric(a2)$contributing_person_count==2&&metric(a2,"correct_test_rt_sd")$contributing_person_count==1&&is.null(metric(a2,"correct_test_rt_sd")$between_person_sd))
  check("actual partial rates retain the1/6 equal-person denominator and omissions95percent",identical(metric(a2,"test_first_response_error_rate")$mean,1/6)&&isTRUE(all.equal(metric(a2,"test_omission_rate")$mean,.95,tolerance=1e-15)))
  check("membership subset is explicit and original parent report remains full",length(a2$membership)==2L&&length(brohn_get_entity(store,"report",first$report$id)$body$analysis$task_attempts)==3L)
  review3<-prepare(list(first$report$id),unlinked=TRUE);saved3<-run_job(do.call(brohn_queue_task_cohort,review3$args));a3<-saved3$report$body$analysis
  check("actual unlinked cohort saves administration evidence while withholding all person summaries",saved3$report$body$status=="Needs review"&&!a3$quality$fully_linked&&is.null(a3$quality$selected_person_count)&&length(a3$attempt_metrics)==15L&&is.null(metric(a3)$mean))
  count<-length(brohn_list_entities(store,"report"))
  for(kind in c("crosswalk","plan","report")) {
    modified<-queued$request
    if(kind=="crosswalk")modified$identity_map$participants[[1L]]$person_id<-"Unexpected changed identity"
    if(kind=="plan")modified$plan$repeat_policy<-"one_selected_attempt_per_person"
    if(kind=="report")modified$reports[[1L]]$body_hash<-brohn_hash("Unexpected source report mutation")
    failed<-run_job(brohn_enqueue_job(store,"analyse_task_cohort",modified,paste0("original-mutated-cohort-",kind)),FALSE)
    check(paste("supervised",kind,"mutation fails without publishing a replacement"),failed$status=="failed"&&length(brohn_list_entities(store,"report"))==count)
  }
  modified<-frozen_input$task_cohort;modified$attempts[[1L]]$score$metrics[[1L]]$value<-99
  check("child rejects changed input metrics against frozen administration hash",rejects(brohn_analyse_task_cohort(modified)))
  modified<-frozen_input$task_cohort;modified$request$identity_map$participants[[1L]]$person_id<-"Changed only in child input"
  check("child independently checks reviewed crosswalk hash",rejects(brohn_analyse_task_cohort(modified)))
  expected<-brohn_hash(r$body);brohn_close_store(store);store<-brohn_open_store(file.path(root,"workspace"))
  check("reopen preserves full report binary64 values source evidence and immutable history",brohn_hash(brohn_get_entity(store,"report",r$id)$body)==expected&&length(brohn_entity_history(store,"report",r$id))==1L&&identical(metric(brohn_read_json_file(brohn_object_path(store,r$body$result_object$hash))$report$analysis,"test_first_response_error_rate")$mean,1/6))
  check("all original source and registry bytes remain readable",all(vapply(first$report$body$analysis$task_attempts,function(a)file.exists(brohn_object_path(store,a$source$original_hash))&&file.exists(brohn_object_path(store,a$source$registry_object_hash)),logical(1))))
  check("no pending processing remains in isolated evidence workspace",!any(vapply(brohn_list_jobs(store),function(j)j$status %in% c("queued","running"),logical(1))))
  passed<-TRUE
  cat("Task cohort worker:",checks,"checks passed;",sum(vapply(jobs,function(j)j$status=="succeeded",logical(1))),"successful scientific publications;",length(jobs),"supervised attempts; evidence",root,"\n")
})
