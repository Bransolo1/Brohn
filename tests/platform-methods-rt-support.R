# Original complete task journals and hand arithmetic; no hardware or browser
# timing qualification. This is the metric-specific support regression scope.
source("R/platform-core.R")
source("R/platform-methods.R")
source("R/platform-delivery.R")
source("R/platform-task-delivery.R")
checks<-0L
check<-function(value,label){checks<<-checks+1L;if(!isTRUE(value))stop(label,call.=FALSE)}
near<-function(x,y)isTRUE(all.equal(x,y,tolerance=1e-12,check.attributes=FALSE))
trials<-function(compiled)Filter(function(x)x$type=="task_trial",compiled$timeline)
metric<-function(score,name)Filter(function(x)x$name==name,score$metrics)[[1]]
clock<-function(value)list(id="browser-monotonic",unit="ms",value=format(value,scientific=FALSE,trim=TRUE),instance_id="original-test-page",time_origin_ms="0")

# Exercise every instruction, onset, observed gap and terminal key/timeout through
# the production receiver before its summaries reach the scorer.
native_responses<-function(compiled,outcome_for) {
  step<-list(task=compiled)
  state<-list(active=list(instance="original-test-page",time=0,task=.brohn_task_delivery_new()))
  responses<-list();last_time<-0
  send<-function(kind,data,time) {
    event<-list(clock=clock(time),payload=list(kind=kind,data=data))
    state<<-.brohn_task_delivery_apply(state,event,step)
    last_time<<-time
  }
  for(trial in compiled$timeline) {
    t<-state$active$task
    if(trial$type=="task_instructions") {
      send("task_instructions",list(task_id=compiled$id,step_id=trial$id,block_id=trial$block_id,clock=clock(last_time)),last_time)
      next
    }
    boundary<-max(brohn_default(t$boundary_time,0),if(is.null(t$previous_response))0 else t$previous_response+t$previous_intertrial)
    onset<-boundary+trial$foreperiod_ms
    send("task_trial_started",list(task_id=compiled$id,trial_id=trial$id,block_id=trial$block_id,clock=clock(onset),
      observed_foreperiod_ms=trial$foreperiod_ms,scheduled_foreperiod_ms=trial$foreperiod_ms,
      observed_gap_since_previous_response_ms=if(is.null(t$previous_response))NULL else onset-t$previous_response,
      timing_reference="requestAnimationFrame_before_paint",viewport=list(width=800,height=600,device_pixel_ratio=1),
      stimulus_rect=list(x=100,y=100,width=50,height=50)),onset)
    response<-outcome_for(trial)
    responded<-response$outcome!="timeout"
    correct<-identical(response$outcome,"correct")
    rt<-if(responded)response$rt else NULL
    code<-if(!responded)NULL else if(correct)trial$correct_code else setdiff(unlist(trial$allowed_codes),trial$correct_code)[[1]]
    finish<-onset+if(responded)rt else trial$timeout_ms
    data<-list(task_id=compiled$id,trial_id=trial$id,block_id=trial$block_id,outcome=response$outcome,clock=clock(finish),
      response_code=code,final_code=if(correct)code else NULL,first_correct=correct,
      first_response_ms=rt,final_correct_ms=if(correct)rt else NULL,
      clock_instance_id="original-test-page",onset_ms=onset,foreperiod_start_ms=boundary,observed_foreperiod_ms=trial$foreperiod_ms,
      anticipatory_count=0L,keypresses=if(responded)list(list(code=code,clock=clock(finish),rt_ms=rt,accepted=TRUE,
        phase="response",correct=correct,ignored_reason=NULL))else list(),frame_count=1L,max_frame_gap_ms=16)
    send("task_trial_finished",data,finish)
    responses[[length(responses)+1L]]<-data
  }
  .brohn_task_delivery_complete(state,step,list(clock=clock(last_time)))
  check(length(state$active$task$completed)==length(trials(compiled)),"Every original trial was accepted by the strict receiver")
  responses
}
make<-function(profile,id)brohn_task_compile(brohn_task_new(profile,id=id),1L)
choice<-make("rt-deary-liewald-choice/1.0","rt-support-choice")
choice_hash<-brohn_hash(choice)

