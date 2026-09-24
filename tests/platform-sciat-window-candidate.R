# Pure candidate arithmetic and separately pinned open-package reference. No
# application, task registry, participant store or worker is opened by this test.
source("R/platform-sciat-window-candidate.R",encoding="UTF-8")
local({
  folder<-Sys.getenv("BROHN_SCIAT_WINDOW_TEST_ROOT",tempfile("brohn-sciat-window-candidate-"));dir.create(folder,recursive=TRUE)
  stopifnot(!file.exists(file.path(folder,"results.json")))
  checks<-character();check<-function(label,x){stopifnot(isTRUE(x));checks<<-c(checks,label);cat("PASS",label,"\n")}
  rejects<-function(x)inherits(try(force(x),silent=TRUE),"try-error")
  make<-function(a,b,ca=rep(TRUE,length(a)),cb=rep(TRUE,length(b))){
    rt<-c(a,b);accuracy<-c(ca,cb);accuracy[is.na(rt)]<-NA
    data.frame(trial_id=paste0("original-probe-",seq_along(rt)),mapping=c(rep("A",length(a)),rep("B",length(b))),
      outcome=ifelse(is.na(rt),"omission","response"),latency_ms=as.numeric(rt),correct=as.logical(accuracy),stringsAsFactors=FALSE)
  }
  cases<-list(all_correct=make(c(400,600),c(600,1000)),
    error_base_includes_errors=make(c(400,600,800),c(600,1000,1200),c(TRUE,TRUE,FALSE),c(TRUE,TRUE,FALSE)),
    explicit_omissions_fast_and_boundary=make(c(200,350,500,NA,900),c(349,400,750,1500,NA),c(FALSE,TRUE,TRUE,NA,FALSE),c(TRUE,TRUE,FALSE,TRUE,NA)),
    exactly_75pct_accuracy=make(c(400,500,600,700),c(600,700,800,1000),c(TRUE,TRUE,TRUE,FALSE),c(TRUE,TRUE,TRUE,FALSE)),
    below_75pct_accuracy=make(c(400,500,600,700,800),c(600,700,800,1000,1200),c(TRUE,TRUE,TRUE,FALSE,FALSE),c(TRUE,TRUE,TRUE,FALSE,FALSE)))
  cases$opposite_order<-cases$error_base_includes_errors[c(4:6,1:3),]
  i<-seq_len(72L);a<-400+(i%%9)*50;b<-500+(i%%11)*55
  a[i%%19L==0L]<-200;b[i%%23L==0L]<-350;a[i%%17L==0L]<-NA;b[i%%13L==0L]<-NA
  cases$complete_test_counts<-make(a,b,i%%7L!=0L,i%%8L!=0L)
  result<-lapply(cases,brohn_sciat_window_candidate_reduce)
  near<-function(x,y)isTRUE(all.equal(x,y,tolerance=1e-12,check.attributes=FALSE))
  check("Candidate remains unregistered and never qualifies a collected task",all(vapply(result,function(x)!x$candidate$registered&&!x$qualified_task_result,logical(1))))
  check("Independent tiny oracle uses pooled correct sample SD",near(result$all_correct$pooled_correct_sample_sd_ms,sqrt(190000/3))&&near(result$all_correct$target_positive_d,300/sqrt(190000/3)))
  err<-result$error_base_includes_errors
  check("Error replacement bases include raw incorrect latencies",err$mapping$A$error_replacement_base_ms==600&&near(err$mapping$B$error_replacement_base_ms,2800/3))
  check("Original error latencies remain preserved beside substituted score inputs",identical(err$rows$latency_ms,c(400,600,800,600,1000,1200))&&near(err$rows$scoring_latency_ms,c(400,600,1000,600,1000,4000/3)))
  check("Error-penalty mean and correct-only sample SD have independent oracle",near(err$target_positive_d,(2800/9)/sqrt(190000/3)))
  check("Reported direction explicitly reverses the package mapping sign",all(vapply(result,function(x)near(x$target_positive_d,-x$reference_package_d),logical(1))))
  boundary<-result$explicit_omissions_fast_and_boundary
  check("350ms and1500ms boundary responses remain;349ms and200ms are removed",identical(boundary$rows$reason,c("below_350_ms","retained_correct","retained_correct","explicit_omission","retained_error","below_350_ms","retained_correct","retained_error","retained_correct","explicit_omission")))
  check("Presented responded omitted fast and scored denominators remain distinct",identical(unlist(boundary$counts),c(presented=10L,responded=8L,omitted=2L,removed_fast=2L,retained=6L,retained_correct=4L,retained_errors=2L)))
  check("Accuracy threshold is below .75 with no silent participant exclusion",!result$exactly_75pct_accuracy$qc$below_75pct_response_accuracy&&result$below_75pct_accuracy$qc$below_75pct_response_accuracy&&!result$below_75pct_accuracy$qc$exclusion_applied&&!is.null(result$below_75pct_accuracy$target_positive_d))
  check("Actual mapping order retained without changing mapping contrast",result$opposite_order$mapping_order=="B_then_A"&&result$error_base_includes_errors$mapping_order=="A_then_B"&&near(result$opposite_order$target_positive_d,err$target_positive_d))
  check("144 numerical test rows do not falsely establish complete task replay",result$complete_test_counts$counts$presented==144L&&!result$complete_test_counts$qualified_task_result)
  unavailable<-list(one_mapping=make(c(400,600),numeric()),all_fast_A=make(c(200,300),c(600,800)),
    zero_sd=make(c(500,500),c(500,500)),one_correct=make(c(400,500),c(600,700),c(TRUE,FALSE),c(FALSE,FALSE)),
    all_omitted_A=make(c(NA,NA),c(600,800)))
  unavail<-lapply(unavailable,brohn_sciat_window_candidate_reduce)
  check("Insufficient retained support and zero variance remain unavailable",all(vapply(unavail,function(x)x$status=="unavailable"&&is.null(x$target_positive_d)&&!is.null(x$reason),logical(1))))
  base<-cases$all_correct
  mutations<-list(duplicate=function(x){x$trial_id[2]<-x$trial_id[1];x},unknown_mapping=function(x){x$mapping[1]<-"C";x},numeric_accuracy=function(x){x$correct<-as.integer(x$correct);x},
    coerced_latency=function(x){x$latency_ms<-as.character(x$latency_ms);x},outside_deadline=function(x){x$latency_ms[1]<-1500.001;x},negative_latency=function(x){x$latency_ms[1]<- -1;x},
    infinite_latency=function(x){x$latency_ms[1]<-Inf;x},missing_response=function(x){x$latency_ms[1]<-NA_real_;x},invented_omission=function(x){x$outcome[1]<-"omission";x},
    nonliteral_accuracy=function(x){x$correct[1]<-NA;x},unknown_outcome=function(x){x$outcome[1]<-"corrected";x},mixed_order=function(x){x$mapping<-c("A","B","A","B");x},
    hidden_column=function(x){x$extra<-1;x},too_many=function(x){x<-x[rep(1:4,37),];x$trial_id<-paste0("too-many-",seq_len(nrow(x)));x})
  for(name in names(mutations))check(paste("Rejects",name),rejects(brohn_sciat_window_candidate_reduce(mutations[[name]](base))))
  # The installed open package is an independent numerical reference. Match its
  # function bodies to the immutable upstream source in memory, retaining hashes.
  stopifnot(requireNamespace("implicitMeasures",quietly=TRUE),as.character(utils::packageVersion("implicitMeasures"))=="1.0.0")
  commit<-"41b3812ab1d94f624113eb3e11028cf50fff6b2c";sources<-list();reference_env<-new.env(parent=asNamespace("implicitMeasures"))
  for(name in c("clean_sciat","compute_sciat")){
    address<-paste0("https://raw.githubusercontent.com/OttaviaE/implicitMeasures/",commit,"/R/",name,".R")
    con<-url(address,"rb");bytes<-readBin(con,"raw",n=1024^2);close(con);stopifnot(length(bytes)<1024^2)
    eval(parse(text=rawToChar(bytes)),envir=reference_env)
    check(paste("Installed reference matches pinned upstream body",name),identical(body(getExportedValue("implicitMeasures",name)),body(reference_env[[name]])))
    sources[[name]]<-list(url=address,bytes=length(bytes),sha256=digest::digest(bytes,algo="sha256",serialize=FALSE))
  }
  refs<-list();single_reference_error<-NULL
  for(name in names(cases)){
    x<-cases[[name]];frame<-data.frame(participant="original-synthetic-probe",block=x$mapping,correct=as.integer(x$correct),latency=x$latency_ms,trial=x$outcome)
    clean_frame<-function(f)implicitMeasures::clean_sciat(f,sbj_id="participant",block_id="block",accuracy_id="correct",latency_id="latency",trial_id="trial",trial_eliminate=character(),block_sciat_1=c("A","B"))
    if(name=="explicit_omissions_fast_and_boundary"){
      single_reference_error<-tryCatch({implicitMeasures::compute_sciat(clean_frame(frame),mappingA="A",mappingB="B",non_response="omission");NULL},error=conditionMessage)
      check("Upstream single-person mixed-fast table error is retained",is.character(single_reference_error)&&grepl("differing number of rows",single_reference_error,fixed=TRUE))
    }
    # The current external package drops names when a diagnostic table has one
    # participant. A separately labelled synthetic twin preserves its dimensions;
    # these are comparator inputs, not independent research observations.
    twin<-frame;twin$participant<-"original-synthetic-reference-twin";frame<-rbind(frame,twin)
    ref<-implicitMeasures::compute_sciat(clean_frame(frame),mappingA="A",mappingB="B",non_response="omission");refs[[name]]<-as.list(ref[1,]);r<-result[[name]]
    check(paste("Pinned external D and adjusted mapping means agree for both comparator IDs",name),near(ref$d_sciat,rep(r$reference_package_d,2))&&near(ref$RT_mean.mappingA,rep(r$mapping$A$adjusted_mean_ms,2))&&near(ref$RT_mean.mappingB,rep(r$mapping$B$adjusted_mean_ms,2)))
    check(paste("Pinned external retained accuracy and prefilter QC agree",name),near(ref$accuracy.mappingA,rep(r$mapping$A$accuracy_among_retained,2))&&near(ref$accuracy.mappingB,rep(r$mapping$B$accuracy_among_retained,2))&&identical(ref$out_accuracy=="out",rep(r$qc$below_75pct_response_accuracy,2)))
  }
  check("Upstream order-label mismatch is exposed instead of reproduced",refs$all_correct$cond_ord=="MappingB_First"&&result$all_correct$mapping_order=="A_then_B")
  receipt<-list(passed=TRUE,checks=checks,candidate=brohn_sciat_window_candidate(),source_identity=list(module_sha256=digest::digest(file="R/platform-sciat-window-candidate.R",algo="sha256"),R=R.version.string),
    reference=list(package="implicitMeasures",version="1.0.0",commit=commit,source=sources,single_administration_mixed_fast_error=single_reference_error,
      comparator_shape="Two separately labelled synthetic copies per case to preserve upstream diagnostic table dimensions; not independent research observations"),cases=cases,results=result,reference_outputs=refs,unavailable=unavail,
    limitations=c("Numerical arithmetic prototype only; not a registered or qualified participant task.","No vendor runtime, physical timing, collection replay, general scientific validity or new real participant data."))
  jsonlite::write_json(receipt,file.path(folder,"results.json"),auto_unbox=TRUE,digits=16,na="null",null="null",pretty=TRUE)
  cat("PASS",length(checks),"candidate assertions; retained",folder,"\n")
})
