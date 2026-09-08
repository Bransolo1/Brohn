# Prepare runs only the receiver and direct R calculation. Execute workers only
# after a coordinated shared-source freeze: this-file run <retained folder>.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)>0L);mode<-args[[1L]]
stopifnot(mode %in% c('prepare','run','continue'))
source('R/platform-load.R',encoding='UTF-8');brohn_load(ui=TRUE)
source('tests/fixtures/original-questionnaire-boundary.R',encoding='UTF-8')
local({
  parent<-normalizePath('../../work/test-runs',winslash='/',mustWork=TRUE)
  folder<-if(length(args)>1L)normalizePath(args[[2L]],winslash='/',mustWork=TRUE)else{
    stopifnot(mode=='prepare');p<-file.path(parent,paste0('brohn-questionnaire-artifact-worker-',format(Sys.time(),'%Y%m%d-%H%M%S'),'-',substr(brohn_id('qa'),4L,11L)));dir.create(p);p}
  stopifnot(startsWith(tolower(folder),paste0(tolower(parent),'/')),startsWith(basename(folder),'brohn-questionnaire-artifact-worker-'))
  historical<-file.path(parent,'brohn-questionnaire-revision-boundary','sizes.json');historical_hash<-digest::digest(file=historical,algo='sha256')
  historical_sizes<-brohn_read_json_file(historical)
  store<-brohn_open_store(file.path(folder,'workspace'));on.exit(brohn_close_store(store),add=TRUE)
  config_path<-file.path(folder,'fixture.json');rawhash<-function(text)digest::digest(charToRaw(enc2utf8(text)),algo='sha256',serialize=FALSE)
  row_fingerprint<-function(id){rows<-DBI::dbGetQuery(store$con,'SELECT sequence,event_id,event_hash,length(CAST(event_json AS BLOB)) AS bytes FROM delivery_events WHERE run_id=? ORDER BY sequence',params=list(id));brohn_hash(lapply(seq_len(nrow(rows)),function(i)as.list(rows[i,,drop=FALSE])))}
  full_write<-function(value,path)writeBin(charToRaw(enc2utf8(brohn_json(value))),path)
  full_read<-function(path)brohn_parse(rawToChar(readBin(path,'raw',n=file.info(path)$size)),max_bytes=512*1024^2)
  if(mode=='prepare') {
    stopifnot(!file.exists(config_path));brohn_initialise_library(store)
    cat('Preparing faithful new retained receiver boundary in',folder,'\n');flush.console()
    existing<-brohn_runs(store)
    recovered<-length(existing)>0L
    if(!recovered)f<-brohn_original_questionnaire_boundary(store)else{
      # Resume a preparation that already completed and wrote its baseline before
      # a test assertion failed. Never regenerate or change its receiver source.
      stopifnot(length(existing)==1L,existing[[1L]]$completion_status=='completed',existing[[1L]]$acked_sequence==804L,
        file.exists(file.path(folder,'original-current-code-report.json')))
      run<-existing[[1L]];jobs<-brohn_list_jobs(store,request_filters=list(run_id=run$id));stopifnot(length(jobs)==1L,jobs[[1L]]$status=='cancelled',jobs[[1L]]$attempt==0L)
      text<-strrep('a',19000L)
      f<-list(study_id=run$study_id,run_id=run$id,original_job_id=jobs[[1L]]$id,
        independent=list(question_count=200L,entered_answer_count=400L,final_record_count=200L,text_characters=19000L,
          final_values=lapply(seq_len(200L),function(i)paste(text,2L,i)),first_values=lapply(seq_len(200L),function(i)paste(text,1L,i))),
        recovered_page_count=200L,journal_hash=brohn_hash(brohn_run_events(store,run$id)))
    }
    job<-brohn_get_job(store,f$original_job_id);stopifnot(job$status=='cancelled',job$attempt==0L)
    input<-brohn_job_input(store,job);report<-if(recovered)full_read(file.path(folder,'original-current-code-report.json'))else brohn_analyse_runs(input)
    if(!recovered)full_write(report,file.path(folder,'original-current-code-report.json'))
    sizes<-list(input_bytes=nchar(brohn_json(input),type='bytes'),output_bytes=nchar(brohn_json(list(schema='brohn-analysis-output/1.0',code_identity=list(),report=report)),type='bytes'))
    stopifnot(length(report$analysis$observations)==200L,length(report$analysis$questionnaire_revision$runs[[1L]]$effective_records)==200L,
      length(report$analysis$questionnaire_revision$runs[[1L]]$history_events)==803L,
      sum(vapply(report$analysis$questionnaire_revision$runs[[1L]]$history_events,function(e)e$payload$kind=='commit',logical(1)))==400L,sizes$output_bytes>16*1024^2)
    brohn_write_json_file(list(schema='brohn-questionnaire-artifact-worker-fixture/1.0',folder=folder,fixture=f,sizes=sizes,
      historical_sizes=historical_sizes,historical_sizes_hash=historical_hash,historical_store_available=dir.exists(historical_sizes$workspace),
      evidence_category='New original synthetic reproduction through actual receiver; the historical R-temp source is absent, and only its sizes.json was retained.',preparation_metadata_recovered=recovered,
      source_rows_hash=row_fingerprint(f$run_id),run_hash=brohn_hash(brohn_run(store,f$run_id)),
      original_analysis_hash=brohn_hash(report$analysis),original_provenance_hash=brohn_hash(report$provenance),
      expected_value_hashes=lapply(f$independent$final_values,rawhash)),config_path)
    cat('Prepared completed receiver run',f$run_id,'with own cancelled autojob',job$id,'; full report bytes',sizes$output_bytes,'; no scientific worker executed.\n')
    return(invisible(NULL))
  }
  config<-brohn_read_json_file(config_path);f<-config$fixture;checks<-0L;passed<-FALSE;published<-list();runids<-list(f$run_id)
  check<-function(label,value){if(!isTRUE(value))stop('Questionnaire artifact worker: ',label,call.=FALSE);checks<<-checks+1L;cat('PASS',label,'\n');flush.console()}
  rejects<-function(expr)inherits(try(force(expr),silent=TRUE),'try-error')
  on.exit({for(j in brohn_list_jobs(store))if(j$status %in% c('queued','running'))brohn_cancel_job(store,j$id)
    brohn_write_json_file(list(schema='brohn-questionnaire-artifact-worker-evidence/1.0',passed=passed,checks=checks,folder=folder,study_id=f$study_id,
      main_run_id=f$run_id,continuation=mode=='continue',source_origin=config$evidence_category,historical_sizes_hash=historical_hash,reports=published,jobs=brohn_list_jobs(store),
      limits='Actual receiver qualification only for recreated 200-question source; second source is explicitly seeded storage-transport evidence. Full analysis reconstruction still occurs in R memory.'),file.path(folder,'evidence.json'))},add=TRUE,after=FALSE)
  check('Historical size evidence is unchanged and missing original source is not called retained',historical_hash==config$historical_sizes_hash&&!config$historical_store_available&&historical_sizes$output_bytes==24090330)
  original<-brohn_get_job(store,f$original_job_id)
  check('New retained fixture owns its cancelled zero-attempt autojob',original$status=='cancelled'&&original$attempt==0L&&original$request$run_id==f$run_id)
  check('Prepared completed receiver rows are unchanged before retry',row_fingerprint(f$run_id)==config$source_rows_hash&&brohn_hash(brohn_run(store,f$run_id))==config$run_hash)
  baseline<-full_read(file.path(folder,'original-current-code-report.json'));current<-brohn_analyse_runs(brohn_job_input(store,original))
  check('Current complete analysis matches preparation before representation changes',brohn_hash(current$analysis)==config$original_analysis_hash&&brohn_hash(current$provenance)==config$original_provenance_hash&&brohn_hash(baseline)==brohn_hash(current))
  scratch<-file.path(store$root,'scratch','independent-boundary-input')
  if(mode=='run') {
  retry<-brohn_retry_processing(store,original$id)
  check('Explicit retry keeps original cancelled job and exact same request',brohn_get_job(store,original$id)$status=='cancelled'&&retry$request$run_id==f$run_id&&retry$id!=original$id)
  claim<-brohn_claim_job(store,'original-questionnaire-artifact-worker',lease_seconds=120L);stopifnot(claim$id==retry$id)
  dir.create(scratch,recursive=TRUE)
  compact_input<-brohn_prepare_run_evidence_input(store,claim,scratch);hydrated<-brohn_read_run_evidence_input(compact_input,scratch)
  brohn_write_json_file(compact_input,file.path(folder,'independent-boundary-manifest.json'))
  check('Compact worker input preserves full exact receiver journal and protocol',nchar(brohn_json(compact_input),type='bytes')<16384&&brohn_hash(hydrated$events)==brohn_hash(brohn_job_input(store,original)$events)&&length(hydrated$events[[f$run_id]])==804L)
  brohn_process_job(store,claim,timeout_seconds=900)
  done<-brohn_get_job(store,retry$id);if(done$status!='succeeded')stop('Actual boundary child failed: ',brohn_json(done$error))
  } else {
    successes<-Filter(function(j)j$status=='succeeded',brohn_list_jobs(store,request_filters=list(run_id=f$run_id)))
    check('Continuation reuses the single retained successful main publication without another main worker',length(successes)==1L&&successes[[1L]]$attempt==1L)
    done<-successes[[1L]]
  }
  r<-brohn_get_entity(store,'report',done$result$report_id);published[[1L]]<-list(id=r$id,result_object=r$body$result_object,run_id=f$run_id)
  if(mode=='run')check('Saved run provenance pins the exact compact manifest and full journal hashes',r$body$provenance$run_evidence$binding_hash==compact_input$run_evidence$binding_hash&&
    r$body$provenance$run_evidence$runs[[1L]]$journal_sha256==compact_input$run_evidence$runs[[1L]]$journal$sha256&&r$body$provenance$run_evidence$runs[[1L]]$event_count==804L)
  else check('Retained publication binds the unchanged independent full journal and protocol bytes',
    r$body$provenance$run_evidence$runs[[1L]]$journal_sha256==digest::digest(file=file.path(scratch,'input-evidence','run-00000001.events.jsonl'),algo='sha256')&&
    r$body$provenance$run_evidence$runs[[1L]]$protocol_sha256==digest::digest(file=file.path(scratch,'input-evidence','run-00000001.protocol.json'),algo='sha256')&&
    r$body$provenance$run_evidence$runs[[1L]]$event_count==804L)
  check('Actual large-history child publishes a compact artifact-backed report',brohn_questionnaire_is_artifact(r$body$analysis)&&r$body$result_object$size<=16*1024^2&&nchar(brohn_json(r$body),type='bytes')<=16*1024^2)
  ref<-brohn_questionnaire_report_artifact(r$body);artifact_path<-brohn_object_path(store,ref$hash)
  artifact<-brohn_read_questionnaire_artifact(artifact_path,ref,expected_source=brohn_questionnaire_artifact_source(r$body))
  check('Complete typed reconstruction exactly equals original current-code analysis',brohn_hash(artifact)==config$original_analysis_hash&&brohn_hash(artifact)==ref$analysis_sha256&&file.info(artifact_path)$size==ref$size)
  rev<-artifact$questionnaire_revision$runs[[1L]]
  commits<-Filter(function(e)e$payload$kind=='commit',rev$history_events)
  check('All200 final answers and803 events containing400 answer versions remain present',length(artifact$observations)==200L&&length(rev$effective_records)==200L&&length(rev$history_events)==803L&&length(rev$history_records)==803L&&length(commits)==400L)
  final<-rev$effective_records
  check('Independent final text oracle preserves complete19000-character prefixes and suffixes',all(vapply(seq_len(200L),function(i)identical(final[[i]]$value,f$independent$final_values[[i]])&&rawhash(final[[i]]$value)==config$expected_value_hashes[[i]],logical(1))))
  check('Every final answer retains exactly one revision and no fabricated initial response time',all(vapply(final,function(x)x$revision_count==1L&&is.null(x$response_time_ms),logical(1))))
  check('Both original answer passes remain separate in the complete history',identical(lapply(commits, function(e)e$payload$value),c(f$independent$first_values,f$independent$final_values)))
  check('Preview is explicitly bounded and never replaces scientific observations',length(r$body$analysis$preview$observations)<=10L&&is.null(r$body$analysis$observations)&&r$body$analysis$questionnaire_artifact$counts$observations==200L&&r$body$analysis$questionnaire_artifact$counts$revision_history==803L)
  full<-brohn_complete_questionnaire_report(store,r$body)
  check('Saved-report hydration resolves exact artifact instead of preview rows',brohn_hash(full$analysis)==config$original_analysis_hash)
  object<-brohn_read_json_file(brohn_object_path(store,r$body$result_object$hash))
  check('Compact catalog and retained publication envelope remain exactly equal',brohn_hash(object$report)==brohn_hash(r$body[setdiff(names(r$body),'result_object')])&&r$body$processing$publication$native_seal)
  json_path<-file.path(folder,'complete-report-export.json');brohn_export_complete_questionnaire_report(store,r$body,json_path);export<-full_read(json_path)
  check('Explicit complete JSON export exceeds old limit and preserves every typed analysis value',file.info(json_path)$size>16*1024^2&&brohn_hash(export$analysis)==config$original_analysis_hash&&export$export$saved_report_hash==brohn_hash(r$body)&&export$export$artifact$hash==ref$hash)
  csv_path<-file.path(folder,'complete-observations.csv');brohn_export_report_csv(full,csv_path);csv<-brohn_read_table(csv_path,'csv',1000L)
  check('Complete observation CSV exports200 untruncated final text values',nrow(csv)==200L&&identical(as.list(csv$value),f$independent$final_values))
  check('CSV canonical response records preserve complete typed original observations',"response_record_json" %in% names(csv)&&
    identical(brohn_hash(lapply(csv$response_record_json,brohn_parse)),brohn_hash(artifact$observations)))
  copied<-file.path(folder,'complete-questionnaire-artifact.jsonl');brohn_copy_object_download(store,ref$hash,copied)
  check('Full original typed artifact download retains exact bytes and source binding',digest::digest(file=copied,algo='sha256')==ref$hash&&brohn_hash(brohn_read_questionnaire_artifact(copied,ref,expected_source=brohn_questionnaire_artifact_source(r$body)))==config$original_analysis_hash)
  wrong<-r$body;wrong$origin<-'pilot'
  check('Cross-source artifact hydration is rejected',rejects(brohn_complete_questionnaire_report(store,wrong)))
  check('Original receiver evidence and cancelled autojob remain unchanged after successful retry',row_fingerprint(f$run_id)==config$source_rows_hash&&brohn_hash(brohn_run(store,f$run_id))==config$run_hash&&brohn_get_job(store,original$id)$status=='cancelled'&&brohn_get_job(store,original$id)$attempt==0L)
  # Separate original storage-level >16MiB journal. These are synthetic transport
  # rows deliberately seeded directly; they do not claim receiver acceptance.
  d<-brohn_new_design('Original large journal storage transport only','blank');d$instructions<-''
  d$questions<-list(brohn_question('Original optional unanswered transport fixture','number','end','transport-optional'))
  d$questions[[1L]]$required<-FALSE
  brohn_put_entity(store,'study',d$id,d);release<-brohn_publish(store,d$id,'sample')
  start<-.brohn_delivery_start(store,release$token,list(consented=TRUE,client_id='original-large-storage-client',operation_id='original-large-storage-start'))
  stopifnot(length(start$protocol$timeline)==1L);step<-start$protocol$timeline[[1L]]
  paragraph<-paste(rep('Original synthetic long answer. ',18000L),collapse='')
  event<-function(i,type,payload,scoped=FALSE)list(sequence=i,id=paste0('original-storage-transport-',i),type=type,
    step_id=if(scoped)step$id else NULL,stimulus_id=if(scoped)step$stimulus_id else NULL,condition_id=if(scoped)step$condition_id else NULL,question_id=if(scoped)step$question$id else NULL,
    phase=if(scoped)step$phase else 'storage_transport_fixture',clock=list(id='browser-monotonic',unit='ms',value=as.character(i*100L),instance_id='original-storage-clock',time_origin_ms='9007199254740993'),payload=payload)
  events<-c(list(event(1L,'step_started',list(resumed=FALSE),TRUE)),
    lapply(2:37,function(i)event(i,'visibility',list(hidden=FALSE,original_text=paragraph,assessment=i))),
    list(event(38L,'response',list(value=NULL,response_time_ms=NULL,scope='end'),TRUE),
      event(39L,'step_finished',list(elapsed_ms=3800L),TRUE),event(40L,'run_finished',list(outcome='completed'))))
  replay<-.brohn_delivery_replay(start$protocol,events)
  check('Direct storage fixture is separately labelled and has a valid optional omission and complete replay',replay$run_finished&&replay$ending_outcome=='completed'&&length(replay$completed)==1L&&is.null(replay$responses[[step$id]]$value)&&length(events)==40L)
  texts<-lapply(events,.brohn_store_json);stamp<-brohn_now()
  brohn_store_batch(store,function(){for(i in seq_along(texts))DBI::dbExecute(store$con,'INSERT INTO delivery_events VALUES (?,?,?,?,?,?)',params=list(start$run_id,i,paste0('original-storage-transport-',i),texts[[i]],rawhash(texts[[i]]),stamp))
    DBI::dbExecute(store$con,"UPDATE delivery_runs SET completion_status='completed',transfer_status='saved',acked_sequence=40,finalized_at=?,updated_at=? WHERE id=?",params=list(stamp,stamp,start$run_id))})
  before_large<-row_fingerprint(start$run_id);largejob<-brohn_enqueue_job(store,'analyse_run',list(run_id=start$run_id),'original-large-journal-storage-worker')
  largeclaim<-brohn_claim_job(store,'original-large-storage-worker',120L);stopifnot(largeclaim$id==largejob$id)
  large_scratch<-file.path(store$root,'scratch','independent-large-input');dir.create(large_scratch,recursive=TRUE)
  li<-brohn_prepare_run_evidence_input(store,largeclaim,large_scratch);lh<-brohn_read_run_evidence_input(li,large_scratch)
  brohn_write_json_file(li,file.path(folder,'independent-large-manifest.json'))
  visibility<-Filter(function(e)e$type=='visibility',lh$events[[start$run_id]])
  check('Explicit storage fixture exceeds16MiB journal with compact exact input',li$run_evidence$runs[[1L]]$journal$bytes>16*1024^2&&nchar(brohn_json(li),type='bytes')<16384&&length(lh$events[[start$run_id]])==40L&&length(visibility)==36L&&all(vapply(visibility,function(e)identical(e$payload$original_text,paragraph),logical(1))))
  brohn_process_job(store,largeclaim,timeout_seconds=300);large_done<-brohn_get_job(store,largejob$id)
  if(large_done$status!='succeeded')stop('Actual large input child failed: ',brohn_json(large_done$error))
  large_report<-brohn_get_entity(store,'report',large_done$result$report_id);published[[2L]]<-list(id=large_report$id,result_object=large_report$body$result_object,run_id=start$run_id,evidence='directly seeded storage transport fixture')
  check('Actual large-input worker publishes the explicit omission without inventing an answer',length(large_report$body$analysis$observations)==1L&&is.null(large_report$body$analysis$observations[[1L]]$value)&&large_report$body$analysis$observations[[1L]]$question_id==step$question$id&&large_report$body$session_quality[[1L]]$visibility_event_count==36L&&row_fingerprint(start$run_id)==before_large)
  expected<-brohn_hash(r$body);brohn_close_store(store);store<-brohn_open_store(file.path(folder,'workspace'))
  check('Reopen preserves compact report and complete200/400 history',brohn_hash(brohn_get_entity(store,'report',r$id)$body)==expected&&brohn_hash(brohn_complete_questionnaire_report(store,brohn_get_entity(store,'report',r$id)$body)$analysis)==config$original_analysis_hash&&row_fingerprint(f$run_id)==config$source_rows_hash)
  check('Original historical counterexample evidence is unchanged',digest::digest(file=historical,algo='sha256')==config$historical_sizes_hash)
  check('Exactly two workers succeeded while the recreated source autojob stayed cancelled',sum(vapply(brohn_list_jobs(store),function(j)j$status=='succeeded',logical(1)))==2L&&length(brohn_list_jobs(store))==3L&&!any(vapply(brohn_list_jobs(store),function(j)j$status %in% c('queued','running'),logical(1))))
  passed<-TRUE;cat('Questionnaire artifact worker:',checks,'checks passed; two actual scientific publications with separately stated source categories; evidence',folder,'\n')
})
