source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
local({
  n<-0L;check<-function(ok,label){if(!isTRUE(ok))stop(label);n<<-n+1L;cat("PASS",label,"\n")}
  folder<-tempfile("brohn-question-material-ui-");dir.create(folder);store<-brohn_open_store(file.path(folder,"w"));on.exit(brohn_close_store(store),add=TRUE);brohn_initialise_library(store)
  d<-brohn_new_design("Original question image editor","survey");d$questions<-list(brohn_question("Exact original prompt","single_choice","end","q-first"),brohn_question("Dependent prompt","text","end","q-follow"));d$questions[[2]]$show_if<-list(op="equals",question_id="q-first",value=1)
  study<-brohn_put_entity(store,"study",d$id,d);first<-file.path(folder,"first.png");file.copy("examples/stimuli/sample-design-a.png",first);bad<-file.path(folder,"bad.png");writeBin(charToRaw("Original invalid PNG"),bad)
  server<-function(input,output,session){
    current<-new.env();current$study<-study;registry<-new.env();state<-shiny::reactiveValues(page="study",stage="Questions",study_id=study$id,error=NULL)
    update<-function(design){current$study<-brohn_save_study(store,design,current$study$revision)}
    attempt<-function(fn,...){state$error<-NULL;tryCatch(fn(),error=function(e){state$error<-conditionMessage(e);NULL})}
    editor<-brohn_install_materials(input,output,session,store,current,state,attempt,function(){},update,
      register_resource=function(name,data,filter){registry$data<-data;registry$filter<-filter;"session/mock/dataobj/brohn-material?nonce=original"})
  }
  shiny::testServer(server,{
    open<-function(id="q-first",mode="edit"){session$setInputs(material_open=list(study_id=study$id,kind="question",material_id=id,task_id=NULL,mode=mode));session$setInputs(material_dialog_identity=editor$dialog()$token);list(token=editor$dialog()$token)}
    get<-function(){registry$filter(registry$data,list(REQUEST_METHOD="GET",QUERY_STRING=paste0("material_key=",registry$data$token)))}
    session$setInputs(study_form_identity=paste(study$id,"Questions",sep=":"));token<-open()
    check(identical(editor$dialog()$target_hash,brohn_hash(d$questions[[1]])),"Question editor pins the full canonical owner, including answers and logic")
    session$setInputs(material_file=list(datapath=bad,name="bad.png"),material_alt="Original illustration",material_attach=token)
    check(grepl("PNG",output$material_error$html)&&is.null(current$study$body$questions[[1]]$illustration),"Invalid image stays in the local editor without altering the question")
    session$setInputs(material_file=list(datapath=first,name="first.png"),material_alt="",material_attach=token)
    check(grepl("Describe",output$material_error$html),"Question attachment requires an authored description")
    session$setInputs(material_alt="Original illustration <literal>",material_attach=token)
    check(is.null(editor$dialog())&&current$study$body$questions[[1]]$illustration$image_alt=="Original illustration <literal>","Recovered attachment commits the optional illustration explicitly")
    token<-open(mode="preview");check(get()$status==200L&&grepl("Original illustration &lt;literal&gt;",output$material_saved_preview$html,fixed=TRUE),"Saved question preview uses exact streamed bytes and safe authored alt")
    session$setInputs(material_alt="Forged preview edit",material_describe=token)
    check(grepl("Open Edit",output$material_error$html),"Preview cannot write through a forged editor command")
    session$setInputs(material_close=token);check(get()$status==404L,"Closing the question preview revokes its bytes")
    token<-open();session$setInputs(material_alt="Revised exact description",material_describe=token)
    check(current$study$body$questions[[1]]$illustration$image_alt=="Revised exact description","Description-only question edit retains the same target")
    token<-open();session$setInputs(material_text="Different prompt",material_use_text=token)
    check(grepl("without changing",output$material_error$html)&&current$study$body$questions[[1]]$prompt=="Exact original prompt","Passive text-conversion command cannot change question semantics")
    session$setInputs(material_remove_illustration=token)
    check(identical(brohn_json(current$study$body$questions),brohn_json(d$questions)),"Explicit removal preserves every original question, option and dependency")
    token<-open();changed<-current$study$body;changed$questions[[1]]$options[[1]]$label<-"Concurrent option edit";newer<-brohn_save_study(store,changed,current$study$revision)
    session$setInputs(material_file=list(datapath=first,name="first.png"),material_alt="Stale image",material_attach=token)
    check(grepl("changed",output$material_error$html)&&is.null(brohn_study(store,study$id)$body$questions[[1]]$illustration),"Concurrent option edits reject stale illustration attachment")
    state$stage<-"Plan";session$flushReact();check(is.null(editor$dialog()),"Leaving Questions clears its material context")
  })
  check(!length(brohn_runs(store)),"Question material preparation creates no participant allocation")
  cat("PASS",n,"question illustration Shiny checks\n")
})
