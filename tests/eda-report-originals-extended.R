# Genuine additional synthetic originals; no display/export preparation.
# Rscript this-file <checkout> <basic-originals> <fresh-external-evidence>
args<-commandArgs(TRUE);stopifnot(length(args)==3L)
repo<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE)
original<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
future_path<-function(x)file.path(normalizePath(dirname(x),winslash="/",mustWork=TRUE),basename(x))
inside<-function(x,parent){if(.Platform$OS.type=="windows"){x<-tolower(x);parent<-tolower(parent)};identical(x,parent)||startsWith(x,paste0(parent,"/"))}
out<-future_path(args[[3L]]);stopifnot(!file.exists(out),!inside(out,original),!inside(out,repo))
prior<-jsonlite::fromJSON(file.path(original,"results.json"),simplifyVector=FALSE)
stopifnot(isTRUE(prior$passed),identical(prior$schema,"brohn-eda-original-source-corpus/0.1"),
 (!file.exists(file.path(original,"workspace","catalog.sqlite-wal"))||file.info(file.path(original,"workspace","catalog.sqlite-wal"))$size==0))
stopifnot(dir.create(out),file.copy(file.path(original,"workspace"),out,recursive=TRUE,copy.mode=TRUE,copy.date=TRUE))
required<-c("study.json","event-original.csv","event-dataset.json","event-report.json","continuous-report.json","liking-report.json")
for(name in required)stopifnot(file.copy(file.path(original,name),file.path(out,name)),
 identical(digest::digest(file=file.path(original,name),algo="sha256"),digest::digest(file=file.path(out,name),algo="sha256")))
