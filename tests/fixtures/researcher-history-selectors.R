# Extend only a separately owned historical catalog with old study selectors.
args<-commandArgs(trailingOnly=TRUE);mode<-args[[1L]]
source('R/platform-load.R');brohn_load(ui=FALSE)
folder<-normalizePath(args[[2L]],winslash='/',mustWork=TRUE)
stopifnot(grepl('^brohn-history-pages-',basename(folder)))
local({
  config<-brohn_read_json_file(file.path(folder,'fixture.json'));store<-brohn_open_store(config$workspace)
  on.exit(brohn_close_store(store),add=TRUE)
  path<-file.path(folder,'selector-fixture.json')
  if(mode=='create') {
    stopifnot(!file.exists(path))
    target<-brohn_archive_study(store,config$target_id,TRUE)
    base<-brohn_study(store,config$other_id)$body
    brohn_store_batch(store,function(){
      for(i in 1:510) {d<-base;d$id<-sprintf('history-selector-newer-study-%03d',i);d$title<-sprintf('Unrelated newer study selector %03d',i)
        brohn_put_entity(store,'study',d$id,d)}
      d<-base;d$id<-'history-selector-foreign-study';d$title<-'DO NOT SELECT another project study';d$project_id<-'history-foreign'
      brohn_put_entity(store,'study',d$id,d,project_id='history-foreign')
    })
    csv<-file.path(folder,'original-selector-source.csv');q<-target$body$questions[[1L]];s<-target$body$stimuli[[1L]]
    writeLines(paste0('person,visit,question,value,stimulus,condition,assessment\nORIGINAL-SELECTOR-P001,V001,',q$id,',2,',s$id,',',s$condition_id,',A001'),csv,useBytes=TRUE)
    first<-brohn_ingest_dataset(store,csv,'Original old-study mapping destination','questionnaire',origin='sample')
    second<-brohn_ingest_dataset(store,csv,'Original protected other mapping destination','questionnaire',origin='sample')
    metadata<-list(target_id=target$id,target_title=target$body$title,target_revision=target$revision,
      first_id=first$id,first_title=first$body$title,second_id=second$id,second_title=second$body$title,
      second_original_hash=brohn_hash(second$body),old_reports=as.list(unlist(config$ids$reports)[1:2]),source_hash=first$body$source$hash,
      foreign_study_id='history-selector-foreign-study',foreign_report_id='history-foreign-report')
    brohn_write_json_file(metadata,path)
  } else metadata<-brohn_read_json_file(path)
  studies<-brohn_study_choices(store,'default');reports<-brohn_source_report_choices(store,metadata$target_id)
  stopifnot(metadata$target_id %in% unname(studies),!metadata$foreign_study_id %in% unname(studies),
    all(unlist(metadata$old_reports) %in% unname(reports)),!metadata$foreign_report_id %in% unname(reports))
  # Readonly snapshots let browser checks verify saved identity and queued
  # transport without asserting that a scientific worker ran in this fixture.
  snapshot<-list(study=brohn_study(store,metadata$target_id),first=brohn_get_entity(store,'dataset',metadata$first_id),
    second=brohn_get_entity(store,'dataset',metadata$second_id),
    jobs=brohn_search_related(store,'dataset_jobs',metadata$first_id)$records,
    study_choice_count=length(studies),report_choice_count=length(reports),
    second_unchanged=identical(brohn_hash(brohn_get_entity(store,'dataset',metadata$second_id)$body),metadata$second_original_hash))
  brohn_write_json_file(snapshot,file.path(folder,'selector-snapshot.json'))
  cat('Original old-study and old-report selector metadata checks passed.\n')
})
