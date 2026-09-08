# Pure original arithmetic and canonical-import fixtures. No store/worker/UI claim.
for(n in c("core","methods","analysis","task-import","task-cohort"))source(paste0("R/platform-",n,".R"))
local({
  checks<-0L
  check<-function(label,x){if(!isTRUE(x))stop("Task cohort: ",label,call.=FALSE);checks<<-checks+1L}
  rejects<-function(expr,pattern=NULL){error<-tryCatch({force(expr);NULL},error=conditionMessage);!is.null(error)&&(is.null(pattern)||grepl(pattern,error,fixed=TRUE))}
  near<-function(a,b)isTRUE(all.equal(a,b,tolerance=1e-12,check.attributes=FALSE))
  directory<-"tests/fixtures/task-import";manifest<-brohn_parse(rawToChar(readBin(file.path(directory,"manifest.json"),"raw",n=1e6)))
  fixtures<-list();serial<-0L
  for(name in names(manifest$fixtures)) {
    f<-manifest$fixtures[[name]];r<-brohn_parse(rawToChar(readBin(file.path(directory,f$registry),"raw",n=16*1024^2)))
    d<-brohn_new_design("Original cohort source","blank",paste0("cohort-study-",name));d$blocks<-list(r$task)
    fixtures[[name]]<-list(data=brohn_read_table(file.path(directory,f$csv),"csv",20000L),r=r,d=d,m=f$metadata,f=f)
  }
  attempt<-function(person="P",session="S1",visit="A1",collection="C1",mean_ms=NULL,kind="choice",partial=FALSE,omitted=FALSE,incomplete=FALSE,unknown=FALSE,linkage=TRUE) {
    f<-fixtures[[kind]];data<-f$data;m<-f$m
    data[[m$participant_column]]<-person;data[[m$session_column]]<-session;data[[m$attempt_column]]<-visit
    data[[m$participant_linkage_column]]<-if(linkage)"true"else"false";m$source_collection_id<-collection
    if(!is.null(mean_ms))data$first_response_ms<-data$final_correct_ms<-as.character(mean_ms)
    trials<-Filter(function(s)s$type=="task_trial",f$r$protocols[[1L]]$compiled$timeline)
    scored<-which(vapply(trials,`[[`,logical(1),"scored"))
    if(partial||omitted) {
      chosen<-if(omitted)scored else scored[-1L]
      data$outcome[chosen]<-"timeout";data$first_correct[chosen]<-"false"
      for(field in c("first_code","final_code","first_response_ms","final_correct_ms"))data[[field]][chosen]<-""
    }
    if(incomplete)data<-data[-nrow(data),,drop=FALSE]
    if(unknown)m$source_rt_definition<-"unknown"
    file<-tempfile("brohn-original-cohort-",fileext=".csv")
    on.exit(unlink(file),add=TRUE)
    utils::write.table(data,file,sep=",",row.names=FALSE,col.names=TRUE,quote=TRUE,qmethod="double",fileEncoding="UTF-8",eol="\n")
    serial<<-serial+1L
    source<-list(id=paste0("original-cohort-source-",serial),revision=1L,hash=digest::digest(file=file,algo="sha256"),origin="sample",registry_object_hash=f$f$registry_sha256)
    brohn_import_task_trials(brohn_read_table(file,"csv",20000L),m,f$d,source,f$r)$task_attempts[[1L]]
  }
  plan_for<-function(attempts,policy="equal_attempts_within_session_then_equal_sessions_within_person") {
    a<-attempts[[1L]]
    list(schema="brohn-task-cohort-plan/1.0",description="Original explicitly selected arithmetic fixture",
      membership=lapply(attempts,function(a)list(attempt_id=a$id,attempt_hash=brohn_hash(a))),
      homogeneous=list(task_id=a$task_id,task_definition_hash=a$task_definition_hash,profile=a$profile,
        collection_origin=a$collection_origin,material_origin=a$material_origin,score_schema=a$score$schema_version,
        scoring_recipe=a$score$scoring_recipe,evidence_level=a$evidence_level),repeat_policy=policy)
  }
  linked<-function(attempts) {
    map<-brohn_task_cohort_identity_rows(attempts);map$linkage_statement<-"Original fixture researcher explicitly confirms these person and session identities."
    map$participants<-lapply(map$participants,function(p){p$person_id<-p$participant_id;p})
    map$sessions<-lapply(map$sessions,function(s){s$session_id<-s$source_session_id;s})
    map
  }
  run<-function(attempts,plan=plan_for(attempts),map=linked(attempts))brohn_task_cohort(attempts,plan,map)
  metric<-function(result,name="correct_test_rt_mean")Filter(function(x)x$metric==name,result$summaries)[[1L]]
  a<-attempt(mean_ms=1);b<-attempt(session="S2",mean_ms=1);c<-attempt(person="Q",mean_ms=3)
  originals<-list(a,b,c);result<-run(originals);s<-metric(result)
  check("two repeated sessions are one person: mean2 not5/3",s$mean==2&&s$contributing_person_count==2&&s$selected_attempt_count==3&&near(s$between_person_sd,sqrt(2)))
  check("repeat support stays explicit per metric",s$contributing_session_count==3&&s$eligible_attempt_count==3&&length(result$attempt_metrics)==15L&&length(result$per_person)==10L&&length(result$per_session)==15L)
  check("no inference fields or fake confidence intervals",!result$quality$inference_performed&&length(result$contrasts)==0L&&!any(c("p","p_value","confidence_interval","ci_lower","ci_upper") %in% names(s)))
  check("source and plan evidence remain frozen",identical(result$provenance$plan,plan_for(originals))&&identical(result$membership[[1L]]$source,a$source)&&result$membership[[1L]]$compiled_hash==a$compiled_hash&&result$provenance$identity_map_hash==brohn_hash(linked(originals)))
  check("order supplied by frozen membership not caller input",identical(run(rev(originals),plan_for(originals),linked(originals)),result))
  d<-attempt(session="S3",mean_ms=1)
  s4<-metric(run(c(originals,list(d))))
  check("another identical session cannot inflate person N or shift mean",s4$mean==2&&s4$contributing_person_count==2&&s4$contributing_session_count==4)
  nested<-list(attempt(mean_ms=0),attempt(visit="A2",mean_ms=2),attempt(session="S2",mean_ms=3),attempt(person="Q",mean_ms=6))
  n<-run(nested);ns<-metric(n)
  check("attempt then session then person weighting: ((0+2)/2+3)/2 and6 yields4",ns$mean==4&&ns$contributing_person_count==2&&near(ns$between_person_sd,sqrt(8)))
  pn<-Filter(function(p)p$metric=="correct_test_rt_mean"&&p$person_id=="P",n$per_person)[[1L]]
  check("person P retains three attempts but two equal sessions",pn$value==2&&pn$selected_attempt_count==3&&pn$eligible_session_count==2)
  check("one selected attempt policy rejects repeats before scoring",rejects(run(originals,plan_for(originals,"one_selected_attempt_per_person")),"before considering"))
  single<-run(list(a,c),plan_for(list(a,c),"one_selected_attempt_per_person"))
  check("one selected per person matches direct equal-person mean",metric(single)$mean==2&&metric(single)$contributing_person_count==2)
  partial<-attempt(mean_ms=500,partial=TRUE);full<-attempt(person="Q",mean_ms=300)
  r<-run(list(partial,full));om<-metric(r,"test_omission_rate");sdm<-metric(r,"correct_test_rt_sd")
  check("one correct39 timeouts contributes omission39/40 independently",om$mean==39/80&&om$contributing_person_count==2&&om$eligible_attempt_count==2)
  check("partial RT mean stays usable while its SD cannot add support",metric(r)$mean==400&&metric(r)$contributing_person_count==2&&sdm$mean==0&&sdm$contributing_person_count==1&&is.null(sdm$between_person_sd)&&sdm$eligible_attempt_count==1)
  ar<-Filter(function(x)x$attempt_id==partial$id&&x$metric=="correct_test_rt_sd",r$attempt_metrics)[[1L]]
  check("unsupported selected metric keeps exact null support and reason",!ar$eligible&&is.null(ar$value)&&ar$support$minimum_count==2&&ar$support$eligible_count==1&&nzchar(ar$reason))
  er<-Filter(function(x)x$attempt_id==partial$id&&x$metric=="test_first_response_error_rate",r$attempt_metrics)[[1L]]
  check("known zero errors are not missing and retain their numerator/denominator",er$eligible&&er$value==0&&er$support$numerator==0&&er$support$denominator==1)
  all_missing<-attempt(person="R",omitted=TRUE)
  r<-run(list(all_missing));check("all omitted error rate unavailable and omissions1",is.null(metric(r,"test_first_response_error_rate")$mean)&&metric(r,"test_first_response_error_rate")$contributing_person_count==0&&metric(r,"test_omission_rate")$mean==1)
  check("single person has mean but no between-person SD",metric(run(list(a)))$mean==1&&is.null(metric(run(list(a)))$between_person_sd))
  zero<-list(attempt(mean_ms=0),attempt(person="Q",mean_ms=0));z<-metric(run(zero))
  check("two equal zero-valued people legitimately have zero SD",z$mean==0&&z$between_person_sd==0&&z$contributing_person_count==2)
  missing<-attempt(person="Q",incomplete=TRUE);u<-run(list(a,missing))
  check("incomplete selected administration remains in audit and count",length(u$membership)==2&&u$quality$completed_attempt_count==1&&metric(u)$selected_attempt_count==2&&metric(u)$eligible_attempt_count==1&&metric(u)$contributing_person_count==1)
  check("absent score metrics get unavailable rows rather than zeros",all(vapply(Filter(function(m)m$attempt_id==missing$id,u$attempt_metrics),function(m)is.null(m$value)&&!m$eligible&&nzchar(m$reason),logical(1))))
  missing_same_person<-attempt(session="S2",incomplete=TRUE)
  check("one-selection policy rejects an unavailable repeat too",rejects(run(list(a,missing_same_person),plan_for(list(a,missing_same_person),"one_selected_attempt_per_person")),"before considering"))
  unknown<-attempt(person="Q",unknown=TRUE);u<-run(list(a,unknown))
  check("unknown source timing retains evidence without metrics",metric(u)$contributing_person_count==1&&u$membership[[2L]]$completion_status=="completed"&&!u$membership[[2L]]$timing_quality$definitions_known&&length(Filter(function(m)m$attempt_id==unknown$id,u$attempt_metrics))==5L)
  proposals<-brohn_task_cohort_identity_rows(originals)
  check("identity proposals never silently apply matching labels",all(vapply(proposals$participants,function(p)is.null(p$person_id),logical(1)))&&all(vapply(proposals$sessions,function(s)is.null(s$session_id),logical(1)))&&is.null(proposals$linkage_statement))
  unlinked<-run(originals,map=proposals)
  check("unlinked selection preserves attempts but withholds unique N and every person summary",is.null(unlinked$quality$selected_person_count)&&length(unlinked$attempt_metrics)==15&&length(unlinked$per_person)==0&&length(unlinked$per_session)==0&&all(vapply(unlinked$summaries,function(s)is.null(s$mean)&&is.null(s$contributing_person_count)&&s$status=="linkage_unavailable",logical(1))))
  map<-linked(originals);map$participants[[2L]]["person_id"]<-list(NULL)
  check("partially linked selection never silently chooses a linked subset",is.null(metric(run(originals,map=map))$mean))
  map<-linked(originals);map$sessions<-map$sessions[-1L]
  check("missing explicit session map does not invent session identity",run(originals,map=map)$quality$unlinked_attempt_count==1)
  map<-linked(originals);map["linkage_statement"]<-list(NULL)
  check("mapped IDs require explicit researcher linkage assertion",rejects(run(originals,map=map),"assertion"))
  original_unlinked<-attempt(linkage=FALSE);confirmed<-run(list(original_unlinked))
  check("explicit researcher crosswalk retains original false linkage without rewriting it",metric(confirmed)$mean==325&&!confirmed$membership[[1L]]$original_participant_linkage&&grepl("assertion",confirmed$provenance$identity_policy,fixed=TRUE))
  map<-linked(originals);map$participants<-c(map$participants,list(map$participants[[1L]]))
  check("duplicate person namespace mapping rejects identity collision",rejects(run(originals,map=map),"unique selected"))
  map<-linked(originals);map$sessions<-c(map$sessions,list(map$sessions[[1L]]));map$sessions[[4L]]$session_id<-"split"
  check("one original session cannot be split across two crosswalk rows",rejects(run(originals,map=map),"cannot be split"))
  map<-linked(originals);map$sessions[[2L]]$session_id<-map$sessions[[1L]]$session_id
  check("distinct source sessions cannot silently collapse",rejects(run(originals,map=map),"equivalence statement"))
  map$sessions[[1L]]$equivalence_statement<-map$sessions[[2L]]$equivalence_statement<-"Researcher confirms two source exports describe the same original session."
  check("explicit matching session equivalence is retained and used",metric(run(originals,map=map))$contributing_session_count==2)
  map$sessions[[2L]]$equivalence_statement<-"Different assertion"
  check("ambiguous session equivalence assertions reject",rejects(run(originals,map=map),"same explicit"))
  text_people<-lapply(c("001","1","0","false"),function(p)attempt(person=p,mean_ms=0))
  tr<-run(text_people);check("001 1 0 and false stay four exact text identities",tr$quality$selected_person_count==4&&setequal(vapply(Filter(function(p)p$metric=="correct_test_rt_mean",tr$per_person),`[[`,character(1),"person_id"),c("001","1","0","false")))
  map<-linked(text_people);map$participants[[1L]]$person_id<-0
  check("numeric destination identity is never silently converted",rejects(run(text_people,map=map),"exact text"))
  namespaces<-list(attempt(person="001",collection="C1",mean_ms=1),attempt(person="001",collection="C2",mean_ms=3))
  map<-linked(namespaces);map$participants[[1L]]$person_id<-"original-person-A";map$participants[[2L]]$person_id<-"original-person-B"
  check("same source label across collections is two explicitly mapped people",metric(run(namespaces,map=map))$contributing_person_count==2&&metric(run(namespaces,map=map))$mean==2)
  map$participants[[2L]]$person_id<-"original-person-A";map$sessions[[2L]]$session_id<-"different-visit"
  check("explicit cross-source person linkage gives one person and two sessions",metric(run(namespaces,map=map))$contributing_person_count==1&&metric(run(namespaces,map=map))$contributing_session_count==2)
  check("duplicate source attempt cannot add observations",rejects(run(list(a,a)),"Duplicate administration"))
  copy<-a;copy$source$original_hash<-brohn_hash("Original reformatted export bytes");copy$source$dataset_id<-"original-reformatted-source"
  copy$id<-paste0("task-attempt-",brohn_hash(list(original_source_hash=copy$source$original_hash,logical_evidence_key=copy$logical_evidence_key)));copy$score$attempt_id<-copy$id
  check("reformatted export copy retains logical duplicate detection",rejects(run(list(a,copy)),"Duplicate logical"))
  copy<-a;copy$source_collection_id<-"different-declared-collection"
  copy$logical_evidence_key<-brohn_hash(list(source_collection_id=copy$source_collection_id,participant_id=copy$participant_id,session_id=copy$session_id,attempt_id=copy$attempt_id,task_definition_hash=copy$task_definition_hash))
  copy$id<-paste0("task-attempt-",brohn_hash(list(original_source_hash=copy$source$original_hash,logical_evidence_key=copy$logical_evidence_key)));copy$score$attempt_id<-copy$id
  check("identical original bytes and selected rows cannot evade duplicate check via namespace",rejects(run(list(a,copy)),"same original bytes"))
  copy$source$selected_original_rows<-copy$source$selected_original_rows[-1L]
  check("overlapping partial original row selections remain duplicate evidence",rejects(run(list(a,copy)),"same original bytes"))
  plan<-plan_for(originals);plan$membership[[1L]]$attempt_hash<-brohn_hash("changed")
  check("stale frozen membership rejects before aggregation",rejects(run(originals,plan),"frozen membership hash"))
  check("missing selected administration cannot be replaced or omitted",rejects(run(list(a,c),plan_for(originals)),"exactly the frozen"))
  plan<-plan_for(originals);plan$membership<-c(plan$membership,list(plan$membership[[1L]]))
  check("duplicate frozen selection rejects",rejects(run(originals,plan),"exactly the frozen"))
  plan<-plan_for(originals);plan$repeat_policy<-"pool_trials"
  check("unsupported trial pooling policy rejects",rejects(run(originals,plan),"repeat policy"))
  for(kind in c("iat","biat","aat","simple","choice")) {
    x<-attempt(kind=kind);r<-run(list(x));expected<-manifest$fixtures[[kind]]$expected
    check(paste(kind,"registered profile keeps original independent arithmetic"),all(vapply(names(expected),function(name)near(metric(r,name)$mean,expected[[name]]),logical(1))))
    check(paste(kind,"single-person summaries keep named units and no inference"),all(vapply(r$summaries,function(s)s$contributing_person_count==1&&is.null(s$between_person_sd),logical(1))))
  }
  check("simple and choice RT cannot pool despite identical metric names",rejects(run(list(a,attempt(kind="simple"))),"homogeneous"))
  check("IAT and BIAT cannot pool generic D",rejects(run(list(attempt(kind="iat"),attempt(kind="biat"))),"homogeneous"))
  altered<-a;altered$collection_origin<-"pilot";altered$score$collection_origin<-"pilot"
  check("collection origin mixture rejects",rejects(run(list(altered,c)),"homogeneous"))
  altered<-a;altered$evidence_level<-altered$score$evidence_level<-"native_journal_replay"
  check("native replay and declared summaries are separately reported evidence groups",rejects(run(list(altered,c)),"homogeneous"))
  legacy<-a;legacy$score$schema_version<-"brohn-task-score/1.0";legacy$score$scoring_recipe<-NULL
  legacy$score$metrics<-lapply(legacy$score$metrics,function(m){m$eligible<-NULL;m$support<-NULL;m})
  check("old RT frozen score can be described without new support reinterpretation",metric(run(list(legacy)))$mean==1&&run(list(legacy))$attempt_metrics[[1L]]$eligibility_policy=="frozen_score_1.0_aggregate_gate")
  check("legacy and metric-specific RT scoring cannot silently mix",rejects(run(list(legacy,c)),"homogeneous"))
  bad<-a;bad$score$participant_id<-"different-person"
  check("a score cannot be silently attached to another person's administration",rejects(run(list(bad)),"references disagree"))
  bad<-a;bad$score$eligible<-FALSE
  check("aggregate flag must agree with rather than replace metric eligibility",rejects(run(list(bad)),"aggregate eligibility"))
  bad<-a;bad$score$metrics[[1L]]$value<-NULL
  check("eligible NULL cannot turn into a missing zero or usable value",rejects(run(list(bad)),"eligible metric"))
  bad<-a;bad$score$metrics[[1L]]$unit<-"seconds"
  check("wrong units are rejected before any averaging",rejects(run(list(bad)),"Metric units"))
  bad<-a;bad$score$metrics[[1L]]$value<-Inf
  check("nonfinite values cannot enter cohort mean",rejects(run(list(bad))))
  bad<-a;bad$score$metrics<-c(bad$score$metrics,list(bad$score$metrics[[1L]]))
  check("duplicate metric cannot change weighting",rejects(run(list(bad)),"duplicate or unregistered"))
  bad<-a;bad$score$scoring_recipe<-"future-unchecked-recipe/1.0"
  check("unregistered scoring recipe cannot silently reuse current meaning",rejects(run(list(bad)),"supported exact"))
  bad<-a;bad$completion_status<-"incomplete"
  check("complete administration gate cannot be bypassed by an eligible task flag",rejects(run(list(bad)),"complete administration"))
  cat("Task cohort:",checks,"pure checks passed; no store, worker or live UI integration claimed.\n")
})
