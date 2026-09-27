# Synthetic assembly fixtures; no store, app server, analysis job or device.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==2L)
external<-normalizePath(dirname(sub("^--file=","",grep("^--file=",commandArgs(),value=TRUE)[1L])),winslash="/",mustWork=TRUE)
component<-function(name)if(file.exists(file.path(external,name)))file.path(external,name)else file.path(if(grepl("\\.py$",name))"scripts/workers"else"R",name)
out<-args[[1L]];python<-args[[2L]];stopifnot(!file.exists(out));dir.create(out,recursive=TRUE)
out<-normalizePath(out,winslash="/",mustWork=TRUE)
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
source("R/platform-gaze-report-views.R",encoding="UTF-8")
source("R/platform-explicit-distribution-views.R",encoding="UTF-8")
source("R/platform-paired-plot-views.R",encoding="UTF-8")
source(component("platform-report-package-tables.R"),encoding="UTF-8")
source(component("platform-report-package-render.R"),encoding="UTF-8")
source("tests/fixtures/paired-results-fixture.R")
checks<-list();check<-function(label,value){stopifnot(isTRUE(value));checks[[length(checks)+1L]]<<-label;cat("PASS",label,"\n")}
ref<-function(body,kind="report")list(kind=kind,id=body$id,revision=1L,body_hash=brohn_hash(body),project_id="default")
f<-researcher_paired_fixture();d<-f$design
responses<-unlist(lapply(1:17,function(n)lapply(f$responses,function(r){r$participant_id<-paste0("PRIVATE-PERSON-",n,"-",r$participant_id);r$session_id<-paste0("PRIVATE-SESSION-",n,"-",r$session_id);r$exposure_id<-paste0("PRIVATE-EXPOSURE-",n,"-",r$exposure_id);r})),recursive=FALSE)
q<-brohn_question("Auxiliary Unicode <script> \u65e5\u672c\u8a9e",type="text",scope="after_each",id="q-extra");q$required<-FALSE;d$questions[[2L]]<-q
extra<-c(lapply(1:21,function(i)paste("Category",i)),list(FALSE,NULL,0,"0","",list(a=FALSE,b=NULL),"=HYPERLINK(\"https://example.invalid\")","<script>alert(1)</script> \u65e5\u672c\u8a9e"))
for(i in seq_along(extra))responses[[length(responses)+1L]]<-list(participant_id="PRIVATE-EXTRA",session_id="PRIVATE-EXTRA-SESSION",exposure_id=paste0("PRIVATE-EXTRA-",i),
  question_id="q-extra",prompt=q$prompt,condition_id="condition-a",stimulus_id="stimulus-a",value=extra[[i]],missing_reason=if(is.null(extra[[i]]))"optional_omission"else NULL)
qa<-brohn_questionnaire_analysis(responses,d)
qa$questionnaire_revision<-list(schema="brohn-questionnaire-revision-results/1.0",runs=list(list(schema="brohn-questionnaire-revision-projection/1.0",run_id="PRIVATE-EXTRA-SESSION",
  effective_records=list(responses[[length(responses)]]),history_records=list(list(event_id="PRIVATE-EVENT",sequence=1L,kind="commit",step_id="PRIVATE-STEP",occurrence_id="PRIVATE-OCCURRENCE",visit_id="PRIVATE-VISIT",state_version=1L,confirmation=FALSE,source_event_hash=brohn_hash("synthetic-history"))),
  history_events=list(list(id="PRIVATE-EVENT",sequence=1L,type="questionnaire_event",step_id="PRIVATE-STEP",payload=list(kind="commit",value=list(a=FALSE,b=NULL),occurrence_id="PRIVATE-OCCURRENCE",visit_id="PRIVATE-VISIT",state_version=1L),clock=list(instance_id="PRIVATE-CLOCK",time_origin_ms=0,value=1))),invalidations=list(),quality=list(event_count=1L,visit_count=1L))),interpretation="Synthetic complete typed history projection, not delivery qualification.")
