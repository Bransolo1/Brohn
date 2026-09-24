source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
source("tests/fixtures/paired-aggregation-reference.R")
source("tests/fixtures/paired-results-fixture.R")
args<-commandArgs(trailingOnly=TRUE)
local({
  checks<-0L;check<-function(name,ok){if(!isTRUE(ok))stop(paste("Paired aggregation:",name));checks<<-checks+1L;cat("PASS",name,"\n")}
  f<-researcher_paired_fixture();conditions<-f$design$conditions
  rows<-do.call(rbind,lapply(f$responses,function(r)data.frame(participant_id=r$participant_id,session_id=r$session_id,condition_id=r$condition_id,
    metric="explicit_response",outcome_id="q-liking",unit="response units",value=brohn_default(r$value,NA_real_))))
  exact<-function(x,c=conditions){baseline<-paired_aggregation_reference(x,c);actual<-brohn_paired_contrasts(x,c)
    identical(actual,baseline)&&identical(brohn_json(actual),brohn_json(baseline))}
  result<-brohn_paired_contrasts(rows,conditions)[[1L]]
  check("unequal repeated visits preserve independent person differences4,8,12",identical(vapply(result$participant_differences,`[[`,numeric(1),"value"),c(4,8,12))&&result$estimate==8&&result$paired_session_count==4&&result$participant_count==3&&result$excluded_session_count==1)
  margin<-sqrt(2*.95^2/(1-.95^2))*4/sqrt(3)
  check("uncertainty matches independent df2 closed form",abs(result$interval95$lower-(8-margin))<1e-10&&abs(result$interval95$upper-(8+margin))<1e-10)
  check("complete legacy result is exactly equal to frozen reference",exact(rows))
  permutations<-list(rev(seq_len(nrow(rows))),c(4,3,2,1,16,15,14,13,12,11,10,9,8,7,6,5),c(seq(1,nrow(rows),2),seq(2,nrow(rows),2)))
  for(i in seq_along(permutations))check(paste("source permutation",i,"retains its exact original result and person order"),exact(rows[permutations[[i]],,drop=FALSE]))
  one<-rows[rows$participant_id=="P1"&rows$session_id=="V1",,drop=FALSE];check("one paired person keeps unavailable interval",exact(one)&&is.null(brohn_paired_contrasts(one,conditions)[[1]]$interval95))
  none<-rows[rows$condition_id=="condition-a",,drop=FALSE];check("no condition pairs retain null estimate and all exclusions",exact(none)&&is.null(brohn_paired_contrasts(none,conditions)[[1]]$estimate))
  missing<-rows;missing$value<-NA_real_;check("all missing observations preserve exact zero-person support",exact(missing))
  extremes<-rows;extremes$value[c(1,2,3,5)]<-c(Inf,-Inf,NaN,-0);check("nonfinite values retain original exclusions and signed zero arithmetic",exact(extremes))
  empty<-rows[FALSE,,drop=FALSE];check("empty input and missing conditions remain empty results",exact(empty)&&exact(rows,list())&&exact(rows,conditions[-1]))
  multiple<-rbind(rows,transform(rows,metric="other_metric",outcome_id="outcome-two",unit="scale points",value=value*1e-11))
  check("multiple measures and units preserve exact output ordering",exact(multiple))
  repeats<-rbind(rows,rows[1:3,]);repeats$session_id[(nrow(rows)+1):nrow(repeats)]<-"V-new"
  check("additional unequal visits keep every original denominator",exact(repeats))
  unusual<-rows;unusual$participant_id<-c('person|A','person|A','person|A','person|A',rep('person"B',3),rep('person C',3),rep('person D',3),rep('person E',3))
  check("opaque identity strings preserve original grouping order",exact(unusual))
  # The declared plan consumes the exact legacy contrasts then applies its own
  # saved t-test/multiplicity policy. Switching only the function implementation
  # must preserve that complete analysis, including existing provenance fields.
  d<-f$design;d$analysis_plan<-brohn_new_analysis_plan();d$analysis_plan$rationale<-"Original planned differential regression"
  d$analysis_plan$comparisons<-list(list(id="pair-b",measure="questionnaire_numeric",outcome_id="q-liking",control_id="condition-a",test_id="condition-b"),
    list(id="pair-c",measure="questionnaire_numeric",outcome_id="q-liking",control_id="condition-a",test_id="condition-c"))
  a<-brohn_questionnaire_analysis(f$responses,d);actual<-brohn_analysis_plan_result(a,d)
  original<-brohn_paired_contrasts;assign("brohn_paired_contrasts",paired_aggregation_reference,envir=.GlobalEnv)
  expected<-tryCatch(brohn_analysis_plan_result(a,d),finally=assign("brohn_paired_contrasts",original,envir=.GlobalEnv))
  check("declared p-values, multiplicity and complete analysis remain byte-canonical identical",identical(brohn_json(actual),brohn_json(expected)))
  if(length(args)&&args[[1]] %in% c("--benchmark","--verify-benchmark")) {
    stopifnot(length(args)==if(args[[1]]=="--benchmark")2L else 3L)
    out<-normalizePath(tail(args,1),winslash="/",mustWork=FALSE);dir.create(dirname(out),recursive=TRUE,showWarnings=FALSE)
    stress<-do.call(rbind,lapply(seq_len(1000),function(i){r<-rows[1:3,];r$participant_id<-sprintf("Person%04d",i);r}))
    # An in-process candidate permits profiling during a shared-source freeze.
    code<-paste(readLines("tests/fixtures/paired-aggregation-reference.R",warn=FALSE),collapse="\n")
    code<-sub("paired_aggregation_reference <-","candidate <-",code,fixed=TRUE)
    code<-sub('for \\(group in brohn_group\\(values, c\\("participant_id", "session_id"\\)\\)\\)',
      'session_groups <- brohn_group(values, c("participant_id", "session_id"))\n      for (group in session_groups)',code)
    code<-sub('person <- vapply\\(brohn_group\\(delta, "participant_id"\\),','person_groups <- brohn_group(delta, "participant_id")\n      person <- vapply(person_groups,',code)
    code<-gsub('length\\(brohn_group\\(values, c\\("participant_id", "session_id"\\)\\)\\)','length(session_groups)',code)
    code<-gsub('brohn_group\\(delta, "participant_id"\\)\\[\\[i\\]\\]','person_groups[[i]]',code)
    eval(parse(text=code))
    check("isolated candidate has exactly one cached person grouping call",length(gregexpr('brohn_group(delta, "participant_id")',code,fixed=TRUE)[[1]])==1L&&
      grepl("participant_differences = lapply",code,fixed=TRUE)&&grepl("delta$participant_id[person_groups[[i]][1]]",code,fixed=TRUE))
    group_original<-brohn_group
    measure<-function(fn,label){counts<-list(person_calls=0L,person_rows=0L,session_calls=0L,session_rows=0L)
      assign("brohn_group",function(table,fields){if(identical(fields,"participant_id")){counts$person_calls<<-counts$person_calls+1L;counts$person_rows<<-counts$person_rows+nrow(table)}
        if(identical(fields,c("participant_id","session_id"))){counts$session_calls<<-counts$session_calls+1L;counts$session_rows<<-counts$session_rows+nrow(table)};group_original(table,fields)},envir=.GlobalEnv)
      profile<-paste0(out,".",label,".Rprof");Rprof(profile,interval=.01)
      elapsed<-system.time(value<-fn(stress,conditions))
      Rprof(NULL);assign("brohn_group",group_original,envir=.GlobalEnv)
      stats<-summaryRprof(profile)$by.total;top<-head(stats,12)
      list(value=value,receipt=list(elapsed_s=unname(elapsed[["elapsed"]]),user_s=unname(elapsed[["user.self"]]),group_counts=counts,
        output_hash=brohn_hash(value),profile_top=brohn_rows(data.frame(function_name=rownames(top),top,row.names=NULL))))}
    on.exit({Rprof(NULL);assign("brohn_group",group_original,envir=.GlobalEnv)},add=TRUE)
    if(args[[1]]=="--benchmark") {
      cat("Profiling frozen reference at1000 people/3000 rows...\n");baseline<-measure(paired_aggregation_reference,"baseline")
      cat("Profiling isolated in-process candidate...\n");optimized<-measure(candidate,"candidate")
      check("1000-person candidate equals frozen reference exactly",identical(baseline$value,optimized$value)&&identical(brohn_json(baseline$value),brohn_json(optimized$value)))
    }else {
      previous<-brohn_read_json_file(args[[2]]);stopifnot(previous$people==1000,previous$observations==3000,isTRUE(previous$exact_canonical_equality))
      baseline<-list(receipt=previous$baseline);optimized<-measure(brohn_paired_contrasts,"production")
      check("production1000-person output matches the retained frozen baseline hash",identical(optimized$receipt$output_hash,baseline$receipt$output_hash)&&identical(brohn_json(optimized$value),brohn_json(candidate(stress,conditions))))
    }
    check("person grouping falls from1002calls to2 without changing either contrast",baseline$receipt$group_counts$person_calls==1002&&optimized$receipt$group_counts$person_calls==2)
    brohn_write_json_file(list(schema="brohn-paired-aggregation-benchmark/1.0",origin="original_synthetic",people=1000,observations=3000,
      measured_implementation=if(args[[1]]=="--benchmark")"isolated_candidate"else"production",
      source_sha256=digest::digest(file="R/platform-analysis.R",algo="sha256"),baseline=baseline$receipt,candidate=optimized$receipt,
      exact_canonical_equality=TRUE,checks=checks),out)
    cat("BENCHMARK",brohn_json(list(baseline_s=baseline$receipt$elapsed_s,candidate_s=optimized$receipt$elapsed_s,receipt=out)),"\n")
  }
  cat("PASS paired aggregation:",checks,"checks\n")
})
