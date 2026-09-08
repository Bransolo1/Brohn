# Original authoring workspace; no worker service is launched by this helper.
args<-commandArgs(trailingOnly=TRUE);mode<-args[[1L]]
source('R/platform-load.R');brohn_load(ui=TRUE)
folder<-normalizePath(args[[2L]],winslash='/',mustWork=TRUE)
stopifnot(grepl('^brohn-maxdiff-researcher-',basename(folder)))
config_path<-file.path(folder,'fixture.json');workspace<-file.path(folder,'workspace')
if(mode=='serve') {
  config<-brohn_read_json_file(config_path)
  Sys.setenv(BROHN_WORKSPACE=workspace,BROHN_APP_MODE='platform',BROHN_PARTICIPANT_PORT=config$participant_port)
  stop_path<-file.path(folder,'stop.request');if(file.exists(stop_path))unlink(stop_path)
  check_stop<-function(){if(file.exists(stop_path))shiny::stopApp() else later::later(check_stop,.2)}
  later::later(check_stop,.2)
  options(shiny.maxRequestSize=512*1024^2)
  shiny::runApp('.',host='127.0.0.1',port=config$port,launch.browser=FALSE)
} else local({
  store<-brohn_open_store(workspace);on.exit(brohn_close_store(store),add=TRUE)
  if(mode=='create') {
    stopifnot(!file.exists(config_path));brohn_initialise_library(store)
    port<-httpuv::randomPort(min=19000L,max=49000L);participant_port<-port
    while(participant_port==port)participant_port<-httpuv::randomPort(min=19000L,max=49000L)
    brohn_write_json_file(list(origin='original_synthetic',workspace=workspace,workspace_id=store$workspace_id,port=port,participant_port=participant_port),config_path)
  }
  studies<-brohn_studies(store,archived=NULL)
  selected<-if(length(args)>=3L)brohn_study(store,args[[3L]])else NULL
  result<-list(studies=lapply(studies,function(s)list(id=s$id,revision=s$revision,hash=brohn_hash(s$body),body=s$body)),
    templates=brohn_list_entities(store,'template'),reports=brohn_list_entities(store,'report'),
    deployments=lapply(brohn_deployments(store),function(d)d[setdiff(names(d),'token')]),
    runs=brohn_runs(store),jobs=lapply(brohn_list_jobs(store),function(j)j[c('id','operation','request','status')]),
    selected=selected,compiled=if(is.null(selected))NULL else brohn_compile(selected$body,1L))
  brohn_write_json_file(result,file.path(folder,'snapshot.json'))
  cat('Original MaxDiff authoring workspace snapshot saved.\n')
})
