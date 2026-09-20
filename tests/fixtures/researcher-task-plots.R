args<-commandArgs(trailingOnly=TRUE);mode<-args[[1L]]
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
folder<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE);stopifnot(startsWith(basename(folder),"brohn-task-plots-"))
config_path<-file.path(folder,"fixture.json")
if(mode=="serve"){
  cfg<-brohn_read_json_file(config_path);Sys.setenv(BROHN_WORKSPACE=cfg$workspace,BROHN_APP_MODE="platform")
  stop_owned<-function()if(file.exists(file.path(folder,"stop.request")))shiny::stopApp()else later::later(stop_owned,.2)
  later::later(stop_owned,.2);shiny::runApp(".",host="127.0.0.1",port=cfg$port,launch.browser=FALSE)
}else if(mode=="setup")local({
  stopifnot(!file.exists(config_path));store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE);brohn_initialise_library(store)
  source("tests/fixtures/original-task-plots-store.R");f<-brohn_original_task_plot_fixture(store)
  refs<-c(f$imported,f[c("partial","incomplete","unknown","cohort","native")])
  brohn_write_json_file(list(workspace=store$root,port=httpuv::randomPort(min=21000L,max=49000L),
    reports=lapply(refs,function(r)list(id=r$id,study_id=r$body$study_id,title=r$body$title,study_title=r$body$provenance$design$title,
      expected_rows=if(length(r$body$analysis$task_attempts))length(r$body$analysis$task_attempts[[1L]]$trial_audit)else NULL))),config_path)
})else stop("Unknown task plot fixture mode")
