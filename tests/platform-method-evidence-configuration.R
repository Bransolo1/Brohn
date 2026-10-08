# Repository-owned configuration views/input contracts, actual loader only.
local({
args<-commandArgs(TRUE);stopifnot(length(args)==2L)
checkout<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE)
out<-normalizePath(args[[2L]],winslash="/",mustWork=FALSE)
stopifnot(!dir.exists(out));dir.create(out,recursive=TRUE)
before_wd<-getwd();on.exit(setwd(before_wd),add=TRUE);setwd(checkout)
env<-new.env(parent=globalenv());source("R/platform-load.R",local=env,encoding="UTF-8");env$brohn_load(env,ui=TRUE)
files<-c("platform-method-evidence-config-views.R","platform-eda-events-views.R","platform-neural-views.R",
 "platform-data-views.R","platform-peripheral-views.R","platform-gaze-views.R")
checks<-list();start<-proc.time()[["elapsed"]]
save<-function(status)jsonlite::write_json(list(status=status,checks=checks,count=length(checks),
  elapsed_s=proc.time()[["elapsed"]]-start,scope="Pure configuration views and existing input/default contracts; no jobs, stores or scientific estimates.",
  sources=lapply(files,function(f)list(path=paste0("R/",f),sha256=digest::digest(file=file.path("R",f),algo="sha256")))),
  file.path(out,"RESULTS.json"),auto_unbox=TRUE,pretty=TRUE,null="null")
ok<-function(name,value){checks[[length(checks)+1L]]<<-list(name=name,passed=isTRUE(value));save(if(isTRUE(value))"running"else"failed");if(!isTRUE(value))stop(name,call.=FALSE)}
refuse<-function(name,expr)ok(name,tryCatch({force(expr);FALSE},error=function(e)TRUE))
html<-function(x)as.character(htmltools::renderTags(x)$html)
tags<-function(x){if(inherits(x,"shiny.tag"))return(c(list(x),unlist(lapply(x$children,tags),recursive=FALSE)))
  if(is.list(x))return(unlist(lapply(x,tags),recursive=FALSE));list()}
selected<-function(x,id){n<-Filter(function(t)identical(t$name,"select")&&identical(t$attribs$id,id),tags(x));stopifnot(length(n)==1L)
  # Shiny emits options as retained HTML, not necessarily individual tag objects.
  h<-html(n[[1L]]);z<-regmatches(h,gregexpr('<option[^>]*[[:space:]]selected([^[:alnum:]_]|$)[^>]*>',h,perl=TRUE))[[1L]]
  stopifnot(length(z)==1L,grepl('value="[^"]*"',z))
  unname(sub('^.*value="([^"]*)".*$','\\1',z))}
conditions<-function(x)vapply(Filter(function(t)!is.null(t$attribs[["data-display-if"]]),tags(x)),function(t)t$attribs[["data-display-if"]],character(1))
ok("Actual UI loader supplies all configuration functions in the shared environment",all(vapply(c("brohn_method_evidence_config_ui","brohn_eda_events_settings_ui","brohn_neural_settings_ui","brohn_dataset_detail_ui","brohn_peripheral_settings_ui","brohn_raw_gaze_settings_ui"),function(n)exists(n,envir=env,inherits=FALSE)&&identical(environment(env[[n]]),env),logical(1))))
ok("Revised exact pinned reference remains ready",env$.brohn_method_evidence_app$status=="ready"&&env$.brohn_method_evidence_app$ref$sha256=="cd63ffb8eaa1a2c73b08dddd93573c5fedeb266f6cad8aadc22c5759b22dd9b0")
for(family in c("eda","eeg")){
  view<-if(family=="eda")env$brohn_eda_events_settings_ui else env$brohn_neural_settings_ui
  choices<-if(family=="eda")unname(env$brohn_eda_events_recipe_choices()) else unname(env$brohn_neural_recipe_choices())
  id<-if(family=="eda")"map_eda_event_recipe"else"map_neural_recipe"
  default<-choices[[1]]
  for(m in list(list(),list(parameters=NULL),list(parameters=list()),list(parameters=list(recipe=NULL))))
    ok(paste(family,"existing default selection",length(checks)),identical(selected(view(m),id),default))
  for(ref in choices){
    m<-list(parameters=list(recipe=ref));original<-m;x<-view(m);h<-html(x)
    ok(paste(ref,"exact selected value and live guidance condition"),identical(selected(x,id),ref)&&
      any(conditions(x)==paste0("input.",id," === ",as.character(jsonlite::toJSON(ref,auto_unbox=TRUE)))))
    ok(paste(ref,"under-review disclosure and input conservation"),identical(m,original)&&grepl("not an evidence snapshot saved with this study",h,fixed=TRUE)&&grepl("chosen numerical settings still need review",h,fixed=TRUE))
  }
}
legacy<-list(parameters=list(recipe="eeg-morlet-epochs/1.0"));x<-env$brohn_neural_settings_ui(legacy)
ok("Existing Morlet new-mapping transition remains explicit and original untouched",identical(selected(x,"map_neural_recipe"),"eeg-morlet-epochs/1.1")&&legacy$parameters$recipe=="eeg-morlet-epochs/1.0"&&grepl("saved Morlet 1.0 result keeps its original",html(x),fixed=TRUE))
chosen<-list(parameters=list(recipe="eda-event-highpass/1.0",minimum_scr_amplitude_us=.08));chosen_before<-chosen
x<-env$brohn_eda_events_settings_ui(chosen)
amplitude<-Filter(function(t)identical(t$attribs$id,"map_eda_event_minimum_amplitude"),tags(x))
ok("Chosen numeric amplitude is retained without evidence qualification",length(amplitude)==1L&&as.numeric(amplitude[[1]]$attribs$value)==.08&&identical(chosen,chosen_before)&&grepl("chosen numerical settings still need review",html(x),fixed=TRUE))
unknown<-html(env$brohn_method_evidence_config_ui("ecg-neurokit-detected-rr/99.0"))
ok("Unknown exact version inherits no academic links",grepl("No option-level evidence entry",unknown,fixed=TRUE)&&!grepl("href=",unknown,fixed=TRUE))
future<-env$brohn_method_evidence_selector_ui("future_recipe",c("ecg-neurokit-detected-rr/99.0"))
ok("Future registered selector value still has no inherited sources",!grepl("href=",html(future),fixed=TRUE)&&grepl("!input.future_recipe",paste(conditions(future),collapse="\n"),fixed=TRUE))
ok("Unknown live selector receives separate unavailable guidance",grepl("No academic guidance is linked here",html(future),fixed=TRUE)&&any(grepl("indexOf(input.future_recipe) === -1",conditions(future),fixed=TRUE)))
refuse("Invalid dynamic input IDs cannot form a guidance condition",env$brohn_method_evidence_selector_ui("x';alert(1)","a/1"))
for(modality in c("ecg","ppg")){
  h<-html(env$brohn_method_evidence_cardiac_mapping_ui(modality));ref<-if(modality=="ecg")"ecg-neurokit-detected-rr/1.0"else"ppg-elgendi-detected-prv/1.0"
  ok(paste(modality,"fixed new-mapping guide has exact recipe and scope"),grepl(ref,h,fixed=TRUE)&&grepl("used by Confirm mapping and analyse",h,fixed=TRUE)&&grepl("does not describe a different saved mapping",h,fixed=TRUE))
  ok(paste(modality,"visible physiological distinction"),grepl(if(modality=="ecg")"not confirmed normal-to-normal (NN)"else"not ECG heart-rate variability",h,fixed=TRUE))
  for(p in list(NULL,list(),list(recipe=NULL),list(recipe="future/9"),list(recipe=ref,frequency_min_duration_s=900))){
    d<-list(modality=modality,source=list(format="csv"),metadata=list(parameters=p));original<-d
    m<-env$brohn_dataset_base_mapping(list(map_values="signal",map_time="time",map_sampling_rate=100),d)
    ok(paste(modality,"existing Confirm mapping omits parameters and preserves saved source",length(checks)),!"parameters"%in%names(m)&&identical(d,original))
  }
}
temp<-env$brohn_peripheral_settings_ui(list(parameters=list(recipe="future-temperature/9",minimum_duration_s=30)),c("time","temp"),"temperature")
ok("Temperature guide explicitly describes current Confirm mapping, not future saved recipe",grepl("temperature-calibrated-descriptive/1.0",html(temp),fixed=TRUE)&&grepl("chosen minimum duration still needs study-specific review",html(temp),fixed=TRUE))
ok("Automatic peripheral duration still resolves from existing parser",identical(env$brohn_peripheral_parameters(list(sampling_rate=.5),"temperature")$minimum_duration_s,2))
refuse("Explicit NULL peripheral recipe remains refused",env$brohn_peripheral_parameters(list(sampling_rate=10,parameters=list(recipe=NULL)),"temperature"))
refuse("Explicit NULL peripheral duration remains distinct from missing",env$brohn_peripheral_parameters(list(sampling_rate=10,parameters=list(minimum_duration_s=NULL)),"temperature"))
gaze<-env$brohn_raw_gaze_settings_ui(list(),c("time","pupil"));h<-html(gaze)
ok("Pupil guidance remains below all three actual conditional controls",all(c("input.map_gaze_representation === 'samples'","input.map_pupil && input.map_pupil !== ''","input.map_pupil_baseline_mode === 'subtractive'")%in%conditions(gaze)))
ok("Gaze detector scope does not borrow pupil qualification",grepl("Academic guidance for these detection settings is still being linked",h,fixed=TRUE)&&grepl("Guidance for the chosen pupil baseline only",h,fixed=TRUE))
cards<-env$brohn_method_evidence_cards(env$.brohn_method_evidence_app$registry,"brohn-adjacent-ray-ivt/0.1.0-draft")$cards
ok("Pinned raw-gaze card set contains pupil coverage/duration only",length(cards)==2L&&all(vapply(cards,function(c)identical(c$binding$input_scope,"mapping.pupil_baseline"),logical(1)))&&setequal(vapply(cards,function(c)c$binding$option_path,character(1)),c("/minimum_coverage","/minimum_duration_ms")))
missing<-env$brohn_method_evidence_host_load(out)
h<-html(env$brohn_method_evidence_config_ui("eeg-welch-channel/1.0",state=missing))
ok("Missing reference has loading-failure state, never inherited known cards",grepl("reference_loading_failed",h,fixed=TRUE)&&grepl("not a statement that this procedure has no evidence",h,fixed=TRUE)&&!grepl("href=",h,fixed=TRUE))
ok("Data guidance owns the unchanged scoped wrapping style",grepl("overflow-wrap:anywhere",html(env$brohn_method_evidence_config_ui("eeg-welch-channel/1.0")),fixed=TRUE))
ok("Action distinction explicitly preserves saved rerun semantics",grepl("last confirmed mapping",html(env$brohn_method_evidence_mapping_actions_ui()),fixed=TRUE))
ok("Temperature measured quantity is recorded calibrated temperature at a declared location",
 grepl("Recorded temperature in declared calibrated units and sensor location",html(temp),fixed=TRUE)&&
 grepl("Explicit skin/site identity; retain ambient/core signals as their own quantities",html(temp),fixed=TRUE))
ok("Temperature support does not imply thermal settling or a universal stress signal",
 grepl("does not establish thermal settling",html(temp),fixed=TRUE)&&
 grepl("not a measured experimental baseline or universal stress signal",html(temp),fixed=TRUE))
ok("Current ECG guidance includes the corrected interval-count applicability gap",
 grepl("the interval-count denominator alone does not require a different estimator",
 html(env$brohn_method_evidence_cardiac_mapping_ui("ecg")),fixed=TRUE))
save("passed");cat(length(checks),"pure checks passed\n")

})
