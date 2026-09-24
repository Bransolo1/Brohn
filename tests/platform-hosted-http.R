# Real installed Shiny dispatcher, synthetic local session transport. The
# separate browser journey exercises the actual TLS/OIDC HTTP boundary.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
local({
  args<-commandArgs(trailingOnly=TRUE);folder<-if(length(args))args[[1L]]else tempfile("brohn-hosted-http-")
  stopifnot(!dir.exists(folder));dir.create(folder,recursive=TRUE)
  checks<-character();check<-function(label,value){stopifnot(isTRUE(value));checks<<-c(checks,label);cat("PASS",label,"\n")}
  rev_file<-file.path(folder,"revocations.json")
  rev<-list(schema="brohn-hosted-revocations/1.0",subjects=list(),not_before=0);brohn_write_json_file(rev,rev_file)
  profile<-list(identity="original-http-profile",issuer="original-http-issuer",revocations_file=rev_file)
  now<-as.numeric(Sys.time());context<-list(schema="brohn-hosted-context/1.0",profile_identity=profile$identity,issuer=profile$issuer,subject="original-researcher",started=now,expires=now+600)
  bound<-list(hosted_profile=profile,hosted_context=context,hosted_participant=FALSE)
  generator<-get("ShinySession",asNamespace("shiny"));original_generator<-generator$public_methods$handleRequest
  ws<-new.env();ws$request<-list();ws$send<-function(x)NULL;ws$close<-function()NULL
  session<-generator$new(ws);on.exit(session$close(),add=TRUE)
  called<-new.env();called$filter<-0L;called$filename<-0L;called$body<-0L
  session$registerDataObj("original-cached",list(value=17),function(data,req){called$filter<-called$filter+1L;structure(list(status=200L,content_type="application/json",content=brohn_json(data),headers=list()),class="httpResponse")})
  session$files$set("original-file",list(contentType="text/plain",data="original cached bytes"))
  session$registerDownload("original-download",function(){called$filename<-called$filename+1L;"original.txt"},"text/plain",function(file)writeLines("original data",file))
  request<-function(route,method="GET")list(PATH_INFO=route,REQUEST_METHOD=method,rook.input=list(read=function(n){called$body<-called$body+1L;raw()}))
  brohn_guard_hosted_http(session,bound)
  check("Guard preserves locked per-instance dispatcher and original generator",bindingIsLocked("handleRequest",session)&&identical(generator$public_methods$handleRequest,original_generator))
  first<-session$handleRequest;brohn_guard_hosted_http(session,bound)
  check("Repeated installer does not wrap dispatcher twice",identical(first,session$handleRequest))
  response<-session$handleRequest(request("/dataobj/original-cached"))
  check("Authorized actual cached data filter retains exact response",identical(response$status,200L)&&identical(response$content,brohn_json(list(value=17)))&&called$filter==1L)
  response<-session$handleRequest(request("/file/original-file"))
  check("Authorized actual cached file retains exact bytes",identical(response$status,200)&&identical(response$content,"original cached bytes"))
  rev$subjects<-list(context$subject);brohn_write_json_file(rev,rev_file)
  for(route in c("/dataobj/original-cached","/file/original-file","/download/original-download","/upload/original-upload","/unknown/original")) {
    response<-session$handleRequest(request(route,if(startsWith(route,"/upload/"))"POST"else"GET"))
    check(paste("Revoked actual session refuses",route),identical(response$status,403L)&&identical(response$headers$`Cache-Control`,"no-store"))
  }
  check("Refusal occurs before cached filter, download filename and upload body",called$filter==1L&&called$filename==0L&&called$body==0L)
  rev$subjects<-list();brohn_write_json_file(rev,rev_file)
  check("Cleared operator revocation permits still-valid existing session",identical(session$handleRequest(request("/dataobj/original-cached"))$status,200L))
  expired<-generator$new(ws);on.exit(expired$close(),add=TRUE);past<-bound;past$hosted_context$expires<-now-1
  brohn_guard_hosted_http(expired,past)
  check("Already expired session refuses HTTP before original missing-resource dispatch",identical(expired$handleRequest(request("/dataobj/absent"))$status,403L))
  untouched<-generator$new(ws);on.exit(untouched$close(),add=TRUE);before<-untouched$handleRequest;brohn_guard_hosted_http(untouched,list())
  check("Unbound local session dispatcher remains unchanged",identical(before,untouched$handleRequest))
  brohn_write_json_file(list(passed=TRUE,checks=as.list(checks),shiny_version=as.character(packageVersion("shiny")),scope="Installed Shiny dispatcher with synthetic transport; actual OIDC browser proof is separate."),file.path(folder,"results.json"))
})
