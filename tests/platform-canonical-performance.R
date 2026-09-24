# Exact frozen-original byte/error equivalence, then bounded real request parsing.
source("R/platform-load.R",encoding="UTF-8");brohn_load()
source("tests/fixtures/original-store-json.R",encoding="UTF-8")
brohn_test_canonical_performance<-function(folder,envelope_path,implementation=.brohn_store_json) {
  stopifnot(!dir.exists(folder),file.exists(envelope_path));dir.create(folder,recursive=TRUE)
  checks<-character();check<-function(label,ok){if(!isTRUE(ok))stop(label,call.=FALSE);checks<<-c(checks,label);cat("PASS",label,"\n")}
  on.exit(if(!file.exists(file.path(folder,"results.json")))brohn_write_json_file(list(passed=FALSE,completed_checks=as.list(checks)),file.path(folder,"failure-progress.json")),add=TRUE)
  snapshot<-function(x)serialize(x,NULL,version=3)
  hash<-function(x)digest::digest(charToRaw(enc2utf8(x)),algo="sha256",serialize=FALSE)
  error<-function(fun,x,maximum=16*1024^2)tryCatch(list(value=fun(x,maximum)),error=function(e)list(code=e$code,class=class(e)[[1L]]))
  equal<-function(label,x,maximum=16*1024^2) {
    before<-snapshot(x);expected<-.brohn_reference_store_json(x,maximum);actual<-implementation(x,maximum)
    check(label,identical(charToRaw(actual),charToRaw(expected))&&identical(hash(actual),hash(expected))&&identical(snapshot(x),before))
  }
  refused<-function(label,x,maximum=16*1024^2) {
    before<-snapshot(x);a<-error(.brohn_reference_store_json,x,maximum);b<-error(implementation,x,maximum)
    check(label,is.null(a$value)&&identical(a,b)&&identical(snapshot(x),before))
  }
  equal("Hand-authored null/boolean/empty object/empty array bytes",list(z=NULL,b=FALSE,a=TRUE,object=structure(list(),names=character()),array=list()))
  check("Independent literal wire contract stays exact",identical(implementation(list(z=NULL,b=FALSE,a=TRUE,object=structure(list(),names=character()),array=list())),
    '{"a":true,"array":[],"b":false,"object":{},"z":null}'))
  for(value in list(NULL,TRUE,FALSE,0,-0,1L,1,character(),numeric(),logical(),integer(),list(),structure(list(),names=character()),I(1),I(TRUE),I("one"),I(numeric()),list(1),list(list(NULL))))
    equal(paste("Scalar/vector/list representation",length(checks)),value)
  numbers<-c(0,-0,.1,-.1,1/3,-1/3,1+.Machine$double.eps,1-.Machine$double.eps/2,
    .Machine$double.xmin,.Machine$double.xmax,.Machine$double.eps,5e-324,1e-310,1e-20,1e-17,1e-16,1e16,1e17,1e20,2^53-1,2^53,2^53+2,2147483647,-2147483647)
  equal("Exact binary64 boundaries, subnormals, exponents and negative zero",numbers)
  equal("Integer and double vector formatting remains exact",list(integers=c(-2147483647L,-1L,0L,1L,2147483647L),doubles=as.double(c(-2147483647L,-1L,0L,1L,2147483647L))))
  equal("Atomic vectors, forced singleton arrays and mixed named/unnamed nesting",list(a=I(1),b=c(TRUE,FALSE),c=c("", "x"),d=list(list(z=0,a=I("s")),list(1,2),NULL)))
  controls<-intToUtf8(c(1:31,127,34,47,92,0x2028,0x2029,0xe9,0x6f22,0x1f9e0))
  equal("Escaped controls, quotes, slash, separators and non-BMP text",list(text=controls,empty="",nested=list(controls)))
  equal("UTF-8 key order is independent of insertion order",setNames(as.list(1:8),c("\u00e9","e\u0301","\U0001f9e0","Z","a","I","\u0130","\u0131")))
  latin<-rawToChar(as.raw(c(99,97,102,233)));Encoding(latin)<-"latin1"
  equal("Explicit Latin-1 strings and keys preserve UTF-8 canonical bytes",setNames(list(latin),latin))
  equal("Permitted non-class attributes and list-array legacy semantics remain unchanged",list(value=structure(1,note="ignored"),array=structure(list(1,2),dim=c(1L,2L))))
  equal("AsIs strips all classes exactly as the original encoder",structure(1,class=c("AsIs","original-custom-class")))
  nest<-function(x,n){for(i in seq_len(n))x<-list(x);x}
  equal("Scalar exactly at depth64 is accepted",nest(1,64))
  equal("Empty array exactly at depth64 is accepted",nest(list(),64))
  equal("Empty forced atomic array exactly at depth64 is accepted",nest(I(numeric()),64))
  refused("Scalar beyond depth64 is refused",nest(1,65))
  refused("Object key and value beyond depth64 are refused",nest(list(key=1),64))
  refused("Atomic array children beyond depth64 are refused",nest(c(1,2),64))
  refused("Forced singleton array child beyond depth64 is refused",nest(I(1),64))
  for(value in list(NA,NA_character_,NA_real_,NA_integer_,NaN,Inf,-Inf,c(1,NA),c("valid",NA_character_),factor("x"),as.Date("2026-01-01"),
      as.POSIXct("2026-01-01",tz="UTC"),matrix(1:4,2),data.frame(x=1),list_to_env<-new.env(parent=emptyenv()),quote(x),function()NULL,as.raw(1),1+2i,
      setNames(1,"named"),structure(list(1),names=""),structure(list(1),names=NA_character_),structure(list(1,2),names=c("same","same")),I(list(1))))
    refused(paste("Invalid value/class/names remains refused",length(checks)),value)
  invalid<-rawToChar(as.raw(c(0xc3,0x28)));Encoding(invalid)<-"UTF-8"
  refused("Malformed UTF-8 string stays refused",invalid)
  refused("Malformed UTF-8 object key stays refused",setNames(list(1),invalid))
  bound<-list(value=paste(rep("\u00e9",20),collapse=""));size<-nchar(.brohn_reference_store_json(bound),type="bytes")
  equal("Exact byte maximum accepts multibyte encoded body",bound,size)
  refused("One byte below actual UTF-8 size refuses",bound,size-1)
  for(limit in list(-1,0,NA_real_,numeric()))refused("Invalid or insufficient maximum retains refusal",bound,limit)
  prior_seed<-if(exists(".Random.seed",.GlobalEnv))get(".Random.seed",.GlobalEnv)else NULL
  on.exit(if(is.null(prior_seed)){if(exists(".Random.seed",.GlobalEnv))rm(".Random.seed",envir=.GlobalEnv)}else assign(".Random.seed",prior_seed,.GlobalEnv),add=TRUE)
  set.seed(624091L)
  tree<-function(depth=0L) {
    pick<-sample.int(if(depth<4)7L else 4L,1L)
    switch(pick,NULL,sample(c(TRUE,FALSE),sample(0:4,1),replace=TRUE),stats::runif(sample(0:4,1),-1e15,1e15),
      sample(c("", "plain", "quoted\"", "\u00e9", "\U0001f9e0", "\n"),sample(0:4,1),replace=TRUE),
      lapply(seq_len(sample(0:4,1)),function(i)tree(depth+1L)),
      {n<-sample(0:4,1);setNames(lapply(seq_len(n),function(i)tree(depth+1L)),sample(letters,n))},I(sample(1:20,1)))
  }
  for(i in 1:100)equal(paste("Deterministic independent mixed-tree fuzz",i),tree())
  saved_locale<-Sys.getlocale("LC_COLLATE");on.exit(suppressWarnings(Sys.setlocale("LC_COLLATE",saved_locale)),add=TRUE)
  locale_results<-list()
  for(locale in c("C","English_United States.1252","Turkish_Turkey.1254")) {
    got<-suppressWarnings(Sys.setlocale("LC_COLLATE",locale));if(!nzchar(got))next
    x<-setNames(as.list(1:8),c("\u00e9","e\u0301","\U0001f9e0","Z","a","I","\u0130","\u0131"))
    equal(paste("Exact radix key order under locale",got),x);locale_results[[locale]]<-implementation(x)
  }
  check("All supported collation locales produce the same canonical bytes",length(unique(unlist(locale_results)))==1L)
  raw<-readBin(envelope_path,"raw",n=file.info(envelope_path)$size);source_hash<-digest::digest(raw,algo="sha256",serialize=FALSE)
  body<-jsonlite::fromJSON(rawToChar(raw),simplifyVector=FALSE);before<-snapshot(body)
  reference_time<-system.time(reference<-.brohn_reference_store_json(body,4*1024^2))[["elapsed"]]
  actual_time<-system.time(actual<-implementation(body,4*1024^2))[["elapsed"]]
  check("Complete5000-key envelope is byte/hash identical to independent frozen original",identical(charToRaw(actual),charToRaw(reference))&&identical(hash(actual),hash(reference))&&identical(snapshot(body),before))
  parser_time<-NULL
  if(identical(implementation,.brohn_store_json)) {
    parser_time<-system.time(parsed<-.brohn_delivery_request(list(CONTENT_LENGTH=as.character(length(raw)),CONTENT_TYPE="application/json",rook.input=list(read=function(n=-1L)raw))))[["elapsed"]]
    check("Actual participant request parser completes below existing15second fetch timeout",parser_time<15&&identical(snapshot(parsed),snapshot(body)))
  }
  check("Original envelope bytes remain unchanged",identical(source_hash,digest::digest(file=envelope_path,algo="sha256")))
  receipt<-list(passed=TRUE,checks=as.list(checks),candidate_only=is.null(parser_time),R=R.version.string,jsonlite=as.character(packageVersion("jsonlite")),
    wire_bytes=length(raw),canonical_bytes=nchar(actual,type="bytes"),canonical_sha256=hash(actual),reference_encode_s=unname(reference_time),encode_s=unname(actual_time),request_parse_s=parser_time,
    locale_results=locale_results,source_hash=source_hash,source_hashes=setNames(lapply(c("R/platform-store.R","tests/fixtures/original-store-json.R","tests/platform-canonical-performance.R"),function(p)digest::digest(file=p,algo="sha256")),c("R/platform-store.R","tests/fixtures/original-store-json.R","tests/platform-canonical-performance.R")))
  brohn_write_json_file(receipt,file.path(folder,"results.json"));cat("PASS",length(checks),"exact canonical checks; optimized",actual_time,"s versus",reference_time,"s; parser",parser_time,"s\n")
  invisible(receipt)
}
if(sys.nframe()==0L){args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==2L);brohn_test_canonical_performance(args[[1L]],args[[2L]])}
