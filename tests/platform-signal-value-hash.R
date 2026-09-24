# Hash reuse must preserve canonical identities and still reject changed values.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({
  checks<-0L
  check<-function(ok,label){stopifnot(isTRUE(ok));checks<<-checks+1L;cat("PASS",label,"\n")}
  expected<-digest::digest(charToRaw('{"a":[1],"b":false,"c":null}'),algo="sha256",serialize=FALSE)
  value<-list(c=NULL,b=FALSE,a=list(1))
  check(identical(.brohn_sv_hash(value),expected),"Canonical identity matches independent JSON, including array/false/null")
  check(identical(.brohn_sv_hash(value[c("a","b","c")]),expected),"Equivalent field order preserves canonical identity")
  old<-value;value$a[[1L]]<-2
  check(!identical(.brohn_sv_hash(value),expected)&&identical(.brohn_sv_hash(old),expected),"Nested mutation gets a fresh identity without changing the original")
  check(!identical(.brohn_sv_hash(list(a=0)),.brohn_sv_hash(list(a=NULL))),"Missing and numerical zero remain distinct")
  check(!identical(.brohn_sv_hash(list(a="0")),.brohn_sv_hash(list(a=0))),"Text and numerical values remain distinct")
  invalid<-list(a=NaN)
  check(inherits(try(.brohn_sv_hash(invalid),silent=TRUE),"try-error"),"Invalid source values are still refused")
  check(inherits(try(.brohn_sv_hash(invalid),silent=TRUE),"try-error"),"A rejected value does not become a cached successful hash")
  original<-brohn_hash;calls<-0L
  assign("brohn_hash",function(x){calls<<-calls+1L;original(x)},envir=.GlobalEnv)
  on.exit(assign("brohn_hash",original,envir=.GlobalEnv))
  x<-list(unique_fixture="canonical-cache-test",rows=lapply(seq_len(500),function(i)list(row=i,value=i/7)))
  first<-.brohn_sv_hash(x);second<-.brohn_sv_hash(x)
  check(identical(first,second)&&calls==1L,"Unchanged complete values avoid repeating canonical traversal")
  for(i in seq_len(129)).brohn_sv_hash(list(eviction_fixture=i))
  before<-calls
  check(identical(.brohn_sv_hash(x),first)&&calls==before+1L,"Bounded cache eviction recomputes the exact original hash")
  cat("PASS",checks,"canonical identity and bounded reuse checks\n")
})
