# One actual scientific child against original, directly saved source fixtures.
# Run in a coordinated product-source freeze; no physical device or live service.
source('R/platform-load.R',encoding='UTF-8');brohn_load(ui=TRUE)
source('tests/fixtures/original-task-cohort-store.R',encoding='UTF-8')
local({
  root<-file.path(normalizePath('../../work/test-runs',winslash='/',mustWork=TRUE),paste0('brohn-task-cohort-title-',format(Sys.time(),'%Y%m%d-%H%M%S'),'-',substr(brohn_id('qa'),4L,11L)))
  stopifnot(!file.exists(root));dir.create(root);store<-brohn_open_store(file.path(root,'workspace'));brohn_initialise_library(store)
  checks<-0L;passed<-FALSE;job<-NULL
  check<-function(label,value){if(!isTRUE(value))stop(label,call.=FALSE);checks<<-checks+1L}
  on.exit({for(j in brohn_list_jobs(store))if(j$status %in% c('queued','running'))brohn_cancel_job(store,j$id)
    brohn_write_json_file(list(schema='brohn-task-cohort-title-evidence/1.0',passed=passed,checks=checks,jobs=brohn_list_jobs(store),
      qualification='One actual isolated supervised cohort worker. Original source reports use the explicitly declared direct-save fixture; setup is not an additional import-worker claim.'),file.path(root,'evidence.json'))
    brohn_close_store(store)},add=TRUE)
  f<-brohn_original_cohort_store_fixture(store);originals<-lapply(f$reports,function(r)brohn_hash(r$body))
  c<-brohn_task_cohort_catalog(store,f$study$id,lapply(f$reports,`[[`,'id'));map<-brohn_original_cohort_map(c$attempts)
  title<-'Original P and Q - equal-person report';description<-paste(rep('Original full source selection and repeat notes.',30L),collapse=' ')
  job<-brohn_queue_task_cohort(store,f$study$id,c$report_ids,lapply(c$attempts,`[[`,'id'),map,
    'equal_attempts_within_session_then_equal_sessions_within_person',description,c$selection_hash,report_title=title)
  check('Queued name is distinct from the full original plan',job$request$report_title==title&&job$request$plan$description==description&&nchar(description)>240L)
  claim<-brohn_claim_job(store,'original-title-worker',90L);stopifnot(claim$id==job$id);brohn_process_job(store,claim,timeout_seconds=120)
  done<-brohn_get_job(store,job$id);if(done$status!='succeeded')stop(brohn_json(done$error))
  report<-brohn_get_entity(store,'report',done$result$report_id);a<-report$body$analysis
  check('Actual scientific publication retains the exact short reviewed report name',identical(report$body$title,title)&&identical(report$body$provenance$plan$description,description)&&report$body$processing$publication$native_seal)
  check('Report naming leaves the equal-person scientific result unchanged',Filter(function(m)m$metric=='correct_test_rt_mean',a$summaries)[[1L]]$mean==2&&a$quality$selected_person_count==2L)
  object<-brohn_read_json_file(brohn_object_path(store,report$body$result_object$hash))
  check('Full retained object matches exact named catalog report',object$report$title==title&&brohn_hash(object$report)==brohn_hash(report$body[setdiff(names(report$body),'result_object')]))
  html<-file.path(root,'named-report.html');brohn_export_report_html(report$body,html,store)
  check('Standalone HTML exports the reviewed name',grepl(title,paste(readLines(html,warn=FALSE),collapse='\n'),fixed=TRUE))
  expected<-brohn_hash(report$body);brohn_close_store(store);store<-brohn_open_store(file.path(root,'workspace'))
  check('Reopen and study report catalog preserve exact name without renaming source reports',brohn_hash(brohn_get_entity(store,'report',report$id)$body)==expected&&
    any(vapply(brohn_search_related(store,'study_reports',f$study$id)$records,function(r)identical(r$id,report$id)&&identical(r$body$title,title),logical(1)))&&
    identical(lapply(f$reports,function(r)brohn_hash(brohn_get_entity(store,'report',r$id)$body)),originals))
  check('One actual job completed with no pending work',length(brohn_list_jobs(store))==1L&&brohn_get_job(store,job$id)$status=='succeeded')
  passed<-TRUE;cat('Task cohort title:',checks,'checks passed; one actual scientific publication; evidence',root,'\n')
})