# Original defect: eight correct practice, exactly one correct 500 ms test
# response and 39 observed no-response timeouts. No fabricated missing values.
one<-native_responses(choice,function(t)if(!t$scored||t$trial_index==1L)list(outcome="correct",rt=500)else list(outcome="timeout"))
one_hash<-brohn_hash(one);one_score<-brohn_task_score(choice,one)
check(identical(one_score$schema_version,"brohn-task-score/1.1")&&identical(one_score$scoring_recipe,"brohn-rt-metric-support/1.0"),"New analysis support policy has explicit identities")
check(one_score$status=="partial"&&one_score$eligible,"Partial support is distinct from full RT availability")
check(one_score$counts$expected==48&&one_score$counts$received==48&&one_score$counts$scored==40&&one_score$counts$retained_correct==1,"Exact one-good 39-timeout evidence is retained")
check(near(metric(one_score,"test_omission_rate")$value,39/40),"Known omission rate remains 39/40")
check(metric(one_score,"test_omission_rate")$support$numerator==39&&metric(one_score,"test_omission_rate")$support$denominator==40,"Omission numerator and denominator are explicit")
check(near(metric(one_score,"test_first_response_error_rate")$value,0)&&metric(one_score,"test_first_response_error_rate")$support$denominator==1,"One correct answer gives known zero errors among one answer")
check(near(metric(one_score,"correct_test_rt_mean")$value,500)&&near(metric(one_score,"correct_test_rt_median")$value,500),"Versioned one-response mean and median are observed 500 ms")
check(is.null(metric(one_score,"correct_test_rt_sd")$value)&&!metric(one_score,"correct_test_rt_sd")$eligible&&nzchar(metric(one_score,"correct_test_rt_sd")$reason),"One response never fabricates variability")
check(metric(one_score,"correct_test_rt_sd")$support$minimum_count==2&&metric(one_score,"correct_test_rt_sd")$support$sample_sd_divisor==0,"Sample SD requirement and zero divisor are visible")
check(identical(choice_hash,brohn_hash(choice))&&identical(one_hash,brohn_hash(one)),"Scoring does not mutate frozen protocol or journal")

for(profile in c("rt-deary-liewald-simple/1.0","rt-deary-liewald-choice/1.0")) {
  compiled<-make(profile,paste0("all-omitted-",if(grepl("simple",profile))"simple"else"choice"))
  all_omitted<-native_responses(compiled,function(t)list(outcome="timeout"))
  score<-brohn_task_score(compiled,all_omitted)
  test_n<-if(grepl("simple",profile))20L else 40L
  check(score$status=="partial"&&score$eligible,"Omission evidence remains supported with no responses")
  check(metric(score,"test_omission_rate")$value==1&&metric(score,"test_omission_rate")$eligible,"All observed test omissions give rate one")
  check(metric(score,"test_omission_rate")$support$numerator==test_n&&metric(score,"test_omission_rate")$support$denominator==test_n,"Practice timeouts do not enter test omission denominator")
  error<-metric(score,"test_first_response_error_rate")
  check(is.null(error$value)&&!error$eligible&&error$support$numerator==0&&error$support$denominator==0,"Zero responses make error rate unavailable, never zero")
  check(all(vapply(score$metrics[1:3],function(m)is.null(m$value)&&!m$eligible,logical(1))),"All RT metrics unavailable when no response was retained")
  check(score$counts$scored_responded==0&&score$counts$scored_timeouts==test_n,"Scored-only counts are distinct from whole-task counts")
  check(!brohn_task_score(compiled,all_omitted,completed=FALSE)$eligible&&length(brohn_task_score(compiled,all_omitted,completed=FALSE)$metrics)==0,"Interrupted task cannot claim complete omission denominator")
  check(!brohn_task_score(compiled,all_omitted[-1])$eligible&&length(brohn_task_score(compiled,all_omitted[-1])$metrics)==0,"Missing even one practice trial retains complete-task evidence gate")
}

