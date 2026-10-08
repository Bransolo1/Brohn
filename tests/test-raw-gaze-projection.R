# Portable small synthetic transport/registration checks; no scientific analysis.
args<-commandArgs(TRUE);stopifnot(length(args)>=4L)
checkout<-args[[1L]];module_root<-args[[2L]];profiles<-args[[3L]];out<-args[[4L]]
setwd(checkout);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
baseline_projection<-.brohn_rp_projection;baseline_keys<-.brohn_rp_scientific_keys;source_keys<-.brohn_rpk_scientific_keys
source(profiles,encoding="UTF-8")
for(f in c("platform-report-package-raw-gaze.R","platform-report-package-tables.R","platform-report-package-sources.R","platform-eda-display-sources.R","platform-report-package-cardiac.R","platform-report-package-cardiac-sources.R","platform-report-package-cardiac-render.R"))source(file.path(module_root,"R",f),encoding="UTF-8")
checks<-character();failure<-NULL
check<-function(n,x){if(!isTRUE(x))stop(n,call.=FALSE);checks<<-c(checks,n);cat("PASS",n,"\n")}
deny<-function(n,expr)check(n,inherits(tryCatch(force(expr),error=identity),"error"))
seal<-function(item){item$saved_body$analysis<-item$complete_analysis;item$ref$body_hash<-brohn_hash(item$saved_body);item}
fixture<-function(){
 d<-brohn_new_design("Synthetic projection grammar",id="raw-gaze-fixture")
 thresholds<-list(velocity_threshold_deg_s=30,min_fixation_ms=60,min_saccade_ms=10,max_gap_ms=20,threshold_source="Synthetic grammar fixture; not measured or qualified.")
 common<-list(participant_id="synthetic-person",session_id="synthetic-session",stimulus_id="stimulus-a",exposure_id="synthetic-exposure",condition_id="condition-a")
 a<-list(kind="gaze",features=list(c(common,list(record_type="fixation_candidate",classification="low_velocity",angular_path_deg=-0.0,qualified=FALSE,start_ms=0,end_ms=200,duration_ms=200))),
   observations=list(c(common,list(aoi_id="fixture-aoi",ttff_ms=NULL))),contrasts=list(),quality=list(qualified=FALSE),limitations=list("Synthetic unqualified transport fixture."),
   parameters=list(input="raw_gaze_samples",method=.brohn_rpg_method,blink_boundary_policy="source-labelled-blink-boundaries/1.1",coordinate_space="stimulus_normalized",time_unit="ms",interpolation="none",smoothing="none",merging="none",thresholds=thresholds,pupil_baseline=NULL))
 b<-list(id="report-raw-gaze-fixture",title="Synthetic raw-gaze export",origin="sample",study_id=d$id,analysis=a,
   processing=list(recipe="brohn-analysis/1.0.0-draft",code_hashes=setNames(list(.brohn_rpg_gaze_sha),"R/platform-gaze.R")),
   provenance=list(design=d,design_hash=brohn_hash(d),engine=list(name="Brohn R",version="1.0.0-draft"),mapping=list(parameters=thresholds)))
 list(ref=list(kind="report",id=b$id,revision=1L,body_hash=brohn_hash(b),project_id="default"),saved_body=b,complete_analysis=a)
}
mutate<-function(f){x<-fixture();x<-f(x);seal(x)}
validate<-function(x)brohn_validate_saved_raw_gaze_projection(x,.brohn_rpg_profile)
project<-function(x,admission="task-choice-eda-findings/0.3") .brohn_rp_projection(x,.brohn_rp_alias_context("source_identifiers",list(x)),"report-01",source_admission=admission)
tryCatch({
 item<-fixture();before<-brohn_eda_value_hash(item)
 check("standalone explicit raw-gaze profile validates",isTRUE(validate(item)))
 output<-project(item)
 check("every typed original scientific value is unchanged",identical(brohn_eda_value_hash(output$analysis),brohn_eda_value_hash(item$complete_analysis)))
 check("signed zero survives angular path export",is.infinite(1/output$analysis$features[[1]]$angular_path_deg)&&1/output$analysis$features[[1]]$angular_path_deg<0)
 check("optional null versus absence survives export",is.null(output$analysis$observations[[1]]$ttff_ms)&&"ttff_ms"%in%names(output$analysis$observations[[1]])&&!"estimate"%in%names(output$analysis$observations[[1]]))
 check("registration exists only in portable provenance",identical(output$provenance$projection_registration$profile,.brohn_rpg_profile)&&!"projection_registration"%in%names(output$analysis)&&identical(before,brohn_eda_value_hash(item)))
 check("global closed vocabularies unchanged",identical(baseline_keys,.brohn_rp_scientific_keys)&&identical(source_keys,.brohn_rpk_scientific_keys))
 check("standalone API does not require a cardiac source",identical(brohn_report_package_raw_gaze_projection(item,.brohn_rp_alias_context("source_identifiers",list(item)),"report-01",.brohn_rpg_profile),output))
 check("source admission validates new noncardiac profile",isTRUE(brohn_validate_complete_report_analysis(item,"task-choice-eda-findings/0.3")))
 deny("old EDA profile refuses the additional original fields",project(item,"task-choice-eda-findings/0.2"))
 deny("old complete source admission remains closed",brohn_validate_complete_report_analysis(item,"task-choice-eda-findings/0.2"))
 deny("unknown explicit projection version refuses",brohn_validate_saved_raw_gaze_projection(item,"saved-raw-gaze-projection/9"))
 old<-item;old$complete_analysis$parameters$input<-"legacy_saved_observations";old$complete_analysis$parameters$thresholds$threshold_source<-NULL;old$complete_analysis$features[[1]]$classification<-NULL;old$complete_analysis$features[[1]]$angular_path_deg<-NULL;old<-seal(old)
 prior<-baseline_projection(old,.brohn_rp_alias_context("source_identifiers",list(old)),"report-01",source_admission="task-choice-eda-findings/0.2")
 check("already admitted nonraw projection bytes remain exact",identical(brohn_json(prior),brohn_json(project(old,"task-choice-eda-findings/0.2")))&&identical(brohn_json(prior),brohn_json(project(old))))
 for(change in list(
   family=function(x){x$complete_analysis$kind<-"questionnaire";x},
   input=function(x){x$complete_analysis$parameters$input<-"unknown";x},
   method=function(x){x$complete_analysis$parameters$method<-"unknown";x},
   producer_recipe=function(x){x$saved_body$processing$recipe<-"brohn-analysis/9";x},
   producer_hash=function(x){x$saved_body$processing$code_hashes[["R/platform-gaze.R"]]<-paste(rep("0",64),collapse="");x},
   engine=function(x){x$saved_body$provenance$engine$version<-"9";x},
   blink=function(x){x$complete_analysis$parameters$blink_boundary_policy<-"unknown";x},
   thresholds=function(x){x$saved_body$provenance$mapping$parameters$threshold_source<-"changed";x},
   unknown_field=function(x){x$complete_analysis$features[[1]]$new_science<-1;x},
   wrong_path=function(x){x$complete_analysis$observations[[1]]$classification<-"low_velocity";x},
   wrong_family_record=function(x){x$complete_analysis$features[[1]]$record_type<-"exposure_summary";x},
   class_mismatch=function(x){x$complete_analysis$features[[1]]$classification<-"high_velocity";x},
   qualified=function(x){x$complete_analysis$features[[1]]$qualified<-TRUE;x},
   missing_class=function(x){x$complete_analysis$features[[1]]$classification<-NULL;x},
   null_angle=function(x){x$complete_analysis$features[[1]]["angular_path_deg"]<-list(NULL);x}
 ))deny(paste("registered semantic mutation refuses",deparse(substitute(change))),validate(mutate(change)))
 for(value in list(-1,Inf,NaN,TRUE,"0"))deny(paste("invalid angular type/value refuses",brohn_json(if(is.numeric(value)&&!is.finite(value))"nonfinite"else value)),validate(mutate(function(x){x$complete_analysis$features[[1]]$angular_path_deg<-value;x})))
 for(kind in c("saccade_candidate","short_unclassified_segment")){
   x<-mutate(function(x){x$complete_analysis$features[[1]]$record_type<-kind;x$complete_analysis$features[[1]]$classification<-"high_velocity";x$complete_analysis$features[[1]]$angular_path_deg<-18.924644416051233;x})
   check(paste("registered original candidate class preserved",kind),isTRUE(validate(x))&&identical(brohn_eda_value_hash(project(x)$analysis),brohn_eda_value_hash(x$complete_analysis)))
 }
 check("new outer admission maps only to unchanged EDA scientific profile",identical(.brohn_rpk_algorithm_admission("task-choice-eda-findings/0.3"),"task-choice-eda-findings/0.2")&&is.null(.brohn_rpg_admission_profile("task-choice-eda-findings/0.2")))
 if(length(args)>=5L){
   b<-brohn_eda_read_json_file(args[[5L]],16*1024^2);x<-list(ref=list(kind="report",id=b$id,revision=1L,body_hash=brohn_hash(b),project_id="default"),saved_body=b,complete_analysis=b$analysis)
   original_hash<-brohn_eda_value_hash(x);p<-project(x)
   check("genuine mixed source all science preserved under new registration",identical(brohn_eda_value_hash(p$analysis),brohn_eda_value_hash(x$complete_analysis)))
   check("genuine threshold source and candidate status retained",identical(p$analysis$parameters$thresholds$threshold_source,x$complete_analysis$parameters$thresholds$threshold_source)&&identical(original_hash,brohn_eda_value_hash(x)))
   brohn_write_json_file(p,file.path(out,"genuine-projection.json"),16*1024^2)
   .brohn_rp_csv(p$analysis$features,file.path(out,"genuine-features.csv"))
 }
},error=function(e){failure<<-conditionMessage(e);cat("FAILED",failure,"\n")})
brohn_write_json_file(list(passed=is.null(failure),count=length(checks),checks=as.list(checks),failure=failure,scope="Pure synthetic registered projection controls plus optional saved genuine source; no native/scientific jobs."),file.path(out,"RESULTS.json"))
if(!is.null(failure))stop(failure,call.=FALSE)
