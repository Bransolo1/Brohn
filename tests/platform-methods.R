source("R/platform-core.R")
source("R/platform-methods.R")
source("R/platform-sciat-window.R")
checks<-0L
check<-function(value,label){checks<<-checks+1L;if(!isTRUE(value))stop(label,call.=FALSE)}
near<-function(x,y,tolerance=1e-10)isTRUE(all.equal(x,y,tolerance=tolerance,check.attributes=FALSE))
fails<-function(fn)inherits(try(fn(),silent=TRUE),"try-error")
trials<-function(compiled)Filter(function(step)step$type=="task_trial",compiled$timeline)
responses<-function(compiled,fn=function(trial)if(identical(trial$mapping,"B"))1000 else 600)lapply(trials(compiled),function(trial){rt<-fn(trial);list(trial_id=trial$id,
  outcome="correct",response_code=trial$correct_code,final_code=trial$correct_code,first_correct=TRUE,first_response_ms=rt,final_correct_ms=rt)})

profiles<-brohn_task_profiles()
expected_counts<-c(180L,96L,96L,28L,48L,192L)
compiled<-list()
for(i in seq_along(profiles)) {
  name<-names(profiles)[i];block<-brohn_task_new(name,id=paste0("task-",i))
  compiled[[name]]<-brohn_task_compile(block,1L)
  check(length(trials(compiled[[name]]))==expected_counts[i],paste("Frozen trial count",name))
  check(identical(brohn_hash(compiled[[name]]),brohn_hash(brohn_task_compile(block,1L))),paste("Repeatable seeded task",name))
  check(!anyDuplicated(brohn_ids(compiled[[name]]$timeline)),paste("Unique trial/instruction IDs",name))
}
iat<-compiled[[1]];biat<-compiled[[2]];aat<-compiled[[3]]
check(sum(vapply(trials(iat),function(x)x$scored,logical(1)))==120,"IAT includes combined practice and test")
check(identical(vapply(iat$blocks,function(x)x$trial_count,integer(1)),c(20L,20L,20L,40L,20L,20L,40L)),"IAT seven block counts")
check(brohn_task_compile(brohn_task_new(id="task-reverse"),2)$assignment$initial_mapping=="B","Counterbalanced initial mapping")
check(brohn_task_compile(brohn_task_new(id="task-side"),3)$assignment$positive_attribute_key=="KeyI","Counterbalanced attribute key")
for(block in Filter(function(x)x$block_index %in% c(3,4,6,7),trials(iat))) {
  role<-brohn_find(iat$categories,block$category_id)$role
  check((block$trial_index%%2==1)==startsWith(role,"target"),"Combined IAT alternates target and attribute trials")
}
check(sum(vapply(trials(biat),function(x)x$scored,logical(1)))==64,"BIAT scoring denominator64 before exclusions")
prefix<-Filter(function(x)x$trial_index<=4,trials(biat))
check(all(vapply(prefix,function(x)brohn_find(biat$categories,x$category_id)$role %in% c("target_a","target_b","warmup_a","warmup_b"),logical(1))),"BIAT prefixes are target-only per primary paper")
check(all(vapply(Filter(function(x)x$block_index==1,trials(biat)),function(x)!x$scored,logical(1))),"BIAT warm-up excluded")
aat_test<-Filter(function(x)x$scored,trials(aat))
cells<-table(vapply(aat_test,function(x)paste(x$category_id,x$action),character(1)))
check(length(cells)==4 && all(cells==20),"Keyboard AAT balanced category-by-action cells")
check(all(vapply(trials(compiled[[4]]),function(x)x$foreperiod_ms>=1000 && x$foreperiod_ms<=3000 && x$correct_code=="KeyB",logical(1))),"Simple RT frozen foreperiod and key")
check(all(table(vapply(Filter(function(x)x$scored,trials(compiled[[5]])),function(x)x$position,integer(1)))==10),"Choice RT equal positions")

