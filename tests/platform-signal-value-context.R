# Focused final UI context checks against the retained original synthetic fixture.
source("R/platform-load.R",encoding="UTF-8");brohn_load()
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==1L)
store<-brohn_open_store(args[[1]]);on.exit(brohn_close_store(store))
report<-brohn_get_entity(store,"report","report-values-fixture")
catalog<-Filter(function(r)r$body$operation=="signal_catalog"&&r$body$report_id==report$id,brohn_list_entities(store,"signal_view"))[[1L]]
t<-catalog$body$view$tables[[1L]];checks<-0L
check<-function(name,value){stopifnot(isTRUE(value));checks<<-checks+1L;cat("PASS",name,"\n")}
server<-function(input,output,session){
  state<-shiny::reactiveValues(page="report",report_id=report$id,error=NULL)
  current<-shiny::reactiveVal(report)
  ui<-brohn_install_signal_values(input,output,session,store,state,function(fn)tryCatch(fn(),error=function(e){state$error<-conditionMessage(e);NULL}),function(x)NULL,function(fn)fn(),current,shiny::reactive(catalog),shiny::reactive(t))
}
shiny::testServer(server,{
  session$setInputs(signal_table=t$table_id);session$flushReact()
  newer<-report;newer$revision<-report$revision+1L;newer$body$title<-"A later report revision"
  current(newer);session$flushReact()
  key<-paste(.brohn_sv_identity(newer),.brohn_sv_identity(catalog),brohn_hash(t),sep="|")
  fields<-list(measure="measure",full_range=TRUE,start="",end="",limit="25",form=paste(report$id,catalog$id,sep=":"),measure_form=paste(catalog$id,t$table_id,sep=":"))
  count<-length(brohn_list_jobs(store,limit=500L))
  session$setInputs(signal_values_action=list(action="open",source=key,fields=fields));session$flushReact()
  check("current report cannot reuse a different revision's catalog",grepl("current report",state$error,fixed=TRUE)&&is.null(ui$active())&&length(brohn_list_jobs(store,limit=500L))==count)
  current(report);session$flushReact();key<-paste(.brohn_sv_identity(report),.brohn_sv_identity(catalog),brohn_hash(t),sep="|")
  session$setInputs(signal_values_action=list(action="open",source=key,fields=fields));session$flushReact()
  check("matching exact current catalog remains actionable",!is.null(ui$active()))
  session$setInputs(signal_values_action=list(action="close",source=key));session$flushReact()
  check("close immediately clears active page and verification",is.null(ui$active())&&is.null(ui$ready())&&is.null(ui$exported()))
})
check("count strings preserve every integer digit",identical(.brohn_sv_count(19999999),"19,999,999"))
page<-Filter(function(x)identical(x$body$operation,"signal_values_page"),brohn_list_entities(store,"signal_values"))[[1L]]
html<-as.character(brohn_signal_values_page_ui(page,"source"))
check("hash and source labels have scoped safe wrapping",grepl('class="brohn-exact-selection"',html,fixed=TRUE))
check("paging/export controls precede complete source table",regexpr("Prepare complete selected CSV",html,fixed=TRUE)[[1]]<regexpr("<table",html,fixed=TRUE)[[1]])
cat(sprintf("PASS: %d final exact-value context/UI checks\n",checks))
