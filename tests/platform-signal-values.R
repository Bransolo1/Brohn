# Standalone adapters and real native publication; existing hooks need not be wired.
source("R/platform-load.R",encoding="UTF-8");brohn_load()
source("R/platform-signal-values.R",encoding="UTF-8");source("R/platform-signal-value-views.R",encoding="UTF-8")
local({
  checks<-0L;check<-function(name,value){if(!isTRUE(value))stop(paste("Exact values QA:",name),call.=FALSE);checks<<-checks+1L;cat("PASS",name,"\n")}
  rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
  root<-tempfile("brohn-values-qa-",tmpdir=normalizePath("../../work/test-runs",winslash="/"));dir.create(root);root<-normalizePath(root,winslash="/")
  store<-brohn_open_store(file.path(root,"workspace"));brohn_initialise_library(store)
  on.exit(brohn_close_store(store),add=TRUE)
  fixture_code<-paste(c("import importlib.util,json,sys", "from pathlib import Path", "s=importlib.util.spec_from_file_location('values_test','tests/workers/signal_values.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)",
    "v=m.Values();v.folder=Path(sys.argv[1]);rows=[[float(i),float(i),True,i,'',False] for i in range(137)]", "rows[1][1]=-0.0;rows[2][1]=None;rows[3][2]=False;rows[4][2]=None;rows[5][0]=None;rows[6][4]='\\noriginal \\u96ea'", "request=v.request(rows)", "(v.folder/'fixture.json').write_text(json.dumps(request),encoding='utf-8')"),collapse="\n")
  processx::run(brohn_python_profile("eda"),c("-B","-c",fixture_code,root),windows_hide_window=TRUE)
  fixture<-brohn_read_json_file(file.path(root,"fixture.json"));a<-fixture$artifact
  object<-brohn_store_object(store,path=a$path,media_type="application/x-ndjson")
  body<-list(id="report-values-fixture",title="Original typed value fixture",origin="sample",status="Available",
    analysis=list(artifacts=list(c(list(kind=a$kind),object,a[c("schema","tables","rows","provenance_sha256","complete")])),artifact_verification=fixture$verification_receipt))
  envelope<-file.path(root,"report.json");brohn_write_json_file(list(schema="brohn-analysis-output/1.0",report=body),envelope)
  body$result_object<-brohn_store_object(store,path=envelope,media_type="application/json")
  report<-brohn_put_entity(store,"report",body$id,body,expected_revision=0L,project_id="default");original<-brohn_hash(report$body)
  identities<-function(){paths<-c("R/platform-publication.R","scripts/workers/publication.py","src/publication_guard.c","R/platform-signal-values.R");setNames(lapply(paths,function(p)digest::digest(file=p,algo="sha256")),paths)}
  run_direct<-function(job){
    force(job)
    claim<-brohn_claim_job(store,"exact-values-qa",lease_seconds=180);stopifnot(identical(claim$id,job$id))
    scratch<-file.path(store$root,"scratch",paste0("job-",job$id));dir.create(scratch,recursive=TRUE)
    input<-if(job$operation=="signal_catalog")brohn_signal_input(store,claim)else brohn_signal_values_input(store,claim)
    guards<-if(job$operation=="signal_catalog")list()else brohn_hold_signal_value_sources(store,input)
    on.exit(for(g in guards).brohn_qexplorer_release(g),add=TRUE)
    output<-list(report=if(job$operation=="signal_catalog")brohn_analyse_signal(input,scratch)else brohn_analyse_signal_values(input,scratch),code_identity=identities())
    path<-file.path(scratch,"output.json");brohn_write_json_file(output,path)
    if(job$operation=="signal_catalog")brohn_publish_signal_view(store,output,scratch,claim,input,path)else brohn_publish_signal_values(store,output,scratch,claim,input,path)
    final<-brohn_get_job(store,job$id)
    brohn_get_entity(store,if(job$operation=="signal_catalog")"signal_view"else"signal_values",if(job$operation=="signal_catalog")final$result$signal_view_id else final$result$signal_values_id)
  }
  catalog<-run_direct(brohn_queue_signal_view(store,report$id,a$kind));t<-catalog$body$view$tables[[1L]]
  selection<-list(table_id=t$table_id,recording_id=t$identity$recording_id,channel=t$identity$channel,value_column="measure",range=NULL,row_policy="all_source_rows")
  job<-brohn_queue_signal_values(store,catalog$id,selection,limit=25)
  check("same exact source and selection deduplicate",identical(job$id,brohn_queue_signal_values(store,catalog$id,selection,limit=25)$id))
  page<-run_direct(job);v<-page$body$result
  check("real worker page preserves all source support",length(v$rows)==25&&v$full_source$rows==137&&v$full_source$excluded_retention_rows==1&&v$full_source$unknown_retention_rows==1)
  check("R adapter preserves Python exact signed zero and typed null",v$rows[[2]]$value_text=="-0.0"&&isTRUE(v$rows[[3]]$value_is_null)&&grepl('"detected":false',v$rows[[1]]$exact_record_json,fixed=TRUE))
  check("published page reopens with verified original envelopes",identical(brohn_signal_values_record(store,page$id,verify=TRUE)$id,page$id))
  export<-run_direct(brohn_queue_signal_values(store,catalog$id,selection,"export"));ref<-export$body$csv_object
  csv_path<-brohn_object_path(store,ref$hash);csv<-read.csv(csv_path,colClasses="character",check.names=FALSE,na.strings=NULL,fileEncoding="UTF-8")
  check("full CSV publishes all137rows alongside source manifest",nrow(csv)==137&&export$body$result$csv$rows==137&&identical(digest::digest(file=csv_path,algo="sha256"),export$body$result$csv$sha256))
  check("CSV numbers are not reserialized by R",csv$value[[2]]=="-0.0"&&csv$channel[[1]]=="'-1+2"&&csv$source_time_origin[[1]]=="999999999999999999123")
  check("derived source has no private paths",!grepl('"path"',brohn_json(export$body),fixed=TRUE)&&!grepl(root,brohn_json(export$body),fixed=TRUE))
  wrong<-selection;wrong$recording_id<-"other";check("cross-recording selection is rejected before queue",rejects(brohn_queue_signal_values(store,catalog$id,wrong)))
  check("stale catalog hash rejects queue",rejects(brohn_queue_signal_values(store,catalog$id,selection,catalog_hash=paste(rep("0",64),collapse=""))))
  range<-selection;range$range<-list(2,4);ranged<-run_direct(brohn_queue_signal_values(store,catalog$id,range,limit=25))
  check("inclusive range retains missing and excluded rows",ranged$body$result$selected_source$rows==3&&ranged$body$result$unplaceable_coordinate_rows==1&&ranged$body$result$rows[[1]]$value_is_null)
  changed<-brohn_get_entity(store,"project","default");archived<-changed$body;archived$archived<-TRUE
  brohn_put_entity(store,"project","default",archived,changed$revision)
  check("archived project cannot reopen existing values or queue",rejects(brohn_signal_values_record(store,page$id))&&rejects(brohn_queue_signal_values(store,catalog$id,selection)))
  brohn_put_entity(store,"project","default",changed$body,changed$revision+1L)
  # Independent saved-catalog move denies historical source authority too.
  DBI::dbExecute(store$con,"UPDATE entities SET project_id='other' WHERE kind='signal_view' AND id=?",params=list(catalog$id))
  check("moved current catalog rejects retained source revision",rejects(brohn_signal_values_record(store,page$id)))
  DBI::dbExecute(store$con,"UPDATE entities SET project_id='default' WHERE kind='signal_view' AND id=?",params=list(catalog$id))
  # Cancel after a real worker output but before publication: no saved result.
  cancelled<-brohn_queue_signal_values(store,catalog$id,selection,offset=100,limit=25)
  claim<-brohn_claim_job(store,"exact-values-fence",180);data<-brohn_signal_values_input(store,claim)
  scratch<-file.path(store$root,"scratch","cancelled");dir.create(scratch,recursive=TRUE);out<-list(report=brohn_analyse_signal_values(data,scratch),code_identity=identities());path<-file.path(scratch,"output.json");brohn_write_json_file(out,path)
  before<-length(brohn_list_entities(store,"signal_values"));brohn_cancel_job(store,claim$id)
  check("cancelled publication cannot install rows",rejects(brohn_publish_signal_values(store,out,scratch,claim,data,path))&&length(brohn_list_entities(store,"signal_values"))==before)
  retried<-run_direct(brohn_queue_signal_values(store,catalog$id,selection,offset=100,limit=25,retry=TRUE))
  check("explicit retry preserves source and original page position",retried$body$result$page$offset==100&&retried$body$result$rows[[1]]$table_row_index==100)
  server<-function(input,output,session){
    state<-shiny::reactiveValues(page="report",report_id=report$id,error=NULL,status=NULL)
    attempt<-function(fn)tryCatch(fn(),error=function(e){state$error<-conditionMessage(e);NULL})
    route<-new.env(parent=emptyenv())
    ui<-brohn_install_signal_values(input,output,session,store,state,attempt,function(x)state$status<-x,function(fn)fn(),
      shiny::reactive(report),shiny::reactive(catalog),shiny::reactive(t),function(name,data,filter){route$value<-list(data=data,filter=filter);"session/mock/data"})
  }
  shiny::testServer(server,{
    session$setInputs(signal_table=t$table_id);session$flushReact()
    source<-paste(.brohn_sv_identity(report),.brohn_sv_identity(catalog),brohn_hash(t),sep="|")
    fields<-list(measure="measure",full_range=TRUE,start="",end="",limit="25",form=paste(report$id,catalog$id,sep=":"),measure_form=paste(catalog$id,t$table_id,sep=":"))
    action<-function(value){session$setInputs(signal_values_action=value);session$flushReact()}
    settle<-function(test){for(i in 1:70){session$elapse(1100);session$flushReact();if(isTRUE(test()))return(TRUE);Sys.sleep(.05)};FALSE}
    action(list(action="open",source=source,fields=fields))
    check("Shiny reopens already completed exact page through background verification",settle(function()!is.null(ui$ready())))
    html<-output$signal_values_table$html
    check("page UI declares full137rows and typed missing state",grepl("137 selected source rows",html,fixed=TRUE)&&grepl("Unavailable",html,fixed=TRUE)&&grepl("Unknown",html,fixed=TRUE))
    check("table reflows using labelled scroll and exact unbroken numeric cells",grepl('role="region"',html,fixed=TRUE)&&grepl('tabindex="0"',html,fixed=TRUE)&&grepl("brohn-exact-number",html,fixed=TRUE))
    pin<-list(source=source,result=ui$ready()$id,result_hash=brohn_hash(ui$ready()$body))
    action(c(list(action="detail",row=6),pin));check("complete original typed row displays without executing markup",grepl("original",output$signal_values_detail$html,fixed=TRUE)&&grepl("<span>",output$signal_values_detail$html,fixed=TRUE))
    action(c(list(action="export"),pin));settled<-settle(function()!is.null(ui$exported())&&!is.null(route$value))
    if(!settled)cat("EXPORT DIAGNOSTIC ready",!is.null(ui$exported()),"route",!is.null(route$value),"error",state$error,"progress",as.character(output$signal_values_progress$html),"\n")
    check("Shiny export reopens full immutable CSV",settled)
    response<-route$value$filter(route$value$data,list(REQUEST_METHOD="GET",QUERY_STRING=paste0("values_key=",route$value$data$token)))
    check("download streams immutable bytes without R CSV rewrite",response$status==200&&identical(response$content$file,csv_path)&&identical(response$content$owned,FALSE))
    bad<-route$value$filter(route$value$data,list(REQUEST_METHOD="GET",QUERY_STRING="values_key=stale"));check("stale download capability fails",bad$status==404)
    action(c(list(action="page",offset=25),pin));pending<-brohn_get_job(store,brohn_queue_signal_values(store,catalog$id,selection,offset=25,limit=25)$id);run_direct(pending)
    check("page navigation uses exact next source rows",settle(function()!is.null(ui$ready())&&ui$ready()$body$result$page$offset==25))
    action(c(list(action="detail",row=0),pin));check("stale page controls do not erase current data",!is.null(ui$ready())&&grepl("page changed",state$error,fixed=TRUE))
    project<-brohn_get_entity(store,"project","default");b<-project$body;b$archived<-TRUE;brohn_put_entity(store,"project","default",b,project$revision)
    session$elapse(1100);session$flushReact()
    check("authority loss clears ready rows detail and download",is.null(ui$ready())&&is.null(ui$detail())&&is.null(ui$exported())&&is.null(ui$active()))
    check("authority loss is visible and actionable",grepl("available project",output$signal_values_progress$html,fixed=TRUE))
    brohn_put_entity(store,"project","default",project$body,project$revision+1L)
  })
  check("source report and artifact remain byte-identical",brohn_hash(brohn_get_entity(store,"report",report$id)$body)==original&&digest::digest(file=brohn_object_path(store,object$hash),algo="sha256")==object$hash)
  check("derived values reopen after all UI guards close",identical(brohn_signal_values_record(store,export$id,verify=TRUE)$id,export$id))
  cat(sprintf("PASS: %d exact-value R/native publication/Shiny checks; evidence %s\n",checks,root))
})
