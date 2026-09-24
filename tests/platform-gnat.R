source("R/platform-core.R",encoding="UTF-8")
source("R/platform-methods.R",encoding="UTF-8")
module<-Sys.getenv("BROHN_GNAT_CANDIDATE_MODULE","R/platform-gnat.R")
original_profiles<-function(){profiles<-brohn_task_profiles();profiles[names(profiles)!="gnat-brohn-single-target/1.0"]}
before_profiles<-brohn_hash(original_profiles())
source(module,encoding="UTF-8")
source(Sys.getenv("BROHN_GNAT_CANDIDATE_JOURNAL","tests/fixtures/gnat-journal.R"),encoding="UTF-8")
local({
  folder<-commandArgs(TRUE)[1L];if(is.na(folder))folder<-tempfile("gnat-candidate-")
  dir.create(folder,recursive=TRUE);stopifnot(!file.exists(file.path(folder,"results.json")))
  checks<-character();check<-function(label,ok){stopifnot(isTRUE(ok));checks<<-c(checks,label);cat("PASS",label,"\n")}
  refuses<-function(x)inherits(try(force(x),silent=TRUE),"try-error")
  close<-function(a,b)isTRUE(all.equal(a,b,tolerance=1e-12,check.attributes=FALSE))
  block<-brohn_gnat_new(id="gnat-reference");original_rng<-if(exists(".Random.seed",.GlobalEnv))get(".Random.seed",.GlobalEnv)else NULL
  a<-brohn_gnat_compile(block);b<-brohn_gnat_compile(block,2L)
  check("Complete 384 trials, 12 self-paced boundaries and four roles",length(a$timeline)==396L&&length(a$blocks)==12L&&length(a$categories)==4L)
  check("Reproducible compilation without ambient R RNG change",identical(a,brohn_gnat_compile(block))&&
    identical(original_rng,if(exists(".Random.seed",.GlobalEnv))get(".Random.seed",.GlobalEnv)else NULL))
  check("Allocation changes sequence, preserves procedure",a$sequence_hash!=b$sequence_hash&&a$procedure_hash==b$procedure_hash)
  for(bl in a$blocks) {
    trials<-Filter(function(t)t$type=="task_trial"&&t$block_id==bl$id,a$timeline)
    expected<-if(bl$phase=="training")20L else if(bl$phase=="practice")16L else 60L
    check(paste("Exact signal/noise and phase quota",bl$index),length(trials)==expected&&sum(vapply(trials,function(t)t$expected_action=="go",logical(1)))==expected/2)
    roles<-vapply(trials,`[[`,character(1),"category_role");counts<-as.numeric(table(roles))
    check(paste("Equal material-role opportunity",bl$index),all(counts==if(bl$phase=="training")10L else if(bl$phase=="practice")4L else 15L))
    for(role in unique(roles)) {
      items<-vapply(trials[roles==role],function(t)t$material$id,character(1))
      check(paste("Exhaust exemplar deck before reuse",bl$index,role),all(vapply(split(items,ceiling(seq_along(items)/4)),function(x)!anyDuplicated(x),logical(1))))
    }
  }
  check("All six existing profiles unchanged by GNAT module loading",identical(before_profiles,brohn_hash(original_profiles()))&&length(original_profiles())==6L)
  check("Canonical compile validates independently",is.list(brohn_gnat_validate_compiled(a)))
  altered<-a;altered$timeline[[2]]$expected_action<-if(altered$timeline[[2]]$expected_action=="go")"nogo"else"go"
  check("Reject altered expected action even if raw table remains plausible",refuses(brohn_gnat_validate_compiled(altered)))
  mutations<-list(extra_role=function(x){x$categories[[5]]<-list(id="extra",label="Extra",role="target2");x},
    numeric_seed=function(x){x$seed<-"123";x},missing_context=function(x){x$settings$context_rationale<-"";x},
    attribute_only=function(x){x$settings$context_kind<-"attribute_only";x},shorten=function(x){x$settings$procedure$training_trials_per_block<-10;x},
    image=function(x){x$materials[[1]]$type<-"image";x},duplicate_id=function(x){x$materials[[2]]$id<-x$materials[[1]]$id;x},
    duplicate_text=function(x){x$materials[[6]]$content<-paste0("\u00a0",toupper(x$materials[[1]]$content),"\u2009");x})
  for(name in names(mutations))check(paste("Refuse authoring",name),refuses(brohn_gnat_validate(mutations[[name]](block))))
  check("Exact whitespace/ASCII folding and explicit non-NFC semantics",identical(.brohn_gnat_text_key("\u00a0A\u2009\u2009B\u3000"),"a b")&&
    !identical(.brohn_gnat_text_key("\u00e9"),.brohn_gnat_text_key("e\u0301")))
  for(kind in c("generic","single_category","superordinate")){x<-block;x$settings$context_kind<-kind;check(paste("Declared context kind",kind),is.list(brohn_gnat_validate(x)))}
  reference<-brohn_gnat_sensitivity(8,2,2,8)
  check("Independent published 8/10 vs 2/10 oracle",close(reference$d_prime,1.6832424671458286)&&close(reference$criterion,0))
  check("Reversing rates reverses sensitivity",close(brohn_gnat_sensitivity(2,8,8,2)$d_prime,-1.6832424671458286))
  endpoint<-brohn_gnat_sensitivity(30,0,0,30)
  check("Only exact endpoints get named correction",identical(endpoint$raw_rates,list(hit=1,false_alarm=0))&&identical(endpoint$corrected_rates,list(hit=.995,false_alarm=.005)))
  interior<-brohn_gnat_sensitivity(1,999,999,1)
  check("Interior probabilities are not clipped to endpoint bounds",identical(interior$raw_rates,interior$corrected_rates)&&interior$d_prime< -5)
  check("Missing signal/noise yields null unavailable score",is.null(brohn_gnat_sensitivity(0,0,1,1)$d_prime)&&is.null(brohn_gnat_sensitivity(1,1,0,0)$criterion))
  check("Invalid arithmetic counts refused",refuses(brohn_gnat_sensitivity(-1,1,1,1))&&refuses(brohn_gnat_sensitivity(.5,1,1,1))&&refuses(brohn_gnat_sensitivity(NA,1,1,1)))
  events<-original_gnat_journal(a);replay<-brohn_gnat_replay(a,events)
  check("All384 authored receipts replay, without claiming outer consent/session",replay$complete&&!replay$outer_session_qualified&&length(replay$state$responses)==384L)
  score<-brohn_gnat_score(a,replay$state$responses)
  check("Complete four cells and ten dimensionless metrics",score$eligible&&length(score$metrics)==10L&&all(vapply(score$metrics,function(m)m$unit=="dimensionless"&&is.finite(m$value),logical(1))))
  check("Withholding preserves actual accuracy and null response key/RT",all(vapply(Filter(function(r)r$outcome %in% c("miss","correct_rejection"),score$scoring_audit$rows),
    function(r)is.null(r$response_ms)&&is.null(r$response_code)&&identical(r$correct,r$outcome=="correct_rejection"),logical(1))))
  check("Deadline rounds keep independent cells and order",length(score$scoring_audit$rounds)==2L&&score$scoring_audit$rounds[[1]]$deadline_ms==750&&score$scoring_audit$rounds[[2]]$deadline_ms==600)
  check("Zero sensitivity retained with descriptive support flag",score$scoring_audit$cells[[4]]$d_prime==0&&"little_or_reversed_discrimination" %in% unlist(score$scoring_audit$cells[[4]]$flags))
  incomplete<-brohn_gnat_score(a,replay$state$responses[-384L],FALSE)
  check("Partial task retains earlier cells but no primary score",!incomplete$eligible&&all(vapply(incomplete$metrics,function(m)is.null(m$value),logical(1)))&&incomplete$scoring_audit$cells[[1]]$status=="available")
  forged<-replay$state$responses;at<-which(vapply(forged,function(r)r$outcome=="correct_rejection",logical(1)))[1];forged[[at]]$response_ms<-750
  check("Cannot import deadline-valued latency as withholding",refuses(brohn_gnat_score(a,forged)))
  forged<-replay$state$responses;forged[[1]]$correct<-!forged[[1]]$correct
  check("Cannot trust forged accuracy in scorer",refuses(brohn_gnat_score(a,forged)))
  check("Duplicate/unknown trial records refused",refuses(brohn_gnat_score(a,c(replay$state$responses,replay$state$responses[1]))))
  unknown_rows<-replay$state$responses
  at<-which(vapply(score$scoring_audit$rows,function(r)r$phase=="test"&&r$outcome=="hit",logical(1)))[1L]
  unknown_rows[[at]]$response_ms<-2000
  check("Known/default timing still refuses an out-of-window declared response",refuses(brohn_gnat_score(a,unknown_rows))&&refuses(brohn_gnat_score(a,unknown_rows,timing_known=TRUE)))
  unknown<-local({
    had<-exists("qnorm",envir=.GlobalEnv,inherits=FALSE);if(had)old<-get("qnorm",envir=.GlobalEnv)
    on.exit(if(had)assign("qnorm",old,envir=.GlobalEnv)else rm("qnorm",envir=.GlobalEnv))
    assign("qnorm",function(...)stop("Unknown timing cannot invoke normal-quantile scoring."),envir=.GlobalEnv)
    brohn_gnat_score(a,unknown_rows,timing_known=FALSE)
  })
  check("Unknown timing preserves actual declared values without invoking normal scoring",unknown$scoring_audit$rows[[at]]$response_ms==2000&&
    unknown$counts$received==384L&&identical(unknown$scoring_audit$cells[[1]]$raw_rates,score$scoring_audit$cells[[1]]$raw_rates))
  check("Unknown timing never supplies metrics, cell sensitivity or criterion",!unknown$eligible&&unknown$status=="unavailable"&&
    all(vapply(unknown$metrics,function(m)is.null(m$value),logical(1)))&&
    all(vapply(unknown$scoring_audit$cells,function(c)is.null(c$d_prime)&&is.null(c$criterion)&&"declared_timing_unknown" %in% unlist(c$flags),logical(1))))
  check("Unknown timing retains declared response-only descriptive values",any(vapply(unknown$scoring_audit$cells,function(c)c$response_rt$hit$n>0&&c$response_rt$hit$mean_ms>250,logical(1)))&&
    identical(unknown$scoring_audit$timing_known,FALSE)&&grepl("unknown",unknown$reason,fixed=TRUE))
  wrong<-unknown_rows;wrong[[at]]$response_ms<- -1
  check("Unknown timing does not authorize negative/nonfinite values",refuses(brohn_gnat_score(a,wrong,timing_known=FALSE)))
  wrong[[at]]$response_ms<-Inf
  check("Unknown timing refuses infinity",refuses(brohn_gnat_score(a,wrong,timing_known=FALSE)))
  check("Timing definition status must be a literal logical value",refuses(brohn_gnat_score(a,unknown_rows,timing_known="false")))
  check("Saved target label and context remain bound to source categories",identical(score$scoring_audit$target,list(id="target",label="Writing tools"))&&
    identical(score$scoring_audit$context$label,"Other things"))
  writeLines(brohn_json(a,TRUE),file.path(folder,"compiled.json"),useBytes=TRUE)
  writeLines(brohn_json(events,TRUE),file.path(folder,"original-journal.json"),useBytes=TRUE)
  writeLines(brohn_json(score,TRUE),file.path(folder,"score.json"),useBytes=TRUE)
  writeLines(brohn_json(unknown,TRUE),file.path(folder,"unknown-timing-score.json"),useBytes=TRUE)
  result<-list(passed=TRUE,status=if(nzchar(Sys.getenv("BROHN_GNAT_CANDIDATE_MODULE")))"external_staged_candidate"else"isolated_current_tree_component",checks=as.list(checks),count=length(checks),registered=block$profile %in% names(brohn_task_profiles()),
    browser_or_outer_session_qualified=FALSE,original_six_profiles_hash=before_profiles,source_sha256=digest::digest(file=module,algo="sha256"))
  writeLines(brohn_json(result,TRUE),file.path(folder,"results.json"),useBytes=TRUE)
  cat(brohn_json(list(passed=TRUE,count=length(checks),folder=folder)),"\n")
})