report<-list(id="report-explicit",title="Saved explicit <script> \u65e5\u672c\u8a9e",study_id=d$id,origin="sample",created_at="2026-09-27T00:00:00Z",analysis=qa,provenance=list(design=d,design_hash=brohn_hash(d)))
rr<-ref(report)
gobs<-list();gfeatures<-list()
for(i in 1:14){
  common<-list(participant_id=paste0("PRIVATE-GAZE-",i),session_id=paste0("PRIVATE-GAZE-SESSION-",i),stimulus_id="stimulus-a",exposure_id=paste0("PRIVATE-GAZE-EXPOSURE-",i),condition_id="condition-a")
  gobs[[i]]<-c(common,list(aoi_id="logo-1",aoi_label="Logo",valid_ms=1000,inside_ms=250,valid_share_percent=25,fixation_dwell_ms=201,ttff_ms=NULL,ttff_status="left_boundary_candidate_onset_unknown",denominator="Valid interval time; no gap interpolation"))
  gfeatures<-c(gfeatures,lapply(seq_len(if(i==1L)201L else 2L),function(j)c(common,list(record_type="fixation_candidate",x=.25,y=.5,start_ms=as.numeric(j-1),end_ms=as.numeric(j),duration_ms=1,qualified=FALSE,aoi_ids=list("logo-1"),boundary_truncated=j==1))))
  gfeatures[[length(gfeatures)+1L]]<-c(common,list(record_type="exposure_summary",valid_interval_ms=1000,unobserved_interval_ms=200,sample_count=301,passive_sample_count=301,invalid_passive_sample_count=50,complete_observation=FALSE))
}
gaze<-list(id="report-gaze",title="Saved gaze context",study_id=d$id,origin="sample",analysis=list(kind="gaze",title="Saved gaze",observations=gobs,features=gfeatures,contrasts=list(),
  parameters=list(input="raw_gaze_samples",method="brohn-adjacent-ray-ivt/0.1.0-draft",coordinate_space="stimulus_normalized",geometry=list(width_mm=400,height_mm=300)),quality=list(qualified=FALSE),limitations=list("Synthetic unqualified fixation candidates.")),
  provenance=list(design=d,design_hash=brohn_hash(d),study_revision=1L,mapping=list(unit="stimulus_normalized",source_phase="passive_viewing_only"),source=list(hash=brohn_hash("synthetic-gaze"),size=1,filename="C:/private/original.csv")))
gr<-ref(gaze)
distribution<-brohn_build_explicit_distributions(responses,list(),d)
distribution$binding<-list(report_id=rr$id,report_hash=rr$body_hash,analysis_sha256=brohn_hash(qa),origin="sample")
dbody<-list(id="saved-distribution",schema="brohn-saved-explicit-distributions/1.0",report_id=rr$id,result=distribution);dr<-ref(dbody,"explicit_distributions")
intent<-list(kind="report_package_intent",id="intent-report",revision=1L,body_hash=brohn_hash("fixture-intent"),project_id="default")
section<-function(id,adapter,r,selector,display,order,source=r)list(id=id,adapter=adapter,adapter_version="0.1",source_report_ref=r,source_ref=source,selector=selector,display=display,order=order)
ed<-section("explicit","explicit-distribution",rr,list(scope="all_groups"),list(pages="all"),2L,dr);ed$resolved_group_ids<-lapply(distribution$groups,`[[`,"id")
sections<-list(section("gaze","gaze-context",gr,list(scope="all_exposures"),list(candidate_limit=200L),1L),ed,
  section("paired","paired-findings",rr,list(scope="exact_comparison",comparison_id="comparison-1",contrast_hash=brohn_hash(qa$contrasts[[1L]])),list(charts=list("means","differences"),pages="all"),3L))
selection<-list(schema="brohn-report-package-selection/0.1",id="selection-report",intent_ref=intent,study_id=d$id,project_id="default",title="Control and concept \u2014 \u65e5\u672c\u8a9e <script>",
  report_refs=list(gr,rr),display_refs=list(dr),sections=sections,contents_policy=list(profile="complete-findings/0.1",audience="research_team",identifier_mode="package_aliases",stimulus_images="excluded_by_choice",complete_selected_numerical_evidence=TRUE,include_original_evidence=FALSE,include_raw_recordings=FALSE),
  limits_profile="controlled-report-package/0.1",renderer_profile="controlled-gaze-explicit-paired/0.1",frozen_at="2026-09-27T00:00:00Z",coverage=list())
owned<-c("platform-report-package-render.R","platform-report-package-tables.R","report_package_archive.py","report_package_raster.py")
sources<-setNames(lapply(owned,function(name)digest::digest(file=component(name),algo="sha256")),c("R/platform-report-package-render.R","R/platform-report-package-tables.R","scripts/workers/report_package_archive.py","scripts/workers/report_package_raster.py"))
implementation<-list(schema="brohn-report-package-implementation/0.1",profile="static-complete-findings/0.1",sources=sources,
  runtime=list(R=as.character(getRversion()),jsonlite=as.character(packageVersion("jsonlite")),htmltools=as.character(packageVersion("htmltools")),
    Python=brohn_parse(processx::run(python,c("-c","import json,platform; print(json.dumps(dict(implementation=platform.python_implementation(),version=platform.python_version())))"))$stdout),
    Pillow=trimws(processx::run(python,c("-c","import PIL; print(PIL.__version__)"))$stdout)),archive_python=python,archive_script=normalizePath(component("report_package_archive.py"),winslash="/"),raster_script=normalizePath(component("report_package_raster.py"),winslash="/"))
