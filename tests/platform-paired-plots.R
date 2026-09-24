source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
source("R/platform-paired-plots.R",encoding="UTF-8");source("R/platform-paired-plot-views.R",encoding="UTF-8")
source("R/platform-data-views.R",encoding="UTF-8");source("R/platform-shell.R",encoding="UTF-8")
source("tests/fixtures/paired-results-fixture.R")
local({
  checks<-0L;check<-function(name,ok){if(!isTRUE(ok))stop(paste("Paired plots:",name));checks<<-checks+1L;cat("PASS",name,"\n")}
  near<-function(a,b)isTRUE(all.equal(a,b,tolerance=1e-12));rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
  f<-researcher_paired_fixture();brohn_validate_design(f$design)
  a<-brohn_questionnaire_analysis(f$responses,f$design)
  body<-list(id="report-original",study_id=f$design$id,origin="sample",analysis=a,provenance=list(design=f$design,design_hash=brohn_hash(f$design)))
  original_hash<-brohn_hash(body);m<-brohn_paired_plot_model(body,"comparison-1")
  check("original complete ratings reproduce three equal people and four paired visits",m$status=="verified"&&m$saved_contrast$estimate==8&&length(m$people)==3&&sum(vapply(m$sessions,`[[`,logical(1),"paired"))==4)
  check("repeat-person means use only equally weighted paired visits",near(vapply(m$people,`[[`,numeric(1),"control_mean"),c(11,10,10))&&near(vapply(m$people,`[[`,numeric(1),"test_mean"),c(15,18,22))&&near(vapply(m$people,`[[`,numeric(1),"difference"),c(4,8,12)))
  check("complete original rows and unpaired visits remain explicit",length(m$observations)==16&&length(m$sessions)==5&&is.null(m$sessions[[5]]$difference)&&m$sessions[[5]]$reason=="condition_pair_unavailable")
  check("missing values and other conditions cannot become zero or selected values",sum(vapply(m$observations,function(r)is.null(r$value),logical(1)))==2&&sum(vapply(m$observations,function(r)identical(r$missing_reason,"outside_selected_conditions"),logical(1)))==5)
  check("saved uncertainty and original report are untouched",identical(m$saved_contrast,body$analysis$contrasts[[1]])&&identical(brohn_hash(body),original_hash))
  alternative<-brohn_paired_plot_model(body,"comparison-2")
  check("only existing condition pairs are selectable and keep their own evidence",alternative$status=="verified"&&alternative$saved_contrast$estimate==13&&rejects(brohn_paired_plot_model(body,"invented-comparison")))
  altered<-body;altered$analysis$observations[[3]]$value<-999
  check("saved comparison disagreement blocks every paired mark",brohn_paired_plot_model(altered,"comparison-1")$reason=="complete_source_disagrees_with_saved_comparison")
  altered<-body;altered$analysis$observations[[2]]$exposure_id<-altered$analysis$observations[[1]]$exposure_id
  check("ambiguous repeated exposure identity is refused",brohn_paired_plot_model(altered,"comparison-1")$reason=="duplicate_or_ambiguous_observation_identity")
  altered<-body;altered$analysis$observations[[1]]$participant_id<-NULL
  check("a row number cannot manufacture person linkage",brohn_paired_plot_model(altered,"comparison-1")$reason=="paired_person_or_visit_identity_unavailable")
  altered<-body;altered$analysis$observations[[1]]$exposure_id<-NULL
  check("source exposure identity is required for condition means",brohn_paired_plot_model(altered,"comparison-1")$reason=="complete_observation_identity_unavailable")
  altered<-body;altered$analysis$contrasts[[1]]$estimate<-NULL;altered$analysis$contrasts[[1]]$reason<-"participant_identity_not_established"
  check("an unavailable saved result cannot acquire reconstructed pairs",length(brohn_paired_plot_model(altered,"comparison-1")$people)==0)
  plan<-brohn_new_analysis_plan();plan$rationale<-"Original comparison arithmetic";plan$comparisons<-list(list(id="planned",measure="questionnaire_numeric",outcome_id="q-liking",control_id="condition-a",test_id="condition-b"))
  planned<-body;planned$provenance$design$analysis_plan<-plan;planned$analysis<-brohn_analysis_plan_result(a,planned$provenance$design)
  pm<-brohn_paired_plot_model(planned,"comparison-1")
  check("declared explicit comparison retains exact Holm and uncertainty",pm$status=="verified"&&length(pm$observations)==11&&identical(pm$saved_contrast,planned$analysis$contrasts[[1]])&&pm$saved_contrast$multiplicity$method=="holm")
  sd<-f$design;sd$questions[[2]]<-sd$questions[[1]];sd$questions[[2]]$id<-"q-reverse";sd$questions[[2]]$prompt<-"Original reverse-coded item"
  sd$scales<-list(list(schema="brohn-questionnaire-scale/1.0",id="scale-original",label="Original arithmetic scale",version="1.0",source="Original arithmetic; no construct qualification.",scope="after_each",
    items=list(list(question_id="q-liking",reverse=FALSE,min=0,max=100),list(question_id="q-reverse",reverse=TRUE,min=0,max=100)),scoring=list(aggregation="mean",missing="complete",minimum_answered=2,prorate=FALSE),conversion=NULL))
  sd$analysis_plan<-plan;sd$analysis_plan$comparisons[[1]]$measure<-"questionnaire_scale";sd$analysis_plan$comparisons[[1]]$outcome_id<-"scale-original"
  sr<-unlist(lapply(f$responses,function(r)lapply(1:2,function(i){r$assessment_id<-r$exposure_id;r$assessment_exposure_id<-r$exposure_id;r$participant_linkage<-TRUE;r$origin<-"sample"
    if(i==2){r$question_id<-"q-reverse";r$value<-if(is.null(r$value))NULL else 100-r$value};r})),recursive=FALSE)
  sa<-brohn_questionnaire_analysis(sr,sd);sa$scales<-brohn_score_scales(sr,sd,source=list(kind="original_explicit_assessments"));sa<-brohn_analysis_plan_result(sa,sd)
  sb<-body;sb$analysis<-sa;sb$provenance<-list(design=sd,design_hash=brohn_hash(sd));sm<-brohn_paired_plot_model(sb,"comparison-1")
  check("complete assessment-scale scores retain their own keys, units and weighting",sm$status=="verified"&&sm$saved_contrast$estimate==8&&sm$people[[1]]$unit=="scale points"&&sm$observations[[1]]$source_container=="analysis.scales.observations")
  sb$analysis$scales$provenance$scales_hash<-brohn_hash("wrong keys")
  check("changed assessment scoring keys cannot support the saved plot",rejects(brohn_paired_plot_model(sb,"comparison-1")))
  gaze<-body;gaze$analysis<-list(kind="gaze",observations=f$gaze,contrasts=a$contrasts);gaze$analysis$contrasts<-lapply(gaze$analysis$contrasts,function(c){c$metric<-"valid_gaze_share";c$outcome_id<-"Logo";c$unit<-"percentage points";c})
  gm<-brohn_paired_plot_model(gaze,"comparison-1")
  check("gaze uses complete shares with percentage-point units",gm$status=="verified"&&gm$people[[1]]$control_mean==11&&gm$people[[1]]$unit=="percentage points")
  # Explicit reviewed identities and complete synthesis rows; expected answers
  # above do not use the multimodal implementation as their numerical oracle.
  spec<-list(id="combined",report_ids=list("source-q"),modality="questionnaire",metric="explicit_numeric_response",outcome_id="q-liking",unit="response units",control_id="condition-a",test_id="condition-b")
  rows<-lapply(f$responses,function(r)c(r,list(source_report_id="source-q",source_report_hash=paste(rep("a",64),collapse=""),source_row_hash=brohn_hash(r),
    modality="questionnaire",metric=spec$metric,outcome_id=spec$outcome_id,unit=spec$unit,eligible=!is.null(r$value),definition_hash=brohn_hash("original quantitative definition"))))
  mm<-body;mm$analysis<-list(kind="multimodal",observations=rows,contrasts=list(.brohn_mm_contrast(spec,rows,f$design)))
  combined<-brohn_paired_plot_model(mm,"comparison-1")
  check("combined sources keep their reviewed person and visit support",combined$status=="verified"&&combined$saved_contrast$estimate==8&&length(combined$observations)==11&&all(vapply(combined$observations,function(r)r$source_report_id=="source-q",logical(1))))
  mm$analysis$contrasts[[1]]$session_differences[[1]]$control_observations<-999
  check("changed saved visit denominator cannot silently produce a figure",brohn_paired_plot_model(mm,"comparison-1")$reason=="complete_source_disagrees_with_saved_comparison")
  expanded<-body;expanded$analysis$observations<-unlist(lapply(1:55,function(i)lapply(f$responses[1:3],function(r){r$participant_id<-paste0("Person",i);r})),recursive=FALSE)
  expanded$analysis<-brohn_questionnaire_analysis(expanded$analysis$observations,f$design);many<-brohn_paired_plot_model(expanded,"comparison-1")
  check("all people remain accessible beyond the bounded first page",length(many$people)==55&&length(brohn_paired_plot_page(many,2)$rows)==5&&rejects(brohn_paired_plot_page(many,3)))
  page_html<-as.character(.brohn_pp_view_ui(many,2,"people",1));check("people table follows the same figure page rather than stale table paging",grepl("Person51",page_html,fixed=TRUE)&&grepl("Table page 2",page_html,fixed=TRUE)&&!grepl(">Person1<",page_html,fixed=TRUE))
  svg<-as.character(brohn_paired_plot_svg(m,1,"means",320L));diff_svg<-as.character(brohn_paired_plot_svg(m,1,"differences",320L))
  check("accessible SVG retains exact source and person metadata",grepl('role="img"',svg,fixed=TRUE)&&grepl('<metadata>',svg,fixed=TRUE)&&grepl(m$report_hash,svg,fixed=TRUE)&&grepl('data-person="P3"',diff_svg,fixed=TRUE))
  html<-as.character(.brohn_pp_view_ui(m));check("round-trip exact table values are character cells not six-digit rounding",grepl("Exact numerical evidence",html,fixed=TRUE)&&grepl("unavailable",html,ignore.case=TRUE))
  file<-tempfile(fileext=".csv");on.exit(unlink(file),add=TRUE);brohn_paired_plot_csv(m,file);csv<-utils::read.csv(file,check.names=FALSE,colClasses="character",na.strings=NULL)
  check("full CSV includes source, session, person and untouched comparison",nrow(csv)==25&&sum(csv$record_type=="source_observation")==16&&sum(csv$record_type=="session")==5&&sum(csv$record_type=="person")==3&&all(csv$report_hash==m$report_hash))
  m$people[[1]]$participant_id<-"=1+1";m$people[[1]]$difference<-1.2345678901234567;brohn_paired_plot_csv(m,file);csv<-utils::read.csv(file,colClasses="character",na.strings=NULL)
  check("CSV escapes spreadsheet formulas and preserves round-trip numeric values",any(csv$participant_id=="'=1+1")&&any(csv$difference=="1.2345678901234567"))
  # Verify complete packed evidence and authority against real immutable objects.
  root<-tempfile("brohn-paired-domain-");dir.create(root);store<-brohn_open_store(file.path(root,"workspace"));brohn_initialise_library(store)
  on.exit({brohn_close_store(store);actual<-normalizePath(root,winslash="/",mustWork=FALSE);parent<-normalizePath(tempdir(),winslash="/",mustWork=TRUE)
    stopifnot(identical(tolower(dirname(actual)),tolower(parent)),startsWith(basename(actual),"brohn-paired-domain-"));unlink(actual,recursive=TRUE,force=TRUE)},add=TRUE)
  brohn_put_entity(store,"study",f$design$id,f$design)
  publish<-function(b,id){b$id<-id;b$result_object<-NULL;object<-brohn_store_object(store,bytes=charToRaw(brohn_json(list(schema="brohn-analysis-output/1.0",report=b))))
    b$result_object<-object;brohn_put_entity(store,"report",id,b)}
  r<-publish(body,"paired-source");o<-brohn_paired_plot_report(store,r$id,r$revision,brohn_hash(r$body),r$project_id)
  check("immutable report envelope and source design are verified before plotting",brohn_paired_plot_load(store,o,"comparison-1")$status=="verified")
  packed<-brohn_pack_questionnaire_report(body,root,threshold=1024,preview_rows=1)
  ref<-packed$analysis$artifacts[[1]];object<-brohn_store_object(store,path=ref$path);ref$path<-NULL;ref$hash<-object$hash;ref$sha256<-NULL;ref$size<-object$size;ref$bytes<-NULL;packed$analysis$artifacts[[1]]<-ref
  pr<-publish(packed,"paired-packed");po<-brohn_paired_plot_report(store,pr$id,pr$revision,brohn_hash(pr$body),pr$project_id);pm<-brohn_paired_plot_load(store,po,"comparison-1")
  check("one-row questionnaire preview resolves all sixteen original observations",length(pr$body$analysis$preview$observations)==1&&length(pm$observations)==16&&pm$status=="verified"&&identical(brohn_hash(po$body$analysis),brohn_hash(body$analysis)))
  altered<-packed;altered$analysis$preview$observations[[1]]$value_display<-"999";bad<-publish(altered,"paired-wrong-preview")
  check("forged preview cannot change or accompany verified paired evidence",rejects(brohn_paired_plot_report(store,bad$id,bad$revision,brohn_hash(bad$body),bad$project_id)))
  altered<-packed;altered$analysis$artifacts[[1]]$size<-12*1024^2+1;bad<-publish(altered,"paired-oversize")
  check("oversize complete artifact is explicitly refused before partial decoding",rejects(brohn_paired_plot_report(store,bad$id,bad$revision,brohn_hash(bad$body),bad$project_id)))
  handle<-.brohn_pp_async_start(store,"open",list(report_id=pr$id,revision=pr$revision,report_hash=brohn_hash(pr$body),project_id=pr$project_id))
  on.exit(.brohn_pp_async_release(handle),add=TRUE)
  repeat {result<-.brohn_pp_async_poll(handle);if(!is.null(result))break;Sys.sleep(.05)}
  check("supervised child resolves complete evidence without a scientific job",length(result$value$body$analysis$observations)==16&&length(brohn_list_jobs(store,limit=10L))==0)
  .brohn_pp_async_release(handle);handle<-.brohn_pp_async_start(store,"load",list(opened=result$value,comparison_id="comparison-1"))
  repeat {loaded<-.brohn_pp_async_poll(handle);if(!is.null(loaded))break;Sys.sleep(.05)}
  check("background preparation produces full verified CSV and JSON",loaded$value$status=="verified"&&all(vapply(loaded$exports,function(ref)file.exists(ref$path)&&ref$size>0,logical(1)))&&length(brohn_read_json_file(loaded$exports$json$path)$observations)==16)
  temp<-handle$folder;.brohn_pp_async_release(handle);handle<-NULL;check("completed preparation cleanup removes only its owned temporary directory",!dir.exists(temp))
  updated<-r$body;updated$title<-"New explicit revision";brohn_put_entity(store,"report",r$id,updated,expected_revision=r$revision)
  check("a newer report revision revokes the old opened source",rejects(brohn_paired_plot_check(store,o)))
  project<-brohn_project(store,pr$project_id);project$body$archived<-TRUE;brohn_put_entity(store,"project",project$id,project$body,expected_revision=project$revision,project_id=project$id)
  check("archiving the owning project revokes complete artifact review",rejects(brohn_paired_plot_check(store,po)))
  cat("PASS paired visual review:",checks,"independent checks\n")
})
