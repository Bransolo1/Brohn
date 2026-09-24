# One isolated team workspace behind a configured OIDC-verifying edge. This is
# not shared-database tenant ACL or a custom OAuth/JWT implementation.
.brohn_hosted_fail <- function(message, code="hosted_access", status=403L) {
  stop(structure(list(message=message,call=NULL,code=code,status=as.integer(status)),
    class=c("brohn_hosted_error","brohn_delivery_error","error","condition")))
}
.brohn_hosted_require <- function(ok,message,code="hosted_access",status=403L) {
  if(!isTRUE(ok)).brohn_hosted_fail(message,code,status)
  invisible(TRUE)
}
.brohn_hosted_text <- function(x,max=512L) is.character(x)&&length(x)==1L&&!is.na(x)&&nzchar(x)&&nchar(x,type="bytes")<=max&&!grepl("[[:cntrl:]]",x)
.brohn_hosted_number <- function(x,lo,hi) is.numeric(x)&&length(x)==1L&&is.finite(x)&&x==floor(x)&&x>=lo&&x<=hi
.brohn_hosted_origin <- function(x,fixture=FALSE,issuer=FALSE) {
  .brohn_hosted_require(.brohn_hosted_text(x,1024L),"Configure an exact hosted origin.","profile",503L)
  pattern<-if(issuer)"^https://[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:[0-9]{1,5})?(/[A-Za-z0-9._~-]+)*$" else "^https://[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:[0-9]{1,5})?$"
  valid<-grepl(pattern,x)
  if(fixture&&issuer)valid<-valid||grepl("^http://127\\.0\\.0\\.1:[0-9]{1,5}/realms/[a-z0-9-]+$",x)
  .brohn_hosted_require(valid,"Use an exact HTTPS origin without credentials, query, fragment or a trailing slash.","profile",503L)
  authority<-strsplit(sub("^https?://","",x),"/",fixed=TRUE)[[1L]][[1L]]
  components<-strsplit(authority,":",fixed=TRUE)[[1L]]
  if(length(components)==2L).brohn_hosted_require(.brohn_hosted_number(suppressWarnings(as.numeric(components[[2L]])),1,65535),"Hosted origin port is invalid.","profile",503L)
  .brohn_hosted_require(all(grepl("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$",strsplit(components[[1L]],".",fixed=TRUE)[[1L]])),"Hosted origin hostname is invalid.","profile",503L)
  if(!fixture).brohn_hosted_require(!grepl("^https://(localhost|127\\.0\\.0\\.1)(:|/|$)",x),"Public mode needs configured public origins.","profile",503L)
  x
}
.brohn_hosted_read <- function(path,maximum=65536L) {
  .brohn_hosted_require(.brohn_hosted_text(path,4096L)&&file.exists(path)&&!dir.exists(path)&&file.info(path)$size<=maximum,"Hosted configuration is unavailable.","profile",503L)
  tryCatch(jsonlite::fromJSON(path,simplifyVector=FALSE),error=function(e).brohn_hosted_fail("Hosted configuration could not be read.","profile",503L))
}
brohn_validate_hosted_profile <- function(p) {
  required<-c("schema","id","mode","workspace_root","workspace_id","project_id","researcher_origin","participant_origin","issuer","allowed_groups","edge_secret_file","revocations_file","session_seconds","enrollment_seconds","upload_seconds","resource_seconds","researcher_port","participant_port","oauth_port")
  .brohn_hosted_require(is.list(p)&&!is.null(names(p))&&setequal(names(p),required)&&!anyDuplicated(names(p)),"Hosted profile fields are incomplete or unknown.","profile",503L)
  .brohn_hosted_require(identical(p$schema,"brohn-hosted-profile/1.0")&&p$mode %in% c("isolated_team","local_oidc_fixture")&&.brohn_hosted_text(p$id,100L),"Choose the supported isolated-team hosted profile.","profile",503L)
  fixture<-identical(p$mode,"local_oidc_fixture")
  for(key in c("researcher_origin","participant_origin","issuer"))p[[key]]<-.brohn_hosted_origin(p[[key]],fixture,key=="issuer")
  .brohn_hosted_require(!identical(p$researcher_origin,p$participant_origin),"Researcher and participant origins must differ.","profile",503L)
  .brohn_hosted_require(.brohn_hosted_text(p$workspace_root,4096L)&&dir.exists(p$workspace_root)&&.brohn_hosted_text(p$workspace_id,100L)&&identical(p$project_id,"default"),"Bind one existing workspace and its default project.","profile",503L)
  p$workspace_root<-normalizePath(p$workspace_root,winslash="/",mustWork=TRUE)
  .brohn_hosted_require(is.list(p$allowed_groups)&&length(p$allowed_groups)>0L&&length(p$allowed_groups)<=20L&&all(vapply(p$allowed_groups,function(g).brohn_hosted_text(g,120L)&&!grepl("[,\"\\\\]",g),logical(1)))&&!anyDuplicated(unlist(p$allowed_groups)),"Configure an exact researcher group allowlist.","profile",503L)
  bounds<-list(session_seconds=c(30,3600),enrollment_seconds=c(30,30*86400),upload_seconds=c(30,7*86400),resource_seconds=c(30,7*86400),researcher_port=c(1024,65535),participant_port=c(1024,65535),oauth_port=c(1024,65535))
  for(key in names(bounds)).brohn_hosted_require(.brohn_hosted_number(p[[key]],bounds[[key]][[1]],bounds[[key]][[2]]),paste("Configure bounded",key,"."),"profile",503L)
  .brohn_hosted_require(length(unique(unlist(p[c("researcher_port","participant_port","oauth_port")])))==3L,"Internal service ports must differ.","profile",503L)
  .brohn_hosted_require(p$resource_seconds>=p$upload_seconds,"Material access must cover the admitted upload interval.","profile",503L)
  for(key in c("edge_secret_file","revocations_file")) {
    .brohn_hosted_require(.brohn_hosted_text(p[[key]],4096L)&&file.exists(p[[key]])&&!dir.exists(p[[key]]),"Supply protected edge-secret and revocation files.","profile",503L)
    p[[key]]<-normalizePath(p[[key]],winslash="/",mustWork=TRUE)
  }
  .brohn_hosted_require(file.info(p$edge_secret_file)$size==64L,"The edge proof must be an exact 32-byte hexadecimal secret file.","profile",503L)
  secret<-readChar(p$edge_secret_file,64L,useBytes=TRUE)
  .brohn_hosted_require(grepl("^[a-f0-9]{64}$",secret),"Invalid edge secret encoding.","profile",503L)
  p$edge_secret<-secret;p$identity<-brohn_hash(p[setdiff(names(p),"edge_secret")])
  .brohn_hosted_revocations(p)
  p
}
.brohn_hosted_cache<-new.env(parent=emptyenv())
brohn_hosted_profile <- function(path=Sys.getenv("BROHN_HOSTED_PROFILE")) {
  if(!nzchar(path))return(NULL)
  key<-normalizePath(path,winslash="/",mustWork=TRUE)
  if(!exists(key,envir=.brohn_hosted_cache,inherits=FALSE))assign(key,brohn_validate_hosted_profile(.brohn_hosted_read(key)),envir=.brohn_hosted_cache)
  get(key,envir=.brohn_hosted_cache,inherits=FALSE)
}
.brohn_hosted_revocations <- function(profile) {
  r<-.brohn_hosted_read(profile$revocations_file)
  .brohn_hosted_require(is.list(r)&&identical(r$schema,"brohn-hosted-revocations/1.0")&&setequal(names(r),c("schema","subjects","not_before"))&&is.list(r$subjects)&&length(r$subjects)<=1000L&&all(vapply(r$subjects,.brohn_hosted_text,logical(1)))&&is.numeric(r$not_before)&&length(r$not_before)==1L&&is.finite(r$not_before)&&r$not_before>=0,"Hosted revocation policy is invalid.","profile",503L)
  r
}
.brohn_hosted_header <- function(req,key,maximum=2048L) {
  value<-req[[key]]
  .brohn_hosted_require(.brohn_hosted_text(value,maximum),"The trusted hosted edge did not provide a valid request context.")
  value
}
.brohn_hosted_edge <- function(req,p,origin) {
  .brohn_hosted_require(identical(.brohn_hosted_header(req,"HTTP_X_BROHN_EDGE",64L),p$edge_secret),"The trusted hosted edge is required.")
  .brohn_hosted_require(identical(.brohn_hosted_header(req,"HTTP_HOST"),sub("^https://","",origin))&&identical(.brohn_hosted_header(req,"HTTP_X_FORWARDED_PROTO"),"https"),"Hosted request origin was not accepted.","origin")
  if(!is.null(req$HTTP_ORIGIN)&&nzchar(req$HTTP_ORIGIN)).brohn_hosted_require(identical(req$HTTP_ORIGIN,origin),"Cross-origin requests are not accepted.","origin")
  if(!is.null(req$HTTP_SEC_FETCH_SITE)).brohn_hosted_require(req$HTTP_SEC_FETCH_SITE %in% c("same-origin","none","same-site"),"Cross-site requests are not accepted.","origin")
  invisible(TRUE)
}
brohn_hosted_context <- function(req,profile,now=as.numeric(Sys.time())) {
  if(is.null(profile))return(NULL)
  .brohn_hosted_edge(req,profile,profile$researcher_origin)
  subject<-.brohn_hosted_header(req,"HTTP_X_FORWARDED_USER",256L)
  .brohn_hosted_require(!grepl("[,[:space:]]",subject),"A stable verified researcher subject is required.")
  groups<-strsplit(.brohn_hosted_header(req,"HTTP_X_FORWARDED_GROUPS"),",",fixed=TRUE)[[1L]]
  .brohn_hosted_require(any(groups %in% unlist(profile$allowed_groups)),"This researcher is not allowed in this workspace.")
  ctx<-list(schema="brohn-hosted-context/1.0",issuer=profile$issuer,subject=subject,profile_identity=profile$identity,started=now,expires=now+profile$session_seconds)
  .brohn_hosted_context_valid(ctx,profile,now);ctx
}
.brohn_hosted_context_valid <- function(ctx,p,now=as.numeric(Sys.time())) {
  .brohn_hosted_require(is.list(ctx)&&identical(ctx$schema,"brohn-hosted-context/1.0")&&identical(ctx$profile_identity,p$identity)&&identical(ctx$issuer,p$issuer)&&.brohn_hosted_text(ctx$subject,256L)&&is.numeric(ctx$started)&&length(ctx$started)==1L&&is.numeric(ctx$expires)&&length(ctx$expires)==1L&&is.finite(ctx$started)&&is.finite(ctx$expires)&&ctx$started<=now&&now<ctx$expires,"Researcher access has expired. Sign in again to continue.","session_expired",401L)
  revocations<-.brohn_hosted_revocations(p)
  .brohn_hosted_require(!ctx$subject %in% unlist(revocations$subjects)&&ctx$started>=revocations$not_before,"Researcher access was revoked. Contact the workspace operator.","session_revoked",401L)
  invisible(TRUE)
}
brohn_hosted_bind_store <- function(store,profile,context=NULL,participant=FALSE) {
  if(is.null(profile))return(store)
  .brohn_hosted_require(identical(store$workspace_id,profile$workspace_id)&&identical(normalizePath(store$root,winslash="/",mustWork=TRUE),profile$workspace_root),"This hosted profile belongs to a different workspace. Rebind a restored copy explicitly.","workspace",503L)
  rows<-DBI::dbGetQuery(store$con,"SELECT project_id FROM entities UNION SELECT project_id FROM entity_versions")
  .brohn_hosted_require(all(rows$project_id==profile$project_id),"This hosted profile supports one isolated team project only.","workspace",503L)
  if(!participant).brohn_hosted_context_valid(context,profile)
  store$hosted_profile<-profile;store$hosted_context<-context;store$hosted_participant<-isTRUE(participant)
  .brohn_hosted_schema(store);store
}
brohn_hosted_require_session <- function(store) {
  if(!is.null(store$hosted_profile)&&!isTRUE(store$hosted_participant)).brohn_hosted_context_valid(store$hosted_context,store$hosted_profile)
  invisible(TRUE)
}
brohn_hosted_require_project <- function(store,project_id) {
  if(!is.null(store$hosted_profile)).brohn_hosted_require(identical(project_id,store$hosted_profile$project_id),"This project is not part of the isolated hosted workspace.","foreign_project")
  invisible(TRUE)
}
brohn_hosted_require_action <- function(store,action) {
  brohn_hosted_require_session(store)
  .brohn_hosted_require(is.null(store$hosted_profile)||!action %in% c("server_folder_import","backup","resume_workspace"),"This operation requires the trusted workspace operator on the host.","operator_required")
  invisible(TRUE)
}
brohn_hosted_actor <- function(store) {
  if(is.null(store$hosted_context))return(NULL)
  brohn_hosted_require_session(store)
  list(kind="oidc_researcher",issuer=store$hosted_context$issuer,subject=store$hosted_context$subject,profile_id=store$hosted_profile$id)
}
brohn_hosted_participant_request <- function(store,req) {
  p<-store$hosted_profile;if(is.null(p))return(FALSE)
  # The process supervisor's metadata-only probe is internal. The public edge
  # must refuse /api/health; an arbitrary Host header is not sufficient here.
  if(identical(req$REQUEST_METHOD,"GET")&&identical(req$PATH_INFO,"/api/health")&&
    req$REMOTE_ADDR %in% c("127.0.0.1","::1")&&identical(req$HTTP_HOST,paste0("127.0.0.1:",p$participant_port)))return(TRUE)
  .brohn_hosted_edge(req,p,p$participant_origin);TRUE
}
brohn_participant_origin <- function(store,port) {
  if(is.null(store$hosted_profile))paste0("http://127.0.0.1:",port)else store$hosted_profile$participant_origin
}
.brohn_hosted_schema <- function(store) {
  DBI::dbExecute(store$con,"CREATE TABLE IF NOT EXISTS hosted_release_policy(deployment_id TEXT PRIMARY KEY,workspace_id TEXT NOT NULL,created REAL NOT NULL,enrollment_expires REAL NOT NULL,resource_expires REAL NOT NULL,upload_seconds INTEGER NOT NULL,revoked REAL)")
  DBI::dbExecute(store$con,"CREATE TABLE IF NOT EXISTS hosted_run_policy(run_id TEXT PRIMARY KEY,deployment_id TEXT NOT NULL,created REAL NOT NULL,upload_expires REAL NOT NULL,revoked REAL)")
  invisible(TRUE)
}
brohn_hosted_register_release <- function(store,id,now=as.numeric(Sys.time())) {
  p<-store$hosted_profile;if(is.null(p))return(invisible(NULL))
  brohn_hosted_require_session(store)
  DBI::dbExecute(store$con,"INSERT INTO hosted_release_policy VALUES(?,?,?,?,?,?,NULL)",params=list(id,store$workspace_id,now,now+p$enrollment_seconds,now+p$enrollment_seconds+p$resource_seconds,p$upload_seconds))
  invisible(NULL)
}
brohn_hosted_release_policy <- function(store,id) {
  if(is.null(store$hosted_profile))return(NULL)
  row<-DBI::dbGetQuery(store$con,"SELECT * FROM hosted_release_policy WHERE deployment_id=?",params=list(id))
  .brohn_hosted_require(nrow(row)==1L&&identical(row$workspace_id[[1L]],store$workspace_id),"This release was not published for this hosted workspace.","release_access",403L)
  row
}
brohn_hosted_require_release <- function(store,id,operation=c("entry","enroll","resource"),now=as.numeric(Sys.time())) {
  operation<-match.arg(operation);row<-brohn_hosted_release_policy(store,id);if(is.null(row))return(invisible(TRUE))
  .brohn_hosted_require(is.na(row$revoked[[1L]]),"This study link has been revoked. Contact your researcher; saved browser responses have been retained.","release_revoked",403L)
  until<-if(operation=="enroll")row$enrollment_expires[[1L]]else row$resource_expires[[1L]]
  .brohn_hosted_require(now<until,if(operation=="enroll")"This study is no longer accepting new participants because enrollment has expired." else "Access to this study link has expired. Saved browser responses have been retained.","access_expired",403L)
  invisible(TRUE)
}
brohn_hosted_register_run <- function(store,id,deployment_id,now=as.numeric(Sys.time())) {
  row<-brohn_hosted_release_policy(store,deployment_id);if(is.null(row))return(invisible(NULL))
  brohn_hosted_require_release(store,deployment_id,"enroll",now)
  DBI::dbExecute(store$con,"INSERT INTO hosted_run_policy VALUES(?,?,?,?,NULL)",params=list(id,deployment_id,now,now+row$upload_seconds[[1L]]));invisible(NULL)
}
brohn_hosted_require_run <- function(store,id,now=as.numeric(Sys.time())) {
  if(is.null(store$hosted_profile))return(invisible(TRUE))
  row<-DBI::dbGetQuery(store$con,"SELECT r.*,p.workspace_id FROM hosted_run_policy r JOIN hosted_release_policy p ON p.deployment_id=r.deployment_id WHERE r.run_id=?",params=list(id))
  .brohn_hosted_require(nrow(row)==1L&&identical(row$workspace_id[[1L]],store$workspace_id),"This session is not admitted to this hosted workspace.","run_access",403L)
  .brohn_hosted_require(is.na(row$revoked[[1L]]),"This session's access was revoked. Saved browser responses have been retained; contact your researcher.","run_revoked",403L)
  .brohn_hosted_require(now<row$upload_expires[[1L]],"This session's upload window has expired. Saved browser responses have been retained; contact your researcher.","upload_expired",403L)
  invisible(TRUE)
}
brohn_hosted_revoke <- function(store,kind=c("release","run"),id,now=as.numeric(Sys.time())) {
  kind<-match.arg(kind);brohn_hosted_require_session(store)
  .brohn_hosted_require(!is.null(store$hosted_profile),"Only a hosted capability can be revoked here.")
  table<-if(kind=="release")"hosted_release_policy"else"hosted_run_policy";key<-if(kind=="release")"deployment_id"else"run_id"
  changed<-DBI::dbExecute(store$con,paste0("UPDATE ",table," SET revoked=? WHERE ",key,"=? AND revoked IS NULL"),params=list(now,id))
  .brohn_hosted_require(changed==1L,"This capability is unavailable or already revoked.")
  .brohn_store_audit(store,paste0("hosted.",kind,".revoked"),id,list(policy="Revocation preserves original study data and receipt outcomes."));invisible(TRUE)
}

