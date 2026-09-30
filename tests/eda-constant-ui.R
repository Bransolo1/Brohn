# Rscript tests/eda-constant-ui.R REPO FRESH_OUT [LOADER_REPO]
# Pure synthetic shape and real Shiny controller checks; backend calls are spies.
args<-commandArgs(TRUE);stopifnot(length(args)%in%c(2L,3L))
root<-normalizePath(args[[1]],winslash="/",mustWork=TRUE)
loader<-if(length(args)==3L)normalizePath(args[[3]],winslash="/",mustWork=TRUE)else root
out<-args[[2]];stopifnot(!file.exists(out));dir.create(out,recursive=TRUE);out<-normalizePath(out,winslash="/",mustWork=TRUE)
setwd(loader);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
legacy_extract<-.brohn_mm_extract;legacy_input<-brohn_eda_events_input
files<-c("platform-eda-events.R","platform-eda-events-views.R","platform-eda-continuous-review-views.R","platform-data-views.R","platform-multimodal.R","platform-report-package-views.R","platform-report-package-server.R")
hashes<-setNames(lapply(files,function(f)digest::digest(file=file.path(root,"R",f),algo="sha256")),files)
for(f in files)source(file.path(root,"R",f),encoding="UTF-8")
checks<-list();check<-function(ok,label){checks[[length(checks)+1L]]<<-list(label=label,passed=isTRUE(ok));cat(if(isTRUE(ok))"PASS"else"FAIL",label,"\n");if(!isTRUE(ok))stop(label,call.=FALSE)}
refuses<-function(code)isTRUE(tryCatch({force(code);FALSE},error=function(e)TRUE))
html<-function(x)as.character(htmltools::renderTags(x)$html)
main<-function(){
 recipes<-brohn_eda_events_recipe_choices()
 check(length(recipes)==4L&&sum(recipes=="eda-neurokit-highpass/1.1")==1L,"New recipe is explicit and existing three choices remain")
 for(r in brohn_eda_continuous_recipes())check(!brohn_eda_events_is_event(list(parameters=list(recipe=r)))&&brohn_eda_events_worker_request(list(parameters=list(recipe=r)))$operation=="physiology",paste(r,"routes to continuous worker by membership"))
 for(r in c("eda-event-highpass/1.0","eda-event-cvxeda-defaults/1.0"))check(brohn_eda_events_is_event(list(parameters=list(recipe=r))),paste(r,"retains event membership"))
 check(brohn_eda_events_worker_request(list())$operation=="physiology"&&refuses(brohn_eda_events_worker_request(list(parameters=list(recipe="future/2")))),"Missing recipe stays continuous legacy; unknown recipe refuses")
 mapping<-list(parameters=list(recipe="eda-neurokit-highpass/1.0",edge_exclusion_s=12),participant_column="person",event_column="event",recording_column="run",valid_column="valid")
 old<-legacy_input(list(map_eda_event_recipe="eda-neurokit-highpass/1.0"),mapping)
 check(identical(old,brohn_eda_events_input(list(map_eda_event_recipe="eda-neurokit-highpass/1.0"),mapping)),"Existing mapping capture remains exact")
 chosen<-brohn_eda_events_input(list(map_eda_event_recipe="eda-neurokit-highpass/1.1"),mapping)
 check(identical(chosen$parameters,list(recipe="eda-neurokit-highpass/1.1"))&&is.null(chosen$event_column)&&is.null(chosen$events),"Explicit method change resets method settings and never carries event fields into continuous analysis")
 settings<-html(brohn_eda_events_settings_ui(list(),c("time","signal")))
 check(grepl('value="eda-neurokit-highpass/1.0" selected',settings,fixed=TRUE)&&grepl("indexOf(input.map_eda_event_recipe)",settings,fixed=TRUE)&&!grepl("recipe !==",settings,fixed=TRUE),"Default method remains1.0 and event form has explicit event membership")
 names0<-c("tonic_mean","tonic_median","tonic_slope","conductance_raw_mean","scr_count","scr_rate","scr_amplitude_mean","scr_amplitude_median","phasic_area_signed","phasic_area_positive")
 units<-c("uS","uS","uS/s","uS","count","count/min","uS","uS","uS*s","uS*s")
 record<-list(recording_id="recording-1",segment_id="segment-1",channel="EDA",group=list(participant_id="person <1>",session_id="visit-1"),status="descriptive_only",exact_flatline=TRUE,processing_branch="exact_constant_raw_description/1.0",descriptive_status="computed",response_status="unavailable",response_reason="exact_constant_signal",numerical_candidate_count=0L,response_denominator=NULL,start_time_s=.1,end_time_s=120,samples=1200L,retained_samples=1000L,source_unit="uS",scale_factor=1)
 parameters<-list(recipe="eda-neurokit-highpass/1.1",exact_constant_policy="raw_description_only/1.0")
 features<-lapply(seq_along(names0),function(i){raw<-i==4L;f<-list(name=names0[[i]],value=if(raw)5 else NULL,unit=units[[i]],scope="recording",recording_id=record$recording_id,segment_id=record$segment_id,channel=record$channel,group=record$group,eligible=raw,support_status=if(raw)"computed"else"unavailable",missing_reason=if(raw)NULL else"exact_constant_signal");if(i%in%c(7L,8L))f["denominator"]<-list(NULL);f})
 body<-list(analysis=list(kind="eda",recordings=list(record),parameters=parameters,features=features),provenance=list(design=list(conditions=list()),design_hash=brohn_hash("design")),origin="import")
 ref<-list(id="saved-source",revision=3L,hash=brohn_hash(body));original<-brohn_json(body)
 rows<-.brohn_mm_extract(body,ref,NULL)
 check(length(rows)==10L&&identical(vapply(rows,`[[`,logical(1),"source_eligible"),seq_along(rows)==4L),"Exactly raw mean is eligible; all nine withheld observations remain")
 check(rows[[4]]$value==5&&is.null(rows[[4]]$source_missing_reason)&&all(vapply(rows[-4],function(r)is.null(r$value)&&identical(r$source_missing_reason,"exact_constant_signal"),logical(1))),"Null values and precise source reasons survive synthesis")
 check(all(vapply(seq_along(rows),function(i){r<-rows[[i]];identical(r$support,record)&&identical(names(r$definition),c("recipe","dimensions","scope"))&&identical(r$definition$recipe,parameters)&&length(r$definition$dimensions)==0L&&identical(r$definition$scope,"recording")&&identical(r$source_row_hash,brohn_hash(features[[i]]))&&identical(r$source_participant_id,record$group$participant_id)&&r$source_report_revision==3L},logical(1)))&&identical(original,brohn_json(body)),"Exact original support, recipe, row hashes, identities and source body are preserved")
 for(field in c("recipe","exact_constant_policy")){bad<-body;bad$analysis$parameters[[field]]<-"unregistered";check(!any(vapply(.brohn_mm_extract(bad,ref,NULL),`[[`,logical(1),"source_eligible")),paste("Constant admission refuses wrong",field))}
 for(field in c("exact_flatline","processing_branch","descriptive_status","response_status","response_reason","numerical_candidate_count","response_denominator")){bad<-body;bad$analysis$recordings[[1]][[field]]<-NULL;check(!any(vapply(.brohn_mm_extract(bad,ref,NULL),`[[`,logical(1),"source_eligible")),paste("Constant admission refuses absent",field))}
 bad<-body;bad$analysis$recordings<-list(record,record);check(!any(vapply(.brohn_mm_extract(bad,ref,NULL),`[[`,logical(1),"source_eligible")),"Ambiguous recording identity does not admit raw mean")
 for(i in c(1L,4L,7L)){bad<-body;if(i==4L)bad$analysis$features[[i]]$eligible<-FALSE else bad$analysis$features[[i]]$value<-0;rr<-.brohn_mm_extract(bad,ref,NULL)[[i]];check(!rr$source_eligible&&rr$source_missing_reason=="missing_or_ambiguous_computed_signal_support",paste("Malformed feature",i,"cannot acquire constant support or zero-SCR meaning"))}
 ordinary<-body;ordinary$analysis$parameters<-list(recipe="eda-neurokit-highpass/1.0");ordinary$analysis$recordings[[1]]$status<-"computed";ordinary$analysis$features<-lapply(features,function(f){f$value<-2;f[c("eligible","support_status","missing_reason")]<-NULL;f})
 check(identical(legacy_extract(ordinary,ref,NULL),.brohn_mm_extract(ordinary,ref,NULL)),"Existing ordinary1.0 synthesis output remains byte-structurally exact")
 model<-list(schema="brohn-eda-continuous-review/1.1",status="raw_description_only",recording=record,parameters=parameters,features=features,counts=list(segment_coordinate_rows=1200L,segment_retained_coordinate_rows=1000L,segment_excluded_coordinate_rows=200L),selection=list(start_s="0.1",end_s="120"),display_policy="Original support retained",limitations=list("No emotion interpretation"))
 panel<-html(.brohn_ecr_raw_description_ui(model,list(),"review"))
 check(!grepl("<svg",panel,fixed=TRUE)&&!grepl("Download EDA window SVG",panel,fixed=TRUE)&&grepl("other nine estimates remain unavailable",panel,fixed=TRUE)&&grepl("not an SCR denominator",panel,fixed=TRUE),"Direct constant result has evidence and explanation, never a zero waveform or response denominator")
 check(all(vapply(names0,function(n)grepl(n,panel,fixed=TRUE),logical(1)))&&refuses(brohn_eda_continuous_review_svg(model)),"All ten feature keys remain visible and direct SVG request refuses")
 cell<-list(status="raw_description_only",source_record_index=1L,feature_count=10L,original_default_bounds=list(start_s="0.1",end_s="120"))
 details<-html(.brohn_rpv_eda_details(list(details=cell),list(adapter="eda-continuous")))
 check(grepl("one explanatory panel",details,fixed=TRUE)&&!grepl("Change display window",details,fixed=TRUE)&&!grepl("0 saved candidates",details,fixed=TRUE),"Prepared constant catalog explains support without an editable window or zero response claim")
 check(.brohn_rpv_profiles(list(list(source_components=list("eda"))))$renderer_profile=="controlled-gaze-explicit-task-choice-eda-paired/0.2"&&.brohn_rpv_eda_profile("controlled-gaze-explicit-task-choice-eda-paired/0.1"),"New EDA profile is0.2 while saved0.1 remains recognized")
 # Actual Shiny controller; original-source authorization and queue are explicit spies.
 source_record<-list(id="report",revision=1L,project_id="default",body=body)
 state_env<-new.env();state_env$queued<-list();state_env$access<-TRUE
 brohn_get_entity<<-function(store,kind,id)source_record
 .brohn_qexplorer_catalog<<-function(...)stopifnot(state_env$access)
 brohn_eda_continuous_review_supported<<-function(body)TRUE
 brohn_list_entities<<-function(...)list()
 brohn_get_job<<-function(...)list(status="queued",error=NULL)
 brohn_eda_continuous_review_selection<<-function(analysis,selection){stopifnot(selection$recording_id=="recording-1");selection}
 brohn_queue_eda_continuous_review<<-function(store,id,revision,hash,selection,retry=FALSE){state_env$queued<-c(state_env$queued,list(selection));list(id="review-job",status="queued")}
 errors<-character()
 server<-function(input,output,session){state<-shiny::reactiveValues(page="report",report_id="report");attempt<-function(f)tryCatch(f(),error=function(e)errors<<-c(errors,conditionMessage(e)));brohn_install_eda_continuous_review(input,output,session,list(),state,attempt,function(...)NULL,function(f)f())}
 shiny::testServer(server,{
  session$flushReact();session$setInputs(open_eda_continuous_review=list(report_id="report",report_hash=.brohn_sv_hash(source_record$body)))
  identity<-brohn_json(record[c("recording_id","segment_id","channel")]);session$setInputs(eda_continuous_review_recording=identity,eda_continuous_review_start="10",eda_continuous_review_end="20",eda_continuous_review_candidate_start=999L)
  check(is.null(output$eda_continuous_review_window_controls)&&grepl("Prepare descriptive review",output$eda_continuous_review_selection_support$html,fixed=TRUE),"Constant selection hides editable window/candidate controls and offers descriptive review")
  session$setInputs(eda_continuous_review_prepare=1L)
  brohn_write_json_file(list(queued=state_env$queued,errors=as.list(errors)),file.path(out,"queue-diagnostic.json"))
  check(length(state_env$queued)==1L&&identical(state_env$queued[[1]]$start_s,"0.1")&&brohn_eda_decimal_compare(state_env$queued[[1]]$end_s,"120")==0L,"Stale window inputs cannot narrow a constant review; shortest exact original bounds queue")
  state_env$access<-FALSE;session$setInputs(eda_continuous_review_prepare=2L)
  check(length(state_env$queued)==1L&&length(errors)>0L,"Current original-source authorization remains required before queueing")
 })
 source_record$body<-ordinary;state_env$access<-TRUE;state_env$queued<-list()
 shiny::testServer(server,{
  session$flushReact();session$setInputs(open_eda_continuous_review=list(report_id="report",report_hash=.brohn_sv_hash(source_record$body)))
  session$setInputs(eda_continuous_review_recording=brohn_json(record[c("recording_id","segment_id","channel")]),eda_continuous_review_start="1.00000000000000000001",eda_continuous_review_end="20",eda_continuous_review_candidate_start=1L)
  check(grepl("Window start",output$eda_continuous_review_window_controls$html,fixed=TRUE)&&grepl("Prepare candidate window",output$eda_continuous_review_selection_support$html,fixed=TRUE),"Ordinary legacy support keeps its existing window and candidate controls")
  session$setInputs(eda_continuous_review_prepare=1L)
  check(identical(state_env$queued[[1]]$start_s,"1.00000000000000000001")&&identical(state_env$queued[[1]]$end_s,"20"),"Ordinary review keeps exact submitted window strings unchanged")
 })
 state_env$execution_reads<-0L;state_env$history_reads<-0L;state_env$held_input<-NULL
 selection<-c(record[c("recording_id","segment_id","channel")],list(start_s="1",end_s="20"))
 review<-list(id="historical-review",project_id="default",body=list(report_id="report",request=list(selection=selection),result=list(recording=ordinary$analysis$recordings[[1]]),exports=list(),result_object=list(hash=brohn_hash("old bytes"),size=1L)))
 brohn_eda_continuous_review_input<<-function(...){state_env$execution_reads<-state_env$execution_reads+1L;stop("Historical opening must not compare execution code")}
 .brohn_ecr_record_source<<-function(store,id,report_id,project_id){stopifnot(id==review$id,report_id=="report",project_id=="default");state_env$history_reads<-state_env$history_reads+1L;list(record=review,input=list(source_objects=list(),reader_only_stamp="exact original successful job"))}
 brohn_hold_signal_value_sources<<-function(store,input){state_env$held_input<-input;stop("Test stops before any real native hold or child launch")}
 shiny::testServer(server,{
  session$flushReact();session$setInputs(open_eda_continuous_review=list(report_id="report",report_hash=.brohn_sv_hash(source_record$body)))
  session$setInputs(eda_continuous_review_recording=brohn_json(record[c("recording_id","segment_id","channel")]),eda_continuous_review_start="1",eda_continuous_review_end="20",eda_continuous_review_candidate_start=1L)
  session$setInputs(eda_continuous_review_reopen=list(id=review$id,hash=.brohn_ecr_view_hash(review$body)));session$flushReact()
  check(state_env$execution_reads==0L&&state_env$history_reads>=2L&&identical(state_env$held_input$reader_only_stamp,"exact original successful job"),"Historical review uses the original-success reader input before native acquisition, never today's execution-code gate")
 })
}
failure<-tryCatch({main();NULL},error=function(e)conditionMessage(e))
unchanged<-identical(hashes,setNames(lapply(files,function(f)digest::digest(file=file.path(root,"R",f),algo="sha256")),files))
brohn_write_json_file(list(passed=is.null(failure)&&unchanged,checks=checks,error=failure,source_hashes=hashes,source_unchanged=unchanged,
 scope="Synthetic contract shapes and actual Shiny control flow with explicit source/catalog/queue spies. No scientific computation, native authority or service acceptance."),file.path(out,"results.json"))
if(!is.null(failure)||!unchanged)quit(status=1L)
