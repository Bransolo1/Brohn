source("R/platform-core.R",encoding="UTF-8")
module<-Sys.getenv("BROHN_GNAT_CANDIDATE_MODULE","R/platform-gnat.R")
source(module,encoding="UTF-8")
source(Sys.getenv("BROHN_GNAT_CANDIDATE_JOURNAL","tests/fixtures/gnat-journal.R"),encoding="UTF-8")
local({
  folder<-commandArgs(TRUE)[1L];if(is.na(folder))folder<-tempfile("gnat-replay-candidate-")
  dir.create(folder,recursive=TRUE);stopifnot(!file.exists(file.path(folder,"results.json")))
  checks<-character();check<-function(label,ok){stopifnot(isTRUE(ok));checks<<-c(checks,label);cat("PASS",label,"\n")}
  refuses<-function(x)inherits(try(force(x),silent=TRUE),"try-error")
  compiled<-brohn_gnat_compile(brohn_gnat_new(id="gnat-reference"));events<-original_gnat_journal(compiled)
  pair<-function(outcome) {
    at<-which(vapply(events,function(e)identical(e$payload$kind,"task_trial_finished")&&identical(e$payload$data$outcome,outcome),logical(1)))[1L]
    d<-events[[at]]$payload$data;start<-events[[at-1L]]$payload$data
    trial<-Filter(function(t)identical(t$id,d$trial_id),compiled$timeline)[[1L]]
    list(data=d,onset=list(time=as.numeric(start$clock$value),held=start$held_codes),trial=trial,at=at)
  }
  cr<-pair("correct_rejection");hit<-pair("hit");miss<-pair("miss");fa<-pair("false_alarm")
  replay<-function(p,data=p$data).brohn_gnat_trial_replay(data,p$onset,p$trial,as.numeric(data$clock$value))
  for(p in list(cr,hit,miss,fa))check(paste("Derive actual four-outcome state",p$data$outcome),identical(replay(p)$outcome,p$data$outcome))
  key<-function(type,event,observed,open=TRUE,accepted=FALSE,reason="after_deadline",code="Space",trusted=TRUE,repeat_key=FALSE,modifiers=FALSE)
    list(type=type,code=code,event_ms=event,observed_ms=observed,`repeat`=repeat_key,trusted=trusted,modifiers=modifiers,response_open=open,accepted=accepted,ignored_reason=reason)
  exact<-cr$data;exact$keys<-list(key("down",exact$deadline_ms,exact$deadline_ms),key("up",exact$deadline_ms+1,exact$deadline_ms+1,reason="key_release"))
  check("Exactly-at-deadline key is late, with no fabricated response latency",replay(cr,exact)$outcome=="correct_rejection"&&is.null(replay(cr,exact)$response_ms))
  delayed<-miss$data;time<-delayed$deadline_ms-.000001
  delayed$keys<-list(key("down",time,delayed$deadline_ms+4,accepted=TRUE,reason=NULL),key("up",delayed$deadline_ms+5,delayed$deadline_ms+5,reason="key_release"))
  delayed$outcome<-delayed$response_outcome<-"hit";delayed$response_code<-"Space";delayed$response_ms<-round(time-delayed$onset_ms,6);delayed$correct<-TRUE
  check("On-time timestamp dispatched during pending deadline is accepted",replay(miss,delayed)$outcome=="hit"&&replay(miss,delayed)$response_ms<miss$trial$timeout_ms)
  invalid<-delayed;invalid$keys[[1]]$event_ms<-delayed$deadline_ms;invalid$response_ms<-miss$trial$timeout_ms
  check("Cannot shift exact-boundary response inside with tolerance",refuses(replay(miss,invalid)))
  fractional<-hit;fractional$onset$time<-1617.03;fd<-fractional$data;fd$onset_ms<-1617.03
  fd$deadline_ms<-round(fd$onset_ms+fractional$trial$timeout_ms,6)
  fd$keys[[1L]]$event_ms<-fd$keys[[1L]]$observed_ms<-1867.061234
  fd$keys[[2L]]$event_ms<-fd$keys[[2L]]$observed_ms<-1887.061234
  fd$response_ms<-250.031234;fd$response_closed_ms<-fd$feedback_start_ms<-1867.061234
  fd$feedback_end_ms<-1967.061234;fd$blank_end_ms<-2367.061234;fd$clock$value<-"2367.061234"
  fd$visibility[[1L]]$observed_ms<-fd$onset_ms;fd$visibility[[2L]]$observed_ms<-fd$blank_end_ms
  check("Six-decimal native arithmetic preserves fractional onset deadline and Space RT",replay(fractional,fd)$response_ms==250.031234)
  early<-fd;early$feedback_end_ms<-1967.061233
  check("One microsecond short feedback is not rounded into compliance",refuses(replay(fractional,early)))
  early<-fd;early$blank_end_ms<-2367.061233;early$visibility[[2L]]$observed_ms<-early$blank_end_ms
  check("One microsecond short blank is not rounded into compliance",refuses(replay(fractional,early)))
  altered<-fd;altered$response_ms<-250.031235
  check("One microsecond changed response summary is refused",refuses(replay(fractional,altered)))
  late<-cr$data;late$keys<-list(key("down",late$deadline_ms-1,late$response_closed_ms+10,FALSE,reason="eligible_key_after_seal"),
    key("up",late$deadline_ms,late$response_closed_ms+11,FALSE,reason="key_release"))
  check("Eligible timestamp arriving after sealed withholding refuses completion",refuses(replay(cr,late)))
  late$outcome<-"interrupted";late["correct"]<-list(NULL);late$interruption_reason<-"eligible_key_after_seal"
  check("Conflicting sealed outcome retained only as interrupted evidence",replay(cr,late)$outcome=="interrupted"&&is.null(replay(cr,late)$correct))
  mutators<-list(no_timer=function(x){x["deadline_timer_ms"]<-list(NULL);x},no_frame=function(x){x["deadline_frame_ms"]<-list(NULL);x},
    early_timer=function(x){x$deadline_timer_ms<-x$deadline_ms-1;x},early_close=function(x){x$response_closed_ms<-x$deadline_ms-1;x},
    fake_RT=function(x){x$response_ms<-x$deadline_ms-x$onset_ms;x},fake_zero_RT=function(x){x$response_ms<-0;x},fake_key=function(x){x$response_code<-"Space";x},
    null_accuracy=function(x){x["correct"]<-list(NULL);x},false_accuracy=function(x){x$correct<-FALSE;x},wrong_outcome=function(x){x$outcome<-x$response_outcome<-"miss";x$correct<-FALSE;x},
    missing_initial_visibility=function(x){x$visibility<-x$visibility[-1];x},missing_final_visibility=function(x){x$visibility<-x$visibility[1];x},
    hidden_midwindow=function(x){x$visibility<-append(x$visibility,list(list(observed_ms=x$onset_ms+100,visible=FALSE,focused=TRUE)),after=1);x},
    focus_lost=function(x){x$visibility<-append(x$visibility,list(list(observed_ms=x$onset_ms+100,visible=TRUE,focused=FALSE)),after=1);x},
    feedback_short=function(x){x$feedback_end_ms<-x$feedback_start_ms+99;x},blank_short=function(x){x$blank_end_ms<-x$feedback_end_ms+399;x},
    feedback_offset_reference=function(x){x$feedback_start_ms<-x$feedback_start_ms+1;x},hidden_at_onset=function(x){x$visibility[[1]]$visible<-FALSE;x},
    malformed_flag=function(x){x$visibility[[1]]$visible<-1;x},clock_reversed=function(x){x$visibility[[2]]$observed_ms<-x$onset_ms-1;x})
  for(name in names(mutators))check(paste("Refuse false withholding",name),refuses(replay(cr,mutators[[name]](cr$data))))
  interrupted<-mutators$hidden_midwindow(cr$data);interrupted$outcome<-"interrupted";interrupted["correct"]<-list(NULL);interrupted$interruption_reason<-"page_hidden"
  check("Actual visibility interruption preserved without qualified accuracy",is.null(replay(cr,interrupted)$correct))
  for(name in c("synthetic","repeat","modified")) {
    bad<-hit$data
    if(name=="synthetic")bad$keys[[1]]$trusted<-FALSE else if(name=="repeat")bad$keys[[1]][["repeat"]]<-TRUE else bad$keys[[1]]$modifiers<-TRUE
    check(paste("Invalid accepted physical key",name),refuses(replay(hit,bad)))
  }
  held<-hit;held$onset$held<-list("Space")
  check("Held key cannot create a new response",refuses(replay(held)))
  release<-hit$data;release$keys<-release$keys[1]
  check("Complete trial waits for retained Space release",refuses(replay(hit,release)))
  wrong<-cr$data;wrong$keys<-list(key("down",wrong$onset_ms+100,wrong$onset_ms+100,reason="other_key",code="KeyA"),
    key("up",wrong$onset_ms+110,wrong$onset_ms+110,reason="key_release",code="KeyA"))
  check("Other key is retained without becoming a Go response",replay(cr,wrong)$outcome=="correct_rejection")
  unmatched<-cr$data;unmatched$keys<-list(key("up",unmatched$onset_ms+100,unmatched$onset_ms+100,reason="key_release"))
  check("Unmatched trusted Space release cannot manufacture withholding",refuses(replay(cr,unmatched)))
  unmatched$outcome<-"interrupted";unmatched["correct"]<-list(NULL);unmatched$interruption_reason<-"impossible_space_state"
  check("Impossible Space state is retained only as interruption",replay(cr,unmatched)$outcome=="interrupted")
  repeated<-cr$data;repeated$keys<-list(key("down",repeated$onset_ms+100,repeated$onset_ms+100,reason="key_repeat",repeat_key=TRUE),
    key("up",repeated$onset_ms+110,repeated$onset_ms+110,reason="key_release"))
  check("Repeat without a preceding press cannot manufacture withholding",refuses(replay(cr,repeated)))
  early<-cr$data;early$keys<-list(key("down",early$onset_ms-1,early$onset_ms+1,reason="anticipatory"),
    key("up",early$onset_ms+2,early$onset_ms+2,reason="key_release"))
  check("Delayed anticipatory key cannot manufacture clean withholding",refuses(replay(cr,early)))
  reversed<-hit$data;reversed$keys[[2]]$event_ms<-reversed$keys[[1]]$event_ms-1;reversed$keys[[2]]$ignored_reason<-"event_clock_reversed"
  check("Reversed event clock invalidates otherwise correct response",refuses(replay(hit,reversed)))
  incomplete<-brohn_gnat_replay(compiled,events[1:3]);check("Partial journal never completes384 trials",!incomplete$complete)
  bad<-events[1:3];bad[[3]]$clock$instance_id<-bad[[3]]$payload$data$clock$instance_id<-"reload"
  check("Changed page clock refuses timed continuation",refuses(brohn_gnat_replay(compiled,bad)))
  bad<-events[c(1,3,2)];check("No finish without its received onset",refuses(brohn_gnat_replay(compiled,bad)))
  bad<-events[1:3];bad[[3]]$payload$data$procedure_hash<-paste(rep("0",64),collapse="")
  check("Foreign procedure receipt refused",refuses(brohn_gnat_replay(compiled,bad)))
  bad<-events[1:3];bad[[2]]$payload$data$held_codes<-list("Space")
  check("Onset cannot claim a held Space is released",refuses(brohn_gnat_replay(compiled,bad)))
  bad<-events[1:3];bad[[2]]$payload$data$focused<-FALSE
  check("Unfocused onset refused before withholding",refuses(brohn_gnat_replay(compiled,bad)))
  stop_event<-events[[1]];stop_event$payload$kind<-"task_interrupted";stop_event$payload$data<-list(task_id=compiled$id,
    procedure_hash=compiled$procedure_hash,clock=stop_event$clock,step_id=compiled$timeline[[1]]$id,reason="page_restart")
  check("Explicit interruption stays incomplete and cannot resume",!brohn_gnat_replay(compiled,list(events[[1]],stop_event))$complete&&
    refuses(brohn_gnat_replay(compiled,c(list(events[[1]],stop_event),events[2:3]))))
  wait<-events[[2]]$payload$data$release_wait;onset<-as.numeric(events[[2]]$payload$data$clock$value)
  initial<-wait;initial$held_codes<-list("Space");initial$keys<-list(list(type="up",code="Space",event_ms=onset-5,observed_ms=onset-5,
    `repeat`=FALSE,trusted=TRUE,modifiers=FALSE))
  check("Instruction Space release wait retains original held state and release",isTRUE(.brohn_gnat_release_wait(initial,onset,onset-50,list())))
  stalled<-initial;stalled$keys<-list()
  check("Held instruction key without observed release cannot begin stimulus",refuses(.brohn_gnat_release_wait(stalled,onset,onset-50,list())))
  hidden<-initial;hidden$visibility[[1]]$visible<-FALSE
  check("Hidden pre-onset wait cannot become visible stimulus evidence",refuses(.brohn_gnat_release_wait(hidden,onset,onset-50,list())))
  mismatch<-initial
  check("Final onset held snapshot must equal replayed raw state",refuses(.brohn_gnat_release_wait(mismatch,onset,onset-50,list("KeyA"))))
  impossible<-initial;impossible$held_codes<-list()
  check("Unmatched instruction-key release refused in pre-onset guard",refuses(.brohn_gnat_release_wait(impossible,onset,onset-50,list())))
  short<-initial;short$end_ms<-onset-1
  check("Pre-onset evidence must reach the actual onset frame",refuses(.brohn_gnat_release_wait(short,onset,onset-50,list())))
  incomplete_wait<-events[1:3];incomplete_wait[[2]]$payload$data$release_wait<-NULL
  check("Onset cannot omit original release-wait evidence",refuses(brohn_gnat_replay(compiled,incomplete_wait)))
  make_contradiction<-function(p,earlier) {
    e<-events[[p$at]];stamp<-as.numeric(e$clock$value)+10
    e$clock$value<-format(stamp,scientific=FALSE,trim=TRUE,digits=17);k<-key("down",earlier,stamp,FALSE,reason="eligible_key_after_seal")
    e$payload<-list(kind="task_interrupted",data=list(task_id=compiled$id,procedure_hash=compiled$procedure_hash,clock=e$clock,
      step_id=p$trial$id,reason="eligible_key_after_seal",contradiction=list(trial_id=p$trial$id,key=k)))
    e
  }
  contradiction<-make_contradiction(cr,cr$data$deadline_ms-1)
  sealed<-brohn_gnat_replay(compiled,c(events[seq_len(cr$at)],list(contradiction)))
  check("Later contradicting key preserves original correct rejection and both receipts",!sealed$complete&&sealed$state$interrupted&&
    sealed$state$responses[[length(sealed$state$responses)]]$outcome=="correct_rejection"&&
    identical(sealed$state$interruption$contradiction,contradiction$payload$data$contradiction))
  first_conflict<-make_contradiction(hit,hit$data$onset_ms+100)
  check("Earlier eligible key can contradict a previously sealed first response",brohn_gnat_replay(compiled,c(events[seq_len(hit$at)],list(first_conflict)))$state$interrupted)
  after_first<-make_contradiction(hit,hit$data$onset_ms+300)
  check("Later second response cannot be claimed as an earlier-key contradiction",refuses(brohn_gnat_replay(compiled,c(events[seq_len(hit$at)],list(after_first)))))
  at_deadline<-make_contradiction(cr,cr$data$deadline_ms)
  check("Deadline-equal key cannot contradict sealed withholding",refuses(brohn_gnat_replay(compiled,c(events[seq_len(cr$at)],list(at_deadline)))))
  foreign<-contradiction;foreign$payload$data$contradiction$trial_id<-"unknown-trial"
  check("Contradiction needs the exact prior sealed trial",refuses(brohn_gnat_replay(compiled,c(events[seq_len(cr$at)],list(foreign)))))
  failed_wait<-events[[2]];failed_wait$payload$kind<-"task_interrupted"
  failed_wait$payload$data<-list(task_id=compiled$id,procedure_hash=compiled$procedure_hash,clock=failed_wait$clock,
    step_id=compiled$timeline[[2]]$id,reason="impossible_space_state",release_wait=impossible)
  failed<-brohn_gnat_replay(compiled,list(events[[1]],failed_wait))
  check("Failed pre-onset wait retains raw evidence without invented onset or outcome",failed$state$interrupted&&length(failed$state$responses)==0L&&
    is.null(failed$state$active)&&identical(failed$state$interruption$release_wait,impossible))
  failed_wait$payload$data$reason<-"page_hidden";failed_wait$payload$data$release_wait<-hidden
  check("Hidden pre-onset wait remains interrupted evidence",brohn_gnat_replay(compiled,list(events[[1]],failed_wait))$state$interrupted)
  during<-failed_wait;during$payload$data$release_wait<-wait
  check("An active trial cannot disguise its interruption as a pre-onset wait",refuses(brohn_gnat_replay(compiled,list(events[[1]],events[[2]],during))))
  result<-list(passed=TRUE,status=if(nzchar(Sys.getenv("BROHN_GNAT_CANDIDATE_MODULE")))"external_staged_candidate"else"isolated_current_tree_component",checks=as.list(checks),count=length(checks),browser_or_outer_session_qualified=FALSE,
    source_sha256=digest::digest(file=module,algo="sha256"))
  writeLines(brohn_json(result,TRUE),file.path(folder,"results.json"),useBytes=TRUE)
  cat(brohn_json(list(passed=TRUE,count=length(checks),folder=folder)),"\n")
})