cfg<-list(checkout=repo,out=out,original=original,resume=FALSE)
jsonlite::write_json(cfg,file.path(out,"config.json"),auto_unbox=TRUE,pretty=TRUE)
setwd(cfg$checkout);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({
  out<-cfg$out;checks<-list();failure<-NULL;passed<-FALSE;reports<-list();datasets<-list()
  check<-function(label,value){if(!isTRUE(value))stop(label);checks[[length(checks)+1L]]<<-label;cat("PASS",label,"\n")}
  same<-function(a,b)identical(brohn_json(a),brohn_json(b))
  ref<-.brohn_rpk_ref
  store<-brohn_open_store(file.path(out,"workspace"))
  baseline_con<-DBI::dbConnect(RSQLite::SQLite(),dbname=file.path(cfg$original,"workspace","catalog.sqlite"),flags=RSQLite::SQLITE_RO)
  before_jobs<-DBI::dbGetQuery(baseline_con,"SELECT * FROM jobs ORDER BY rowid")
  before_versions<-DBI::dbGetQuery(baseline_con,"SELECT * FROM entity_versions ORDER BY rowid")
  before_objects<-DBI::dbGetQuery(baseline_con,"SELECT * FROM objects ORDER BY hash")
  DBI::dbDisconnect(baseline_con)
  study<-brohn_read_json_file(file.path(out,"study.json"))
  original_liking<-brohn_read_json_file(file.path(out,"liking-report.json"))
  on.exit({
    for(j in brohn_list_jobs(store,limit=100L))if(j$status %in% c("queued","running"))brohn_cancel_job(store,j$id)
    brohn_write_json_file(list(schema="brohn-eda-extended-original-corpus/0.1",passed=passed,checks=checks,failure=failure,
      scope="Genuine synthetic zero-artifact, condition-linked continuous, cvxEDA and reviewed-crosswalk multimodal source outputs from the configured scientific producers; not display/export/device/construct acceptance.",
      reports=lapply(reports,ref),datasets=lapply(datasets,ref),
      jobs=lapply(brohn_list_jobs(store,limit=100L),function(j)j[c("id","operation","status","attempt","error","result")])),file.path(out,"results.json"))
    brohn_close_store(store)
  },add=TRUE)
  tryCatch({
    runjob<-function(job){force(job);claim<-brohn_claim_job(store,"eda-original-extension",lease_seconds=120L)
      stopifnot(!is.null(claim),identical(claim$id,job$id));brohn_process_job(store,claim,timeout_seconds=600L)
      done<-brohn_get_job(store,job$id);if(done$status!="succeeded")stop("Original extension failed: ",brohn_json(done$error));done}
    preserve<-function(name,r){
      reports[[name]]<<-r;brohn_write_json_file(r,file.path(out,paste0(name,"-report.json")))
      dir.create(file.path(out,name));for(a in r$body$analysis$artifacts)stopifnot(file.copy(brohn_object_path(store,a$hash,TRUE),file.path(out,name,paste0(a$kind,".ndjson")),copy.mode=FALSE))
      envelope<-brohn_read_json_file(brohn_object_path(store,r$body$result_object$hash,TRUE),maximum=16*1024^2)
      check(paste(name,"retains exact published original envelope"),same(envelope$report,r$body[setdiff(names(r$body),"result_object")])&&isTRUE(r$body$processing$publication$native_seal))
      r
    }
    ingest<-function(name,path,mapping){
      retained_path<-file.path(out,paste0(name,"-report.json"))
      if(isTRUE(cfg$resume)&&file.exists(retained_path)){
        retained<-brohn_read_json_file(retained_path);r<-brohn_get_entity(store,"report",retained$id,retained$revision)
        check(paste(name,"reuses exact original after harness-only correction"),same(r,retained))
        reports[[name]]<<-r;datasets[[name]]<<-brohn_read_json_file(file.path(out,paste0(name,"-dataset.json")))
        return(r)
      }
      upload<-file.path(tempdir(),paste0("eda-extension-",name,".csv"));stopifnot(!file.exists(upload),file.copy(path,upload,copy.mode=FALSE))
      pending<-brohn_queue_ingestion(store,list(path=upload,name=basename(path),size=as.numeric(file.info(upload)$size),reference=paste0("extension-",name)),
        paste("Original synthetic",name),"eda","sample",study$id,operation_id=paste0("extension-",name))
      intake<-runjob(brohn_get_job(store,pending$body$job_id));d<-brohn_get_entity(store,"dataset",intake$result$dataset_id)
      d<-brohn_curate_dataset(store,d$id,mapping,d$revision,study$id,study$revision);datasets[[name]]<<-d
      brohn_write_json_file(d,file.path(out,paste0(name,"-dataset.json")))
      done<-runjob(brohn_queue_dataset(store,d$id,revision=d$revision))
      preserve(name,brohn_get_entity(store,"report",done$result$report_id))
    }
    mapping<-list(time_column="time",time_unit="s",sampling_rate=10,participant_column="participant",session_column="session",value_columns=list("conductance"),unit="uS",
      parameters=list(recipe="eda-neurokit-highpass/1.0"),origin_statement="Synthetic controlled source for software qualification, not a human or live device.")
    path<-file.path(out,"unavailable-original.csv")
    utils::write.csv(data.frame(time=(0:49)/10,participant="0001",session="short-visit",conductance=5),path,row.names=FALSE,fileEncoding="UTF-8")
    unavailable<-ingest("unavailable",path,mapping);a<-unavailable$body$analysis
    check("All-unavailable original has no manufactured processed artifacts",length(a$recordings)>0L&&all(vapply(a$recordings,function(x)identical(x$status,"unavailable"),logical(1)))&&length(a$artifacts)==0L&&all(vapply(a$features,function(x)is.null(x$value),logical(1))))
    t<-(0:600)/10;rows<-list()
    for(person in 1:2)for(condition in 1:2){
      pulse<-pmax(t-15,0);v<-4+person*.4+(condition-1)*person*.5+.0001*t+exp(-pulse/2)-exp(-pulse/.6)
      rows[[length(rows)+1L]]<-data.frame(time=t,participant=if(person==1)"0001"else"0002",session=if(person==1)"00001"else"00003",
        condition=if(condition==1)"condition-a"else"condition-b",conductance=v)
    }
    path<-file.path(out,"controlled-original.csv");utils::write.csv(do.call(rbind,rows),path,row.names=FALSE,fileEncoding="UTF-8")
    controlled_mapping<-mapping;controlled_mapping$condition_column<-"condition"
    controlled<-ingest("controlled",path,controlled_mapping);a<-controlled$body$analysis
    check("Control and test preserve four computed person-condition cells",length(a$recordings)==4L&&all(vapply(a$recordings,function(x)identical(x$status,"computed"),logical(1)))&&length(a$artifacts)==2L)
    crosswalk<-list()
    for(r in list(controlled,original_liking))for(person in 1:2)crosswalk[[length(crosswalk)+1L]]<-list(report_id=r$id,
      source_participant_id=if(person==1)"0001"else"0002",source_session_id=if(person==1)"00001"else"00003",participant_id=paste0("reviewed-person-",person),session_id="reviewed-visit-1")
    contrasts<-list(
      list(id="tonic-control-test",report_ids=list(controlled$id),modality="eda",metric="tonic_mean",outcome_id="conductance",unit="uS",control_id="condition-a",test_id="condition-b"),
      list(id="liking-control-test",report_ids=list(original_liking$id),modality="questionnaire",metric="explicit_rating",outcome_id="q-liking",unit="rating points",control_id="condition-a",test_id="condition-b"))
    if(isTRUE(cfg$resume)&&file.exists(file.path(out,"paired-report.json"))){
      retained<-brohn_read_json_file(file.path(out,"paired-report.json"));paired<-brohn_get_entity(store,"report",retained$id,retained$revision)
      check("paired reuses exact original after harness-only correction",same(paired,retained));reports$paired<-paired
    }else{
      queued<-brohn_queue_multimodal(store,study$id,list(controlled$id,original_liking$id),crosswalk,contrasts,"sample",
        identity_source="Reviewed synthetic fixture allocation: source person0001/visit00001 maps to reviewed person1, and person0002/visit00003 maps to reviewed person2 in each specified exact report. This statement is fixture provenance, not participant consent or inferred identity.")
      done<-runjob(queued);paired<-preserve("paired",brohn_get_entity(store,"report",done$result$report_id))
    };pa<-paired$body$analysis
    check("Actual multimodal producer retains exact EDA and liking parents",length(paired$body$provenance$selection)==2L&&same(paired$body$provenance$crosswalk,crosswalk)&&paired$body$provenance$crosswalk_hash==brohn_hash(crosswalk))
    tonic<-Filter(function(x)identical(x$id,"tonic-control-test"),pa$contrasts)[[1L]]
    liking<-Filter(function(x)identical(x$id,"liking-control-test"),pa$contrasts)[[1L]]
    check("Saved EDA pairing uses two declared people and control-test direction",tonic$participant_count==2L&&is.finite(tonic$estimate)&&abs(tonic$estimate-.75)<1e-6)
    check("Saved liking keeps its separate one-person denominator",liking$participant_count==1L&&liking$estimate==4&&is.null(liking$interval95))
    eda_rows<-Filter(function(x)identical(x$modality,"eda"),pa$observations)
    check("Multimodal EDA features retain exact original row provenance",length(eda_rows)>0L&&all(vapply(eda_rows,function(x){
      row<-controlled$body$analysis[[x$source_container]][[x$source_row]]
      identical(x$source_report_id,controlled$id)&&x$source_report_revision==controlled$revision&&x$source_report_hash==brohn_hash(controlled$body)&&x$source_row_hash==brohn_hash(row)
    },logical(1))))
    original_mapping<-brohn_read_json_file(file.path(out,"event-dataset.json"))$body$metadata
    original_mapping$parameters$recipe<-"eda-event-cvxeda-defaults/1.0"
    original_mapping$origin_statement<-"Original synthetic event source, separately processed using registered cvxEDA defaults for software output preservation qualification."
    cvx<-ingest("cvxeda",file.path(out,"event-original.csv"),original_mapping)
    check("cvxEDA original records its registered method and complete artifacts",cvx$body$analysis$operation=="eda_events"&&length(cvx$body$analysis$artifacts)==2L&&
      all(vapply(cvx$body$analysis$parameters,function(p)identical(p$recipe,"eda-event-cvxeda-defaults/1.0"),logical(1))))
    after_jobs<-DBI::dbGetQuery(store$con,"SELECT * FROM jobs ORDER BY rowid")
    after_versions<-DBI::dbGetQuery(store$con,"SELECT * FROM entity_versions ORDER BY rowid")
    check("Original six jobs and existing entity versions remain unchanged",identical(before_jobs,after_jobs[match(before_jobs$id,after_jobs$id),,drop=FALSE])&&identical(before_versions,head(after_versions,nrow(before_versions))))
    check("Every original stored object remains byte exact",all(vapply(before_objects$hash,function(h)identical(digest::digest(file=brohn_object_path(store,h,FALSE),algo="sha256"),h),logical(1))))
    check("Seven genuine extension jobs settle with no display or export job",nrow(after_jobs)==nrow(before_jobs)+7L&&all(after_jobs$status=="succeeded")&&all(after_jobs$operation %in% c("ingest_source","analyse_dataset","analyse_multimodal")))
    brohn_write_json_file(list(tonic=tonic,liking=liking,crosswalk=crosswalk,zero_artifact_report=ref(unavailable),cvxeda_report=ref(cvx)),file.path(out,"expected-witnesses.json"))
    passed<-TRUE
  },error=function(e){failure<<-conditionMessage(e);stop(e)})
  cat(length(checks),"extended original checks passed\n")
})
