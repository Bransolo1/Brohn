source("R/platform-load.R");brohn_load(ui=TRUE)
for(n in c("task-cohort","task-cohort-storage","task-cohort-views"))source(paste0("R/platform-",n,".R"))
source("tests/fixtures/original-task-cohort-store.R")
local({
  checks<-0L;check<-function(label,x){if(!isTRUE(x))stop("Cohort storage: ",label,call.=FALSE);checks<<-checks+1L}
  rejects<-function(expr,pattern=NULL){e<-tryCatch({force(expr);NULL},error=conditionMessage);!is.null(e)&&(is.null(pattern)||grepl(pattern,e,fixed=TRUE))}
  root<-tempfile("brohn-task-cohort-storage-");store<-brohn_open_store(root);brohn_initialise_library(store)
  on.exit({for(j in brohn_list_jobs(store))if(j$status %in% c("queued","running"))brohn_cancel_job(store,j$id);brohn_close_store(store)},add=TRUE)
  f<-brohn_original_cohort_store_fixture(store);ids<-lapply(f$reports,`[[`,"id")
  catalog<-brohn_task_cohort_catalog(store,f$study$id,ids)
  check("saved original result objects and canonical administrations are verified",length(catalog$reports)==3L&&length(catalog$attempts)==3L&&length(catalog$groups)==1L&&all(vapply(catalog$reports,function(r)r$status=="supported",logical(1))))
  check("source catalog identity rows remain unapplied",all(vapply(catalog$identities$participants,function(p)is.null(p$person_id),logical(1))))
  map<-brohn_original_cohort_map(catalog$attempts)
  args<-list(store=store,study_id=f$study$id,report_ids=ids,attempt_ids=lapply(catalog$attempts,`[[`,"id"),identity_map=map,
    repeat_policy="equal_attempts_within_session_then_equal_sessions_within_person",description="Original frozen task cohort",expected_selection_hash=catalog$selection_hash)
  request<-do.call(brohn_prepare_task_cohort,args);input<-brohn_task_cohort_input(store,request);report<-brohn_analyse_task_cohort(input)
  null_title<-do.call(brohn_prepare_task_cohort,c(args,list(report_title=NULL)))
  check("omitted or NULL report title preserves legacy request hash and title",identical(request,null_title)&&!"report_title" %in% names(request)&&report$title==paste(request$design$title,"task participants"))
  named_args<-args;named_args$description<-paste(rep("Original full plan notes",100L),collapse=" ");named_args$report_title<-"Original explicit cohort name"
  named_request<-do.call(brohn_prepare_task_cohort,named_args)
  named_report<-brohn_analyse_task_cohort(brohn_task_cohort_input(store,named_request))
  check("short reviewed report title remains independent of full plan description",named_report$title==named_args$report_title&&identical(named_report$provenance$plan$description,named_args$description)&&nchar(named_args$description)>240L)
  named_request$report_title<-paste(rep("\u00e9",120L),collapse="")
  check("exact240 UTF8 byte report name is retained without truncation",identical(brohn_analyse_task_cohort(brohn_task_cohort_input(store,named_request))$title,named_request$report_title))
  for(value in c("","   ","Line\nbreak","Tab\tname",paste0("C1",intToUtf8(133L)),paste(rep("\u00e9",121L),collapse=""))) {
    bad_title<-args;bad_title$report_title<-value
    altered<-input;altered$request$report_title<-value
    check("invalid title rejected by prepare store input and isolated analysis",rejects(do.call(brohn_prepare_task_cohort,bad_title),"report name")&&rejects(brohn_task_cohort_input(store,altered$request),"report name")&&rejects(brohn_analyse_task_cohort(altered),"report name"))
  }
  metric<-Filter(function(s)s$metric=="correct_test_rt_mean",report$analysis$summaries)[[1L]]
  check("actual saved-source adapter preserves mean2 not5/3 and N2",metric$mean==2&&metric$contributing_person_count==2&&metric$contributing_session_count==3)
  check("frozen request retains report revisions objects and attempt hashes",length(request$reports)==3L&&length(request$bindings)==3L&&all(vapply(request$reports,function(r).brohn_task_cohort_hash(r$body_hash)&&.brohn_task_cohort_hash(r$result_object_hash)&&r$revision==1L,logical(1))))
  check("cohort report retains original full source designs and explicit plan",report$study_id==f$study$id&&report$origin=="sample"&&identical(report$provenance$plan,request$plan)&&identical(report$provenance$source_administrations,request$bindings)&&report$analysis$quality$usable)
  job<-do.call(brohn_queue_task_cohort,args);again<-do.call(brohn_queue_task_cohort,args)
  check("identical frozen queue request is idempotent and never autostarts",identical(job$id,again$id)&&job$operation=="analyse_task_cohort"&&job$status=="queued"&&job$attempt==0L)
  brohn_cancel_job(store,job$id)
  before<-length(brohn_list_jobs(store));bad<-args;bad$expected_selection_hash<-brohn_hash("stale")
  check("stale review cannot enqueue or overwrite source reports",rejects(do.call(brohn_queue_task_cohort,bad),"changed after review")&&length(brohn_list_jobs(store))==before)
  bad<-args;bad$repeat_policy<-"one_selected_attempt_per_person"
  check("repeat selection failure occurs before queue write",rejects(do.call(brohn_queue_task_cohort,bad),"before considering")&&length(brohn_list_jobs(store))==before)
  native<-f$publish(list(kind="questionnaire",task_scores=f$reports[[1L]]$body$analysis$task_scores),title="Original native summary only")
  nc<-brohn_task_cohort_catalog(store,f$study$id,list(native$id))
  check("native summary is explicitly unsupported without invented attempts or replay",nc$reports[[1L]]$status=="unsupported_source"&&length(nc$attempts)==0L&&grepl("not inherited",nc$reports[[1L]]$reason,fixed=TRUE))
  mixed<-brohn_task_cohort_catalog(store,f$study$id,c(ids,list(native$id)));bad<-args;bad$report_ids<-mixed$report_ids;bad$expected_selection_hash<-mixed$selection_hash
  check("unsupported source is never silently dropped during queue selection",rejects(do.call(brohn_prepare_task_cohort,bad),"Remove unsupported"))
  unknown<-f$source_report(person="R",unknown=TRUE);missing<-f$source_report(person="T",incomplete=TRUE)
  uc<-brohn_task_cohort_catalog(store,f$study$id,list(unknown$id,missing$id));um<-brohn_original_cohort_map(uc$attempts)
  ur<-brohn_prepare_task_cohort(store,f$study$id,uc$report_ids,lapply(uc$attempts,`[[`,"id"),um,args$repeat_policy,"Selected unavailable attempts",uc$selection_hash)
  ua<-brohn_analyse_task_cohort(brohn_task_cohort_input(store,ur))$analysis
  check("unavailable source quality never filters selected canonical attempts",length(ua$membership)==2L&&ua$quality$selected_attempt_count==2L&&!ua$quality$usable&&ua$status=="needs_review"&&length(ua$attempt_metrics)==10L)
  bad<-args;bad$attempt_ids<-bad$attempt_ids[-3L]
  check("unused selected report requires explicit removal",rejects(do.call(brohn_prepare_task_cohort,bad),"Every selected report"))
  other<-brohn_create_study(store,"Original other study")
  check("same-project report cannot cross study scope",rejects(brohn_task_cohort_catalog(store,other$id,ids),"exact study"))
  brohn_put_entity(store,"project","cohort-foreign-project",list(id="cohort-foreign-project",title="Private other project",archived=FALSE),project_id="cohort-foreign-project")
  fd<-f$study$body;fd$id<-brohn_id("study");fd$project_id<-"cohort-foreign-project";brohn_put_entity(store,"study",fd$id,fd,project_id=fd$project_id)
  foreign<-f$publish(f$reports[[1L]]$body$analysis,design=fd,title="Never leak this foreign report title",project_id=fd$project_id)
  error<-tryCatch(brohn_task_cohort_catalog(store,f$study$id,list(foreign$id)),error=conditionMessage)
  check("foreign project is rejected before its contents/title are returned",is.character(error)&&grepl("outside",error,fixed=TRUE)&&!grepl("Never leak",error,fixed=TRUE))
  check("explicit wrong parent project rejects metadata discovery",rejects(brohn_task_cohort_report_catalog(store,f$study$id,project_id=fd$project_id),"outside"))
  # Metadata pagination deliberately includes many native summaries without loading
  # their complete protocol/report bodies. Other studies must not hide older rows.
  for(i in seq_len(47L)) {
    b<-native$body;b$id<-brohn_id("report");b$title<-paste("Original paged native",i)
    brohn_put_entity(store,"report",b$id,b)
  }
  for(i in seq_len(52L)) {
    b<-native$body;b$id<-brohn_id("report");b$study_id<-other$id
    brohn_put_entity(store,"report",b$id,b)
  }
  none<-native$body;none$id<-brohn_id("report");none$analysis<-list(kind="questionnaire",task_scores=list())
  brohn_put_entity(store,"report",none$id,none)
  page<-brohn_task_cohort_report_catalog(store,f$study$id);page2<-brohn_task_cohort_report_catalog(store,f$study$id,offset=40L)
  check("task report parent filter precedes pagination and includes older sources",page$total==53L&&length(page$records)==40L&&page$has_next&&length(page2$records)==13L&&page2$has_previous&&!page2$has_next)
  check("metadata discovery does not expose protocols identities or analysis bodies",all(vapply(page$records,function(r)!any(c("analysis","protocol","provenance","task_attempts","access_token","participant_id") %in% names(r)),logical(1))))
  check("no empty-task questionnaire report enters task selection",!none$id %in% c(vapply(page$records,`[[`,character(1),"id"),vapply(page2$records,`[[`,character(1),"id")))
  check("out-of-range page keeps last older source reachable",brohn_task_cohort_report_catalog(store,f$study$id,offset=999L)$offset==40L)
  # A newer report head cannot replace the exact queued version.
  changed<-f$reports[[1L]]$body;changed$title<-"Newer independent report metadata"
  brohn_put_entity(store,"report",changed$id,changed,expected_revision=1L)
  pinned<-brohn_task_cohort_input(store,request)
  check("queued report reads pinned old revision after head changes",identical(pinned,input)&&pinned$request$reports[[1L]]$revision==1L)
  check("old UI review cannot silently accept a changed report head",rejects(do.call(brohn_prepare_task_cohort,args),"changed after review"))
  modified<-request;modified$reports[[1L]]$body_hash<-brohn_hash("wrong")
  check("pinned report body mismatch rejects",rejects(brohn_task_cohort_input(store,modified),"frozen source report"))
  modified<-request;modified$bindings[[1L]]$report_id<-ids[[2L]]
  check("report-to-administration source linkage cannot be reassigned",rejects(brohn_task_cohort_input(store,modified),"bindings changed"))
  modified<-request;modified$plan$membership[[1L]]$attempt_hash<-brohn_hash("wrong")
  check("altered administration hash rejects at worker input",rejects(brohn_task_cohort_input(store,modified),"plan or identity"))
  modified<-request;modified$identity_map$participants[[1L]]$person_id<-"unexpected replacement"
  check("valid-looking crosswalk mutation cannot alter a frozen plan",rejects(brohn_task_cohort_input(store,modified),"plan or identity"))
  modified<-input;modified$request$plan$repeat_policy<-"one_selected_attempt_per_person"
  check("scientific child rechecks frozen plan before calculating",rejects(brohn_analyse_task_cohort(modified),"plan or identity"))
  modified<-request;modified$project_id<-fd$project_id
  check("frozen job cannot redirect its project",rejects(brohn_task_cohort_input(store,modified),"outside"))
  # Direct fixture records let us deliberately preserve an internally inconsistent
  # report without mutating immutable real object bytes.
  tamper<-f$reports[[2L]]$body;tamper$id<-brohn_id("report");tamper$analysis$task_attempts[[1L]]$score$metrics[[1L]]$value<-99
  brohn_put_entity(store,"report",tamper$id,tamper)
  check("catalog analysis cannot drift from retained result JSON",rejects(brohn_task_cohort_catalog(store,f$study$id,list(tamper$id)),"catalog and retained"))
  absent<-f$reports[[2L]]$body;absent$id<-brohn_id("report");absent$result_object$hash<-brohn_hash("absent object")
  brohn_put_entity(store,"report",absent$id,absent)
  check("missing complete result object is an integrity failure",rejects(brohn_task_cohort_catalog(store,f$study$id,list(absent$id))))
  missing_source<-f$reports[[1L]]$body$analysis
  a<-missing_source$task_attempts[[1L]];a$source$original_hash<-brohn_hash("absent retained original bytes")
  a$id<-paste0("task-attempt-",brohn_hash(list(original_source_hash=a$source$original_hash,logical_evidence_key=a$logical_evidence_key)));a$score$attempt_id<-a$id
  missing_source$task_attempts[[1L]]<-a;lost_original<-f$publish(missing_source)
  check("retained original source bytes must remain verifiable",rejects(brohn_task_cohort_catalog(store,f$study$id,list(lost_original$id))))
  missing_registry<-f$reports[[1L]]$body$analysis;missing_registry$task_attempts[[1L]]$source$registry_object_hash<-brohn_hash("absent original registry bytes")
  lost_registry<-f$publish(missing_registry)
  check("retained protocol registry bytes must remain verifiable",rejects(brohn_task_cohort_catalog(store,f$study$id,list(lost_registry$id))))
  # Existing source studies may be archived; analysis must use the frozen original
  # design and must never reopen collection or alter any deployment.
  ds<-brohn_get_entity(store,"study",f$study$id);ds$body$archived<-TRUE;brohn_put_entity(store,"study",ds$id,ds$body,ds$revision)
  check("archiving current draft does not rewrite frozen selected report inputs",identical(brohn_task_cohort_input(store,request),input))
  oldhash<-brohn_hash(report);brohn_close_store(store);store<-brohn_open_store(root)
  check("reopen retains exact objects selection and equal-person arithmetic",brohn_hash(brohn_analyse_task_cohort(brohn_task_cohort_input(store,request)))==oldhash)
  html<-as.character(brohn_task_cohort_report_ui(report$analysis))
  check("report preview explains own metric support and total export rows",grepl("measure-specific support",html,fixed=TRUE)&&grepl("no confidence interval",html,fixed=TRUE)&&grepl("Showing up to 30",html,fixed=TRUE))
  path<-tempfile(fileext=".csv");brohn_export_task_cohort_csv(report,path,"summaries")
  csv<-read.csv(path,stringsAsFactors=FALSE,check.names=FALSE);unlink(path)
  check("cohort CSV exports complete named outcomes and frozen plan identity",nrow(csv)==5L&&all(csv$plan_hash==report$analysis$provenance$plan_hash)&&csv$mean[csv$metric=="correct_test_rt_mean"]==2)
  check("all test queue attempts were cancelled without workers",all(vapply(brohn_list_jobs(store),function(j)j$status=="cancelled"&&j$attempt==0L,logical(1))))
  cat("Task cohort storage:",checks,"saved-object and source-bound adapter checks passed; no scientific worker executed.\n")
})