brohn_hosted_write_proxy_config <- function(profile,directory,client_id,client_secret_file,cookie_secret_file) {
  .brohn_hosted_require(!is.null(profile)&&dir.exists(directory)&&.brohn_hosted_text(client_id,120L)&&grepl("^[A-Za-z0-9._-]+$",client_id),"Choose a configuration directory and an OIDC client identifier.")
  for(file in c(client_secret_file,cookie_secret_file)).brohn_hosted_require(file.exists(file)&&!dir.exists(file),"OIDC client and cookie secret files are required.")
  q<-function(x)as.character(jsonlite::toJSON(x,auto_unbox=TRUE))
  p<-profile;fixture<-identical(p$mode,"local_oidc_fixture")
  oauth<-c('provider = "oidc"',paste0('oidc_issuer_url = ',q(p$issuer)),paste0('client_id = ',q(client_id)),
    paste0('client_secret_file = ',q(normalizePath(client_secret_file,winslash="/",mustWork=TRUE))),
    paste0('cookie_secret_file = ',q(normalizePath(cookie_secret_file,winslash="/",mustWork=TRUE))),
    paste0('redirect_url = ',q(paste0(p$researcher_origin,"/oauth2/callback"))),
    paste0('http_address = "127.0.0.1:',p$oauth_port,'"'),paste0('upstreams = ["http://127.0.0.1:',p$researcher_port,'/"]'),
    paste0('allowed_groups = [',paste(vapply(p$allowed_groups,q,character(1)),collapse=","),']'),
    'scope = "openid profile email"','email_domains = ["*"]','code_challenge_method = "S256"',
    'insecure_oidc_skip_nonce = false','insecure_oidc_skip_issuer_verification = false','ssl_insecure_skip_verify = false',
    'reverse_proxy = true','trusted_proxy_ips = ["127.0.0.1/32"]','pass_user_headers = true','pass_basic_auth = false',
    'prefer_email_to_user = false','pass_access_token = false','pass_authorization_header = false','skip_auth_strip_headers = true',
    'proxy_websockets = true','cookie_secure = true','cookie_httponly = true','cookie_samesite = "lax"',
    'cookie_name = "__Host-brohn-research"',paste0('cookie_expire = "',p$session_seconds,'s"'),'cookie_refresh = "0"',
    'session_cookie_minimal = true','request_logging = false','auth_logging = false','standard_logging = true','show_debug_on_error = false',
    'skip_provider_button = true','upstream_timeout = "60s"')
  oauth_path<-file.path(directory,"oauth2-proxy.cfg");.brohn_hosted_require(!file.exists(oauth_path),"Do not overwrite an existing hosted configuration.")
  writeLines(oauth,oauth_path,useBytes=TRUE)
  block<-function(origin,port,participant=FALSE)c(paste0(origin," {"),if(fixture)c("  bind 127.0.0.1","  tls internal"),
    if(participant)c("  @internal path /api/health /oauth2 /oauth2/*","  respond @internal 404","  request_body {","    max_size 5MB","  }"),
    paste0("  reverse_proxy 127.0.0.1:",port," {"),"    header_up -X-Forwarded-User","    header_up -X-Forwarded-Groups",
    "    header_up -X-Forwarded-Email","    header_up -X-Forwarded-Preferred-Username","    header_up -X-Forwarded-Access-Token",
    "    header_up X-Brohn-Edge {$BROHN_EDGE_SECRET}",if(!participant)"    header_up -Authorization","  }","}")
  caddy<-c("{","  admin off",if(fixture)c("  auto_https disable_redirects","  skip_install_trust"),"}",
    block(p$researcher_origin,p$oauth_port),block(p$participant_origin,p$participant_port,TRUE))
  caddy_path<-file.path(directory,"Caddyfile");.brohn_hosted_require(!file.exists(caddy_path),"Do not overwrite an existing hosted edge configuration.")
  writeLines(caddy,caddy_path,useBytes=TRUE)
  list(caddy=caddy_path,oauth=oauth_path)
}
