# Comparator-only engineering controls. No store, worker or source admission.
# Rscript byte-comparator.R <exact-helper-file> <fresh-output>
args<-commandArgs(TRUE);stopifnot(length(args)==2L)
helper<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE)
out<-args[[2L]];stopifnot(!file.exists(out));dir.create(out,recursive=TRUE)
out<-normalizePath(out,winslash="/",mustWork=TRUE)
scope<-new.env(parent=baseenv());sys.source(helper,envir=scope,keep.source=FALSE)
compare<-get(".brohn_rptx_rows_equal",envir=scope)
checks<-list();failure<-NULL
check<-function(label,value){ok<-isTRUE(value);checks[[length(checks)+1L]]<<-list(label=label,passed=ok)
  cat(if(ok)"PASS"else"FAIL",label,"\n");if(!ok)stop(label,call.=FALSE)}
rows<-function(value)data.frame(body_json=value,stringsAsFactors=FALSE)
bytes<-function(value)lapply(value,function(x)if(is.na(x))NA else charToRaw(x))
tryCatch({
  # Explicit bytes make these fixtures independent of the process's C locale.
  utf8<-rawToChar(as.raw(c(123,34,118,34,58,34,99,97,102,195,169,34,125)))
  latin1<-rawToChar(as.raw(c(123,34,118,34,58,34,99,97,102,233,34,125)))
  Encoding(utf8)<-"UTF-8";Encoding(latin1)<-"latin1"
  check("Fixtures decode to the same visible text but retain distinct native bytes",
    identical(enc2utf8(utf8),enc2utf8(latin1))&&!identical(charToRaw(utf8),charToRaw(latin1)))
  a<-rows(c(utf8,NA_character_,""));b<-rows(c(utf8,NA_character_,""))
  before_a<-bytes(a$body_json);before_b<-bytes(b$body_json)
  check("Identical UTF-8 bytes with matching NA and empty values compare equal",compare(a,b))
  c<-rows(c(latin1,NA_character_,""))
  before_c<-bytes(c$body_json)
  check("Equivalent visible text with different native bytes is refused",!compare(a,c))
  changed<-rows(c(utf8,"",NA_character_))
  check("NA and empty strings are distinct even when row count and columns match",!compare(a,changed))
  check("Zero-length SQL string values compare equally without coercion",compare(rows(""),rows("")))
  check("Matching missing SQL string values compare equally",compare(rows(NA_character_),rows(NA_character_)))
  compact<-rows('{"value":1}');spaced<-rows('{ "value" : 1 }')
  compact_before<-bytes(compact$body_json);spaced_before<-bytes(spaced$body_json)
  check("Semantically equivalent JSON with different saved bytes is refused",!compare(compact,spaced))
  check("Comparisons preserve input raw bodies, encodings, NA and empty values",
    identical(before_a,bytes(a$body_json))&&identical(before_b,bytes(b$body_json))&&
    identical(before_c,bytes(c$body_json))&&identical(Encoding(c$body_json[[1L]]),"latin1")&&
    identical(Encoding(a$body_json[[1L]]),"UTF-8")&&
    identical(compact_before,bytes(compact$body_json))&&identical(spaced_before,bytes(spaced$body_json)))
},error=function(e){failure<<-conditionMessage(e)})
result<-list(schema="brohn-transaction-byte-comparator-controls/1.0",status=if(is.null(failure))"passed"else"failed",
  scope="Synthetic character/data-frame controls only; no store, source proof or native qualification",
  helper=helper,checks=checks,error=failure)
writeLines(jsonlite::toJSON(result,auto_unbox=TRUE,null="null",pretty=TRUE),file.path(out,"RESULTS.json"),useBytes=TRUE)
if(!is.null(failure))stop(failure,call.=FALSE)
