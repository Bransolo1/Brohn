# Original symmetric choices: all six ordered pairs once imply zero utilities,
# balanced best/worst counts and negative log-likelihood 6*log(6).
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
local({
  checks<-0L;check<-function(name,ok) {if(!isTRUE(ok))stop("MaxDiff platform: ",name);checks<<-checks+1L}
  rejected<-function(value)inherits(try(force(value),silent=TRUE),"try-error")
  near<-function(x,y)isTRUE(all.equal(x,y,tolerance=1e-9))
  root<-.brohn_port_temp();store<-brohn_open_store(file.path(root,"workspace"));brohn_initialise_library(store)
  on.exit({brohn_close_store(store);.brohn_port_cleanup(root)},add=TRUE)
  record<-brohn_create_study(store,"Original paired choice integration","blank");d<-record$body;d$instructions<-""
  exercise<-brohn_maxdiff_new();exercise$title<-"Original three-feature choices";exercise$items<-exercise$items[1:3]
  exercise$sets<-list(list(id="one-set",item_ids=as.list(brohn_ids(exercise$items))))
  exercise$settings$set_order<-exercise$settings$item_order<-"fixed"
  optional<-brohn_maxdiff_clone(exercise);optional$title<-"Original optional choice";optional$settings$required<-FALSE
  d$maxdiff<-list(exercise,optional);d$questions<-list(brohn_question("Original explicit liking","rating","end","liking"))
  record<-brohn_save_study(store,d,record$revision)
  check("optional extension validates and only creates explicit-choice steps",!rejected(brohn_validate_design(d,TRUE)) && identical(vapply(brohn_compile(d)$timeline,`[[`,character(1),"type"),c("maxdiff","maxdiff","question")))
  check("sample materials cannot be served as pilot or live",rejected(brohn_publish(store,d$id,"pilot")) && rejected(brohn_publish(store,d$id,"live")))
  release<-brohn_publish(store,d$id,"sample",quota=10,alias_required=TRUE)
  app<-brohn_delivery_app(store)
  call<-function(path,payload=NULL,bearer=NULL) {
    bytes<-if(is.null(payload))raw() else charToRaw(.brohn_store_json(payload))
    request<-list(PATH_INFO=path,REQUEST_METHOD=if(is.null(payload))"GET"else"POST",HTTP_HOST="127.0.0.1:3840",HTTP_ORIGIN="http://127.0.0.1:3840",CONTENT_TYPE="application/json",CONTENT_LENGTH=as.character(length(bytes)),rook.input=list(read=function(n=-1L)bytes))
    if(!is.null(bearer))request$HTTP_AUTHORIZATION<-paste("Bearer",bearer)
    r<-app$call(request);if(is.character(r$body)&&grepl("^application/json",r$headers[["Content-Type"]]))r$value<-brohn_parse(r$body);r
  }
  check("participant static files have exact typed allowlisted routes",call("/participant/maxdiff.js")$status==200 && grepl("application/javascript",call("/participant/maxdiff.js")$headers[["Content-Type"]]) && call("/participant/maxdiff.css")$status==200 && call("/participant/maxdiff.json")$status==404)
  pairs<-rbind(c(1,2),c(1,3),c(2,1),c(2,3),c(3,1),c(3,2));runs<-list();all_events<-list()
  for(i in 1:6) {
    started<-call(paste0("/api/start/",release$token),list(consented=TRUE,client_id=paste0("original-client-",i),operation_id=paste0("start-",i),participant_alias=paste0("P",if(i==2)1 else i)))
    if(started$status!=200)stop(started$body)
    start<-started$value;events<-list();time<-100;instance<-"first-page"
    emit<-function(type,step=NULL,payload=list(reason="original_fixture")) {
      e<-list(sequence=length(events)+1L,id=paste0("event-",i,"-",length(events)+1L),type=type,step_id=step$id,stimulus_id=step$stimulus_id,condition_id=step$condition_id,
        question_id=if(identical(step$type,"question"))step$question$id else NULL,phase=if(is.null(step))"session"else step$phase,
        clock=list(id="browser-monotonic",unit="ms",value=as.character(time),instance_id=instance,time_origin_ms="1788800000000"),payload=payload)
      events[[length(events)+1L]]<<-e;e
    }
    for(j in seq_along(start$protocol$timeline)) {
      step<-start$protocol$timeline[[j]];emit("step_started",step,list(resumed=FALSE));resumed<-FALSE
      if(i==1 && j==1) {instance<-"resumed-page";time<-20;emit("step_started",step,list(resumed=TRUE));resumed<-TRUE}
      time<-time+50
      value<-if(step$type=="question") 4 else if(j==2) NULL else list(best_id=step$choice$item_order[[pairs[i,1]]],worst_id=step$choice$item_order[[pairs[i,2]]])
      emit("response",step,list(value=value,response_time_ms=if(resumed)NULL else 50,active_segment_response_ms=50,resumed=resumed))
      emit("step_finished",step,list(elapsed_ms=if(resumed)NULL else 50,resumed=resumed));time<-time+10
    }
    emit("run_finished",payload=list(outcome="completed"))
    if(i==1) {
      path<-paste0("/api/events/",start$run_id)
      try_events<-function(changed,operation)call(path,list(events=changed,operation_id=operation),start$access_token)$status
      invalid<-events;invalid[[3]]$payload$value$worst_id<-invalid[[3]]$payload$value$best_id
      check("same item cannot be best and worst and rejection is atomic",try_events(invalid,"invalid-same")==422 && !length(brohn_run_events(store,start$run_id)))
      invalid<-events;invalid[[3]]$payload$value$worst_id<-"foreign-item"
      check("unoffered choice is rejected",try_events(invalid,"invalid-foreign")==422)
      invalid<-events;invalid[[3]]$payload$response_time_ms<-50
      check("resumed response cannot claim uninterrupted latency",try_events(invalid,"invalid-resume")==422)
      invalid<-events;invalid[[3]]$payload$active_segment_response_ms<-49
      check("response latency must agree with observed segment",try_events(invalid,"invalid-clock")==422)
      invalid<-events;invalid[[3]]$payload["value"]<-list(NULL)
      check("required pair cannot be omitted",try_events(invalid,"invalid-required")==422)
      invalid<-events[-6];for(k in seq_along(invalid))invalid[[k]]$sequence<-k
      check("optional set requires explicit omission evidence",try_events(invalid,"invalid-omission")==422)
      invalid<-append(events,list(events[[3]]),after=3);for(k in seq_along(invalid)){invalid[[k]]$sequence<-k;invalid[[k]]$id<-paste0("dup-",k)}
      check("a different second response cannot double count a set",try_events(invalid,"invalid-duplicate")==409)
    }
    received<-call(paste0("/api/events/",start$run_id),list(events=events,operation_id=paste0("events-",i)),start$access_token)
    if(received$status!=200)stop(received$body)
    repeat_receipt<-call(paste0("/api/events/",start$run_id),list(events=events,operation_id=paste0("events-",i)),start$access_token)
    if(repeat_receipt$status!=200)stop(repeat_receipt$body)
    finished<-call(paste0("/api/finish/",start$run_id),list(outcome="completed",final_sequence=length(events),operation_id=paste0("finish-",i)),start$access_token)
    if(finished$status!=200)stop(finished$body)
    runs[[length(runs)+1L]]<-brohn_run(store,start$run_id);all_events[[start$run_id]]<-brohn_run_events(store,start$run_id)
  }
  check("all exact event retries and closures remain single journal entries",all(vapply(runs,function(r)r$completion_status=="completed" && r$transfer_status=="saved" && r$acked_sequence==length(all_events[[r$id]]),logical(1))))
  input<-list(design=d,runs=runs,events=all_events);report<-brohn_analyse_runs(input);results<-report$analysis$choice_tasks
  check("questionnaire retains six liking answers without choice pseudo-items",length(report$analysis$observations)==6 && all(vapply(report$analysis$observations,function(r)r$question_id=="liking" && r$value==4,logical(1))))
  first<-results[[1]];second<-results[[2]]
  check("symmetric paired likelihood has independently known optimum",first$model$status=="estimated" && all(vapply(first$model$utilities,function(u)near(u$utility,0),logical(1))) && near(first$model$diagnostics$negative_log_likelihood,6*log(6)))
  check("each item has two best two worst choices with actual six-pair denominator",all(vapply(first$items,function(item)item$best_count==2 && item$worst_count==2 && item$answered_exposures==6 && item$exposure_adjusted_score==0,logical(1))))
  check("repeated aliases describe five linked people and six sessions",first$quality$participant_count==5 && first$quality$session_count==6 && !first$quality$participant_inference_performed)
  check("optional omitted choices remain six missing and no invented utilities",second$quality$missing_exposures==6 && second$quality$answered_exposures==0 && second$model$status!="estimated" && all(vapply(second$items,function(item)is.null(item$exposure_adjusted_score),logical(1))))
  check("resumed timing stays separate from scientific preference scoring",isTRUE(first$collection_evidence[[1]]$resumed) && is.null(first$collection_evidence[[1]]$response_time_ms) && first$collection_evidence[[1]]$active_segment_response_ms==50)
  check("full ledger and exact exercise hashes are retained",identical(first$source$hash,brohn_hash(all_events)) && identical(first$design_hash,brohn_hash(exercise)) && identical(first$responses_hash,brohn_hash(first$exposures)))
  tampered<-input;tampered$runs[[1]]$protocol$timeline[[1]]$choice$item_order<-rev(tampered$runs[[1]]$protocol$timeline[[1]]$choice$item_order)
  check("analysis refuses altered offered order despite copied design hash",rejected(brohn_score_run_maxdiff(tampered)))
  partial<-input;partial$events[[runs[[1]]$id]]<-head(partial$events[[runs[[1]]$id]],-1L)
  check("analysis refuses an incomplete ledger disguised as a completed run",rejected(brohn_score_run_maxdiff(partial)))
  unknown<-input;unknown$runs[[1]]$participant_alias_supplied<-FALSE
  check("one unlinked session suppresses unique-person claims",is.null(brohn_analyse_runs(unknown)$analysis$choice_tasks[[1]]$quality$participant_count))
  cloned<-brohn_clone_design(d);md<-cloned$maxdiff[[1]]
  check("clone remaps exercise item set identities while preserving exact framing",md$id!=exercise$id && !any(brohn_ids(md$items)%in%brohn_ids(exercise$items)) && !any(brohn_ids(md$sets)%in%brohn_ids(exercise$sets)) && identical(md$settings,exercise$settings) && all(unlist(md$sets[[1]]$item_ids)%in%brohn_ids(md$items)))
  zip<-file.path(root,"original-choice-design.brohn-study.zip");brohn_export_design(store,d$id,zip)
  imported<-brohn_import_design(store,zip)
  check("actual ZIP reimport retains two remapped design-only exercises",length(imported$body$maxdiff)==2 && imported$body$maxdiff[[1]]$id!=exercise$id && identical(brohn_hash(imported$body$maxdiff[[1]]$settings),brohn_hash(exercise$settings)) && is.null(imported$body$choice_tasks))
  csv<-file.path(root,"choices.csv");brohn_export_report_csv(list(analysis=list(observations=brohn_maxdiff_export_rows(results))),csv)
  rows<-utils::read.csv(csv,stringsAsFactors=FALSE)
  check("choice CSV contains all twelve exact exposures with hashes framing and omissions",nrow(rows)==12 && sum(rows$status=="missing")==6 && all(rows$source_hash==brohn_hash(all_events)) && all(nzchar(rows$design_hash)) && all(nzchar(rows$prompt)))
  report$id<-"original-maxdiff-report";report$status<-"complete";report$created_at<-brohn_now();report$processing<-list(scope="original fixture direct R analysis")
  html<-file.path(root,"report.html");brohn_export_report_html(report,html)
  text<-paste(readLines(html,warn=FALSE),collapse="\n")
  check("standalone report contains explicit choice result and missingness interpretation",grepl("Aggregate paired utilities",text,fixed=TRUE) && grepl("Complete-pair counts",text,fixed=TRUE) && grepl("population confidence intervals are unavailable",text,fixed=TRUE))
  check("collection summary shows dedicated automatic explicit-choice route",any(vapply(brohn_collection_routes(d),function(r)r$id=="maxdiff" && r$participant_link,logical(1))))
  cat(sprintf("PASS: %d MaxDiff compiler, receiver, direct-analysis, report and portable-design checks (supervised-worker journey separate)\n",checks))
})
