# Unregistered arithmetic prototype. No participant task or accepted recipe is
# changed by sourcing this file. See docs/qa/SCIAT-WINDOW-CANDIDATE.md.
brohn_sciat_window_candidate <- function() list(
  id="sciat-response-window-im100/0.1-candidate",registered=FALSE,
  scope="Numerical candidate; collection, replay and method qualification pending",
  response_semantics="First valid response; no correction-inclusive latency",
  response_window_ms=1500L,minimum_retained_ms=350L,error_penalty_ms=400L,
  error_base="All retained response latencies in the same mapping, including errors",
  sd_support="Pooled original retained correct latencies; sample SD with N-1",
  mappings=list(A="Target + positive",B="Target + negative"),
  reference=list(package="implicitMeasures",version="1.0.0",
    source="https://github.com/OttaviaE/implicitMeasures/tree/41b3812ab1d94f624113eb3e11028cf50fff6b2c",
    procedure="https://myscp.org/wp-content/uploads/2023/03/2007-proceedings.pdf#page=149"))

brohn_sciat_window_candidate_reduce <- function(trials) {
  # This pure reducer accepts small arithmetic probes as well as complete test
  # counts. It NEVER asserts that design, participant completion or clock replay
  # have been verified. A future source-bound adapter must establish those facts.
  require<-function(ok,text)if(!isTRUE(ok))stop(text,call.=FALSE)
  fields<-c("trial_id","mapping","outcome","latency_ms","correct")
  require(is.data.frame(trials)&&identical(names(trials),fields)&&nrow(trials)>0L&&nrow(trials)<=144L,
    "Supply the exact five-column test-trial contract, with 1 to 144 rows.")
  require(is.character(trials$trial_id)&&!anyNA(trials$trial_id)&&
    all(nchar(trials$trial_id,type="bytes") %in% 1:160)&&!anyDuplicated(trials$trial_id),
    "Every test trial needs a unique bounded identity.")
  require(is.character(trials$mapping)&&!anyNA(trials$mapping)&&all(trials$mapping %in% c("A","B")),
    "Declare only mapping A (target-positive) or B (target-negative).")
  require(is.character(trials$outcome)&&!anyNA(trials$outcome)&&all(trials$outcome %in% c("response","omission")),
    "Declare an actual first response or an explicit omission for every row.")
  require(is.numeric(trials$latency_ms)&&!is.factor(trials$latency_ms)&&is.logical(trials$correct),
    "Latency must be numeric milliseconds and accuracy literal logical values.")
  response<-trials$outcome=="response";omission<-!response
  require(all(is.finite(trials$latency_ms[response]))&&all(trials$latency_ms[response]>=0)&&
    all(trials$latency_ms[response]<=1500)&&!anyNA(trials$correct[response]),
    "First responses need finite latency within 0 to 1500 ms and observed accuracy.")
  require(all(is.na(trials$latency_ms[omission]))&&all(!is.nan(trials$latency_ms[omission]))&&
    all(is.na(trials$correct[omission])),"Explicit omissions must not acquire invented latency or accuracy.")
  order<-rle(trials$mapping)$values
  require(length(order)<=2L&&!anyDuplicated(order),"The two test mappings must retain their contiguous administration order.")
  fast<-response&!is.na(trials$latency_ms)&trials$latency_ms<350
  retained<-response&!fast
  correct<-retained&!is.na(trials$correct)&trials$correct
  error<-retained&!is.na(trials$correct)&!trials$correct
  rows<-trials;rows$reason<-ifelse(omission,"explicit_omission",ifelse(fast,"below_350_ms",ifelse(correct,"retained_correct","retained_error")))
  rows$scoring_latency_ms<-NA_real_
  mapping<-lapply(c("A","B"),function(m){
    selected<-trials$mapping==m;kept<-selected&retained;answered<-selected&response
    base<-if(any(kept))mean(trials$latency_ms[kept])else NULL
    rows$scoring_latency_ms[selected&correct]<<-trials$latency_ms[selected&correct]
    if(!is.null(base))rows$scoring_latency_ms[selected&error]<<-base+400
    list(mapping=m,presented=sum(selected),responded=sum(answered),omitted=sum(selected&omission),
      removed_fast=sum(selected&fast),retained=sum(kept),retained_correct=sum(selected&correct),retained_errors=sum(selected&error),
      accuracy_among_responses=if(any(answered))mean(trials$correct[answered])else NULL,
      accuracy_among_retained=if(any(kept))mean(trials$correct[kept])else NULL,
      correct_fraction_of_presented=if(any(selected))sum(trials$correct[answered])/sum(selected)else NULL,
      error_replacement_base_ms=base,adjusted_mean_ms=if(any(kept))mean(rows$scoring_latency_ms[kept])else NULL)
  });names(mapping)<-c("A","B")
  original_correct<-trials$latency_ms[correct]
  sd<-if(length(original_correct)>=2L)stats::sd(original_correct)else NULL
  unavailable<-if(any(vapply(mapping,function(x)x$retained==0L,logical(1))))"mapping_without_retained_responses"else
    if(length(original_correct)<2L)"fewer_than_two_pooled_correct_responses"else
      if(!is.finite(sd)||sd<=0)"zero_or_nonfinite_correct_response_variance"else NULL
  package_d<-if(is.null(unavailable))(mapping$A$adjusted_mean_ms-mapping$B$adjusted_mean_ms)/sd else NULL
  if(!is.null(package_d)&&!is.finite(package_d)){unavailable<-"nonfinite_standardized_contrast";package_d<-NULL}
  list(schema="brohn-sciat-window-candidate-result/0.1",candidate=brohn_sciat_window_candidate(),
    qualified_task_result=FALSE,scope="Arithmetic only; complete frozen design and participant replay are not verified",
    mapping_order=paste(order,collapse="_then_"),status=if(is.null(unavailable))"available_arithmetic"else"unavailable",reason=unavailable,
    counts=list(presented=nrow(trials),responded=sum(response),omitted=sum(omission),removed_fast=sum(fast),retained=sum(retained),
      retained_correct=sum(correct),retained_errors=sum(error)),
    mapping=mapping,pooled_correct_sample_sd_ms=sd,
    reference_package_d=package_d,target_positive_d=if(is.null(package_d))NULL else -package_d,
    qc=list(below_75pct_response_accuracy=any(vapply(mapping,function(x)!is.null(x$accuracy_among_responses)&&x$accuracy_among_responses<.75,logical(1))),
      exclusion_applied=FALSE),rows=rows)
}
