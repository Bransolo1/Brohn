# Connected publication, HTTP dispatcher, atomic admission and backup checks.
# Request objects invoke the real dispatcher; Chrome/HTTP has separate evidence.
source("R/platform-load.R", encoding="UTF-8"); brohn_load(ui=FALSE)
local({
  folder <- tempfile("brohn-runner-delivery-"); dir.create(folder)
  store <- brohn_open_store(file.path(folder,"workspace"))
  on.exit(brohn_close_store(store),add=TRUE)
  brohn_initialise_library(store)
  checks <- character()
  check <- function(name,ok) {if(!isTRUE(ok))stop("FAIL: ",name);checks<<-c(checks,name);cat("PASS",name,"\n")}
  rejects <- function(expr) inherits(try(force(expr),silent=TRUE),"try-error")
  site<-file.path(folder,"site");dir.create(site);dir.create(file.path(site,"participant"));dir.create(file.path(site,"brand"))
  for(path in .brohn_runner_paths())stopifnot(file.copy(file.path("www",path),file.path(site,path)))
  static<-file.path(site,"participant")
  secret_file<-file.path(folder,"edge.secret");writeChar(brohn_token(),secret_file,eos=NULL,useBytes=TRUE)
  rev_file<-file.path(folder,"revocations.json")
  brohn_write_json_file(list(schema="brohn-hosted-revocations/1.0",subjects=list(),not_before=0),rev_file)
  profile<-brohn_validate_hosted_profile(list(schema="brohn-hosted-profile/1.0",id="runtime-hooks",mode="local_oidc_fixture",
    workspace_root=store$root,workspace_id=store$workspace_id,project_id="default",researcher_origin="https://localhost:3991",
    participant_origin="https://localhost:3992",issuer="http://127.0.0.1:3993/realms/brohn",allowed_groups=list("researchers"),
    edge_secret_file=secret_file,revocations_file=rev_file,session_seconds=600,enrollment_seconds=600,upload_seconds=1200,
    resource_seconds=1200,researcher_port=3994,participant_port=3995,oauth_port=3996))
  context<-brohn_hosted_context(list(HTTP_HOST="localhost:3991",HTTP_X_FORWARDED_PROTO="https",HTTP_X_BROHN_EDGE=profile$edge_secret,
    HTTP_X_FORWARDED_USER="runtime-fixture",HTTP_X_FORWARDED_GROUPS="researchers"),profile)
  researcher<-brohn_hosted_bind_store(store,profile,context)
  participant<-brohn_hosted_bind_store(store,profile,participant=TRUE)
  study<-brohn_create_study(researcher,"Preserved browser source fixture","survey")
  design<-study$body;design$questions<-list(brohn_question("Which concept do you prefer?","rating","end","q-preference"))
  study<-brohn_save_study(researcher,design,study$revision)
  release<-brohn_publish(researcher,study$id,"sample",participant_static_root=static)
  runtime<-brohn_runner_assets_read(store,release$id)
  check("new production publication preserves all original distribution bytes",runtime$status=="pinned"&&length(runtime$manifest$files)==17L&&
    all(vapply(runtime$manifest$files,function(x)identical(x$hash,digest::digest(file=file.path(site,x$path),algo="sha256")),logical(1))))
  counts<-function()setNames(lapply(c("delivery_deployments","delivery_deployment_credentials","delivery_runtimes","hosted_release_policy",
    "delivery_runs","delivery_run_credentials","delivery_run_runtimes","hosted_run_policy","delivery_receipts","objects","audit_log"),function(table)
      if(table%in%DBI::dbListTables(store$con))DBI::dbGetQuery(store$con,paste("SELECT count(*) AS n FROM",table))$n[[1L]]else 0L),
    c("release","release_secret","runtime","release_policy","run","run_secret","assignment","run_policy","receipts","objects","audit"))
  # Ensure policy tables exist before comparing exact count snapshots.
  .brohn_hosted_schema(store)
  app<-brohn_delivery_app(participant,static)
  call<-function(path,payload=NULL,header=NULL,query="",edge=profile$edge_secret,bearer=NULL) {
    bytes<-if(is.null(payload))raw()else charToRaw(.brohn_store_json(payload))
    req<-list(PATH_INFO=path,QUERY_STRING=query,REQUEST_METHOD=if(is.null(payload))"GET"else"POST",HTTP_HOST="localhost:3992",
      HTTP_ORIGIN=profile$participant_origin,HTTP_X_FORWARDED_PROTO="https",HTTP_X_BROHN_EDGE=edge,REMOTE_ADDR="127.0.0.1",
      CONTENT_TYPE="application/json",CONTENT_LENGTH=as.character(length(bytes)),rook.input=list(read=function(n=-1L)bytes))
    if(!is.null(header))req$HTTP_X_BROHN_PARTICIPANT_RUNTIME<-header
    if(!is.null(bearer))req$HTTP_AUTHORIZATION<-paste("Bearer",bearer)
    response<-app$call(req)
    if(is.character(response$body)&&grepl("^application/json",response$headers[["Content-Type"]]))response$value<-brohn_parse(response$body)
    response
  }
  path<-paste0("/api/start/",release$token)
  request<-list(consented=TRUE,client_id="runtime-client",operation_id="runtime-start")
  before<-counts()
  check("missing runtime identity refuses new HTTP admission",call(path,request)$status==409L&&identical(counts(),before))
  check("mismatched runtime identity refuses without quota or private rows",call(path,request,strrep("a",64))$status==409L&&identical(counts(),before))
  original_bind<-brohn_runner_bind_run
  assign("brohn_runner_bind_run",function(...) {original_bind(...);stop("Injected failure after runtime binding")},envir=.GlobalEnv)
  failed<-tryCatch(call(path,request,runtime$manifest_hash),finally=assign("brohn_runner_bind_run",original_bind,envir=.GlobalEnv))
  check("failed binding rolls back run credential assignment policy receipt and audit",failed$status!=200L&&identical(counts(),before))
  started<-call(path,request,runtime$manifest_hash)
  check("matching original runtime admits one session",started$status==200L)
  run_id<-started$value$run_id;assignment<-brohn_runner_run_read(store,run_id)
  check("run code is separately bound to its exact release",identical(assignment$manifest_hash,runtime$manifest_hash)&&identical(assignment$deployment_id,release$id))
  check("runtime does not modify scientific protocol or raw request",!"participant_runtime"%in%names(brohn_run(store,run_id)$protocol)&&
    identical(DBI::dbGetQuery(store$con,"SELECT request_hash FROM delivery_receipts WHERE scope=? AND operation='start'",params=list(release$id))$request_hash[[1L]],
      .brohn_delivery_hash(.brohn_store_json(request))))
  before<-counts();repeat_start<-call(path,request,runtime$manifest_hash)
  check("exact pending start retry returns original run and secret without mutation",identical(started$value,repeat_start$value)&&identical(counts(),before))
  check("runtime identity remains required on an admitted retry",call(path,request)$status==409L&&call(path,request,strrep("b",64))$status==409L&&identical(counts(),before))
  refused<-FALSE;authenticated_refused<-FALSE
  try(.brohn_store_tx(store,function(){DBI::dbExecute(store$con,"DROP TRIGGER delivery_run_runtime_no_delete")
    DBI::dbExecute(store$con,"DELETE FROM delivery_run_runtimes WHERE run_id=?",params=list(run_id))
    refused<<-call(path,request,runtime$manifest_hash)$status==409L&&DBI::dbGetQuery(store$con,"SELECT count(*) n FROM delivery_run_runtimes")$n[[1L]]==0L
    authenticated_refused<<-call(paste0("/api/session_status/",run_id),bearer=started$value$access_token)$status==409L
    stop("Rollback deliberate missing assignment")}),silent=TRUE)
  check("missing admitted assignment is refused rather than retrospectively recreated",refused&&identical(counts(),before))
  check("authenticated operations also refuse a missing preserved assignment",authenticated_refused&&identical(counts(),before))
  redirect<-call("/participant/",query=paste0("token=",release$token))
  prefix<-paste0("/api/runtime/",release$token,"/",runtime$manifest_hash,"/")
  check("production dispatcher redirects new release to original runtime",redirect$status==302L&&identical(redirect$headers$Location,paste0(prefix,"participant/index.html?token=",release$token)))
  check("actual httpuv query representation produces the identical preserved redirect",identical(call("/participant/",query=paste0("?token=",release$token)),redirect))
  check("runtime route retains original edge boundary",call(paste0(prefix,"participant/runner.js"),edge=strrep("0",64))$status==403L)
  check("pinned entry refuses another release query",call(paste0(prefix,"participant/index.html"),query=paste0("token=",strrep("a",64)))$status==400L)
  check("relative worklet and icon route exact original objects",all(vapply(c("participant/audio-worklet.js","brand/brohn-app-icon.svg"),function(p)
    identical(call(paste0(prefix,p))$body,readBin(file.path(site,p),"raw",n=file.info(file.path(site,p))$size)),logical(1))))
  original<-call(paste0(prefix,"participant/runner.js"))$body
  writeBin(c(original,charToRaw("\n// New fixture installation\n")),file.path(static,"runner.js"))
  newer<-brohn_publish(researcher,study$id,"sample",participant_static_root=static)
  check("later release has changed code while original bytes stay exact",!identical(newer$participant_runtime$manifest_hash,runtime$manifest_hash)&&identical(call(paste0(prefix,"participant/runner.js"))$body,original))
  before<-counts();original_object<-brohn_store_object;n<-0L
  assign("brohn_store_object",function(...) {n<<-n+1L;if(n==3L)stop("Injected source publication failure");original_object(...)},envir=.GlobalEnv)
  failed<-tryCatch(rejects(brohn_publish(researcher,study$id,"sample",participant_static_root=static)),finally=assign("brohn_store_object",original_object,envir=.GlobalEnv))
  check("failed production publication rolls back release secret hosted policy objects and audit",failed&&n==3L&&identical(counts(),before))
  legacy<-.brohn_publish_release(researcher,study$id,"sample")
  legacy_start<-call(paste0("/api/start/",legacy$token),list(consented=TRUE,client_id="legacy-client",operation_id="legacy-start"))
  check("simulated pre-feature release and session retain explicit unknown code history",legacy_start$status==200L&&
    identical(brohn_runner_run_read(store,legacy_start$value$run_id)$status,"legacy_unpinned"))
  check("legacy request cannot claim current preserved runtime",call(paste0("/api/start/",legacy$token),list(consented=TRUE,client_id="legacy-client",operation_id="legacy-start"),runtime$manifest_hash)$status==409L)
  brohn_hosted_revoke(researcher,"release",release$id)
  check("revoked recruitment preserves only original generic code and admitted start recovery",call(paste0(prefix,"participant/runner.js"))$status==200L&&
    call(paste0("/api/entry/",release$token))$status==403L&&call(path,request,runtime$manifest_hash)$status==200L)
  candidate<-request;candidate$client_id<-"never-admitted";candidate$operation_id<-"never-admitted-op"
  check("revoked recruitment refuses a previously uncommitted start",call(path,candidate,runtime$manifest_hash)$status==403L)
  brohn_hosted_revoke(researcher,"run",run_id)
  check("generic code availability does not reauthorize a revoked run",call(paste0(prefix,"participant/runner.js"))$status==200L&&identical(call(path,request,runtime$manifest_hash)$value$error$code,"run_revoked"))
  stopifnot(file.rename(site,paste0(site,"-removed")))
  app<-brohn_delivery_app(participant,static)
  check("restarted dispatcher serves original runtime without installation files",identical(call(paste0(prefix,"participant/runner.js"))$body,original)&&call("/participant/runner.js")$status==503L)
  backup<-file.path(folder,"source.brohn-backup");brohn_backup_workspace(store,backup)
  check("wired backup accepts complete preserved runtime catalog",brohn_verify_backup(backup)$verified)
  damaged<-file.path(folder,"damaged.sqlite");.brohn_backup_online_copy(store$con,damaged)
  con<-.brohn_backup_connect(damaged,FALSE)
  DBI::dbExecute(con,"PRAGMA foreign_keys=OFF");DBI::dbExecute(con,"DROP TABLE delivery_run_runtimes")
  DBI::dbExecute(con,"DROP TRIGGER delivery_runtime_no_delete");DBI::dbExecute(con,"DROP TABLE delivery_runtimes");DBI::dbDisconnect(con)
  check("wired backup catalog refuses loss of both runtime tables",rejects(.brohn_backup_catalog(damaged)))
  check("original source remains intact after corruption probe",brohn_runner_catalog_integrity(store$con)&&identical(brohn_runner_run_read(store,run_id)$manifest_hash,runtime$manifest_hash))
  receipt<-Sys.getenv("BROHN_TEST_RECEIPT","")
  result<-list(schema="brohn-runner-delivery-tests/1.0",passed=length(checks),checks=as.list(checks),
    scope="Real connected domain/HTTP dispatcher and SQLite backup. Synthetic edge identity; not network/TLS/browser qualification.",
    code_hashes=setNames(lapply(c("R/platform-runner-assets.R","R/platform-delivery.R","R/platform-backup.R","tests/platform-runner-delivery.R"),function(p)digest::digest(file=p,algo="sha256")),
      c("R/platform-runner-assets.R","R/platform-delivery.R","R/platform-backup.R","tests/platform-runner-delivery.R")))
  if(nzchar(receipt))brohn_write_json_file(result,receipt)
  cat("PASS",length(checks),"connected runtime delivery checks\n")
})
