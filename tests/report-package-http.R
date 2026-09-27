args<-commandArgs(TRUE);stopifnot(length(args)==3L)
out<-normalizePath(args[[1]],winslash="/",mustWork=TRUE);port<-as.integer(args[[2]])
report_env<-new.env(parent=globalenv())
sys.source(args[[3]],envir=report_env)
stopifnot(!exists("$<-.brohn_rpk_response_headers",envir=globalenv(),inherits=FALSE))
artifact<-function(name,text,type){path<-file.path(out,name);bytes<-charToRaw(enc2utf8(text));writeBin(bytes,path);list(path=path,bytes=as.numeric(length(bytes)),media_type=type)}
html<-artifact("source.html",paste0("<!doctype html><title>Transport fixture</title><p>",strrep("saved findings ",500),"</p>"),"text/html")
zip<-artifact("source.zip",paste0("PK",strrep("deterministic synthetic transport ",400)),"application/zip")
hundred<-artifact("source-100000.html",strrep("x",100000L),"text/html")
legacy<-function(a=NULL)structure(if(is.null(a))list(status=404L,content_type="text/plain",content="Reopen the saved report to download its current evidence.")else
 list(status=200L,content_type=a$media_type,content=list(file=a$path,owned=FALSE),headers=list("Cache-Control"="no-store","X-Content-Type-Options"="nosniff")),class="httpResponse")
ui<-shiny::fluidPage(shiny::uiOutput("links"))
server<-function(input,output,session){
 links<-lapply(c("legacy-html","legacy-error","new-html","new-zip","new-error","new-html-100000"),function(name){
  url<-session$registerDataObj(name,list(),function(data,req){
   a<-if(grepl("error",name,fixed=TRUE))NULL else if(grepl("100000",name,fixed=TRUE))hundred else if(grepl("zip",name,fixed=TRUE))zip else html
   cat(name,req$REQUEST_METHOD,"\n")
   if(startsWith(name,"legacy"))legacy(a)else report_env$.brohn_rpk_download_response(req,a,if(grepl("zip",name,fixed=TRUE))"zip"else"html")
  });shiny::tags$a(name,id=name,href=url)
 });output$links<-shiny::renderUI(shiny::tagList(links))
}
later::later(function()quit(save="no",status=0),45)
shiny::runApp(list(ui=ui,server=server),port=port,host="127.0.0.1",launch.browser=FALSE)
