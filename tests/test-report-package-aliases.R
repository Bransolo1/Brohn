# Self-contained exact-reference identity regression; no store or analysis.
args<-commandArgs(TRUE);stopifnot(length(args)==1L);out<-args[[1L]];stopifnot(!file.exists(out));dir.create(out,recursive=TRUE)
external<-normalizePath(dirname(sub("^--file=","",grep("^--file=",commandArgs(),value=TRUE)[1L])),winslash="/",mustWork=TRUE)
component<-file.path(external,"platform-report-package-tables.R");if(!file.exists(component))component<-"R/platform-report-package-tables.R"
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE);source(component,encoding="UTF-8")
checks<-list();check<-function(name,x){stopifnot(isTRUE(x));checks[[length(checks)+1L]]<<-name;cat("PASS",name,"\n")}
item<-function(id,revision,observations,provenance=list(),project="default"){
  body<-list(id=id,analysis=list(observations=observations),provenance=provenance)
  list(ref=list(kind="report",id=id,revision=revision,body_hash=brohn_hash(body),project_id=project),saved_body=body,complete_analysis=body$analysis)
}
row<-list(participant_id="SOURCE-PERSON",session_id="SOURCE-VISIT",exposure_id="SOURCE-EXPOSURE",value=1.25)
first<-item("same-source",1L,list(row));second<-item("same-source",2L,list(row))
check("identical original bodies can have distinct exact catalog revisions",identical(first$ref$body_hash,second$ref$body_hash)&&first$ref$revision!=second$ref$revision)
source_ref<-list(id=second$ref$id,revision=second$ref$revision,hash=second$ref$body_hash)
crosswalk<-list(report_id=second$ref$id,source_participant_id=row$participant_id,source_session_id=row$session_id,participant_id="REVIEWED-PERSON",session_id="REVIEWED-VISIT")
combined_row<-c(list(source_report_id=second$ref$id,source_report_revision=2L,source_report_hash=second$ref$body_hash,
  source_participant_id=row$participant_id,source_session_id=row$session_id,source_exposure_id=row$exposure_id),
  list(participant_id="REVIEWED-PERSON",session_id="REVIEWED-VISIT",value=1.25))
combined<-item("combined",1L,list(combined_row),list(selection=list(source_ref),crosswalk=list(crosswalk)))
reports<-list(first,second,combined);aliases<-.brohn_rp_alias_context("package_aliases",reports)
one<-.brohn_rp_project(row,aliases,"report-01");two<-.brohn_rp_project(row,aliases,"report-02")
joined<-.brohn_rp_project(combined_row,aliases,"report-03")
edge<-.brohn_rp_project(crosswalk,aliases,"report-03","provenance/crosswalk/*")
check("same body distinct revision has separate original-source labels",one$participant_id!=two$participant_id&&one$session_id!=two$session_id)
check("combined source person joins exact revision two",identical(joined$source_participant_id,two$participant_id))
check("combined source visit joins exact revision two",identical(joined$source_session_id,two$session_id))
check("combined source exposure joins exact revision two",identical(joined$source_exposure_id,two$exposure_id))
check("crosswalk source uses its saved provenance revision",identical(edge$source_participant_id,two$participant_id)&&identical(edge$source_session_id,two$session_id))
check("crosswalk reviewed target remains an explicit distinct identity",identical(edge$participant_id,joined$participant_id)&&edge$participant_id!=two$participant_id&&identical(edge$session_id,joined$session_id))
check("scientific value and explicit source revision unchanged",joined$value==1.25&&joined$source_report_revision==2L&&identical(joined$source_report_hash,second$ref$body_hash))
bad<-combined_row;bad$source_report_revision<-1L
error<-tryCatch({.brohn_rp_project(bad,aliases,"report-03");NULL},error=conditionMessage)
check("row cannot override its parent saved source revision",!is.null(error)&&grepl("no unambiguous exact report binding",error,fixed=TRUE))
unbound<-item("unbound",1L,list());unbound_refs<-c(list(first,second),list(unbound));u<-.brohn_rp_alias_context("package_aliases",unbound_refs)
bad<-combined_row;bad$source_report_revision<-NULL
error<-tryCatch({.brohn_rp_project(bad,u,"report-03");NULL},error=conditionMessage)
check("unbound identical-body revisions fail instead of taking first",!is.null(error)&&grepl("no unambiguous exact report binding",error,fixed=TRUE))
third<-second;third$ref$project_id<-"another-project";foreign<-.brohn_rp_alias_context("package_aliases",list(third,unbound))
error<-tryCatch({.brohn_rp_project(combined_row,foreign,"report-02");NULL},error=conditionMessage)
check("same report label from another project cannot bind",!is.null(error)&&grepl("no unambiguous exact report binding",error,fixed=TRUE))
error<-tryCatch({.brohn_rp_alias_context("package_aliases",list(first,first));NULL},error=conditionMessage)
check("duplicate exact source ref is refused",!is.null(error)&&grepl("duplicated",error,fixed=TRUE))
missing<-list(source_report_id="missing-report",revision=NULL,hash=NULL,status="unavailable",reason="source_was_unavailable",extracted_rows=0L,eligible_rows=0L)
check("unavailable source metadata stays exact without invented identity",.brohn_rp_same(.brohn_rp_project(missing,aliases,"report-03"),missing))
with_missing<-combined;with_missing$complete_analysis$recordings<-list(missing)
check("unavailable source metadata does not prevent alias context preparation",is.list(.brohn_rp_alias_context("package_aliases",list(first,second,with_missing))))
.brohn_rp_write(list(schema="brohn-report-package-alias-tests/0.1",passed=TRUE,checks=checks,check_count=length(checks),tables_sha256=digest::digest(file=component,algo="sha256"),
  scope="Pure synthetic exact-ref alias tests only; no source authority or analysis claim"),file.path(out,"results.json"),TRUE)
