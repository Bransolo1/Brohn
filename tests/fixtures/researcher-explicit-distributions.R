# Independently specified synthetic full-source questionnaire/scale QA.
args<-commandArgs(trailingOnly=TRUE);mode<-args[[1L]]
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
folder<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-explicit-distributions-"))
config_path<-file.path(folder,"fixture.json")
if(mode=="serve"){
  config<-brohn_read_json_file(config_path);Sys.setenv(BROHN_WORKSPACE=config$workspace,BROHN_APP_MODE="platform")
  stop_owned<-function()if(file.exists(file.path(folder,"stop.request")))shiny::stopApp()else later::later(stop_owned,.2)
  later::later(stop_owned,.2);shiny::runApp(".",host="127.0.0.1",port=config$port,launch.browser=FALSE)
}else local({
  config<-if(file.exists(config_path))brohn_read_json_file(config_path)else NULL
  stopifnot(mode!="setup"||is.null(config))
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE)
  if(mode=="setup"){
    brohn_initialise_library(store)
    design<-brohn_new_design("Explicit distributions synthetic study","survey","study-explicit-original")
    questions<-lapply(1:2,function(i){q<-brohn_question(paste("Original numeric",i),"number","after_each",paste0("q-number-",i));q$min<-0;q$max<-10;q$step<-1;q$required<-FALSE;q})
    catq<-brohn_question("Original typed categories","single_choice","after_each","q-category");catq$required<-FALSE
    values<-c(list(FALSE,0,"0","=1+1","\u96ea"),as.list(paste0("Choice ",6:30)))
    catq$options<-lapply(seq_along(values),function(i)list(id=paste0("opt-",i),label=if(i==4)"=1+1"else if(i==5)"\u96ea"else paste("Choice",i),value=values[[i]]))
    design$questions<-c(questions,list(catq))
    design$conditions<-lapply(c("A","B"),function(c)list(id=c,label=c,role=if(c=="A")"control"else"test"))
    design$stimuli<-lapply(c("A","B"),function(c)list(id=paste0("stimulus-",c),title=paste("Concept",c),condition_id=c,type="text",content=paste("Original synthetic concept",c),asset=NULL,duration_ms=5000,aois=list()))
    design$scales<-list(list(schema="brohn-questionnaire-scale/1.0",id="scale-original",label="Original two-item keyed scale",version="1.0",
      source="Original synthetic arithmetic fixture; no psychometric validity claim",scope="after_each",
      items=lapply(1:2,function(i)list(question_id=paste0("q-number-",i),reverse=i==2,min=0,max=10)),
      scoring=list(aggregation="sum",missing="complete",minimum_answered=2,prorate=FALSE),conversion=NULL))
    brohn_validate_scales(design$scales,design);brohn_put_entity(store,"study",design$id,design)
    rows<-list()
    for(i in 1:60){
      value<-(i-1)%%11
      for(k in 1:3){
        state<-if(k==1&&i==5)"optional_omission"else if(k==1&&i==17)"not_displayed"else"answered"
        rows[[length(rows)+1L]]<-list(question_id=design$questions[[k]]$id,prompt=design$questions[[k]]$prompt,
          participant_id=paste0("P",ceiling(i/3)),participant_linkage=i!=60,session_id=paste0("session-",i),assessment_id=paste0("assessment-",i),
          condition_id=if(i<=30)"A"else"B",stimulus_id=if(i<=30)"stimulus-A"else"stimulus-B",assessment_exposure_id=paste0("exposure-",i),origin="sample",status=state,missing_reason=if(state=="answered")NULL else state,
          value=if(state!="answered")NULL else if(k==1)value else if(k==2)10-value else values[[(i-1)%%30+1]])
      }
    }
    scores<-brohn_score_scales(rows,design,source=list(fixture="Independent arithmetic: each complete keyed sum is twice its first item"))
    body<-list(schema_version="brohn-report/1.0.0",id="report-explicit-original",title="Complete explicit distributions - original synthetic fixture",
      study_id=design$id,dataset_id=NULL,origin="sample",status="Available",created_at=brohn_now(),
      provenance=list(design=design,design_hash=brohn_hash(design),fixture="Synthetic complete-source distributions; not observed people or validated psychometrics"),
      analysis=list(kind="questionnaire",title="Complete saved synthetic questionnaire",observations=rows,features=list(),scales=scores,
        quality=list(usable=TRUE,response_count=180),limitations=list("Synthetic arithmetic and application evidence only.")))
    staging<-file.path(folder,"source-staging");dir.create(staging)
    packed<-brohn_pack_questionnaire_report(body,staging,threshold=1024)
    a<-packed$analysis$artifacts[[1]];object<-brohn_store_object(store,path=a$path,media_type="application/x-ndjson")
    packed$analysis$artifacts<-list(c(a[setdiff(names(a),c("path","sha256","bytes"))],object))
    report<-brohn_put_entity(store,"report",packed$id,packed)
    stopifnot(length(packed$analysis$scales$observations)<60)
    config<-list(schema="brohn-explicit-distributions-qa/1.0",workspace=store$root,port=3883,
      original=list(study_id=design$id,study_title=design$title,report_id=report$id,report_hash=brohn_hash(report$body),
        analysis_hash=brohn_hash(body$analysis),answers=180,scale_assessments=60,groups=8,inline_scale_rows=length(packed$analysis$scales$observations)))
    brohn_write_json_file(body,file.path(folder,"independent-source.json"));brohn_write_json_file(config,config_path)
  }else if(mode=="inspect"){
    brohn_write_json_file(list(jobs=brohn_list_jobs(store,limit=1000),distributions=brohn_list_entities(store,"explicit_distributions"),
      source_hash=brohn_hash(brohn_get_entity(store,"report",config$original$report_id)$body),
      resources=brohn_rows(DBI::dbGetQuery(store$con,"SELECT * FROM audit_log WHERE action='explicit_distributions.resources'"))),file.path(folder,"snapshot.json"))
  }else if(mode=="worker"){
    checks<-0L;check<-function(label,ok){if(!isTRUE(ok))stop(label);checks<<-checks+1L;cat("PASS",label,"\n");flush.console()}
    report<-brohn_get_entity(store,"report",config$original$report_id)
    initial_count<-length(brohn_list_entities(store,"explicit_distributions"))
    queued<-brohn_queue_explicit_distributions(store,report$id,config$original$report_hash)
    claimed<-brohn_claim_job(store,"qa-explicit-original",60);stopifnot(identical(claimed$id,queued$id))
    brohn_process_job(store,claimed);job<-brohn_get_job(store,queued$id)
    if(job$status!="succeeded")stop(brohn_json(job$error))
    check("Actual supervised worker publishes complete source-bound distributions",job$status=="succeeded")
    saved<-brohn_explicit_distribution_record(store,job$result$explicit_distributions_id);result<-saved$body$result
    check("Both complete source collections exceed previews",result$source_counts$question_records==180&&result$source_counts$scale_records==60&&length(result$groups)==8)
    for(condition in c("A","B")){
      start<-if(condition=="A")1 else 31;end<-start+29
      expected<-((start:end)-1)%%11;keep<-if(condition=="A")!(start:end %in% c(5,17))else rep(TRUE,30)
      select<-function(id)Filter(function(g)g$item_id==id&&g$condition_id==condition,result$groups)[[1]]
      numeric<-select("q-number-1");scale<-select("scale-original");category<-select("q-category")
      check(paste(condition,"numeric counts and mean match independent arithmetic"),numeric$source_records==30&&numeric$usable_records==sum(keep)&&abs(numeric$summary$mean-sum(expected[keep])/sum(keep))<1e-12)
      check(paste(condition,"saved reversed-key scale scores and denominator match independent arithmetic"),scale$source_records==30&&scale$assessment_count==30&&scale$usable_records==sum(keep)&&abs(scale$summary$mean-2*sum(expected[keep])/sum(keep))<1e-12)
      check(paste(condition,"30 typed categories retain all source values"),length(category$categories)==30&&sum(vapply(category$categories,`[[`,numeric(1),"count"))==30)
      check(paste(condition,"person linkage remains distinct from assessments"),if(condition=="A")scale$participant_count==10 else is.null(scale$participant_count))
    }
    check("Reopening same source reuses exact completed job",identical(brohn_queue_explicit_distributions(store,report$id,config$original$report_hash)$id,job$id))
    retry<-brohn_queue_explicit_distributions(store,report$id,config$original$report_hash,retry=TRUE);brohn_cancel_job(store,retry$id)
    check("Cancelled preparation publishes nothing",brohn_get_job(store,retry$id)$status=="cancelled"&&length(brohn_list_entities(store,"explicit_distributions"))==initial_count+1)
    late<-brohn_queue_explicit_distributions(store,report$id,config$original$report_hash,retry=TRUE);claimed<-brohn_claim_job(store,"qa-explicit-timeout",60)
    brohn_process_job(store,claimed,timeout_seconds=.001)
    check("Actual timed-out child publishes no partial result",brohn_get_job(store,late$id)$status=="failed"&&length(brohn_list_entities(store,"explicit_distributions"))==initial_count+1)
    check("Original full report and scale scores remain unchanged",identical(brohn_hash(brohn_get_entity(store,"report",report$id)$body),config$original$report_hash))
    brohn_write_json_file(list(passed=TRUE,checks=checks,result=saved$body,jobs=brohn_list_jobs(store)),file.path(folder,"worker-evidence.json"))
  }else stop("Unknown fixture mode")
})