# Practice errors are deliberately present. Test trials: two correct at 300/700,
# three wrong first responses and 35 timeouts. Errors use 3/5, omissions 35/40.
mixed<-native_responses(choice,function(t)if(!t$scored)list(outcome="incorrect",rt=400)else if(t$trial_index<=2L)list(outcome="correct",rt=if(t$trial_index==1L)300 else 700)else if(t$trial_index<=5L)list(outcome="incorrect",rt=450)else list(outcome="timeout"))
score<-brohn_task_score(choice,mixed)
check(score$status=="computed"&&all(vapply(score$metrics,function(m)m$eligible,logical(1))),"Two correct responses plus known rates support every metric")
check(near(metric(score,"correct_test_rt_mean")$value,500)&&near(metric(score,"correct_test_rt_median")$value,500),"Two-value mean and median hand arithmetic")
check(near(metric(score,"correct_test_rt_sd")$value,sqrt(80000))&&metric(score,"correct_test_rt_sd")$support$sample_sd_divisor==1,"Two-value sample SD uses explicit n minus one")
check(near(metric(score,"test_first_response_error_rate")$value,3/5)&&near(metric(score,"test_omission_rate")$value,35/40),"Error and omission populations remain separate")
check(score$counts$first_response_errors==11&&score$counts$errors==3,"Practice errors remain traceable without contaminating test error rate")

all_errors<-native_responses(choice,function(t)list(outcome="incorrect",rt=400))
score<-brohn_task_score(choice,all_errors)
check(score$status=="partial"&&metric(score,"test_first_response_error_rate")$value==1&&metric(score,"test_omission_rate")$value==0,"All answered incorrectly gives error one and omission zero")
check(is.null(metric(score,"correct_test_rt_mean")$value),"Incorrect response times never become correct RTs")

# Frozen collection timeout can exceed the fixed analysis window. Correct and
# wrong answers outside that window still belong to answered-trial error counts.
long_task<-brohn_task_new("rt-deary-liewald-choice/1.0",id="long-timeout-support")
long_task$settings$trial_timeout_ms<-10000L
long<-brohn_task_compile(long_task,1L)
outside<-native_responses(long,function(t)if(!t$scored)list(outcome="correct",rt=500)else if(t$trial_index==1L)list(outcome="correct",rt=6000)else if(t$trial_index==2L)list(outcome="incorrect",rt=7000)else list(outcome="timeout"))
score<-brohn_task_score(long,outside)
check(score$counts$retained_correct==0&&score$counts$outside_rt_window==1,"Frozen RT window excludes the long correct response")
check(metric(score,"test_first_response_error_rate")$value==1/2&&metric(score,"test_omission_rate")$value==38/40,"Response-window exclusion never changes response or omission denominators")
check(is.null(metric(score,"correct_test_rt_mean")$value)&&metric(score,"test_first_response_error_rate")$eligible,"Response evidence can support rates without RT support")

zero<-native_responses(choice,function(t)list(outcome="correct",rt=0))
score<-brohn_task_score(choice,zero)
check(all(vapply(score$metrics,function(m)m$eligible&&identical(m$value,0),logical(1))),"Declared zero lower bound preserves genuine zero RT and observed zero sample SD")
check(metric(score,"correct_test_rt_mean")$support$denominator==40&&metric(score,"correct_test_rt_sd")$support$sample_sd_divisor==39,"Zero-valued data retain their nonzero sample count")
interrupted<-one;interrupted[[length(interrupted)]]$outcome<-"interrupted"
check(!brohn_task_score(choice,interrupted)$eligible&&length(brohn_task_score(choice,interrupted)$metrics)==0,"An explicitly interrupted trial suppresses complete-task metrics")
check(inherits(try(brohn_task_score(choice,c(one,one[1])),silent=TRUE),"try-error"),"Duplicate terminal trials still reject")
unknown<-one;unknown[[1]]$trial_id<-"not-in-this-protocol"
check(inherits(try(brohn_task_score(choice,unknown),silent=TRUE),"try-error"),"Unknown terminal trial still rejects")

