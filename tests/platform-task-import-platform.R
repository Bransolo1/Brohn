# Actual original-source -> registry -> curation -> supervised R -> immutable
# report pipeline. All data are synthetic, in an isolated retained QA workspace.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
local({
  checks<-0L;passed<-FALSE
  check<-function(label,value){if(!isTRUE(value))stop("Task import platform QA: ",label,call.=FALSE);checks<<-checks+1L}
  rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
  near<-function(a,b)isTRUE(all.equal(a,b,tolerance=1e-12,check.attributes=FALSE))
  configured_parent<-Sys.getenv("BROHN_QA_EVIDENCE_PARENT","")
  if(!nzchar(configured_parent)||!dir.exists(configured_parent))stop("Run through scripts/run-checks.R with an external output directory, or explicitly supply BROHN_QA_EVIDENCE_PARENT.",call.=FALSE)
  parent<-normalizePath(configured_parent,winslash="/",mustWork=TRUE)
  root<-file.path(parent,paste0("brohn-task-import-platform-",format(Sys.time(),"%Y%m%d-%H%M%S"),"-",substr(brohn_id("evidence"),10,17)))
  stopifnot(!file.exists(root));dir.create(root)
  root<-normalizePath(root,winslash="/",mustWork=TRUE)
  stopifnot(startsWith(tolower(root),paste0(tolower(parent),"/")))
  store<-brohn_open_store(file.path(root,"workspace"));brohn_initialise_library(store)
  jobs<-list();reports<-list()
  on.exit({
    pending<-Filter(function(j)j$status %in% c("queued","running"),brohn_list_jobs(store))
    for(j in pending)brohn_cancel_job(store,j$id)
    brohn_write_json_file(list(schema="brohn-task-import-platform-evidence/1.0",passed=passed,checks=checks,
      root=root,jobs=lapply(brohn_list_jobs(store),function(j)list(id=j$id,status=j$status,attempt=j$attempt,error=j$error,result=j$result)),
      reports=lapply(reports,function(r)list(id=r$id,hash=brohn_hash(r$body),result_object=r$body$result_object)),
      qualification="Original synthetic imports and actual isolated supervised worker/publication. No physical device, population, hosted deployment or construct qualification."),file.path(root,"evidence.json"))
    brohn_close_store(store)
  },add=TRUE)
  fixture_root<-"tests/fixtures/task-import"
  manifest<-brohn_read_json_file(file.path(fixture_root,"manifest.json"))
  create_source<-function(name,title=NULL,path=NULL,origin="sample") {
    f<-manifest$fixtures[[name]]
    registry<-brohn_read_json_file(file.path(fixture_root,f$registry))
    d<-brohn_new_design(paste("Original saved",name,"study"),"blank",id=brohn_id("study"));d$blocks<-list(registry$task)
    study<-brohn_put_entity(store,"study",d$id,d)
    dataset<-brohn_ingest_dataset(store,brohn_default(path,file.path(fixture_root,f$csv)),brohn_default(title,paste("Original",name,"trial source")),modality="implicit",origin=origin)
    list(f=f,registry=registry,study=study,dataset=dataset,metadata=f$metadata,registry_path=file.path(fixture_root,f$registry))
  }
  stage<-function(x,dataset_revision=x$dataset$revision,study=x$study,task_id=x$f$metadata$task_id,path=x$registry_path)
    brohn_stage_task_registry(store,path,basename(path),x$dataset$id,dataset_revision,study$id,study$revision,task_id)
  accept<-function(x,metadata=x$metadata)brohn_curate_dataset(store,x$dataset$id,metadata,x$dataset$revision,x$study$id,x$study$revision)
  run_job<-function(job,succeeds=TRUE) {
    force(job)
    claim<-brohn_claim_job(store,"task-import-platform-qa",lease_seconds=90L)
    stopifnot(!is.null(claim),identical(claim$id,job$id))
    brohn_process_job(store,claim,timeout_seconds=90)
    done<-brohn_get_job(store,job$id);jobs[[length(jobs)+1L]]<<-done
    if(succeeds&&done$status!="succeeded")stop("Actual task worker failed: ",brohn_json(done$error),call.=FALSE)
    done
  }
  current_hash<-function(id)brohn_hash(brohn_get_entity(store,"dataset",id))
  objects<-function()DBI::dbGetQuery(store$con,"SELECT count(*) AS n FROM objects")$n[[1L]]
  x<-create_source("iat");original_dataset_hash<-current_hash(x$dataset$id)
  check("actual frozen IAT CSV retains exact byte identity and needs mapping",x$dataset$body$status=="needs_mapping"&&x$dataset$body$source$hash=="a7d6fdfb544a6008fa0eb04dfd1df9cdac21f70bc4c2f266dc9c08a852de0af3"&&file.info(brohn_object_path(store,x$dataset$body$source$hash))$size==23720)
  check("unconfirmed original cannot be queued",rejects(brohn_queue_dataset(store,x$dataset$id)))
  reference<-stage(x);x$metadata$protocol_registry<-reference
  check("registry stage retains original exact bytes and canonical task identity",reference$hash==x$f$registry_sha256&&reference$canonical_hash==brohn_hash(x$registry)&&reference$task_definition_hash==brohn_hash(x$registry$task)&&digest::digest(file=brohn_object_path(store,reference$hash),algo="sha256")==reference$hash)
  check("stage alone does not change dataset mapping or status",identical(current_hash(x$dataset$id),original_dataset_hash))
  check("exact study revision is required before mapping acceptance",rejects(brohn_curate_dataset(store,x$dataset$id,x$metadata,x$dataset$revision,x$study$id))&&identical(current_hash(x$dataset$id),original_dataset_hash))
  foreign<-create_source("choice")
  check("different original study task cannot attach this registry",rejects(stage(x,study=foreign$study))&&identical(current_hash(x$dataset$id),original_dataset_hash))
  check("unknown task cannot attach compatible-looking file",rejects(stage(x,task_id="not-in-study")))
  brohn_put_entity(store,"project","foreign-import-project",list(id="foreign-import-project",title="Original foreign project",archived=FALSE),project_id="foreign-import-project")
  d<-x$study$body;d$id<-brohn_id("study");d$project_id<-"foreign-import-project"
  foreign_project<-brohn_put_entity(store,"study",d$id,d,project_id=d$project_id)
  check("registry stage is project scoped even with identical task definition",rejects(stage(x,study=foreign_project)))

  before_objects<-objects()
  malformed<-file.path(root,"original-invalid.json");writeBin(charToRaw("{original invalid JSON"),malformed)
  invalid_utf8<-file.path(root,"original-invalid-utf8.json");writeBin(as.raw(c(123,255,125)),invalid_utf8)
  nul<-file.path(root,"original-nul.json");writeBin(as.raw(c(123,0,125)),nul)
  check("invalid JSON bytes fail before object registration",rejects(stage(x,path=malformed))&&objects()==before_objects&&identical(current_hash(x$dataset$id),original_dataset_hash))
  check("invalid UTF8 bytes fail without a mapping write",rejects(stage(x,path=invalid_utf8))&&objects()==before_objects&&identical(current_hash(x$dataset$id),original_dataset_hash))
  check("embedded NUL bytes fail without a mapping write",rejects(stage(x,path=nul))&&objects()==before_objects)
  changed_registry<-x$registry;changed_registry$protocols[[1L]]$compiled$timeline[[2L]]$correct_code<-"KeyX"
  changed_registry$protocols[[1L]]$compiled_hash<-brohn_hash(changed_registry$protocols[[1L]]$compiled)
  changed_path<-file.path(root,"original-rehashed-incompatible-registry.json");brohn_write_json_file(changed_registry,changed_path)
  check("rehashed incompatible trial table is rejected before retention",rejects(stage(x,path=changed_path))&&objects()==before_objects&&identical(current_hash(x$dataset$id),original_dataset_hash))
  bad<-x$metadata;bad$protocol_registry$hash<-strrep("f",64)
  check("unavailable registry object cannot create accepted mapping",rejects(accept(x,bad))&&identical(current_hash(x$dataset$id),original_dataset_hash))
  bad<-x$metadata;bad$protocol_registry$canonical_hash<-strrep("a",64)
  check("tampered canonical registry reference cannot create accepted mapping",rejects(accept(x,bad))&&identical(current_hash(x$dataset$id),original_dataset_hash))
  bad<-x$metadata;bad$protocol_registry$bytes<-bad$protocol_registry$bytes+1
  check("tampered original byte count cannot create accepted mapping",rejects(accept(x,bad))&&identical(current_hash(x$dataset$id),original_dataset_hash))
  bad<-x$metadata;bad$protocol_registry$task_definition_hash<-strrep("b",64)
  check("different task reference rejects atomically",rejects(accept(x,bad))&&identical(current_hash(x$dataset$id),original_dataset_hash)&&length(brohn_entity_history(store,"dataset",x$dataset$id))==1L)
  synthetic<-brohn_ingest_dataset(store,file.path(fixture_root,x$f$csv),"Original synthetic origin conflict",modality="implicit",origin="imported")
  check("synthetic materials cannot become imported research by curation",rejects(brohn_curate_dataset(store,synthetic$id,x$metadata,synthetic$revision,x$study$id,x$study$revision))&&brohn_get_entity(store,"dataset",synthetic$id)$body$status=="needs_mapping")

  accepted<-accept(x);accepted_hash<-brohn_hash(accepted$body)
  check("accepted source pins study mapping and registry with no filepath",accepted$revision==2L&&accepted$body$study_revision==x$study$revision&&accepted$body$metadata$protocol_registry$hash==reference$hash&&!"path"%in%names(accepted$body$metadata$protocol_registry))
  check("stale dataset stage and curation reject without changing mapping",rejects(stage(x))&&rejects(accept(x))&&brohn_hash(brohn_get_entity(store,"dataset",accepted$id)$body)==accepted_hash)
  queued<-brohn_queue_dataset(store,accepted$id)
  check("exact mapped requests deduplicate",brohn_queue_dataset(store,accepted$id)$id==queued$id)
  input<-brohn_job_input(store,queued)
  check("worker input holds exact verified source and registry paths",digest::digest(file=input$source_path,algo="sha256")==x$f$csv_sha256&&digest::digest(file=input$registry_path,algo="sha256")==reference$hash&&input$dataset_revision==accepted$revision)
  # Mutable heads change after queuing; the actual child must use pinned history.
  later_design<-x$study$body;later_design$blocks[[1L]]$materials[[1L]]$content<-"Later original draft material"
  later_study<-brohn_save_study(store,later_design,x$study$revision)
  later_metadata<-x$metadata;later_metadata$origin_statement<-"Later source note; the earlier exact mapping remains available."
  later_dataset<-brohn_curate_dataset(store,accepted$id,later_metadata,accepted$revision,x$study$id,x$study$revision)
  done<-run_job(queued)
  report<-brohn_get_entity(store,"report",done$result$report_id);reports[[length(reports)+1L]]<-report
  a<-report$body$analysis;score<-a$task_scores[[1L]];attempt<-a$task_attempts[[1L]]
  check("actual supervised child publishes named IAT result",done$status=="succeeded"&&a$kind=="implicit"&&score$profile=="iat-gnb2003-d1/1.0"&&report$body$origin=="sample")
  check("saved full IAT equals independent hand arithmetic",near(score$metrics[[1L]]$value,(400/sqrt(2000000/39)+400/sqrt(4000000/79))/2)&&score$scoring_audit$fast_denominator==120&&score$scoring_audit$slow_count==0)
  check("saved analysis retains every raw row and full expected trial audit",a$quality$source_row_count==180&&length(a$source_rows)==180&&length(attempt$trial_audit)==180&&a$source_rows_hash==brohn_hash(a$source_rows))
  check("queued child uses original study and mapping despite changed heads",report$body$provenance$dataset_revision==accepted$revision&&report$body$provenance$dataset_hash==accepted_hash&&report$body$provenance$study_revision==x$study$revision&&report$body$provenance$design_hash==brohn_hash(x$study$body)&&brohn_get_entity(store,"dataset",accepted$id)$revision==later_dataset$revision&&brohn_study(store,x$study$id)$revision==later_study$revision)
  check("saved attempt provenance binds original bytes registry and source revision",attempt$source$original_hash==x$f$csv_sha256&&attempt$source$registry_object_hash==reference$hash&&attempt$source$registry_canonical_hash==reference$canonical_hash&&attempt$source$revision==accepted$revision)
  check("saved result does not upgrade declared summaries to journal or population qualification",attempt$evidence_level=="declared_trial_summary"&&!attempt$timing_quality$journal_replayed&&!a$quality$scientifically_qualified&&a$quality$participant_count==1)
  identities<-report$body$processing$code_hashes
  check("actual source closure pins importer registry reader scorer and bootstrap",all(c("R/platform-task-import.R","R/platform-task-import-storage.R","R/platform-methods.R","scripts/analysis-worker.R")%in%names(identities))&&all(vapply(names(identities),function(path)identical(identities[[path]],digest::digest(file=path,algo="sha256")),logical(1))))
  check("publication returns a verified immutable result object",report$body$result_object$hash==done$result$output_hash&&digest::digest(file=brohn_object_path(store,done$result$output_hash),algo="sha256")==done$result$output_hash)
  envelope<-brohn_read_json_file(brohn_object_path(store,done$result$output_hash))
  check("catalog and retained result object preserve exact binary64 analysis",identical(brohn_hash(envelope$report$analysis),brohn_hash(a))&&isTRUE(all.equal(envelope$report$analysis,a,tolerance=0)))
  original_copy<-file.path(root,"downloaded-original-iat.csv");brohn_copy_object_download(store,x$f$csv_sha256,original_copy)
  registry_copy<-file.path(root,"downloaded-original-registry.json");brohn_copy_object_download(store,reference$hash,registry_copy)
  check("original and registry downloads preserve hashes and writable transfers",digest::digest(file=original_copy,algo="sha256")==x$f$csv_sha256&&digest::digest(file=registry_copy,algo="sha256")==reference$hash&&file.access(original_copy,2)==0&&file.access(registry_copy,2)==0)
  score_path<-file.path(root,"downloaded-iat-scores.csv");brohn_export_task_scores_csv(report$body,score_path)
  exported<-brohn_read_table(score_path,"csv",20000L)
  check("dedicated score CSV retains profile value and scoring audit",nrow(exported)==1&&exported$metric[[1L]]=="IAT_D1"&&near(as.numeric(exported$value[[1L]]),score$metrics[[1L]]$value)&&grepl("fast_denominator",exported$scoring_audit[[1L]],fixed=TRUE))
  json_path<-file.path(root,"downloaded-iat-report.json");brohn_write_json_file(report$body,json_path)
  html_path<-file.path(root,"downloaded-iat-report.html");brohn_export_report_html(report$body,html_path,store)
  check("full JSON export and offline HTML are usable",brohn_hash(brohn_read_json_file(json_path))==brohn_hash(report$body)&&grepl("IAT D1",paste(readLines(html_path,warn=FALSE),collapse="\n"),fixed=TRUE))
  roundtrip<-brohn_import_task_trials(brohn_read_table(original_copy,"csv",20000L),x$metadata,x$study$body,
    list(id=accepted$id,revision=accepted$revision,hash=x$f$csv_sha256,origin="sample",registry_object_hash=reference$hash),brohn_read_json_file(registry_copy))
  check("downloaded original and registry reproduce full saved analysis",brohn_hash(roundtrip)==brohn_hash(a))
  report_hash<-brohn_hash(report$body)

  rt_fixture<-manifest$fixtures$choice;rt<-brohn_read_table(file.path(fixture_root,rt_fixture$csv),"csv",20000L)
  rt$first_response_ms[[9L]]<-rt$final_correct_ms[[9L]]<-"500"
  rt$outcome[10:48]<-"timeout";rt$first_correct[10:48]<-"false"
  for(field in c("first_code","final_code","first_response_ms","final_correct_ms"))rt[[field]][10:48]<-""
  rt_path<-file.path(root,"original-choice-one-correct-39-timeouts.csv")
  utils::write.table(rt,rt_path,sep=",",row.names=FALSE,quote=TRUE,qmethod="double",fileEncoding="UTF-8")
  y<-create_source("choice",path=rt_path);y$metadata$protocol_registry<-stage(y)
  y_saved<-accept(y);rt_done<-run_job(brohn_queue_dataset(store,y_saved$id))
  rt_report<-brohn_get_entity(store,"report",rt_done$result$report_id);reports[[length(reports)+1L]]<-rt_report
  metric<-function(name)Filter(function(m)m$name==name,rt_report$body$analysis$task_scores[[1L]]$metrics)[[1L]]
  check("actual saved RT report retains partial support and independent39over40",rt_report$body$analysis$task_scores[[1L]]$status=="partial"&&metric("test_omission_rate")$value==39/40&&metric("correct_test_rt_mean")$value==500&&is.null(metric("correct_test_rt_sd")$value))
  check("actual saved partial rates retain their own denominators",metric("test_omission_rate")$support$denominator==40&&metric("test_first_response_error_rate")$support$denominator==1&&metric("test_first_response_error_rate")$value==0)
  rt_csv<-file.path(root,"downloaded-partial-rt-scores.csv");brohn_export_task_scores_csv(rt_report$body,rt_csv)
  rt_export<-brohn_read_table(rt_csv,"csv",20000L)
  check("partial score CSV keeps five metrics with absent SD and support reason",nrow(rt_export)==5&&rt_export$value[rt_export$metric=="correct_test_rt_sd"]==""&&grepl("two retained",rt_export$metric_reason[rt_export$metric=="correct_test_rt_sd"],fixed=TRUE))
  unknown<-y$metadata;unknown$source_rt_definition<-"unknown"
  unknown_saved<-brohn_curate_dataset(store,y_saved$id,unknown,y_saved$revision,y$study$id,y$study$revision)
  unknown_done<-run_job(brohn_queue_dataset(store,unknown_saved$id))
  unknown_report<-brohn_get_entity(store,"report",unknown_done$result$report_id);reports[[length(reports)+1L]]<-unknown_report
  check("unknown-definition job preserves a saved unavailable report instead of inventing scores",unknown_done$status=="succeeded"&&!unknown_report$body$analysis$quality$usable&&length(unknown_report$body$analysis$task_scores[[1L]]$metrics)==0&&unknown_report$body$analysis$quality$source_row_count==48&&unknown_report$body$analysis$task_attempts[[1L]]$completion_status=="completed")
  unknown_csv<-file.path(root,"downloaded-unknown-definition.csv");brohn_export_task_scores_csv(unknown_report$body,unknown_csv)
  unknown_export<-brohn_read_table(unknown_csv,"csv",20000L)
  check("unavailable score export retains reason instead of numeric zero",nrow(unknown_export)==1&&unknown_export$value[[1L]]==""&&grepl("explicitly unknown",unknown_export$task_reason[[1L]],fixed=TRUE))

  before_reports<-length(brohn_list_entities(store,"report"))
  tampered<-queued$request;tampered$study_hash<-strrep("f",64)
  rejected<-run_job(brohn_enqueue_job(store,"analyse_dataset",tampered,"original-task-design-hash-conflict"),FALSE)
  check("tampered queued study hash fails without report publication",rejected$status=="failed"&&length(brohn_list_entities(store,"report"))==before_reports)
  tampered<-queued$request;tampered$dataset_hash<-strrep("f",64)
  rejected<-run_job(brohn_enqueue_job(store,"analyse_dataset",tampered,"original-task-dataset-hash-conflict"),FALSE)
  check("tampered queued dataset hash fails without report publication",rejected$status=="failed"&&length(brohn_list_entities(store,"report"))==before_reports)
  scratch<-file.path(root,"direct-input-check");dir.create(scratch)
  wrong_input<-input;wrong_input$registry_path<-changed_path
  check("a different registry path cannot bypass worker byte integrity",rejects(brohn_analyse_input(wrong_input,scratch))&&length(brohn_list_entities(store,"report"))==before_reports)
  wrong_input<-input;wrong_input$source_path<-rt_path
  check("a different trial source path fails the worker integrity check",rejects(brohn_analyse_input(wrong_input,scratch)))
  check("all failed attempts preserve original report and source objects",brohn_hash(brohn_get_entity(store,"report",report$id)$body)==report_hash&&length(brohn_entity_history(store,"report",report$id))==1L&&digest::digest(file=brohn_object_path(store,x$f$csv_sha256),algo="sha256")==x$f$csv_sha256&&digest::digest(file=brohn_object_path(store,reference$hash),algo="sha256")==reference$hash)
  brohn_close_store(store);store<-brohn_open_store(file.path(root,"workspace"))
  check("workspace reopen returns exact original report and full source evidence",brohn_hash(brohn_get_entity(store,"report",report$id)$body)==report_hash&&brohn_read_json_file(brohn_object_path(store,done$result$output_hash))$report$analysis$source_rows_hash==a$source_rows_hash)
  check("isolated workspace has no pending or running jobs",!any(vapply(brohn_list_jobs(store),function(j)j$status%in%c("queued","running"),logical(1))))
  passed<-TRUE
  cat(sprintf("Task import platform: %d checks passed; %d actual supervised processing attempts; evidence %s\n",checks,length(jobs),root))
})
