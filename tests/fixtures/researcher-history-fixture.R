# Original catalog fixtures: saved bodies are explicit inputs, not fabricated
# claims of scientific processing. All writes stay in this owned test workspace.
args <- commandArgs(trailingOnly=TRUE)
source('R/platform-load.R');brohn_load(ui=TRUE)
mode<-args[[1L]];folder<-normalizePath(args[[2L]],winslash='/',mustWork=TRUE)
stopifnot(grepl('^brohn-history-pages-',basename(folder)))
workspace<-file.path(folder,'workspace');config_path<-file.path(folder,'fixture.json')
if(mode=='serve') {
  config<-brohn_read_json_file(config_path)
  Sys.setenv(BROHN_WORKSPACE=workspace,BROHN_APP_MODE='platform')
  stop_path<-file.path(folder,'stop.request')
  if(file.exists(stop_path))unlink(stop_path)
  check_stop<-function(){if(file.exists(stop_path))shiny::stopApp() else later::later(check_stop,.2)}
  later::later(check_stop,.2)
  shiny::runApp('.',host='127.0.0.1',port=config$port,launch.browser=FALSE)
} else local({
  store<-brohn_open_store(workspace);on.exit(brohn_close_store(store),add=TRUE)
  if(mode=='create') {
    stopifnot(is.null(brohn_get_entity(store,'project','default')))
    brohn_initialise_library(store)
    target<-brohn_create_study(store,'Original historical target study')
    other<-brohn_create_study(store,'Original unrelated recent study')
    empty<-brohn_create_study(store,'Original empty study')
    source_file<-file.path(folder,'original-single-row.csv')
    writeLines('person,visit,question,value\nORIGINAL-HISTORY-P001,V001,original-item,2',source_file,useBytes=TRUE)
    first<-brohn_ingest_dataset(store,source_file,'Original target dataset 001','questionnaire',study_id=target$id,origin='sample')
    ids<-list(datasets=list(first$id),reports=list(),noise_datasets=list(),noise_reports=list())
    make_report<-function(id,index,study,dataset_id,title) list(id=id,title=title,study_id=study$id,dataset_id=dataset_id,
      created_at='2026-09-08T00:00:00.000Z',status='Original catalog fixture',origin='sample',
      analysis=list(kind='questionnaire',observations=list(),features=list(),contrasts=list(),
        quality=list(original_fixture_index=index,response_count=0L,participant_count=0L,session_count=0L),
        parameters=list(original_catalog_fixture=TRUE),limitations=list('Original catalog retrieval fixture. No participant or scientific analysis was executed.')),
      provenance=list(design=study$body,design_hash=brohn_hash(study$body),source_hash=first$body$source$hash),
      processing=list(origin='original_synthetic_catalog_fixture',computed=FALSE))
    brohn_store_batch(store,function(){
      for(i in 2:43) {body<-first$body;body$id<-sprintf('history-target-dataset-%03d',i);body$title<-sprintf('Original target dataset %03d',i)
        brohn_put_entity(store,'dataset',body$id,body);ids$datasets[[i]]<<-body$id}
      for(i in 1:43) {id<-sprintf('history-target-report-%03d',i);body<-make_report(id,i,target,first$id,sprintf('Original target report %03d',i))
        brohn_put_entity(store,'report',id,body);ids$reports[[i]]<<-id
        if(i==1L)brohn_write_json_file(body,file.path(folder,'expected-oldest-report.json'))}
      # A separate project's corrupted parent reference must not contaminate
      # the target project's list. These bodies are deliberate boundary inputs.
      brohn_put_entity(store,'project','history-foreign',list(id='history-foreign',title='Original other project',archived=FALSE))
      foreign<-first$body;foreign$id<-'history-foreign-dataset';foreign$title<-'DO NOT SHOW foreign project dataset'
      brohn_put_entity(store,'dataset',foreign$id,foreign,project_id='history-foreign')
      foreign_report<-make_report('history-foreign-report',999L,target,first$id,'DO NOT SHOW foreign project report')
      brohn_put_entity(store,'report',foreign_report$id,foreign_report,project_id='history-foreign')
      old_job<-brohn_enqueue_job(store,'analyse_dataset',list(dataset_id=first$id,original_catalog_fixture=TRUE),'history-old-matching-job')
      brohn_cancel_job(store,old_job$id);ids$old_job<<-old_job$id
      for(i in 1:510) {
        body<-first$body;body$id<-sprintf('history-noise-dataset-%03d',i);body$title<-sprintf('Unrelated recent dataset %03d',i);body$study_id<-other$id
        brohn_put_entity(store,'dataset',body$id,body);ids$noise_datasets[[i]]<<-body$id
        id<-sprintf('history-noise-report-%03d',i);report<-make_report(id,i,other,body$id,sprintf('Unrelated recent report %03d',i))
        brohn_put_entity(store,'report',id,report);ids$noise_reports[[i]]<<-id
        if(i<=110) {job<-brohn_enqueue_job(store,'analyse_dataset',list(dataset_id=body$id,original_catalog_fixture=TRUE),paste0('history-unrelated-job-',i));brohn_cancel_job(store,job$id)}
      }
    })
    original_design<-target$body;original_design$description<-'Original historical revision one remains independently inspectable.'
    target<-brohn_save_study(store,original_design,target$revision)
    original_design$description<-'Original latest revision keeps the same historical evidence.'
    target<-brohn_save_study(store,original_design,target$revision)
    config<-list(origin='original_synthetic_catalog_fixture',workspace=workspace,port=httpuv::randomPort(min=19000L,max=49000L),
      target_id=target$id,other_id=other$id,empty_id=empty$id,target_title=target$body$title,other_title=other$body$title,empty_title=empty$body$title,
      ids=ids,source_file=source_file,source_sha256=first$body$source$hash,expected_reports=43L,expected_datasets=43L,newer_unrelated=510L,
      oldest_report_hash=brohn_hash(brohn_get_entity(store,'report',ids$reports[[1L]])$body))
    brohn_write_json_file(config,config_path)
  } else config<-brohn_read_json_file(config_path)
  checks<-list();check<-function(name,ok){stopifnot(isTRUE(ok));checks[[length(checks)+1L]]<<-name}
  check('Original target reports disappear from the old global500-then-filter retrieval',!any(vapply(brohn_list_entities(store,'report'),function(r)identical(r$body$study_id,config$target_id),logical(1))))
  check('Original target datasets disappear from the old global500-then-filter retrieval',!any(vapply(brohn_list_entities(store,'dataset'),function(r)identical(r$body$study_id,config$target_id),logical(1))))
  check('Original matching processing attempt lies beyond the old global100 bound',!config$ids$old_job %in% vapply(brohn_list_jobs(store),`[[`,character(1),'id'))
  for(relation in c('study_reports','study_datasets','dataset_reports')) {
    parent<-if(relation=='dataset_reports')config$ids$datasets[[1L]] else config$target_id
    expected<-if(relation=='study_datasets')rev(unlist(config$ids$datasets)) else rev(unlist(config$ids$reports))
    first_page<-brohn_search_related(store,relation,parent);last_page<-brohn_search_related(store,relation,parent,offset=40L)
    check(paste(relation,'has exact43 records and40/3 pages'),first_page$total==43L&&last_page$total==43L&&length(first_page$records)==40L&&length(last_page$records)==3L)
    actual<-vapply(c(first_page$records,last_page$records),`[[`,character(1),'id')
    check(paste(relation,'returns exact independently inserted reverse chronology including oldest source'),identical(actual,expected))
  }
  check('Dataset attempts select the one old matching row before limiting',identical(brohn_search_related(store,'dataset_jobs',config$ids$datasets[[1L]])$records[[1L]]$id,config$ids$old_job))
  state<-new.env(parent=emptyenv());state$page<-'study';state$study_id<-config$target_id;state$stage<-'Results';state$related_offsets<-list()
  command<-list(relation='study_reports',parent_id=config$target_id,offset=0L,limit=40L,direction=1L)
  check('Visible first-page command advances only its own relation',isTRUE(brohn_related_page_command(store,state,command))&&brohn_related_offset(state,'study_reports',config$target_id)==40L)
  check('Stale command offset cannot advance a changed page',inherits(try(brohn_related_page_command(store,state,command),silent=TRUE),'try-error'))
  state$study_id<-config$other_id;command$offset<-40L;command$direction<--1L
  check('A prior study pager cannot affect the newly opened study',inherits(try(brohn_related_page_command(store,state,command),silent=TRUE),'try-error')&&brohn_related_offset(state,'study_reports',config$other_id)==0L)
  check('Oldest immutable report retains its original independent body hash',identical(config$oldest_report_hash,brohn_hash(brohn_get_entity(store,'report',config$ids$reports[[1L]])$body)))
  brohn_write_json_file(list(checks=checks),file.path(folder,'backend-results.json'))
  cat(sprintf('History retrieval fixture: %d independent backend assertions passed.\n',length(checks)))
})