positive<-data.frame(score_block=rep(c("Ap","At","Bp","Bt"),each=2),latency_ms=c(500,700,600,800,900,1100,1000,1200))
expected<-400/sqrt(200000/3)
check(near(brohn_iat_d1(positive)$value,expected),"Independent IAT sample-SD contrast")
negative<-positive;negative$score_block<-c(Ap="Bp",At="Bt",Bp="Ap",Bt="At")[negative$score_block]
check(near(brohn_iat_d1(negative)$value,-expected),"Mapping reversal reverses D")
corrected<-positive;corrected$latency_ms[1]<-1300
check(near(brohn_iat_d1(corrected)$value,expected/2),"Correction-inclusive latency has no added penalty")
check(near(brohn_iat_d1(rbind(positive,transform(positive[1,],latency_ms=10001)))$value,expected),"Slow trial exclusion above10000")
zero<-positive;zero$latency_ms<-700
check(is.null(brohn_iat_d1(zero)$value),"Zero pairSD unavailable")
boundary<-positive[rep(seq_len(nrow(positive)),each=5),];boundary$latency_ms[1:4]<-250
check(brohn_iat_d1(boundary)$eligible,"Exactly10percent fast retained")
boundary$latency_ms[5]<-250
check(!brohn_iat_d1(boundary)$eligible,"Above10percent fast excluded")
check(!brohn_iat_d1(positive,completed=FALSE)$eligible,"Incomplete task not scored")

biat_responses<-responses(biat,function(trial) if(identical(trial$mapping,"B"))1000+trial$trial_index else 600+trial$trial_index)
biat_trials<-trials(biat);eligible<-which(vapply(biat_trials,function(x)x$scored,logical(1)))
for(index in eligible[1:6]){biat_responses[[index]]$first_response_ms<-250;biat_responses[[index]]$final_correct_ms<-250}
biat_responses[[eligible[17]]]$first_response_ms<-10001;biat_responses[[eligible[17]]]$final_correct_ms<-10001
score<-brohn_task_score(biat,biat_responses)
check(score$eligible && score$scoring_audit$fast_numerator==6 && score$scoring_audit$fast_denominator==63,"BIAT6over63 fast screen before bounding")
check(all(vapply(score$scoring_audit$pairs,function(x)x$mapping_a_mean_ms>=400,logical(1))),"BIAT bound applied after fast audit")
check(!brohn_task_score(iat,responses(iat)[-1])$eligible,"Missing frozen trial denies score")
check(fails(function()brohn_task_score(iat,c(responses(iat),responses(iat)[1]))),"Duplicate trial IDs rejected")
wrong<-responses(iat);wrong[[1]]$response_code<-if(wrong[[1]]$response_code=="KeyE")"KeyI"else"KeyE"
check(fails(function()brohn_task_score(iat,wrong)),"Accuracy cannot contradict frozen expected key")
aat_result<-brohn_task_score(aat,responses(aat,function(trial)if(trial$category_id=="target-a")if(trial$action=="avoid")800 else 500 else if(trial$action=="avoid")700 else 600))
check(aat_result$eligible && near(aat_result$metrics[[1]]$value,200),"Keyboard AAT independent double difference")
reordered<-aat;reordered$categories<-rev(reordered$categories)
check(near(brohn_task_score(reordered,responses(aat,function(trial)if(trial$category_id=="target-a")if(trial$action=="avoid")800 else 500 else if(trial$action=="avoid")700 else 600))$metrics[[1]]$value,200),"AAT direction follows roles not category-list order")
rt_result<-brohn_task_score(compiled[[4]],responses(compiled[[4]],function(trial)300+trial$trial_index))
check(rt_result$eligible && near(rt_result$metrics[[1]]$value,310.5),"Simple RT excludes practice from mean")

work<-normalizePath("../../work",winslash="/",mustWork=TRUE)
.libPaths(c(file.path(work,"r-library-implicit-methods"),.libPaths()))
environment<-new.env();data("raw_data",package="implicitMeasures",envir=environment);data("iatdscores",package="implicitMeasures",envir=environment)
reference<-implicitMeasures::clean_iat(environment$raw_data,sbj_id="Participant",block_id="blockcode",
  mapA_practice="practice.iat.Milkbad",mapA_test="test.iat.Milkbad",mapB_practice="practice.iat.Milkgood",mapB_test="test.iat.Milkgood",
  latency_id="latency",accuracy_id="correct",trial_id="trialcode",trial_eliminate=c("reminder","reminder1"))[[1]]
rows<-split(reference,reference$participant)
values<-lapply(rows,function(participant)brohn_iat_d1(data.frame(score_block=paste0(ifelse(participant$condition=="MappingA","A","B"),ifelse(participant$block_pool=="practice","p","t")),latency_ms=participant$latency)))
eligible_names<-names(values)[vapply(values,function(value)value$eligible,logical(1))]
check(length(values)==162,"All162 upstream reference tasks checked")
for(id in eligible_names) {
  expected_value<-environment$iatdscores$dscore_d1[as.character(environment$iatdscores$participant)==id]
  check(near(values[[id]]$value,expected_value,1e-12),"Eligible D matches upstream reference")
}
cat(sprintf("Task methods: %d checks passed; %d/162 upstream tasks eligible and matched.\n",checks,length(eligible_names)))
