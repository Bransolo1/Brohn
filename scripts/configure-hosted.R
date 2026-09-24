# Operator-only configuration validation and generation. Starts no listeners.
args<-commandArgs(trailingOnly=TRUE)
if(length(args)!=5L)stop("Supply PROFILE_JSON OUTPUT_DIRECTORY CLIENT_ID CLIENT_SECRET_FILE COOKIE_SECRET_FILE.")
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
profile<-brohn_hosted_profile(args[[1L]])
if(is.null(profile))stop("Choose a complete hosted profile.")
store<-brohn_open_store(profile$workspace_root)
tryCatch({
  bound<-brohn_hosted_bind_store(store,profile,participant=TRUE)
  output<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
  generated<-brohn_hosted_write_proxy_config(profile,output,args[[3L]],args[[4L]],args[[5L]])
  brohn_write_json_file(list(schema="brohn-hosted-configuration-check/1.0",status="configuration_generated",
    profile_id=profile$id,profile_identity=profile$identity,workspace_id=store$workspace_id,
    researcher_origin=profile$researcher_origin,participant_origin=profile$participant_origin,
    files=lapply(generated,function(path)list(path=path,sha256=digest::digest(file=path,algo="sha256"))),
    limitation="Configuration validation only. Actual proxy/OIDC/application journey and deployment-specific access, TLS, storage and operations remain required."),file.path(output,"hosted-configuration-check.json"))
  cat("Hosted configuration generated. Run both vendor configuration checks before starting the configured edge.\n")
},finally=brohn_close_store(store))