# Independent arithmetic for all five complete profiles. Non-RT result contracts
# stay /1.0 and retain their existing D and keyboard contrast definitions.
complete<-function(compiled,fn)lapply(trials(compiled),function(t){rt<-fn(t);list(trial_id=t$id,outcome="correct",response_code=t$correct_code,final_code=t$correct_code,first_correct=TRUE,first_response_ms=rt,final_correct_ms=rt)})
iat<-make("iat-gnb2003-d1/1.0","import-iat-audit")
biat<-make("biat-nosek2014-goodfocal/1.0","import-biat-audit")
alternating<-function(t)if(identical(t$mapping,"B"))if(t$trial_index%%2L)900 else 1100 else if(t$trial_index%%2L)500 else 700
iat_score<-brohn_task_score(iat,complete(iat,alternating))
biat_score<-brohn_task_score(biat,complete(biat,alternating))
check(near(iat_score$metrics[[1]]$value,(400/sqrt(2000000/39)+400/sqrt(4000000/79))/2),"Complete original IAT hand-sum oracle is unchanged")
check(near(biat_score$metrics[[1]]$value,400/sqrt(1600000/31)),"Complete original BIAT hand-sum oracle is unchanged")
check(identical(brohn_hash(iat),"e7fd8704914e0a29dd78863d50789021890f973a8e9d82ac346b4b8c84465359"),"Original audited compiled IAT identity remains exact")
aat<-make("aat-keyboard-cue-balanced/1.0","import-aat-audit")
aat_score<-brohn_task_score(aat,complete(aat,function(t)if(t$category_id=="target-a")if(t$action=="avoid")800 else 500 else if(t$action=="avoid")700 else 600))
check(near(aat_score$metrics[[1]]$value,200),"Complete keyboard AAT difference of differences is unchanged")
check(all(vapply(list(iat_score,biat_score,aat_score),function(s)identical(s$schema_version,"brohn-task-score/1.0")&&is.null(s$scoring_recipe),logical(1))),"Non-RT result identity and eligibility policy are unchanged")
simple<-make("rt-deary-liewald-simple/1.0","import-simple-audit")
simple_score<-brohn_task_score(simple,complete(simple,function(t)300+10*t$trial_index))
choice_score<-brohn_task_score(choice,complete(choice,function(t)300+10*t$position))
check(near(metric(simple_score,"correct_test_rt_mean")$value,405)&&near(metric(simple_score,"correct_test_rt_median")$value,405)&&near(metric(simple_score,"correct_test_rt_sd")$value,sqrt(66500/19)),"Complete simple RT mean median and hand-sum sample SD are unchanged")
check(near(metric(choice_score,"correct_test_rt_mean")$value,325)&&near(metric(choice_score,"correct_test_rt_median")$value,325)&&near(metric(choice_score,"correct_test_rt_sd")$value,sqrt(5000/39)),"Complete choice RT mean median and hand-sum sample SD are unchanged")
check(isTRUE(one_score$support_policy$complete_trial_evidence_required)&&one_score$support_policy$mean_median_minimum_correct==1&&one_score$support_policy$sample_sd_minimum_correct==2,"Saved policy declares changed support requirements")
cat(sprintf("RT metric-specific support: %d checks passed; original complete receiver journals and all five hand arithmetic oracles.\n",checks))
