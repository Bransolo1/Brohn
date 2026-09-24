source("R/platform-core.R",encoding="UTF-8")
source("R/platform-methods.R",encoding="UTF-8")
source("R/platform-sciat-window.R",encoding="UTF-8")
source("R/platform-sciat-window-delivery.R",encoding="UTF-8")
source("tests/fixtures/sciat-window-journal.R",encoding="UTF-8")
local({
  folder<-Sys.getenv("BROHN_SCIAT_CORE_TEST_ROOT",tempfile("brohn-sciat-core-"));dir.create(folder,recursive=TRUE)
  stopifnot(!file.exists(file.path(folder,"results.json")))
  checks<-character();check<-function(label,x){stopifnot(isTRUE(x));checks<<-c(checks,label);cat("PASS",label,"\n")}
  rejects<-function(x)inherits(try(force(x),silent=TRUE),"try-error")
  legacy<-brohn_parse(paste(readLines("tests/fixtures/sciat-legacy-profile-contract.json",warn=FALSE),collapse="\n"))
  # Exact five-profile snapshot from pre-registration commit 0a6bde71c38f7419bcd979b322e20a6526cddad1.
  legacy_hash<-"9b4045230a5a6885341f6179ccfe2219a3f31c84a021e4978e442a406435f653"
  stopifnot(identical(brohn_hash(legacy),legacy_hash));block<-brohn_sciat_window_new(id="original-sciat-core")
  before<-if(exists(".Random.seed",.GlobalEnv))get(".Random.seed",.GlobalEnv)else NULL
  a<-brohn_sciat_window_compile(block,1L);b<-brohn_sciat_window_compile(block,2L)
  check("Three roles without a second target and all192 trials",length(a$timeline)==196L&&length(a$categories)==3L&&
    sum(vapply(a$timeline,function(t)t$type=="task_trial",logical(1)))==192L&&!"target_b" %in% vapply(a$categories,`[[`,character(1),"role"))
  check("Opposite allocation orders keep positive on E",identical(vapply(a$blocks,`[[`,character(1),"mapping"),c("A","A","B","B"))&&
    identical(vapply(b$blocks,`[[`,character(1),"mapping"),c("B","B","A","A"))&&b$assignment$positive_attribute_key=="KeyE")
  check("Compiler reproducible and leaves global R RNG unchanged",identical(a,brohn_sciat_window_compile(block,1L))&&
    identical(before,if(exists(".Random.seed",.GlobalEnv))get(".Random.seed",.GlobalEnv)else NULL))
  changed<-block;changed$seed<-changed$seed+1L
  check("Changed seed changes realized sequence without changing method",brohn_sciat_window_compile(changed)$sequence_hash!=a$sequence_hash&&
    brohn_sciat_window_compile(changed)$procedure_hash==a$procedure_hash)
  for(compiled in list(a,b))for(bl in compiled$blocks) {
    trials<-Filter(function(t)t$type=="task_trial"&&t$block_id==bl$id,compiled$timeline)
    actual<-table(factor(vapply(trials,`[[`,character(1),"category_role"),levels=c("target","attribute_positive","attribute_negative")))
    expected<-if(bl$mapping=="A")if(bl$phase=="practice")c(7,7,10)else c(21,21,30)else if(bl$phase=="practice")c(7,10,7)else c(21,30,21)
    check(paste("Exact independent quota",compiled$assignment$initial_mapping,bl$index),identical(as.numeric(actual),expected)&&length(trials)==if(bl$phase=="practice")24L else 72L)
    for(role in c("target","attribute_positive","attribute_negative")) {
      items<-vapply(Filter(function(t)t$category_role==role,trials),function(t)t$material$id,character(1))
      check(paste("Per-block two-exemplar cycles",compiled$assignment$initial_mapping,bl$index,role),all(vapply(split(items,ceiling(seq_along(items)/2)),function(x)!anyDuplicated(x),logical(1))))
    }
  }
  check("Compiled source/procedure/hash is independently reconstructible",is.list(brohn_sciat_window_validate_compiled(a)))
  bad<-a;bad$timeline[[2L]]$correct_code<-if(bad$timeline[[2L]]$correct_code=="KeyE")"KeyI"else"KeyE"
  check("Reject altered frozen key",rejects(brohn_sciat_window_validate_compiled(bad)))
  mutations<-list(extra_target=function(x){x$categories[[4]]<-list(id="other",role="target_b",label="Other");x},
    wrong_profile=function(x){x$profile<-"iat-gnb2003-d1/1.0";x},
    changed_window=function(x){x$settings$procedure$response_window_ms<-1400;x},
    unknown_setting=function(x){x$settings$shorten<-TRUE;x},
    duplicate_material=function(x){x$materials[[2]]$id<-x$materials[[1]]$id;x},
    malformed_seed=function(x){x$seed<-"104729";x},
    missing_rights=function(x){x$materials_rights<-"";x},
    missing_language=function(x){x$settings$language<-"";x})
  for(n in names(mutations))check(paste("Reject authoring",n),rejects(brohn_sciat_window_validate(mutations[[n]](block))))
  ea<-original_sciat_window_journal(a);eb<-original_sciat_window_journal(b)
  ra<-brohn_sciat_window_replay(a,ea);rb<-brohn_sciat_window_replay(b,eb)
  check("Both full192 original journals replay without invented outer session qualification",ra$complete&&rb$complete&&!ra$outer_session_qualified&&!rb$outer_session_qualified&&length(ra$state$responses)==192L)
  delayed<-lapply(ea,function(e){e$clock$value<-format(as.numeric(e$clock$value)+.25,scientific=FALSE,trim=TRUE,digits=17);e})
  check("Callback dispatch can follow its nested observation without changing task onset",brohn_sciat_window_replay(a,delayed)$complete)
  check("First error remains error despite later correct key",identical(ra$state$responses[[1]]$correct,FALSE)&&ra$state$responses[[1]]$latency_ms==417)
  check("Exact1500 timestamp accepted and explicit omission has no fake latency",ra$state$responses[[2]]$latency_ms==1500&&
    ra$state$responses[[3]]$outcome=="omission"&&is.null(ra$state$responses[[3]]$latency_ms))
  check("Incomplete received journal never qualifies a full task",!brohn_sciat_window_replay(a,ea[1:3])$complete)
  bad<-ea;bad[[3]]$payload$data$correct<-TRUE
  check("Reject forged first-response accuracy",rejects(brohn_sciat_window_replay(a,bad)))
  bad<-ea;bad[[3]]$payload$data$keys[[3]]$accepted<-TRUE;bad[[3]]$payload$data$keys[[3]]$ignored_reason<-NULL
  check("Reject correction as second accepted response",rejects(brohn_sciat_window_replay(a,bad)))
  for(field in c("feedback_end_ms","blank_end_ms")) {
    bad<-ea;bad[[3]]$payload$data[[field]]<-bad[[3]]$payload$data[[field]]-1
    check(paste("Reject shortened",field),rejects(brohn_sciat_window_replay(a,bad)))
  }
  bad<-ea;bad[[3]]$payload$data$response_ms<-400
  check("Reject handler/claimed RT replacing event latency",rejects(brohn_sciat_window_replay(a,bad)))
  bad<-ea;bad[[3]]$payload$data$procedure_hash<-paste(rep("0",64),collapse="")
  check("Reject foreign procedure receipt",rejects(brohn_sciat_window_replay(a,bad)))
  bad<-ea;bad[[3]]$clock$instance_id<-"reloaded-page";bad[[3]]$payload$data$clock$instance_id<-"reloaded-page"
  check("Refresh cannot continue across a new clock instance",rejects(brohn_sciat_window_replay(a,bad)))
  bad<-ea[c(1,3,2,4:length(ea))]
  check("Reject finish before received onset",rejects(brohn_sciat_window_replay(a,bad)))
  bad<-ea;bad[[3]]$payload$data$keys[[1]]$trusted<-FALSE
  check("Synthetic key cannot be a physical response",rejects(brohn_sciat_window_replay(a,bad)))
  bad<-ea;bad[[3]]$payload$data$keys[[1]][["repeat"]]<-TRUE
  check("Held repeat cannot become a first response",rejects(brohn_sciat_window_replay(a,bad)))
  bad<-ea;bad[[2]]$payload$data$held_codes<-list(bad[[3]]$payload$data$keys[[1]]$code)
  check("Held-at-onset key requires actual release before response",rejects(brohn_sciat_window_replay(a,bad)))
  check("All five prior registered profile definitions preserve their independent pre-registration snapshot",
    identical(legacy_hash,brohn_hash(brohn_task_profiles()[names(legacy)])))
  check("Named SC-IAT adaptation is registered separately alongside prior profiles",block$profile %in% names(brohn_task_profiles())&&
    identical(brohn_task_new(block$profile,id="registered-sciat-probe")$profile,block$profile))
  writeLines(brohn_json(list(A=a,B=b),TRUE),file.path(folder,"compiled.json"),useBytes=TRUE)
  writeLines(brohn_json(list(A=ea,B=eb),TRUE),file.path(folder,"original-journals.json"),useBytes=TRUE)
  result<-list(passed=TRUE,origin="original_synthetic_component_evidence",checks=as.list(checks),
    complete_browser_or_session_qualification=FALSE,legacy_profile_contract_hash=legacy_hash,registered_profile=block$profile,compiled_hash=list(A=brohn_hash(a),B=brohn_hash(b)),
    source=lapply(c("R/platform-sciat-window.R","R/platform-sciat-window-delivery.R","www/participant/sciat-window-core.js","www/participant/sciat-window.js"),
      function(p)list(path=p,sha256=digest::digest(file=p,algo="sha256"))))
  writeLines(brohn_json(result,TRUE),file.path(folder,"results.json"),useBytes=TRUE)
  cat(brohn_json(list(passed=TRUE,checks=length(checks),folder=folder)),"\n")
})
