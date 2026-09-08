# Original paired-condition examples with independently specified person means.
source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = TRUE)
local({
  checks <- 0L
  check <- function(name, ok) {if (!isTRUE(ok)) stop(paste("Scale comparison QA:", name), call. = FALSE); checks <<- checks+1L}
  near <- function(a,b) isTRUE(all.equal(a,b,tolerance=1e-10))
  rejected <- function(expr) inherits(try(force(expr), silent=TRUE), "try-error")
  d <- brohn_new_design("Original paired scale fixture")
  d$stimuli <- lapply(d$stimuli, function(s) {s$content <- "Original concept"; s})
  d$questions <- lapply(c("item-one","item-two"), function(id) {q <- brohn_question(paste("Original",id),"number","after_each",id); q$min<-0;q$max<-100;q$step<-1;q$required<-FALSE;q})
  d$scales <- list(list(schema="brohn-questionnaire-scale/1.0",id="scale-original",label="Original concept scale",version="1.0",
    source="Original arithmetic fixture; no instrument validity claim.",scope="after_each",
    items=list(list(question_id="item-one",reverse=FALSE,min=0,max=100),list(question_id="item-two",reverse=TRUE,min=0,max=100)),
    scoring=list(aggregation="mean",missing="complete",minimum_answered=2,prorate=FALSE),conversion=NULL))
  spec <- list(id="comparison-scale",measure="questionnaire_scale",outcome_id="scale-original",control_id="condition-a",test_id="condition-b")
  plan <- brohn_new_analysis_plan();plan$rationale<-'Original controlled concept comparison';plan$comparisons<-list(spec);d$analysis_plan<-plan
  check("scale plan validates with its quantitative after-stimulus key", !rejected(brohn_validate_design(d,TRUE)))
  # P1 visits have differences 2 and 6, hence one person difference 4.
  # P2 and P3 have differences 8 and 12. P4 lacks a complete test assessment.
  fixtures <- list(c("P1","V1","A","10"),c("P1","V1","A","14"),c("P1","V1","B","14"),
    c("P1","V2","A","10"),c("P1","V2","B","16"),c("P2","V3","A","10"),c("P2","V3","B","18"),
    c("P3","V4","A","10"),c("P3","V4","B","22"),c("P4","V5","A","10"),c("P4","V5","B",NA_character_))
  responses <- unlist(lapply(seq_along(fixtures),function(i) {
    f<-fixtures[[i]];v<-if(is.na(f[4])) NULL else as.numeric(f[4])
    lapply(1:2,function(j) list(participant_id=f[1],session_id=f[2],assessment_id=paste0("occasion-",i),
      stimulus_id=paste0("stimulus-",tolower(f[3])),condition_id=paste0("condition-",tolower(f[3])),assessment_exposure_id=paste0("presentation-",i),
      question_id=d$questions[[j]]$id,prompt=d$questions[[j]]$prompt,value=if(is.null(v)) NULL else if(j==1) v else 100-v,
      missing_reason=if(is.null(v)) "optional_omission" else NULL,participant_linkage=TRUE,origin="sample",source_row=2*(i-1)+j))
  }),recursive=FALSE)
  score <- function(design=d, rows=responses) {
    a<-brohn_questionnaire_analysis(rows,design);a$scales<-brohn_score_scales(rows,design,source=list(kind="original_explicit_assessments"));a
  }
  a<-score();before<-brohn_hash(a);result<-brohn_analysis_plan_result(a,d);contrast<-result$contrasts[[1]]
  check("three equally weighted people have independent mean difference 8", contrast$estimate==8 && contrast$participant_count==3 && contrast$paired_session_count==4)
  check("repeat visits contribute the person differences 4,8,12", near(sort(vapply(contrast$participant_differences,`[[`,numeric(1),"value")),c(4,8,12)))
  check("missing complete assessment excludes one pair without becoming zero",contrast$excluded_session_count==1 && length(result$scales$observations)==11 && contrast$scale_source$unavailable_assessment_count==1)
  # With three differences (4,8,12), t=sqrt(12), df=2. The exact two-sided
  # Student t probability is 1 - sqrt(6/7), independent of implementation pt().
  probability<-1-sqrt(6/7)
  check("two-sided probability matches the independent df2 closed form",near(contrast$p_value,probability) && near(contrast$p_adjusted,probability))
  check("unadjusted interval uses three people, not eleven assessments",contrast$interval95$df==2 && near(contrast$interval95$lower,8-4.30265272974946*4/sqrt(3)))
  check("comparison retains exact scoring source and unmodified item results",identical(before,brohn_hash(a)) && identical(contrast$scale_source$scale_hash,brohn_hash(d$scales[[1]])) &&
    identical(result$scales,a$scales) && grepl("assessment",contrast$aggregation,fixed=TRUE))
  mixed<-d;mixed$analysis_plan$comparisons[[2]]<-list(id="comparison-item",measure="questionnaire_numeric",outcome_id="item-one",control_id="condition-a",test_id="condition-b")
  both<-brohn_analysis_plan_result(score(mixed),mixed)
  check("item and scale share one complete Holm family",length(both$contrasts)==2 && all(vapply(both$contrasts,function(c) c$multiplicity$method=="holm" && c$multiplicity$family_size==2 && near(c$p_adjusted,2*probability),logical(1))))
  for(i in 1:2) mixed$stimuli[[i]]$aois<-list(list(id=paste0("area-",i),label="Brand",x=0,y=0,width=.5,height=.5))
  mixed$analysis_plan$comparisons[[3]]<-list(id="comparison-gaze",measure="gaze_valid_share",outcome_id="Brand",control_id="condition-a",test_id="condition-b")
  partial<-brohn_analysis_plan_result(score(mixed),mixed)
  check("absent gaze retains its place in the full family",all(vapply(partial$contrasts,function(c) c$multiplicity$method=="bonferroni_incomplete_family" && c$multiplicity$family_size==3 && near(c$p_adjusted,3*probability),logical(1))))
  hidden<-a;hidden$scales$observations[[1]]$participant_linkage<-FALSE
  check("unknown repeat identity withholds the whole scale comparison",brohn_analysis_plan_result(hidden,d)$contrasts[[1]]$reason=="participant_identity_not_established")
  check("global source identity gate also applies",brohn_analysis_plan_result(a,d,FALSE)$contrasts[[1]]$reason=="participant_identity_not_established")
  absent<-a;absent$scales<-NULL
  check("missing scoring output has an explicit unavailable comparison",brohn_analysis_plan_result(absent,d)$contrasts[[1]]$reason=="scale_results_not_available")
  tampered<-a;tampered$scales$provenance$scales_hash<-paste(rep("0",64),collapse="")
  check("different score keys cannot silently enter inference",rejected(brohn_analysis_plan_result(tampered,d)))
  tampered<-a;tampered$scales$observations<-c(tampered$scales$observations,tampered$scales$observations[1])
  check("duplicate assessment records cannot inflate contribution",rejected(brohn_analysis_plan_result(tampered,d)))
  tampered<-a;tampered$scales$observations[[2]]$origin<-"live"
  check("live and synthetic origins cannot share a contrast",rejected(brohn_analysis_plan_result(tampered,d)))
  whole<-d;whole$questions<-lapply(whole$questions,function(q){q$scope<-"end";q});whole$scales[[1]]$scope<-"end"
  check("whole-study scales cannot acquire a condition contrast",rejected(brohn_validate_analysis_plan(whole$analysis_plan,whole)))
  descriptive<-d;descriptive$analysis_plan$comparisons<-list()
  check("explicit descriptive plan retains scores but no tests",length(brohn_analysis_plan_result(score(descriptive),descriptive)$contrasts)==0)
  cloned<-brohn_clone_design(d,"Original cloned comparison")
  check("design clone remaps the planned scale and its questions together",cloned$analysis_plan$comparisons[[1]]$outcome_id==cloned$scales[[1]]$id && cloned$scales[[1]]$id!=d$scales[[1]]$id &&
    all(vapply(cloned$scales[[1]]$items,`[[`,character(1),"question_id") %in% brohn_ids(cloned$questions)))

  # Exercise the real saved-import worker and immutable portable graph.
  root<-tempfile("brohn-scale-comparison-");dir.create(root);store<-brohn_open_store(file.path(root,"workspace"))
  brohn_initialise_library(store)
  on.exit({try(brohn_close_store(store),silent=TRUE);actual<-normalizePath(root,winslash="/",mustWork=FALSE)
    stopifnot(startsWith(tolower(actual),paste0(tolower(normalizePath(tempdir(),winslash="/")),"/")),grepl("^brohn-scale-comparison-",basename(actual)))
    unlink(actual,recursive=TRUE,force=TRUE)},add=TRUE)
  invisible(brohn_put_entity(store,"study",d$id,d))
  rows<-do.call(rbind,lapply(responses,function(r) data.frame(person=r$participant_id,session=r$session_id,assessment=r$assessment_id,
    stimulus=r$stimulus_id,condition=r$condition_id,question=r$question_id,value=brohn_default(r$value,NA_real_))))
  csv<-file.path(root,"original.csv");utils::write.csv(rows,csv,row.names=FALSE,na="")
  dataset<-brohn_ingest_dataset(store,csv,"Original paired scale input","questionnaire",study_id=d$id,origin="sample")
  mapping<-list(participant_column="person",session_column="session",assessment_column="assessment",stimulus_column="stimulus",condition_column="condition",
    question_column="question",value_columns=list("value"),unit="numeric_rating",origin_statement="Original explicit assessment identities and independent arithmetic.")
  dataset<-brohn_curate_dataset(store,dataset$id,mapping,dataset$revision);queued<-brohn_queue_dataset(store,dataset$id)
  job<-brohn_claim_job(store,"original-comparison",lease_seconds=60);brohn_process_job(store,job,timeout_seconds=30);done<-brohn_get_job(store,queued$id)
  check("actual independent worker publishes the scale comparison",done$status=="succeeded")
  report<-brohn_get_entity(store,"report",done$result$report_id)
  check("published comparison retains arithmetic, dataset and implementation identity",report$body$analysis$contrasts[[1]]$estimate==8 &&
    identical(report$body$processing$code_hashes$`R/platform-scale-comparisons.R`,digest::digest(file="R/platform-scale-comparisons.R",algo="sha256")) &&
    report$body$analysis$contrasts[[1]]$scale_source$source$dataset_id==dataset$id)
  archive<-file.path(root,"design.brohn-study.zip");brohn_export_design(store,d$id,archive)
  imported<-brohn_import_design(store,archive,"Original imported comparison")
  imported_design<-if(!is.null(imported$body)) imported$body else imported
  check("portable study retains the remapped scale hypothesis",!rejected(brohn_validate_design(imported_design)) &&
    imported_design$analysis_plan$comparisons[[1]]$outcome_id==imported_design$scales[[1]]$id)
  html<-file.path(root,"report.html");brohn_export_report_html(report$body,html,store)
  check("offline report displays scale units and saved inference",grepl("scale points",paste(readLines(html,warn=FALSE),collapse="\n"),fixed=TRUE))
  hash<-brohn_hash(report$body);brohn_close_store(store);store<-brohn_open_store(file.path(root,"workspace"))
  check("reopening preserves the complete comparison report",identical(brohn_hash(brohn_get_entity(store,"report",report$id)$body),hash))
  server<-function(input,output,session) {
    current<-shiny::reactiveValues(study=brohn_study(store,d$id))
    state<-shiny::reactiveValues(page="study",stage="Plan",error=NULL)
    attempt<-function(fn) tryCatch({state$error<-NULL;fn()},error=function(e) state$error<-conditionMessage(e))
    update_study<-function(design) {current$study<-brohn_save_study(store,design,current$study$revision);invisible(current$study)}
    api<-brohn_install_analysis_plan_ui(input,output,session,current,attempt,function() invisible(NULL),update_study,state)
  }
  shiny::testServer(server,{
    session$setInputs(edit_analysis_plan=1L);session$flushReact();original_token<-api$context()$token
    session$setInputs(plan_form_identity=original_token,plan_measure="questionnaire_scale",plan_outcome_id="scale-original",
      plan_control="condition-a",plan_test="condition-b",plan_rationale=plan$rationale,plan_alpha=.05)
    session$flushReact()
    check("actual Shiny picker offers saved after-stimulus scale",grepl("Original concept scale",output$plan_outcome$html,fixed=TRUE) && grepl("After-stimulus scale",output$plan_outcome$html,fixed=TRUE))
    revision<-current$study$revision;session$setInputs(plan_save=1L)
    check("analysis-plan Save writes one revision and closes its draft",is.null(state$error) && current$study$revision==revision+1L && !api$context()$active)
    revision<-current$study$revision;session$setInputs(plan_save=2L)
    check("late Save after closing cannot write another revision",!is.null(state$error) && current$study$revision==revision)
    session$setInputs(edit_analysis_plan=2L);session$flushReact()
    session$setInputs(plan_save=3L)
    check("old modal input token cannot save a reopened draft",!is.null(state$error) && current$study$revision==revision)
    session$setInputs(plan_form_identity=api$context()$token,plan_remove=list(id=spec$id,token=original_token))
    check("late remove command cannot target the reopened plan",!is.null(state$error) && length(current$study$body$analysis_plan$comparisons)==1)
    session$setInputs(plan_cancel=1L,plan_save=4L)
    check("Cancel invalidates a queued save",!api$context()$active && current$study$revision==revision)
    session$setInputs(edit_analysis_plan=3L);session$flushReact();session$setInputs(plan_form_identity=api$context()$token)
    state$stage<-"Questions";session$setInputs(plan_save=5L)
    check("stage navigation invalidates analysis-plan publication",!is.null(state$error) && current$study$revision==revision)
    state$stage<-"Plan";session$setInputs(edit_analysis_plan=4L);session$flushReact();session$setInputs(plan_form_identity=api$context()$token)
    changed<-current$study$body;changed$title<-"Original changed title";update_study(changed);revision<-current$study$revision
    session$setInputs(plan_save=6L)
    check("a concurrent study revision cannot be overwritten by a plan draft",!is.null(state$error) && current$study$revision==revision && current$study$body$title==changed$title)
  })
  cat(sprintf("Scale comparisons: %d scoped checks passed.\n",checks))
})