bundle<-list(schema="brohn-report-package-render-input/0.1",selection=selection,reports=list(list(ref=gr,saved_body=gaze,complete_analysis=gaze$analysis),list(ref=rr,saved_body=report,complete_analysis=qa)),
  distributions=list(list(ref=dr,body=dbody)),assets=list(),implementation=implementation,limits=brohn_report_package_limits())
.brohn_rp_write(bundle,file.path(out,"fixture-bundle.json"),TRUE)
# Scientific setup above is separate. Any accidental scientific call while
# packaging is an explicit failure, including display-distribution aggregation.
for(fn in c("brohn_questionnaire_analysis","brohn_build_explicit_distributions","brohn_raw_gaze_analysis","brohn_gaze_analysis","brohn_paired_contrasts","brohn_score_scales","brohn_analyse_multimodal"))assign(fn,function(...)stop("Scientific route called by package assembler"),.GlobalEnv)
before<-brohn_hash(bundle);result<-brohn_render_report_package(bundle,file.path(out,"first"))
check("complete assembly leaves all original fixture values unchanged",identical(brohn_hash(bundle),before))
.brohn_rp_write(result,file.path(out,"render-result.json"),TRUE)
check("fourteen selected gaze exposures are not reduced to twelve",result$coverage[[1L]]$selected_exposures==14L&&result$coverage[[1L]]$selected_figures==14L)
check("paired charts include person51 with both saved chart kinds",result$coverage[[3L]]$selected_figures==4L)
paired<-brohn_parse(paste(readLines(file.path(out,"first/data/paired/section-003-comparison-001.json"),warn=FALSE,encoding="UTF-8"),collapse="\n"))
check("saved equal-person8 estimate and51people68pairedvisits remain exact",paired$saved_contrast$estimate==8&&length(paired$people)==51L&&sum(vapply(paired$sessions,`[[`,logical(1),"paired"))==68L)
check("unpaired visits and complete source observations survive",length(paired$sessions)==85L&&length(paired$observations)==272L)
proj<-brohn_parse(paste(readLines(file.path(out,"first/evidence/report-02.json"),warn=FALSE,encoding="UTF-8"),collapse="\n"))
check("complete effective observations and typed history survive",length(proj$analysis$observations)==length(responses)&&length(proj$analysis$questionnaire_revision$runs[[1L]]$history_events)==1L)
check("typedfalse/null/zero/textzero/empty/object values survive exactly",.brohn_rp_same(lapply(tail(proj$analysis$observations,8L),`[[`,"value"),tail(extra,8L)))
old_options<-options(OutDec=",",scipen=99);second<-brohn_render_report_package(bundle,file.path(out,"second"));options(old_options)
check("fresh output directory and different formatting options produce identical payload hashes",.brohn_rp_same(result$files,second$files))
check("pure assembly is byte deterministic including archive",.brohn_rp_same(result$manifest,second$manifest))
rejected<-function(b,name,pattern){e<-tryCatch({brohn_render_report_package(b,file.path(out,name));NULL},error=function(e)conditionMessage(e));check(name,!is.null(e)&&grepl(pattern,e,fixed=TRUE));e}
bad<-bundle;bad$reports[[2L]]$complete_analysis$new_required_measure<-17;rejected(bad,"changed-analysis-refusal","Inline analysis changed")
bad<-bundle;bad$reports[[2L]]$saved_body$analysis$new_required_measure<-17;bad$reports[[2L]]$complete_analysis<-bad$reports[[2L]]$saved_body$analysis
bad$reports[[2L]]$ref<-ref(bad$reports[[2L]]$saved_body);bad$selection$report_refs[[2L]]<-bad$reports[[2L]]$ref
rejected(bad,"unknown-scientific-refusal","unsupported fields")
bad<-bundle;bad$limits$max_panels<-1L;rejected(bad,"panel-bound-refusal","Selected figure pages exceed")
bad<-bundle;bad$limits$max_html_bytes<-1024L;rejected(bad,"html-bound-refusal","standalone HTML bound")
bad<-bundle;bad$selection$contents_policy$profile<-"complete-findings-with-original-evidence/0.1";rejected(bad,"optional-original-profile-refusal","Original-byte report packages are unavailable")
bad<-bundle;bad$selection$sections[[3L]]$selector$contrast_hash<-brohn_hash("wrong");rejected(bad,"contrast-identity-refusal","Saved contrast identity changed")
bad<-bundle;bad$selection$sections[[1L]]$selector<-list(scope="exact_exposure",exposure_key=paste(rep("0",64),collapse=""));rejected(bad,"exposure-identity-refusal","selected exposure does not belong")
focused<-bundle;groups<-Filter(function(g)length(g$categories)>20L,distribution$groups);stopifnot(length(groups)==1L);group<-groups[[1L]]
focused$selection$sections[[1L]]$selector<-list(scope="exact_exposure",exposure_key=brohn_gaze_report_model(gaze)$groups[[14L]]$key)
focused$selection$sections[[2L]]$selector<-list(scope="exact_item_condition",family=group$family,item_id=group$item_id,condition_id=group$condition_id)
focused$selection$sections[[2L]]$resolved_group_ids<-list(group$id);focused$selection$sections[[2L]]$display<-list(pages="selected",offsets=list(20L))
focused$selection$sections[[3L]]$display<-list(charts=list("means","differences"),pages="selected",page_numbers=list(2L))
focused_result<-brohn_render_report_package(focused,file.path(out,"focused"))
check("exact exposure14/categorypage2/personpage2 produces all four selected figures",sum(vapply(focused_result$coverage,`[[`,numeric(1),"selected_figures"))==4L)
check("focused figures retain identical complete typed numerical projections",identical(digest::digest(file=file.path(out,"first/evidence/report-02.json"),algo="sha256"),digest::digest(file=file.path(out,"focused/evidence/report-02.json"),algo="sha256")))
source_labels<-focused;source_labels$selection$contents_policy$identifier_mode<-"source_identifiers"
label_result<-brohn_render_report_package(source_labels,file.path(out,"source-identifiers"))
labels<-brohn_parse(paste(readLines(file.path(out,"source-identifiers/evidence/report-02.json"),warn=FALSE,encoding="UTF-8"),collapse="\n"))
check("explicit original-label choice preserves all original analysis exactly",.brohn_rp_same(labels$analysis,qa))
duplicate<-focused;duplicate$selection$sections[[4L]]<-focused$selection$sections[[3L]];duplicate$selection$sections[[4L]]$id<-"paired-again";duplicate$selection$sections[[4L]]$order<-4L
duplicate_result<-brohn_render_report_package(duplicate,file.path(out,"duplicate-panels"))
check("repeated comparison panels retain deliberate selection",sum(vapply(duplicate_result$coverage,`[[`,numeric(1),"selected_figures"))==6L)
# Actual helper invocation from the R raster adapter for both supported formats.
image_cache<-new.env(parent=emptyenv());scratch<-file.path(out,"job-0000000000000000000000000000000000000000000000000000000000000000","attempt-00000000000000000000000000000000","artifacts",".private");dir.create(scratch,recursive=TRUE);assign(".scratch",scratch,image_cache)
for(format in c("PNG","JPEG")){
  path<-file.path(out,paste0("test.",tolower(format)))
  processx::run(python,c("-c","from PIL import Image; import sys; Image.new('RGB',(8,6),(80,120,160)).save(sys.argv[1],format=sys.argv[2])",path,format))
  bytes<-readBin(path,"raw",file.info(path)$size);hash<-digest::digest(bytes,algo="sha256",serialize=FALSE)
  stimulus<-list(id="synthetic-image",asset=list(hash=hash,size=length(bytes),media_type=if(format=="PNG")"image/png"else"image/jpeg",width=8,height=6))
  images<-bundle;images$assets<-list(list(ref=list(hash=hash,bytes=length(bytes),media_type=stimulus$asset$media_type),path=path,stimulus_refs=list(list(report_ref=gr,stimulus_id=stimulus$id))))
  shown<-.brohn_rp_asset(images,list(ref=gr),stimulus,"included",image_cache)
  check(paste("R adapter actually decodes and embeds exact",format),identical(base64enc::base64decode(sub("^data:[^,]+,","",shown$uri)),bytes))
  check(paste("R adapter preserves immutable bytes",format),identical(readBin(path,"raw",file.info(path)$size),bytes))
  bad_stimulus<-stimulus;bad_stimulus$asset$width<-9
  err<-tryCatch({.brohn_rp_asset(images,list(ref=gr),bad_stimulus,"included",image_cache);NULL},error=conditionMessage)
  check(paste("cache never hides inconsistent saved dimensions",format),!is.null(err)&&grepl("Repeated raster dimensions",err,fixed=TRUE))
  check(paste("excluded image gives labelled frame without raster use",format),is.null(.brohn_rp_asset(images,list(ref=gr),stimulus,"excluded_by_choice",image_cache)$uri))
}
.brohn_rp_write(list(schema="brohn-report-package-pure-tests/0.1",passed=TRUE,checks=checks,check_count=length(checks),
  qualification="Pure synthetic render/projection/archive checks only. No source authority, worker publication, research collection or physical device qualification.",sources=sources),file.path(out,"results.json"),TRUE)
cat("Report package pure checks:",length(checks),"passed\n")
