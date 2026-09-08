# Independent arithmetic and explicit repeated-assessment identity fixtures.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
source("R/platform-scales.R",encoding="UTF-8")
local({
  checks<-0L
  check<-function(name,ok) {if(!isTRUE(ok)) stop(paste("Scale QA failed:",name),call.=FALSE);checks<<-checks+1L}
  rejected<-function(x) inherits(try(force(x),silent=TRUE),"try-error")
  near<-function(x,y) isTRUE(all.equal(x,y,tolerance=1e-10))
  question<-function(id,scope="end",min=0,max=4,type="rating") {
    q<-brohn_question(paste("Original item",id),type,scope,id);q$required<-FALSE;q$min<-min;q$max<-max;q$step<-1
    q$options<-lapply(seq.int(min,max),function(v) list(id=paste0("choice-",v),label=as.character(v),value=v));q
  }
  make_scale<-function(questions,id="scale-original",scope="end") list(schema="brohn-questionnaire-scale/1.0",id=id,label="Original arithmetic scale",version="1.0",
    source="Researcher-defined original test items and arithmetic; no validation claim.",scope=scope,
    items=lapply(questions,function(q) {b<-brohn_scale_question_bounds(q);list(question_id=q$id,reverse=FALSE,min=b[1],max=b[2])}),
    scoring=list(aggregation="sum",missing="complete",minimum_answered=length(questions),prorate=FALSE),conversion=NULL)
  design<-brohn_new_design("Original numerical scale");design$questions<-lapply(c("q-one","q-two","q-three"),question)
  scale<-make_scale(design$questions);scale$items[[2]]$reverse<-TRUE;scale$conversion<-list(min=0,max=100);design$scales<-list(scale)
  check("explicit scale configuration is valid",!rejected(brohn_validate_scales(design$scales,design)))
  rows<-function(values,assessment="assessment-1",person="P1",session="S1",questions=design$questions) lapply(seq_along(values),function(i)
    list(participant_id=person,session_id=session,assessment_id=assessment,question_id=questions[[i]]$id,value=values[[i]],
      stimulus_id=NULL,condition_id=NULL,assessment_exposure_id=NULL,participant_linkage=TRUE,origin="sample",source_row=i,missing_reason=NULL))
  raw<-rows(list(0,1,4));score<-brohn_score_scales(raw,design)
  check("independent reverse/sum oracle retains zero",score$observations[[1]]$raw_aggregate==7 && score$item_evidence[[1]]$items[[1]]$raw_value==0 && score$item_evidence[[1]]$items[[2]]$keyed_value==3)
  check("bounded conversion uses theoretical score range",near(score$observations[[1]]$value,700/12))
  check("scale and original questionnaire provenance is frozen",identical(score$provenance$scales_hash,brohn_hash(design$scales)) && identical(score$provenance$questionnaire,design$questions))
  check("source rows retain exact typed response hashes",all(vapply(score$item_evidence[[1]]$items,function(i) grepl("^[a-f0-9]{64}$",i$source[[1]]$response_hash),logical(1))))
  mean_design<-design;mean_design$scales[[1]]$scoring$aggregation<-"mean";mean_design$scales[[1]]["conversion"]<-list(NULL)
  check("independent complete-item mean oracle",near(brohn_score_scales(raw,mean_design)$observations[[1]]$value,7/3))
  omitted<-raw;omitted[[3]]$value<-NULL;omitted[[3]]$missing_reason<-"optional_omission"
  missing<-brohn_score_scales(omitted,design)$observations[[1]]
  check("complete-item rule cannot score omitted response",is.null(missing$value) && missing$missing_reason=="insufficient_answered_items" && missing$answered_items==2)
  partial<-design;partial$scales[[1]]$scoring<-list(aggregation="sum",missing="minimum_answered",minimum_answered=2,prorate=TRUE)
  estimated<-brohn_score_scales(omitted,partial)$observations[[1]]
  check("declared item-mean prorated sum matches independent4.5 oracle",estimated$raw_aggregate==4.5 && estimated$value==37.5 && estimated$prorated)
  partial$scales[[1]]$scoring$aggregation<-"mean";partial$scales[[1]]$scoring$prorate<-FALSE;partial$scales[[1]]["conversion"]<-list(NULL)
  check("available-item mean is1.5 without a hidden zero",brohn_score_scales(omitted,partial)$observations[[1]]$value==1.5)
  empty<-rows(list(NULL,NULL,NULL));check("all missing never yields zero",is.null(brohn_score_scales(empty,design)$observations[[1]]$value))
  invalid<-raw;invalid[[1]]$value<-FALSE
  check("boolean false is not numeric zero",brohn_score_scales(invalid,design)$observations[[1]]$missing_reason=="invalid_or_ambiguous_item")
  invalid[[1]]$value<-9;check("out-of-range responses cannot be prorated away",brohn_score_scales(invalid,partial)$observations[[1]]$missing_reason=="invalid_or_ambiguous_item")
  invalid<-raw;invalid[[1]]$missing_reason<-"not_supported"
  check("non-null value with failed support is excluded explicitly",brohn_score_scales(invalid,partial)$observations[[1]]$missing_reason=="invalid_or_ambiguous_item")
  duplicate<-c(raw,list(raw[[1]]));check("duplicate item makes assessment ambiguous",brohn_score_scales(duplicate,partial)$observations[[1]]$missing_reason=="invalid_or_ambiguous_item")
  repeated<-c(raw,rows(list(4,1,4),assessment="assessment-2"));repeated_score<-brohn_score_scales(repeated,design)
  check("repeated assessments never pool item rows",length(repeated_score$observations)==2 && setequal(vapply(repeated_score$observations,`[[`,numeric(1),"raw_aggregate"),c(7,11)))
  check("assessment count is not participant count",repeated_score$features[[1]]$assessment_count==2 && repeated_score$features[[1]]$participant_count==1)
  unknown<-lapply(raw,function(r) {r$participant_linkage<-FALSE;r})
  check("unknown repeat identity has no unique-person count",is.null(brohn_score_scales(unknown,design)$features[[1]]$participant_count))
  unidentified<-lapply(raw,function(r) {r$assessment_id<-NULL;r})
  check("missing assessment IDs do not fall back to session or row order",length(brohn_score_scales(unidentified,design)$observations)==0 && brohn_score_scales(unidentified,design)$quality$unassigned_response_count==3)
  bad<-design;bad$questions[[1]]$type<-"single_choice"
  check("nominal numeric option codes cannot become scale items",rejected(brohn_validate_scales(bad$scales,bad)))
  bad<-design;bad$questions[[1]]$options[[1]]$value<-FALSE
  check("mixed boolean/numeric rating codes are not quantitative scale codes",rejected(brohn_validate_scales(bad$scales,bad)))
  options_bound<-design;options_bound$questions[[1]]$min<-100;options_bound$questions[[1]]$max<-200
  check("rating bounds come from declared codes, not generic UI range",!rejected(brohn_validate_scales(options_bound$scales,options_bound)))
  bad<-design;bad$scales[[1]]$items[[1]]$min<-1;check("reverse keys cannot use mismatched question bounds",rejected(brohn_validate_scales(bad$scales,bad)))
  bad<-design;bad$questions[[1]]$scope<-"before";check("mixed questionnaire scopes cannot define one scale",rejected(brohn_validate_scales(bad$scales,bad)))
  bad<-design;bad$scales[[1]]$items[[2]]$question_id<-"q-one";check("duplicate scale item references rejected",rejected(brohn_validate_scales(bad$scales,bad)))
  bad<-partial;bad$scales[[1]]$scoring$aggregation<-"sum";check("partial sums require explicit prorating",rejected(brohn_validate_scales(bad$scales,bad)))
  bad<-partial;bad$questions[[1]]<-question("q-one",min=1,max=5);bad$scales[[1]]$items[[1]]$min<-1;bad$scales[[1]]$items[[1]]$max<-5
  check("equal widths with different endpoints are not commensurate partial items",rejected(brohn_validate_scales(bad$scales,bad)))
  stepped<-design;stepped$questions[[1]]<-question("q-one",type="number");stepped$questions[[1]]$step<-.5
  invalid<-raw;invalid[[1]]$value<-1.2;check("number step grid enforced by shared typed validator",brohn_score_scales(invalid,stepped)$observations[[1]]$missing_reason=="invalid_or_ambiguous_item")
  check("integer-valued number bounds survive JSON restart types",!rejected(brohn_validate_scales(brohn_parse(brohn_json(stepped))$scales,brohn_parse(brohn_json(stepped)))))
  blank_context<-lapply(raw,function(r) {r$stimulus_id<-"";r$condition_id<-"";r})
  check("blank optional imported context remains missing, not a fake stimulus",brohn_score_scales(blank_context,design)$observations[[1]]$raw_aggregate==7)
  map<-stats::setNames(paste0("clone-",seq_along(design$questions)),brohn_ids(design$questions));cloned<-brohn_clone_scales(design$scales,map)
  check("clone remaps every question and scale identity",cloned[[1]]$id!=scale$id && identical(vapply(cloned[[1]]$items,`[[`,character(1),"question_id"),unname(map)))
  check("missing clone references reject rather than drop items",rejected(brohn_clone_scales(design$scales,map[-1])))
  # Ten original item labels exercise the published SUS arithmetic without
  # copying the questionnaire or implying these original items constitute SUS.
  sus<-design;sus$questions<-lapply(paste0("original-item-",1:10),question,min=1,max=5)
  sus_scale<-make_scale(sus$questions,id="sus-arithmetic");sus_scale$items<-lapply(seq_along(sus_scale$items),function(i) {x<-sus_scale$items[[i]];x$reverse<-i%%2==0;x})
  sus_scale$conversion<-list(min=0,max=100);sus$scales<-list(sus_scale)
  check("published SUS key arithmetic gives100 at favorable endpoints",brohn_score_scales(rows(as.list(rep(c(5,1),5)),questions=sus$questions),sus)$observations[[1]]$value==100)
  check("published SUS key arithmetic gives0 at adverse endpoints",brohn_score_scales(rows(as.list(rep(c(1,5),5)),questions=sus$questions),sus)$observations[[1]]$value==0)
  check("published SUS key arithmetic midpoint is50",brohn_score_scales(rows(as.list(rep(3,10)),questions=sus$questions),sus)$observations[[1]]$value==50)
  # Participant protocol has different question-step IDs per item. They must
  # share the exact preceding stimulus-step assessment, not their question ID.
  timed<-brohn_new_design("Original protocol scale")
  timed$stimuli<-lapply(timed$stimuli,function(s) {s$content<-"Original test concept";s})
  timed$questions<-unlist(lapply(c("before","after_each","end"),function(scope) lapply(1:2,function(i) question(paste0("item-",scope,"-",i),scope))),recursive=FALSE)
  timed$scales<-lapply(c("before","after_each","end"),function(scope) make_scale(Filter(function(q) q$scope==scope,timed$questions),paste0("scale-",scope),scope))
  # Until the root optional-field hook lands, compile the identical execution
  # design then attach this frozen scoring-only field to the protocol design.
  execution<-timed;execution$scales<-NULL;protocol<-brohn_compile(execution);protocol$design<-timed;protocol$design_hash<-brohn_hash(timed)
  make_input<-function(id="run-original",alias=TRUE) {
    ev<-lapply(Filter(function(s) s$type=="question",protocol$timeline),function(s) list(id=paste0("event-",s$id),sequence=match(s$id,brohn_ids(protocol$timeline)),
      type="response",step_id=s$id,payload=list(value=if(s$question$scope=="after_each" && s$stimulus_id=="stimulus-b") 4 else 2)))
    run<-list(id=id,participant_alias="P1",participant_alias_supplied=alias,origin="sample",protocol=protocol)
    list(design=timed,runs=list(run),events=stats::setNames(list(ev),id))
  }
  input<-make_input();prepared<-brohn_scale_run_responses(input);result<-brohn_score_run_scales(input)
  check("before, each stimulus and end remain four separate assessments",length(result$observations)==4)
  after<-Filter(function(r) r$scope=="after_each",result$observations)
  check("question steps share their exact stimulus occurrence",length(after)==2 && length(unique(vapply(after,`[[`,character(1),"assessment_exposure_id")))==2 && setequal(vapply(after,`[[`,numeric(1),"value"),c(4,8)))
  check("source question-step IDs are preserved separately",all(vapply(result$item_evidence,function(e) length(unique(vapply(e$items,function(i) i$source[[1]]$step_id,character(1))))==2,logical(1))))
  hidden<-input;event<-hidden$events[[1]][[1]];hidden$events[[1]]<-hidden$events[[1]][-1];event$type<-"step_finished";event$payload<-list(skipped=TRUE);hidden$events[[1]]<-c(hidden$events[[1]],list(event))
  result_hidden<-brohn_score_run_scales(hidden)
  check("conditionally hidden item remains distinguishable from omission",any(vapply(result_hidden$item_evidence,function(e) any(vapply(e$items,function(i) identical(i$missing_reason,"not_displayed"),logical(1))),logical(1))))
  mislinked<-input;at<-which(vapply(mislinked$runs[[1]]$protocol$timeline,function(s) s$type=="question" && identical(s$question$scope,"after_each"),logical(1)))[1]
  mislinked$runs[[1]]$protocol$timeline[[at]]$stimulus_id<-"stimulus-b"
  check("question cannot attach to a different preceding stimulus occurrence",rejected(brohn_scale_run_responses(mislinked)))
  wrong_hash<-input;wrong_hash$runs[[1]]$protocol$design_hash<-paste(rep("0",64),collapse="")
  check("frozen design hash mismatch rejects scoring",rejected(brohn_score_run_scales(wrong_hash)))
  check("no scale definitions produces no scale score claim",is.null(brohn_score_run_scales(list(design=list(scales=list())))))
  source("R/platform-scale-views.R",encoding="UTF-8")
  state<-list(page="study",stage="Questions");current<-list(study=list(id=design$id,body=design,revision=1))
  draft<-list(active=TRUE,study_id=design$id,revision=1,design_hash=brohn_hash(design),token="original-form")
  editor_input<-list(study_form_identity=paste(design$id,"Questions",sep=":"),scale_form_identity="original-form")
  check("current explicit editor can save",brohn_scale_editor_current(draft,current,state,editor_input))
  check("cancelled draft cannot receive late Save",!brohn_scale_editor_current(modifyList(draft,list(active=FALSE)),current,state,editor_input))
  check("modal from another study cannot save",!brohn_scale_editor_current(draft,modifyList(current,list(study=list(id="another-study"))),state,editor_input))
  check("new study revision invalidates open editor",!brohn_scale_editor_current(draft,modifyList(current,list(study=list(revision=2))),state,editor_input))
  check("study-stage navigation invalidates open editor",!brohn_scale_editor_current(draft,current,modifyList(state,list(stage="Collect")),editor_input))
  check("old modal token cannot save a reopened scale",!brohn_scale_editor_current(draft,current,state,modifyList(editor_input,list(scale_form_identity="older-form"))))
  # Original cross-scope design: scope/membership changes must never schedule a
  # server replacement of an already edited checkbox. Actual rapid DOM change
  # and persistence is exercised separately by researcher-scales.mjs.
  control_key<-timed$scales[[1]]
  controls<-brohn_scale_selection_ui(timed,control_key,"original-modal-a")
  control_html<-htmltools::renderTags(shiny::tagList(controls))$html
  check("all placement drafts have stable separate item pickers",all(vapply(c("scale_question_ids", "scale_question_ids_before", "scale_question_ids_after_each"),function(id)
    grepl(paste0('id="',id,'"'),control_html,fixed=TRUE),logical(1))))
  check("scale key controls cannot rerender when membership changes",!grepl("shiny-html-output",control_html,fixed=TRUE) &&
    grepl("data-display-if",control_html,fixed=TRUE))
  eligible<-Filter(function(q) !inherits(try(brohn_scale_question_bounds(q),silent=TRUE),"try-error"),timed$questions)
  check("every eligible question has one modal-bound reverse control",all(vapply(eligible,function(q)
    length(gregexpr(paste0('id="scale_reverse_original-modal-a_',q$id,'"'),control_html,fixed=TRUE)[[1]])==1L &&
      grepl(paste0('id="scale_reverse_original-modal-a_',q$id,'"'),control_html,fixed=TRUE),logical(1))))
  next_html<-htmltools::renderTags(shiny::tagList(brohn_scale_selection_ui(timed,control_key,"original-modal-b")))$html
  check("reopened modal cannot receive a prior reverse input binding",!grepl("scale_reverse_original-modal-a_",next_html,fixed=TRUE) &&
    grepl("scale_reverse_original-modal-b_",next_html,fixed=TRUE))
  # Actual saved design, portable package and independent scientific children.
  root<-tempfile("brohn-scales-integration-");dir.create(root);root<-normalizePath(root,winslash="/")
  store<-brohn_open_store(file.path(root,"workspace"));brohn_initialise_library(store)
  target<-brohn_open_store(file.path(root,"replication"));brohn_initialise_library(target)
  on.exit({
    brohn_close_store(store);brohn_close_store(target)
    actual<-normalizePath(root,winslash="/",mustWork=FALSE)
    stopifnot(startsWith(tolower(actual),paste0(tolower(normalizePath(tempdir(),winslash="/")),"/")),grepl("^brohn-scales-integration-",basename(actual)))
    unlink(actual,recursive=TRUE,force=TRUE)
  },add=TRUE)
  check("root design validator includes scale configuration",!rejected(brohn_validate_design(design)))
  saved<-brohn_put_entity(store,"study",design$id,design)
  invalid_design<-design;invalid_design$questions[[1]]$scope<-"before"
  err<-tryCatch({brohn_save_study(store,invalid_design,saved$revision);NULL},error=conditionMessage)
  check("saved keyed question scope change is rejected with recovery guidance",is.character(err) && grepl(scale$label,err,fixed=TRUE) && grepl("Discard unsaved question edits",err,fixed=TRUE))
  invalid_design<-design;invalid_design$questions[[1]]$options[[1]]$value<--1
  check("saved rating-code range change cannot silently rekey scale",rejected(brohn_save_study(store,invalid_design,saved$revision)))
  invalid_design<-design;invalid_design$questions<-invalid_design$questions[-1]
  check("deleting a referenced question cannot leave a broken saved key",rejected(brohn_save_study(store,invalid_design,saved$revision)))
  check("failed question changes leave saved design revision intact",brohn_study(store,design$id)$revision==saved$revision && identical(brohn_hash(brohn_study(store,design$id)$body),brohn_hash(design)))
  cloned_study<-brohn_clone_study(store,design$id)
  check("actual study clone remaps scale item references",cloned_study$body$scales[[1]]$id!=scale$id &&
    identical(vapply(cloned_study$body$scales[[1]]$items,`[[`,character(1),"question_id"),brohn_ids(cloned_study$body$questions)))
  template<-brohn_save_template(store,design$id);reused<-brohn_use_template(store,template$id)
  check("saved design template retains key and remaps reused questions",reused$body$scales[[1]]$source==scale$source && reused$body$scales[[1]]$items[[2]]$reverse &&
    identical(vapply(reused$body$scales[[1]]$items,`[[`,character(1),"question_id"),brohn_ids(reused$body$questions)))
  package<-brohn_export_design(store,design$id,file.path(root,"original-scales.brohn-study.zip"))
  imported<-brohn_import_design(target,package)
  check("actual portable package preserves scoring and conversion with new refs",imported$body$scales[[1]]$conversion$max==100 && imported$body$scales[[1]]$scoring$minimum_answered==3 &&
    imported$body$scales[[1]]$items[[2]]$reverse && identical(vapply(imported$body$scales[[1]]$items,`[[`,character(1),"question_id"),brohn_ids(imported$body$questions)))
  check("portable scale arithmetic survives package identity remapping",near(brohn_score_scales(rows(list(0,1,4),questions=imported$body$questions),imported$body)$observations[[1]]$value,700/12))
  survey<-brohn_new_design("Original saved scale delivery","survey");survey$instructions<-"";survey$questions<-design$questions;survey$scales<-design$scales
  invisible(brohn_put_entity(store,"study",survey$id,survey));deployment<-brohn_publish(store,survey$id,origin="sample",quota=2)
  delivery<-.brohn_delivery_start(store,deployment$token,list(consented=TRUE,client_id="original-scale-client",operation_id="original-scale-start",participant_alias="P1"))
  journal<-list();sequence<-0L
  event<-function(type,step=NULL,value=NULL) {
    sequence<<-sequence+1L
    list(id=paste0("scale-event-",sequence),sequence=sequence,type=type,step_id=if(is.null(step)) NULL else step$id,
      stimulus_id=NULL,condition_id=NULL,question_id=if(is.null(step)) NULL else step$question$id,phase=if(is.null(step)) "session" else step$phase,
      clock=list(id="browser-monotonic",unit="ms",value=as.character(sequence*10),instance_id="original-scale-clock",time_origin_ms="1000"),
      payload=switch(type,step_started=list(resumed=FALSE),response=list(value=value,response_time_ms=10),step_finished=list(elapsed_ms=20),run_finished=list(outcome="completed")))
  }
  values<-list(0,1,4)
  for(i in seq_along(delivery$protocol$timeline)) {
    step<-delivery$protocol$timeline[[i]];journal<-c(journal,list(event("step_started",step),event("response",step,values[[i]]),event("step_finished",step)))
  }
  journal<-c(journal,list(event("run_finished")))
  .brohn_delivery_receive(store,delivery$run_id,delivery$access_token,list(operation_id="original-scale-events",events=journal))
  .brohn_delivery_finish(store,delivery$run_id,delivery$access_token,list(operation_id="original-scale-finish",outcome="completed",final_sequence=sequence))
  claim<-brohn_claim_job(store,"scale-integration",lease_seconds=60);check("completed delivery automatically queues run scoring",claim$operation=="analyse_run")
  brohn_process_job(store,claim,timeout_seconds=30);finished<-brohn_get_job(store,claim$id)
  if(finished$status!="succeeded") stop(paste("Actual scale worker failed:",brohn_json(finished$error)))
  report<-brohn_get_entity(store,"report",finished$result$report_id);run_scale<-report$body$analysis$scales
  check("actual fenced run report matches independent scale arithmetic",near(run_scale$observations[[1]]$value,700/12) && length(run_scale$observations)==1)
  check("saved run scale retains exact journal and question-step references",identical(run_scale$provenance$source$runs[[1]]$events_hash,brohn_hash(brohn_run_events(store,delivery$run_id))) &&
    run_scale$item_evidence[[1]]$items[[1]]$source[[1]]$step_id==delivery$protocol$timeline[[1]]$id)
  check("scientific publication pins scale implementation and result bytes",identical(report$body$processing$code_hashes$`R/platform-scales.R`,digest::digest(file="R/platform-scales.R",algo="sha256")) &&
    identical(report$body$result_object$hash,finished$result$output_hash) && identical(digest::digest(file=brohn_object_path(store,finished$result$output_hash),algo="sha256"),finished$result$output_hash))
  import_path<-file.path(root,"original-scale-responses.csv")
  imported_rows<-data.frame(person=rep("P1",6),session=rep("S1",6),assessment=rep(c("first","second"),each=3),question=rep(brohn_ids(survey$questions),2),value=c(0,1,4,4,1,4))
  utils::write.csv(imported_rows,import_path,row.names=FALSE)
  ingested<-brohn_ingest_dataset(store,import_path,"Original repeated scale assessments","questionnaire",study_id=survey$id,origin="sample")
  mapping<-list(participant_column="person",session_column="session",assessment_column="assessment",question_column="question",value_columns=list("value"),unit="numeric_rating",
    origin_statement="Original arithmetic data; participant and repeated-assessment IDs were explicitly supplied by the fixture.")
  accepted<-brohn_curate_dataset(store,ingested$id,mapping,ingested$revision);queued<-brohn_queue_dataset(store,accepted$id)
  claim<-brohn_claim_job(store,"scale-import",lease_seconds=60);brohn_process_job(store,claim,timeout_seconds=30);finished_import<-brohn_get_job(store,queued$id)
  if(finished_import$status!="succeeded") stop(paste("Actual scale import failed:",brohn_json(finished_import$error)))
  import_report<-brohn_get_entity(store,"report",finished_import$result$report_id)
  check("actual imported repeated assessments stay separate",length(import_report$body$analysis$scales$observations)==2 &&
    setequal(vapply(import_report$body$analysis$scales$observations,`[[`,numeric(1),"raw_aggregate"),c(7,11)))
  check("import scales pin original source and explicit assessment mapping",identical(import_report$body$analysis$scales$provenance$source$source_hash,accepted$body$source$hash) &&
    import_report$body$analysis$scales$provenance$source$mapping$assessment_column=="assessment")
  missing_map<-mapping;missing_map$assessment_column<-NULL
  single_path<-file.path(root,"original-single-assessment.csv");utils::write.csv(imported_rows[1:3,],single_path,row.names=FALSE)
  plain<-brohn_ingest_dataset(store,single_path,"Original unmapped assessment","questionnaire",study_id=survey$id,origin="sample")
  plain<-brohn_curate_dataset(store,plain$id,missing_map,plain$revision);job<-brohn_queue_dataset(store,plain$id)
  claim<-brohn_claim_job(store,"scale-missing-assessment",lease_seconds=60);brohn_process_job(store,claim,timeout_seconds=30);done<-brohn_get_job(store,job$id)
  check("missing assessment mapping retains ordinary questionnaire report",done$status=="succeeded")
  plain_report<-brohn_get_entity(store,"report",done$result$report_id)
  check("unmapped assessment exposes quality gap without invented scale",length(plain_report$body$analysis$observations)==3 &&
    plain_report$body$analysis$scales$quality$unassigned_response_count==3 && length(plain_report$body$analysis$scales$observations)==0)
  csv_path<-file.path(root,"scale-scores.csv");brohn_scale_scores_csv(import_report$body$analysis$scales,csv_path)
  csv<-utils::read.csv(csv_path,colClasses="character",check.names=FALSE,na.strings=character())
  check("dedicated CSV exports all separate assessment scores and provenance",nrow(csv)==2 && setequal(csv$assessment_id,c("first","second")) && all(csv$design_hash==brohn_hash(survey)))
  check("canonical CSV records preserve typed scores",near(brohn_parse(csv$score_record_json[[1]])$value,as.numeric(csv$value[[1]])))
  unsafe<-run_scale;unsafe$observations[[1]]$participant_id<-"=1+2";brohn_scale_scores_csv(unsafe,csv_path)
  escaped<-utils::read.csv(csv_path,colClasses="character",na.strings=character())
  check("spreadsheet text is safe while canonical identity stays exact",escaped$participant_id[[1]]=="'=1+2" && brohn_parse(escaped$score_record_json[[1]])$participant_id=="=1+2")
  brohn_load(ui=TRUE)
  summary_html<-htmltools::renderTags(brohn_scales_summary_ui(design))$html
  check("saved scale offers explicit recovery from invalid unsaved questions",grepl("scale_restore_questions",summary_html,fixed=TRUE))
  rendered<-htmltools::renderTags(brohn_scale_results_ui(import_report$body$analysis$scales))$html
  check("report preview names complete exports and bounded rows",grepl("up to 30",rendered,fixed=TRUE) && grepl("Scale scores CSV",rendered,fixed=TRUE))
  report_hash<-brohn_hash(report$body);brohn_close_store(store);store<-brohn_open_store(file.path(root,"workspace"))
  check("reopen retains immutable original scale result",identical(brohn_hash(brohn_get_entity(store,"report",report$id)$body),report_hash))
  cat(sprintf("Questionnaire scales: %d scoped checks passed.\n",checks))
})
