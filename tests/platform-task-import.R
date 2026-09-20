source("R/platform-participant-equipment.R") # Registered optional new-draft policy.
source("R/platform-core.R");source("R/platform-methods.R");source("R/platform-analysis.R");source("R/platform-task-import.R")
local({
  checks<-0L
  check<-function(label,value){if(!isTRUE(value))stop("Task import: ",label,call.=FALSE);checks<<-checks+1L}
  rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
  near<-function(a,b)isTRUE(all.equal(a,b,tolerance=1e-12,check.attributes=FALSE))
  directory<-"tests/fixtures/task-import"
  manifest<-brohn_parse(paste(readLines(file.path(directory,"manifest.json"),warn=FALSE,encoding="UTF-8"),collapse="\n"))
  fixtures<-list();results<-list()
  for(name in names(manifest$fixtures)) {
    f<-manifest$fixtures[[name]];csv<-file.path(directory,f$csv);json<-file.path(directory,f$registry)
    check(paste(name,"frozen original CSV and registry byte hashes"),digest::digest(file=csv,algo="sha256")==f$csv_sha256&&digest::digest(file=json,algo="sha256")==f$registry_sha256)
    registry<-brohn_parse(rawToChar(readBin(json,"raw",n=file.info(json)$size)))
    d<-brohn_new_design("Original trial import study","blank",id=paste0("source-study-",name));d$blocks<-list(registry$task)
    data<-brohn_read_table(csv,"csv",20000L)
    source<-list(id=paste0("original-source-",name),revision=1L,hash=f$csv_sha256,origin="sample",registry_object_hash=f$registry_sha256)
    fixtures[[name]]<-list(data=data,m=f$metadata,d=d,r=registry,s=source)
    dataset<-list(id=source$id,modality="implicit",source=list(format="csv",hash=source$hash),origin="sample",study_id=d$id,study_revision=1L,columns=as.list(names(data)),metadata=f$metadata)
    check(paste(name,"mapped dataset and registry validate without mutation"),identical(brohn_validate_task_import_mapping(dataset,d),dataset)&&identical(brohn_validate_task_protocol_registry(registry,d,registry$task$id),registry))
    result<-brohn_import_task_trials(data,f$metadata,d,source,registry);results[[name]]<-result
    check(paste(name,"complete original trial table retains every source row"),result$kind=="implicit"&&result$quality$source_row_count==f$rows&&result$quality$selected_row_count==f$rows&&result$quality$derived_missing_trial_count==0&&result$quality$completed_attempt_count==1)
    values<-stats::setNames(lapply(result$task_scores[[1L]]$metrics,`[[`,"value"),vapply(result$task_scores[[1L]]$metrics,`[[`,character(1),"name"))
    for(metric in names(f$expected))check(paste(name,"independent hand arithmetic",metric),near(values[[metric]],f$expected[[metric]]))
    attempt<-result$task_attempts[[1L]]
    check(paste(name,"frozen source and table provenance remains bound"),attempt$source$original_hash==source$hash&&attempt$source$registry_object_hash==source$registry_object_hash&&attempt$compiled_hash==registry$protocols[[1L]]$compiled_hash&&attempt$task_definition_hash==brohn_hash(registry$task))
    check(paste(name,"summary never invents clocks key history or software"),!attempt$timing_quality$journal_replayed&&!attempt$timing_quality$physical_timing_qualified&&is.null(attempt$timing_quality$source_clock)&&is.null(attempt$timing_quality$key_history)&&is.null(attempt$timing_quality$source_software)&&is.null(attempt$timing_quality$anticipatory_count))
    check(paste(name,"one administration is not many people"),result$quality$participant_count==1&&result$quality$session_count==1&&result$quality$attempt_count==1)
    check(paste(name,"every original cell and source row hash is retained"),all(vapply(seq_len(nrow(data)),function(i)identical(result$source_rows[[i]]$original_cells,lapply(as.list(data[i,,drop=FALSE]),unname))&&result$source_rows[[i]]$source_row_hash==brohn_hash(lapply(as.list(data[i,,drop=FALSE]),unname)),logical(1))))
  }
  run<-function(name="choice",data=NULL,m=NULL,d=NULL,r=NULL,s=NULL) {
    f<-fixtures[[name]]
    brohn_import_task_trials(brohn_default(data,f$data),brohn_default(m,f$m),brohn_default(d,f$d),brohn_default(s,f$s),brohn_default(r,f$r))
  }
  value<-function(result,name)Filter(function(m)m$name==name,result$task_scores[[1L]]$metrics)[[1L]]
  check("deterministic pure import exactly repeats result",identical(results$iat,run("iat")))
  check("IAT matches independently pinned audit identity",fixtures$iat$s$hash=="a7d6fdfb544a6008fa0eb04dfd1df9cdac21f70bc4c2f266dc9c08a852de0af3"&&fixtures$iat$s$registry_object_hash=="0a40b8b2db1c1f47b08279fbcb61d7c61fe5d1c222583e19d37e243f9e207bb5")
  check("RT imports retain the per-metric support recipe",results$choice$task_scores[[1L]]$schema_version=="brohn-task-score/1.1"&&results$simple$task_scores[[1L]]$scoring_recipe=="brohn-rt-metric-support/1.0")

  t<-fixtures$choice$data;test<-which(vapply(Filter(function(x)x$type=="task_trial",fixtures$choice$r$protocols[[1L]]$compiled$timeline),`[[`,logical(1),"scored"))
  omit<-function(table,rows,outcome="timeout",presented="true",reason="") {
    table$outcome[rows]<-outcome;table$presented[rows]<-presented;table$first_correct[rows]<-"false"
    for(field in c("first_code","final_code","first_response_ms","final_correct_ms"))table[[field]][rows]<-""
    table$missing_reason[rows]<-reason;table
  }
  one<-omit(t,test[-1L]);one$first_response_ms[test[[1L]]]<-one$final_correct_ms[test[[1L]]]<-"500"
  result<-run(data=one)
  check("one correct plus39 omissions is complete and partially supported",result$task_attempts[[1L]]$completion_status=="completed"&&result$task_scores[[1L]]$status=="partial"&&value(result,"test_omission_rate")$value==39/40)
  check("one RT never fabricates SD or loses known zero error rate",is.null(value(result,"correct_test_rt_sd")$value)&&value(result,"correct_test_rt_mean")$value==500&&value(result,"test_first_response_error_rate")$value==0)
  all_missing<-run(data=omit(t,test))
  check("all test omissions retain rate1 and unavailable error rate",value(all_missing,"test_omission_rate")$value==1&&is.null(value(all_missing,"test_first_response_error_rate")$value)&&value(all_missing,"test_first_response_error_rate")$support$denominator==0)
  zero<-t;zero$first_response_ms<-zero$final_correct_ms<-"000.000"
  z<-run(data=zero)
  check("zero remains valid and original decimal strings survive",value(z,"correct_test_rt_mean")$value==0&&z$task_attempts[[1L]]$responses[[1L]]$first_response_ms_source=="000.000")
  exponent<-t;exponent$first_response_ms<-exponent$final_correct_ms<-"5e2"
  e<-run(data=exponent)
  check("standard machine numeric notation preserves values and original lexemes",value(e,"correct_test_rt_mean")$value==500&&e$task_attempts[[1L]]$responses[[1L]]$first_response_ms_source=="5e2")
  impossible<-omit(t,test[[1L]],"incorrect")
  check("impossible wrong-without-key accepted by old raw scorer is rejected before import scoring",rejects(run(data=impossible)))
  wrong<-t;trial<-fixtures$choice$r$protocols[[1L]]$compiled$timeline
  trial<-Filter(function(x)x$type=="task_trial",trial)[[test[[1L]]]]
  wrong$first_code[test[[1L]]]<-setdiff(unlist(trial$allowed_codes),trial$correct_code)[[1L]];wrong$first_correct[test[[1L]]]<-"false"
  check("a non-correction task cannot correct a wrong first answer",rejects(run(data=wrong)))
  wrong$outcome[test[[1L]]]<-"incorrect";wrong$final_code[test[[1L]]]<-wrong$final_correct_ms[test[[1L]]]<-""
  check("genuine incorrect response keeps explicit error denominator",value(run(data=wrong),"test_first_response_error_rate")$value==1/40)
  bad<-t;bad$outcome[test[[1L]]]<-"timeout"
  check("a received terminal answer cannot be relabelled timeout",rejects(run(data=bad)))
  for(token in c("NA","NaN","null","-1","5e"," 500 ","Infinity")) {
    bad<-t;bad$first_response_ms[[1L]]<-bad$final_correct_ms[[1L]]<-token
    check(paste("unexpected latency token rejected",token),rejects(run(data=bad)))
  }
  bad<-t;bad$first_response_ms[[1L]]<-bad$final_correct_ms[[1L]]<-"5000.003"
  check("response after fixed acceptance tolerance rejected",rejects(run(data=bad)))
  bad<-t;bad$first_response_ms[[1L]]<-"400";bad$final_correct_ms[[1L]]<-"399"
  check("first/final reversal rejected",rejects(run(data=bad)))
  bad<-t;bad$first_response_ms[[1L]]<-"400";bad$final_correct_ms[[1L]]<-"400.001"
  check("correct-first source times obey existing equal-latency scorer constraint",rejects(run(data=bad)))

  iat<-fixtures$iat$data;it<-Filter(function(x)x$type=="task_trial",fixtures$iat$r$protocols[[1L]]$compiled$timeline)
  index<-which(vapply(it,`[[`,logical(1),"scored"))[[1L]]
  corrected<-iat;corrected$first_correct[[index]]<-"false";corrected$first_code[[index]]<-setdiff(unlist(it[[index]]$allowed_codes),it[[index]]$correct_code)[[1L]]
  corrected$first_response_ms[[index]]<-"500";corrected$final_correct_ms[[index]]<-"1300"
  result<-run("iat",data=corrected)
  check("forced correction uses final latency without added penalty",near(value(result,"IAT_D1")$value,(360/sqrt(2144000/39)+400/sqrt(4000000/79))/2))
  check("forced correction preserves wrong first and correct final evidence",!result$task_attempts[[1L]]$responses[[index]]$first_correct&&result$task_attempts[[1L]]$responses[[index]]$first_response_ms==500&&result$task_attempts[[1L]]$responses[[index]]$final_correct_ms==1300)
  check("forced-correction task cannot end a trial simply incorrect",rejects(run("iat",data=omit(iat,nrow(iat),"incorrect"))))
  timed_out<-omit(iat,nrow(iat))
  check("unresolved final forced correction is an incomplete administration",run("iat",data=timed_out)$task_attempts[[1L]]$completion_status=="incomplete"&&!run("iat",data=timed_out)$task_scores[[1L]]$eligible)
  check("forced timeout cannot continue with later presented trials",rejects(run("iat",data=omit(iat,1L))))
  partial<-run("iat",data=iat[-c(1L,180L),])
  check("absent expected rows generate diagnostics not fabricated source rows",partial$quality$source_row_count==178&&partial$quality$derived_missing_trial_count==2&&length(partial$source_rows)==178&&partial$task_attempts[[1L]]$completion_status=="incomplete"&&!partial$task_scores[[1L]]$eligible)
  check("derived missing diagnostics never pretend to have original row IDs",all(vapply(Filter(function(a)a$derived,partial$task_attempts[[1L]]$trial_audit),function(a)is.null(a$source_row)&&a$disposition=="missing_expected_source_row",logical(1))))
  tail_missing<-omit(iat,171:180,"not_presented","false","Original run ended before these trials")
  result<-run("iat",data=tail_missing)
  check("explicit unpresented tail retains source rows and stays unavailable",result$quality$source_row_count==180&&result$quality$derived_missing_trial_count==0&&result$task_attempts[[1L]]$completion_status=="incomplete"&&!result$quality$usable)
  interrupted<-omit(iat,171L,"interrupted","true","Original page interrupted");interrupted<-omit(interrupted,172:180,"not_presented","false","Not reached")
  check("source interruption and unpresented tail remain a distinct terminal status",run("iat",data=interrupted)$task_attempts[[1L]]$completion_status=="interrupted")
  check("interrupted trial requires explicit source reason",rejects(run("iat",data=omit(iat,180L,"interrupted"))))

  biat<-fixtures$biat$data;bt<-Filter(function(x)x$type=="task_trial",fixtures$biat$r$protocols[[1L]]$compiled$timeline)
  scored<-which(vapply(bt,`[[`,logical(1),"scored"))
  biat$first_response_ms[scored[1:6]]<-biat$final_correct_ms[scored[1:6]]<-"250"
  biat$first_response_ms[scored[[17L]]]<-biat$final_correct_ms[scored[[17L]]]<-"10001"
  result<-run("biat",data=biat)
  check("BIAT fast screen retains original6over63 before bounding",result$task_scores[[1L]]$scoring_audit$fast_numerator==6&&result$task_scores[[1L]]$scoring_audit$fast_denominator==63&&result$task_scores[[1L]]$eligible)
  check("BIAT audit preserves original250 and candidate400 values separately",result$task_attempts[[1L]]$trial_audit[[scored[[1L]]]]$declared_latency_ms==250&&result$task_attempts[[1L]]$trial_audit[[scored[[1L]]]]$scoring_latency_ms==400)
  biat$first_response_ms[scored[[7L]]]<-biat$final_correct_ms[scored[[7L]]]<-"250"
  check("BIAT threshold exclusion is a retained administration not dropped rows",!run("biat",data=biat)$task_scores[[1L]]$eligible&&run("biat",data=biat)$quality$source_row_count==96)

  reversed<-run(data=t[nrow(t):1L,])
  check("explicit ordinal survives reversed file row order",near(value(reversed,"correct_test_rt_mean")$value,325)&&reversed$source_rows[[1L]]$original_cells$trial_id==t$trial_id[[nrow(t)]])
  bad<-t;bad$presentation_index[[1L]]<-"2"
  check("wrong declared ordinal is not repaired from row order",rejects(run(data=bad)))
  bad<-t;bad$trial_id[[1L]]<-"foreign-trial"
  check("unknown trial cannot inherit a same-position key",rejects(run(data=bad)))
  check("duplicate export cannot add observations",rejects(run(data=rbind(t,t[1L,]))))
  for(field in c("participant_id","session_id","attempt_id")) {
    bad<-t;bad[[field]][[1L]]<-""
    check(paste("required original identity missing",field),rejects(run(data=bad)))
  }
  literal<-t;literal$participant_id<-"NA";literal$session_id<-"001";literal$attempt_id<-"0"
  result<-run(data=literal)
  check("literal NA and leading-zero identities remain exact text",result$task_attempts[[1L]]$participant_id=="NA"&&result$task_attempts[[1L]]$session_id=="001"&&result$task_attempts[[1L]]$attempt_id=="0")
  bad<-t;bad$participant_id[[1L]]<-NA_character_
  check("inferred R missing values are rejected",rejects(run(data=bad)))
  bad<-t;bad$first_response_ms<-as.numeric(bad$first_response_ms)
  check("inferred numeric columns require a character-preserving reread",rejects(run(data=bad)))
  bad<-t;bad$participant_linkage[[1L]]<-"false"
  check("linkage cannot change inside an administration",rejects(run(data=bad)))
  bad<-t;bad$participant_linkage<-"false"
  check("unlinked administrations never claim unique people",is.null(run(data=bad)$quality$participant_count))
  bad<-t;bad$participant_linkage<-"yes"
  check("boolean tokens are not guessed",rejects(run(data=bad)))

  repeated<-t;repeated$session_id<-"S2"
  original_compile<-brohn_task_compile;compile_count<-0L
  assign("brohn_task_compile",function(...){compile_count<<-compile_count+1L;original_compile(...)},envir=.GlobalEnv)
  result<-tryCatch(run(data=rbind(t,repeated)),finally=assign("brohn_task_compile",original_compile,envir=.GlobalEnv))
  check("registry table is recompiled once rather than per row or administration",compile_count==1L)
  check("repeated administrations keep one declared person and two sessions with separate scores",result$quality$participant_count==1&&result$quality$session_count==2&&result$quality$attempt_count==2&&length(result$task_scores)==2)
  s<-fixtures$choice$s;s$hash<-strrep("a",64);changed_source<-run(s=s)
  check("another source hash changes canonical ID but retains duplicate-evidence logical key",changed_source$task_attempts[[1L]]$id!=results$choice$task_attempts[[1L]]$id&&changed_source$task_attempts[[1L]]$logical_evidence_key==results$choice$task_attempts[[1L]]$logical_evidence_key)
  m<-fixtures$choice$m;m$source_rt_definition<-"unknown"
  result<-run(m=m)
  check("unknown latency definition retains completed evidence without scores",result$task_attempts[[1L]]$completion_status=="completed"&&!result$quality$usable&&length(result$task_scores[[1L]]$metrics)==0)
  m<-fixtures$choice$m;m$terminal_response_rule<-"unknown"
  check("unknown response rule never silently adopts a known procedure",!run(m=m)$quality$usable)
  m$terminal_response_rule<-"corrected_response_or_fixed_deadline"
  check("contradictory response rule is a structural failure",rejects(run(m=m)))

  mixed<-t;m<-fixtures$choice$m;m$task_column<-"task_id";m$origin_column<-"origin"
  mixed$task_id<-m$task_id;mixed$origin<-"sample"
  other<-mixed[1L,];other$task_id<-"other-task";other$origin<-"live";other$outcome<-"unparsed foreign outcome";other$protocol_id<-"other-registry"
  result<-run(data=rbind(other,mixed),m=m)
  check("only explicit task selector excludes rows with complete original evidence",result$quality$excluded_row_count==1&&!result$source_rows[[1L]]$selected&&result$source_rows[[1L]]$reason=="different_task"&&result$source_rows[[1L]]$original_cells$outcome=="unparsed foreign outcome")
  bad<-mixed;bad$origin[[1L]]<-"live"
  check("selected conflicting origin cannot be silently filtered out",rejects(run(data=bad,m=m)))
  m$task_column<-NULL
  check("without explicit selector other-task rows are not silently excluded",rejects(run(data=rbind(other,mixed),m=m)))
  s<-fixtures$choice$s;s$origin<-"live"
  check("synthetic source cannot be promoted to live by import",rejects(run(s=s)))

  r<-fixtures$iat$r;r$protocols[[1L]]$compiled_hash<-strrep("a",64)
  check("supplied compiled hash must match whole frozen table",rejects(run("iat",r=r)))
  r<-fixtures$iat$r;r$protocols[[1L]]$compiled$timeline[[2L]]$correct_code<-"KeyX";r$protocols[[1L]]$compiled_hash<-brohn_hash(r$protocols[[1L]]$compiled)
  check("a rehashed altered table still fails exact local compiler qualification",rejects(run("iat",r=r)))
  r<-fixtures$iat$r;r$task$materials[[1L]]$content<-"Changed source material"
  check("registry material cannot substitute for pinned task definition",rejects(run("iat",r=r)))
  r<-fixtures$iat$r;r$protocols<-c(r$protocols,r$protocols)
  check("duplicate registry identities are rejected",rejects(run("iat",r=r)))
  m<-fixtures$choice$m;m$protocol_registry$canonical_hash<-strrep("f",64)
  check("immutable reference must bind exact canonical registry",rejects(run(m=m)))
  m<-fixtures$choice$m;m$protocol_registry$filename<-"../foreign.json"
  check("registry metadata never contains a source filepath",rejects(run(m=m)))
  m<-fixtures$choice$m;m$first_code_column<-m$final_code_column
  check("distinct evidence fields cannot share one source column",rejects(run(m=m)))
  sparse<-iat[rep(1L,112L),];sparse$attempt_id<-paste0("sparse-",seq_len(nrow(sparse)))
  check("sparse expected-gap expansion is bounded without truncation",rejects(run("iat",data=sparse)))
  check("source row bound is checked before truncated scoring",rejects(run(data=t[rep(1L,20001L),])))
  r<-fixtures$iat$r;r$task$materials[[1L]]$content<-strrep("x",16*1024^2)
  check("registry serialization is explicitly bounded16MiB",rejects(run("iat",r=r)))
  rm(r)
  tmp<-tempfile("brohn-original-trial-",fileext=".tsv")
  on.exit(unlink(tmp),add=TRUE)
  utils::write.table(t,tmp,sep="\t",row.names=FALSE,quote=TRUE,qmethod="double",fileEncoding="UTF-8")
  s<-fixtures$choice$s;s$hash<-digest::digest(file=tmp,algo="sha256")
  tabbed<-run(data=brohn_read_table(tmp,"tsv",20000L),s=s)
  check("actual character-preserved TSV retains same choice arithmetic",near(value(tabbed,"correct_test_rt_mean")$value,325)&&near(value(tabbed,"correct_test_rt_sd")$value,sqrt(5000/39)))
  check("module performs no cohort inference or composite score",is.null(tabbed$contrasts)&&is.null(tabbed$cohort)&&!tabbed$quality$scientifically_qualified)
  cat(sprintf("Implicit trial import: %d checks passed across five frozen original CSV/registry fixtures, strict summary validation, missingness, provenance and hand arithmetic.\n",checks))
})
