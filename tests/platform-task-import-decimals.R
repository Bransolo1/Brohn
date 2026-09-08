source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
source("tests/fixtures/original-task-journal.R",encoding="UTF-8")
local({
  n<-0L;check<-function(ok,label){if(!isTRUE(ok))stop(label,call.=FALSE);n<<-n+1L}
  parse<-function(x).brohn_task_import_decimal(x,"RT",1L)
  reject<-function(x)inherits(try(parse(x),silent=TRUE),"try-error")
  for(x in c(.000001,1e-20,.Machine$double.xmin,.Machine$double.xmin*.Machine$double.eps,500,5000))
    check(identical(parse(brohn_json(x)),x),"Native exact finite numeric CSV notation round trips")
  for(x in c("1e-400","1e309","1e13","NA","NaN","null","+1","-1","1e","1e+","1,000"))
    check(reject(x),paste("Malformed, underflowed or unsupported numeric token rejected:",x))
  check(parse("0e-400")==0 && is.null(parse("")),"Explicit zero and genuinely absent response stay distinct")
  d<-brohn_new_design("Original tiny RT interchange fixture","blank")
  d$blocks<-list(brohn_task_new("rt-deary-liewald-simple/1.0",id="original-tiny-rt"));p<-brohn_compile(d,1)
  events<-original_task_journal(p,function(t)list(outcome="correct",rt=.000001))
  run<-list(id="original-tiny-run",deployment_id="original-tiny-release",completion_status="completed",transfer_status="saved",protocol=p,
    origin="sample",participant_alias="001",participant_alias_supplied=TRUE)
  evidence<-brohn_task_evidence_from_run(run,events,d$blocks[[1]]$id)
  check(all(vapply(evidence$rows,function(row)identical(parse(row$first_response_ms),.000001),logical(1))),
    "Actual complete original receiver journal exports tiny RTs without import parser loss")
  check(identical(evidence$rows[[1]]$first_response_ms,brohn_json(.000001)),"Machine export keeps original numeric identity without fixed-decimal rounding")
  cat(sprintf("PASS: %d task-import decimal interchange checks\n",n))
})
