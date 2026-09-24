source("R/platform-load.R",encoding="UTF-8");brohn_load()
source("R/platform-explicit-distributions.R",encoding="UTF-8")
source("R/platform-explicit-distribution-views.R",encoding="UTF-8")
local({
  checks<-0L;check<-function(label,ok){if(!isTRUE(ok))stop(label);checks<<-checks+1L;cat("PASS",label,"\n")}
  rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
  d<-brohn_new_design("Original distribution arithmetic","survey")
  n<-brohn_question("Original numeric response","number","end","q-number");n$min<-0;n$max<-10;n$step<-1;n$required<-FALSE
  c<-brohn_question("Original typed category","single_choice","end","q-category");c$required<-FALSE
  c$options<-lapply(seq_along(list(FALSE,0,"0","=1+1","\u96ea")),function(i)list(id=paste0("option-",i),label=paste("Category",i),value=list(FALSE,0,"0","=1+1","\u96ea")[[i]]))
  d$questions<-list(n,c)
  row<-function(value,question="q-number",i=1L,state="answered",condition=NULL)list(question_id=question,prompt=question,value=value,status=state,
    missing_reason=if(state=="answered")NULL else state,participant_id=if(i<=2)"P1"else"P2",participant_linkage=TRUE,session_id=paste0("session-",i),assessment_id=paste0("assessment-",i),condition_id=condition,origin="sample")
  answers<-list(row(0,i=1),row(4,i=2),row(8,i=3),row(NULL,i=4,state="optional_omission"),row(NULL,i=5,state="not_displayed"),row(FALSE,i=6))
  result<-brohn_build_explicit_distributions(answers,list(),d);g<-result$groups[[1]]
  check("Zero retained; no boolean-to-number coercion",g$usable_records==3&&g$invalid_or_unsupported==1&&g$summary$mean==4&&g$summary$median==4)
  check("Repeated visits are six assessments but two linked people",g$assessment_count==6&&g$participant_count==2&&g$source_records==6)
  check("Omitted and hidden remain separate saved states",all(c("optional_omission","not_displayed") %in% vapply(g$states,`[[`,character(1),"state")))
  check("All numeric values occur once in explicit full-range bins",sum(vapply(g$bins,`[[`,numeric(1),"count"))==3&&g$bins[[1]]$count==1&&tail(g$bins,1)[[1]]$count==1)
  categories<-lapply(seq_along(list(FALSE,0,"0","=1+1","\u96ea")),function(i)row(list(FALSE,0,"0","=1+1","\u96ea")[[i]],"q-category",i))
  cat_group<-brohn_build_explicit_distributions(categories,list(),d)$groups[[1]]
  check("False, numeric zero and text zero remain separate categories",length(cat_group$categories)==5&&setequal(vapply(cat_group$categories,`[[`,character(1),"value_json"),c("false","0",'"0"','"=1+1"','"\u96ea"')))
  check("Nominal numeric codes never receive a numerical mean",!cat_group$quantitative&&is.null(cat_group$summary)&&!length(cat_group$bins))
  unlinked<-answers;unlinked[[1]]$participant_linkage<-FALSE
  check("Person denominator withheld when linkage is incomplete",is.null(brohn_build_explicit_distributions(unlinked,list(),d)$groups[[1]]$participant_count))
  unassigned<-answers;unassigned[[1]]$assessment_id<-NULL
  u<-brohn_build_explicit_distributions(unassigned,list(),d)$groups[[1]]
  check("No assessment identity inferred from order/session",is.null(u$assessment_count)&&u$known_assessments==5&&u$unassigned_records==1)
  duplicate<-c(answers,list(answers[[1]]));g2<-brohn_build_explicit_distributions(duplicate,list(),d)$groups[[1]]
  check("Repeated records in same explicit assessment are disclosed",g2$source_records==7&&g2$assessment_count==6&&g2$repeated_assessment_records==1)
  conditioned<-list(row(0,condition="A"),row(10,i=2,condition="B"));split<-brohn_build_explicit_distributions(conditioned,list(),d)
  check("Different conditions remain separate distributions",length(split$groups)==2&&identical(vapply(split$groups,function(g)g$summary$mean,numeric(1)),c(0,10)))
  absent<-brohn_build_explicit_distributions(list(row(NULL,state="not_displayed")),list(),d)$groups[[1]]
  check("All hidden records give no invented score or zero plot",is.null(absent$summary)&&!length(absent$bins)&&is.null(brohn_explicit_distribution_svg(absent)))
  unknown<-d;unknown$questions<-list()
  check("Undeclared numeric values stay typed categories",!brohn_build_explicit_distributions(list(row(4)),list(),unknown)$groups[[1]]$quantitative)
  extreme<-list(row(10),row(10,i=2));constant<-brohn_build_explicit_distributions(extreme,list(),d)$groups[[1]]
  check("Constant numeric value forms one count bin",length(constant$bins)==1&&constant$bins[[1]]$count==2&&constant$bins[[1]]$lower==10)
  scales<-lapply(1:3,function(i)list(scale_id="scale-original",label="Original scale",scale_hash=strrep("a",64),scale_version="1.0",unit="scale points",value=if(i<3)i*2 else NULL,
    status=if(i<3)"scored"else"not_scoreable",missing_reason=if(i<3)NULL else"insufficient_answered_items",participant_id="P1",participant_linkage=TRUE,session_id=paste0("s",i),assessment_id=paste0("a",i),condition_id=NULL))
  sg<-brohn_build_explicit_distributions(list(),scales,d)$groups[[1]]
  check("Saved scale scores retain eligibility, two-score mean and repeated person",sg$source_records==3&&sg$usable_records==2&&sg$summary$mean==3&&sg$participant_count==1)
  mixed<-scales;mixed[[2]]$unit<-"other units"
  check("Different scale units cannot be pooled",rejects(brohn_build_explicit_distributions(list(),mixed,d)))
  mixed<-scales;mixed[[2]]$scale_hash<-strrep("b",64)
  check("Different scoring keys cannot be pooled",rejects(brohn_build_explicit_distributions(list(),mixed,d)))
  before<-brohn_hash(list(answers,scales,d));invisible(brohn_build_explicit_distributions(answers,scales,d))
  check("Original responses, scores and frozen design unchanged",identical(before,brohn_hash(list(answers,scales,d))))
  check("SVG contains source-bound metadata and explicit denominator",grepl("source",as.character(brohn_explicit_distribution_svg(cat_group,binding=list(report_hash=strrep("a",64)))),fixed=TRUE))
  skewed<-cat_group;skewed$categories<-lapply(1:30,function(i)list(label=paste("Category",i),value_kind="text",value_json=brohn_json(paste("Category",i)),count=if(i==1)100 else 1));skewed$usable_records<-129
  check("Category pages keep the complete distribution count scale",grepl('width="5.01"',as.character(brohn_explicit_distribution_svg(skewed,offset=20L)),fixed=TRUE))
  csv<-tempfile(fileext=".csv");on.exit(unlink(csv),add=TRUE)
  brohn_explicit_distribution_csv(list(body=list(result=list(binding=list(report_id="report-original",report_hash=strrep("a",64),analysis_sha256=strrep("b",64))))),cat_group,csv)
  bytes<-rawToChar(readBin(csv,"raw",file.info(csv)$size))
  check("C-locale CSV preserves real UTF-8 category bytes",grepl(enc2utf8("\u96ea"),bytes,fixed=TRUE,useBytes=TRUE)&&!grepl("<U+96EA>",bytes,fixed=TRUE))
  check("CSV explicitly carries exclusions and linkage",all(vapply(c("invalid_or_unsupported","unassigned_records","repeated_assessment_records","participant_linkage_complete"),grepl,logical(1),x=bytes,fixed=TRUE)))
  too_large<-cat_group;too_large$states<-list(list(state=strrep("x",4*1024^2),count=1));blocked_csv<-tempfile(fileext=".csv")
  check("Oversize repeated metadata rejected before any CSV write",rejects(brohn_explicit_distribution_csv(list(body=list(result=list(binding=list(report_id="r",report_hash=strrep("a",64),analysis_sha256=strrep("b",64))))),too_large,blocked_csv))&&!file.exists(blocked_csv))
  keyed<-d;second<-n;second$id<-"q-second";keyed$questions<-list(n,second)
  keyed$scales<-list(list(schema="brohn-questionnaire-scale/1.0",id="scale-keyed",label="Original keyed scale",version="1.0",source="Original test arithmetic",scope="end",
    items=lapply(keyed$questions,function(q)list(question_id=q$id,reverse=FALSE,min=0,max=10)),scoring=list(aggregation="sum",missing="complete",minimum_answered=2,prorate=FALSE),conversion=NULL))
  scored<-brohn_score_scales(list(row(2),row(4,question="q-second")),keyed)
  check("Original scale provenance and saved eligibility accepted",!rejects(.brohn_ed_validate_scales(scored,keyed)))
  bad<-scored;bad$recipe<-"unknown";check("Unsupported scale recipe rejected",rejects(.brohn_ed_validate_scales(bad,keyed)))
  bad<-scored;bad$provenance$design_hash<-strrep("f",64);check("Changed frozen scale design rejected",rejects(.brohn_ed_validate_scales(bad,keyed)))
  bad<-scored;bad$observations[[1]]$scale_hash<-strrep("f",64);check("Changed score key rejected",rejects(.brohn_ed_validate_scales(bad,keyed)))
  bad<-scored;bad$observations[[1]]$unit<-"other";check("Changed saved scale unit rejected",rejects(.brohn_ed_validate_scales(bad,keyed)))
  bad<-scored;bad$observations[[1]]$value<-FALSE;check("Boolean scale score rejected before distribution",rejects(.brohn_ed_validate_scales(bad,keyed)))
  bad<-scored;bad$observations[[1]]$status<-"not_scoreable";check("Ineligible scale cannot carry numeric score",rejects(.brohn_ed_validate_scales(bad,keyed)))
  cat("Explicit distribution checks:",checks,"\n")
})
