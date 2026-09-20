# Actual Shiny observers and exact session-bound media resource filters.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
source("R/platform-materials.R",encoding="UTF-8");source("R/platform-material-views.R",encoding="UTF-8")
local({
  n<-0L;check<-function(ok,label){if(!isTRUE(ok))stop(label);n<<-n+1L;cat("PASS",label,"\n")}
  folder<-tempfile("brohn-material-ui-");dir.create(folder);store<-brohn_open_store(file.path(folder,"w"));brohn_initialise_library(store);on.exit(brohn_close_store(store),add=TRUE)
  study<-brohn_create_study(store,"Original material authoring");d<-study$body;d$blocks<-list(brohn_task_new());study<-brohn_save_study(store,d,study$revision)
  first<-file.path(folder,"first.png");second<-file.path(folder,"second.png");bad<-file.path(folder,"bad.png")
  file.copy("examples/stimuli/sample-design-a.png",first);file.copy("examples/stimuli/sample-design-b.png",second);writeBin(charToRaw("invalid original fixture"),bad)
  server<-function(input,output,session){
    state<-shiny::reactiveValues(page="study",stage="Plan",study_id=study$id,refresh=0L,error=NULL)
    current<-new.env();current$study<-study;registered<-new.env()
    update<-function(d){current$study<-brohn_save_study(store,d,current$study$revision);state$refresh<-state$refresh+1L}
    capture<-function(){};attempt<-function(fn,...){state$error<-NULL;tryCatch(fn(),error=function(e){state$error<-conditionMessage(e);NULL})}
    editor<-brohn_install_materials(input,output,session,store,current,state,attempt,capture,update,
      register_resource=function(name,data,filter){registered$data<-data;registered$filter<-filter;"session/mock/dataobj/brohn-material?nonce=original"})
  }
  shiny::testServer(server,{
    cmd<-list(study_id=study$id,kind="stimulus",material_id=study$body$stimuli[[1]]$id,task_id=NULL,mode="edit")
    open<-function(command=cmd){session$setInputs(material_open=command);session$setInputs(material_dialog_identity=editor$dialog()$token);list(token=editor$dialog()$token)}
    request<-function(key=registered$data$token){registered$filter(registered$data,list(REQUEST_METHOD="GET",QUERY_STRING=paste0("material_key=",key)))}
    session$setInputs(study_form_identity=paste(study$id,"Plan",sep=":"));token<-open()
    session$setInputs(material_attach=token)
    check(grepl("new PNG",output$material_error$html),"Missing transfer is an actionable dialog-local error")
    session$setInputs(material_file=list(datapath=bad,name="bad.png"),material_alt="Original material",material_attach=token)
    check(grepl("PNG",output$material_error$html)&&is.null(current$study$body$stimuli[[1]]$asset),"Invalid upload preserves the draft and open editor")
    session$setInputs(material_file=list(datapath=first,name="first.png"),material_alt="",material_attach=token)
    check(grepl("Describe",output$material_error$html),"Description is required before an image can attach")
    session$setInputs(material_alt="Original source picture",material_attach=token)
    hash<-current$study$body$stimuli[[1]]$asset$hash
    check(is.null(editor$dialog())&&nchar(hash)==64L,"Recovered attachment saves exact media and closes the context")
    token<-open();old_key<-token$token;response<-request()
    check(response$status==200L&&response$content_type=="image/png"&&is.list(response$content)&&isFALSE(response$content$owned)&&digest::digest(file=response$content$file,algo="sha256")==hash,"Preview resource streams the exact verified object rather than hydrating it")
    check(request("foreign")$status==404L,"An arbitrary preview key cannot request a material")
    session$setInputs(material_attach=token)
    check(grepl("new PNG",output$material_error$html),"Reopened editor cannot silently reuse a prior dialog's upload")
    session$setInputs(material_alt="Authored exact description <img>",material_describe=token)
    check(current$study$body$stimuli[[1]]$image_alt=="Authored exact description <img>"&&current$study$body$stimuli[[1]]$asset$hash==hash,"Description-only save preserves exact original bytes")
    check(request()$status==404L,"Closed editor revokes its preview URL")
    token<-open();check(request(old_key)$status==404L,"Old preview token cannot be used after another dialog opens")
    d<-current$study$body;d$description<-"Saved concurrently";newer<-brohn_save_study(store,d,current$study$revision)
    session$setInputs(material_file=list(datapath=second,name="second.png"),material_alt="Replacement",material_attach=token)
    check(grepl("changed",output$material_error$html)&&brohn_study(store,study$id)$body$description=="Saved concurrently"&&request()$status==404L,"Concurrent revision rejects attachment and source access without overwriting newer work")
    current$study<-newer;session$setInputs(material_close=token);token<-open()
    project<-brohn_project(store,current$study$project_id);archived<-project$body;archived$archived<-TRUE
    archived_record<-brohn_put_entity(store,"project",project$id,archived,expected_revision=project$revision)
    session$setInputs(material_alt="Should not save after access loss",material_describe=token)
    check(grepl("available project",output$material_error$html)&&request()$status==404L&&brohn_study(store,study$id)$body$stimuli[[1]]$image_alt=="Authored exact description <img>","Current project access loss rejects both material writes and preview bytes")
    brohn_put_entity(store,"project",project$id,project$body,expected_revision=archived_record$revision)
    state$page<-"home";session$flushReact();check(is.null(editor$dialog())&&request()$status==404L,"Leaving the study clears editor and source authority")
    state$page<-"study";session$flushReact();token<-open()
    session$setInputs(material_text="",material_use_text=token)
    check(current$study$body$stimuli[[1]]$type=="text"&&is.null(current$study$body$stimuli[[1]]$asset),"Passive remove returns to a visibly incomplete text draft")
    state$stage<-"Tasks";session$setInputs(study_form_identity=paste(study$id,"Tasks",sep=":"));task<-current$study$body$blocks[[1]]
    task_cmd<-list(study_id=study$id,kind="exemplar",material_id=task$materials[[1]]$id,task_id=task$id,mode="edit")
    token<-open(task_cmd);session$setInputs(material_file=list(datapath=first,name="first.png"),material_alt="Task illustration",material_attach=token)
    check(current$study$body$blocks[[1]]$materials[[1]]$type=="image","Task exemplar uses the same source-bound attachment flow")
    token<-open(task_cmd);session$setInputs(material_text="",material_use_text=token)
    check(grepl("participant text",output$material_error$html)&&current$study$body$blocks[[1]]$materials[[1]]$type=="image","Empty task text keeps the image and recoverable editor")
    session$setInputs(material_text="Original replacement exemplar",material_use_text=token)
    check(current$study$body$blocks[[1]]$materials[[1]]$type=="text"&&current$study$body$blocks[[1]]$materials[[1]]$category_id==task$materials[[1]]$category_id,"Recovered task removal retains exact category membership")
    session$setInputs(material_open=cmd);check(!is.null(state$error)&&is.null(editor$dialog()),"Delayed Plan command cannot open against the Tasks form")
  })
  check(!DBI::dbExistsTable(store$con,"delivery_runs"),"Material component authoring never creates a participant session")
  cat("PASS",n,"material component checks\n")
})
