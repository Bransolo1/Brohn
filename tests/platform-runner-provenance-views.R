source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
source("R/platform-runner-provenance-views.R",encoding="UTF-8")
local({
  checks<-character();check<-function(label,x){if(!isTRUE(x))stop(label,call.=FALSE);checks<<-c(checks,label);cat("PASS",label,"\n")}
  rejects<-function(x)inherits(try(force(x),silent=TRUE),"try-error")
  folder<-Sys.getenv("BROHN_RUNNER_PROVENANCE_TEST_ROOT",tempfile("brohn-runner-provenance-"));dir.create(folder,recursive=TRUE,showWarnings=FALSE)
  stopifnot(startsWith(basename(folder),"brohn-runner-provenance-"),!file.exists(file.path(folder,"workspace","catalog.sqlite")))
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE);brohn_initialise_library(store)
  study<-brohn_create_study(store,"Original code-history review fixture","survey")
  d<-study$body;d$participant_equipment<-NULL;d$instructions<-"";d$questions<-list(brohn_question("Original fixture response","rating","end"))
  study<-brohn_save_study(store,d,study$revision);other<-brohn_create_study(store,"Other source study","survey")
  # Only this explicit historical fixture bypasses current release publication.
  # It does not assign today's code retrospectively or alter an existing source.
  legacy<-.brohn_publish_release(store,study$id,"sample")
  start<-function(release,n).brohn_delivery_start(store,release$token,list(consented=TRUE,client_id=paste0("fixture-client-",n),operation_id=paste0("fixture-start-",n)))
  old<-start(legacy,1L);pinned<-brohn_publish(store,study$id,"sample",quota=100L);new<-start(pinned,2L)
  release_command<-function(id)list(kind="release",id=id,study_id=study$id)
  run_command<-function(id)list(kind="run",id=id,study_id=study$id)
  read<-function(c)brohn_runner_provenance_read(store,c,study$project_id)
  a<-read(release_command(pinned$id));b<-read(run_command(new$run_id));historic<-read(run_command(old$run_id))
  check("new release and run preserve one exact code manifest",a$status=="pinned"&&identical(a$manifest,b$manifest)&&identical(a$manifest_hash,pinned$participant_runtime$manifest_hash))
  check("legacy release and run remain explicitly unknown",read(release_command(legacy$id))$status=="legacy_unpinned"&&historic$status=="legacy_unpinned"&&is.null(historic$manifest)&&is.null(historic$manifest_hash))
  check("assigned code keeps scientific design and protocol identities separate",identical(b$source$protocol_hash,brohn_hash(new$protocol))&&identical(a$source$design_hash,new$protocol$design_hash))
  check("runtime sidecar does not alter ordinary scientific run shape",!"participant_runtime" %in% names(brohn_run(store,new$run_id)))
  foreign<-run_command(new$run_id);foreign$study_id<-other$id
  check("cross-study cross-project and unknown-source reads refuse",rejects(read(foreign))&&rejects(brohn_runner_provenance_read(store,run_command(new$run_id),"another-project"))&&rejects(read(run_command("run-absent"))))
  invalid<-run_command(new$run_id);invalid$extra<-"unexpected"
  check("unexpected command fields and malformed identifiers refuse",rejects(read(invalid))&&rejects(read(run_command("../run"))))
  manifest_file<-file.path(folder,"exact-manifest.json");brohn_write_json_file(a$manifest,manifest_file)
  saved<-DBI::dbGetQuery(store$con,"SELECT manifest_json FROM delivery_runtimes WHERE deployment_id=?",params=list(pinned$id))$manifest_json[[1L]]
  check("manifest export is byte-exact to original stored JSON",identical(readBin(manifest_file,"raw",n=file.info(manifest_file)$size),charToRaw(saved)))
  serialized<-brohn_json(list(a,b,historic))
  check("evidence excludes release/run capabilities and participant client identifiers",!any(vapply(c(legacy$token,pinned$token,new$access_token,old$access_token,"fixture-client-"),grepl,logical(1),x=serialized,fixed=TRUE)))
  current<-as.character(.brohn_rp_evidence_ui(b));unknown<-as.character(.brohn_rp_evidence_ui(historic))
  check("readable copy distinguishes assigned from executed and historic unknown",grepl("does not prove",current,fixed=TRUE)&&grepl("Historical code is unknown",unknown,fixed=TRUE)&&!grepl("Preserved file inventory",unknown,fixed=TRUE))
  check("Collect entry keeps technical inventory out of normal setup",grepl("Code preserved with this release",as.character(brohn_runner_release_entry_ui(pinned,study$id)),fixed=TRUE)&&!grepl(a$manifest_hash,as.character(brohn_runner_release_entry_ui(pinned,study$id)),fixed=TRUE))
  runs<-list(new,old);for(i in 3:43)runs[[length(runs)+1L]]<-start(pinned,i)
  # Explicit synthetic report-shaped fixture tests links only. No scientific
  # analysis/result job is represented by this domain fixture.
  refs<-lapply(runs,function(r){rr<-brohn_run(store,r$run_id);list(run_id=r$run_id,deployment_id=rr$deployment_id,design_hash=rr$protocol$design_hash)})
  body<-list(title="Synthetic provenance-link fixture, not a scientific result",study_id=study$id,dataset_id=NULL,provenance=list(runs=refs),analysis=list(kind="questionnaire"))
  report<-brohn_put_entity(store,"report","report-runtime-fixture",body,project_id=study$project_id)
  command<-list(kind="report",id=report$id,study_id=study$id,revision=report$revision,hash=brohn_hash(body))
  linked<-brohn_runner_report_provenance(store,command,study$project_id)
  check("direct report inventory retains all43 exact original references",linked$total==43L&&identical(linked$refs,refs))
  bad<-command;bad$hash<-strrep("a",64L)
  check("stale report hash refuses instead of substituting latest result",rejects(brohn_runner_report_provenance(store,bad,study$project_id)))
  imported<-report;imported$body$dataset_id<-"dataset-declared-summary"
  check("imported summaries receive no guessed participant-code entry",is.null(brohn_runner_report_entry_ui(imported)))
  original<-list(protocols=DBI::dbGetQuery(store$con,"SELECT id,protocol_json,protocol_hash FROM delivery_runs ORDER BY id"),
    report=brohn_get_entity(store,"report",report$id),jobs=brohn_list_jobs(store),audit=DBI::dbGetQuery(store$con,"SELECT * FROM audit_log"))
  server<-function(input,output,session) {
    current<-new.env(parent=emptyenv());current$study<-study
    state<-shiny::reactiveValues(page="study",stage="Collect",report_id=NULL,error=NULL)
    attempt<-function(fn){state$error<-NULL;tryCatch(fn(),error=function(e){state$error<-conditionMessage(e);NULL})}
    api<-brohn_install_runner_provenance(input,output,session,store,state,current,attempt,function(fn)fn())
  }
  shiny::testServer(server,{
    session$setInputs(runner_provenance_open=run_command(new$run_id));s<-api$selected(FALSE)
    check("current study can open its exact assigned code",is.null(state$error)&&identical(s$evidence$manifest,b$manifest))
    check("unbound browser selection cannot download",rejects(api$evidence()))
    session$setInputs(runner_provenance_identity=s$identity)
    check("bound download retains selected source authority",identical(api$evidence(),b))
    state$stage<-"History";check("changing stage invalidates late download",rejects(api$evidence()));state$stage<-"Collect"
    current$study<-other;check("changing study invalidates late download",rejects(api$evidence()));current$study<-study
    session$setInputs(runner_provenance_close=1L);check("closing modal invalidates download",rejects(api$evidence()))
    returned<-FALSE;api$open(run_command(new$run_id),return_view=function()returned<<-TRUE);s<-api$selected(FALSE);session$setInputs(runner_provenance_identity=s$identity,runner_provenance_close=2L)
    check("close returns to original source review",returned&&rejects(api$evidence()))
    state$page<-"report";state$report_id<-report$id;session$setInputs(runner_provenance_open=command);s<-api$selected(FALSE)
    session$setInputs(runner_provenance_identity=s$identity)
    check("report opens original direct sources without selecting arbitrary code",s$report$total==43L&&is.null(s$evidence)&&rejects(api$evidence()))
    session$setInputs(runner_provenance_page=list(identity=s$identity,offset=40L));check("source paging reaches last three references",is.null(state$error)&&api$selected()$offset==40L)
    session$setInputs(runner_provenance_page=list(identity=s$identity,offset=43L));check("invalid source page refuses",!is.null(state$error)&&api$selected()$offset==40L)
    session$setInputs(runner_provenance_run=list(identity=s$identity,run_id="run-unrelated"));check("foreign session cannot be injected into report review",!is.null(state$error)&&is.null(api$selected()$evidence))
    session$setInputs(runner_provenance_run=list(identity=s$identity,run_id=old$run_id));chosen<-api$selected(FALSE)
    session$setInputs(runner_provenance_identity=chosen$identity)
    check("historic report source stays unknown with exact report link",api$evidence()$status=="legacy_unpinned"&&identical(api$evidence()$report$hash,command$hash))
    session$setInputs(runner_provenance_run=list(identity=s$identity,run_id=new$run_id));check("stale nested source command refuses",!is.null(state$error))
    session$setInputs(runner_provenance_back=1L);s<-api$selected(FALSE);session$setInputs(runner_provenance_identity=s$identity)
    check("back restores same report source page",s$offset==40L&&is.null(s$evidence)&&identical(s$command,command))
    session$setInputs(runner_provenance_run=list(identity=s$identity,run_id=new$run_id));chosen<-api$selected(FALSE);session$setInputs(runner_provenance_identity=chosen$identity)
    check("pinned report source preserves its exact native identity",api$evidence()$status=="pinned"&&identical(api$evidence()$source$protocol_hash,brohn_hash(new$protocol)))
    state$report_id<-"report-other";check("late report download cannot cross another report",rejects(api$evidence()))
  })
  check("all read and UI operations leave scientific records jobs and audit untouched",identical(original$protocols,DBI::dbGetQuery(store$con,"SELECT id,protocol_json,protocol_hash FROM delivery_runs ORDER BY id"))&&
    identical(original$report,brohn_get_entity(store,"report",report$id))&&identical(original$jobs,brohn_list_jobs(store))&&identical(original$audit,DBI::dbGetQuery(store$con,"SELECT * FROM audit_log")))
  brohn_write_json_file(list(passed=TRUE,checks=as.list(checks),manifest_hash=a$manifest_hash,scope="Original synthetic assigned-code/link/UI fixtures. No scientific worker or human observation."),file.path(folder,"results.json"))
  cat(length(checks),"participant-code provenance checks passed;",folder,"\n")
})
