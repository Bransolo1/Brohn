source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
local({
  n<-0L;check<-function(ok,label){if(!isTRUE(ok))stop(label);n<<-n+1L;cat("PASS",label,"\n")}
  folder<-tempfile("brohn-md-material-ui-");dir.create(folder);store<-brohn_open_store(file.path(folder,"w"));on.exit(brohn_close_store(store),add=TRUE);brohn_initialise_library(store)
  d<-brohn_new_design("Original best-worst illustration editor","survey");d$maxdiff<-list(brohn_maxdiff_new(id="md-original"));study<-brohn_put_entity(store,"study",d$id,d)
  first<-file.path(folder,"first.png");file.copy("examples/stimuli/sample-design-a.png",first);bad<-file.path(folder,"bad.png");writeBin(charToRaw(paste(rep("Invalid PNG",8),collapse=" ")),bad)
  server<-function(input,output,session){
    current<-new.env();current$study<-study;registry<-new.env();state<-shiny::reactiveValues(page="study",stage="Tasks",study_id=study$id,error=NULL)
    update<-function(design){current$study<-brohn_save_study(store,design,current$study$revision)};attempt<-function(fn,...){state$error<-NULL;tryCatch(fn(),error=function(e){state$error<-conditionMessage(e);NULL})}
    md<-brohn_install_maxdiff_ui(input,output,session,current,state,attempt,function(){},update)
    editor<-brohn_install_materials(input,output,session,store,current,state,attempt,function(){},update,
      register_resource=function(name,data,filter){registry$data<-data;registry$filter<-filter;"session/mock/dataobj/brohn-material?nonce=original"},can_open=function(kind)kind!="maxdiff_item"||is.null(md$context()))
  }
  shiny::testServer(server,{
    open<-function(mode="edit"){session$setInputs(material_open=list(study_id=study$id,kind="maxdiff_item",material_id="item-1",task_id="md-original",mode=mode));if(is.null(editor$dialog()))return(NULL);session$setInputs(material_dialog_identity=editor$dialog()$token);list(token=editor$dialog()$token)}
    fill<-function(){ctx<-md$context();e<-ctx$exercise;args<-list(maxdiff_form_identity=ctx$token,maxdiff_structure_identity=paste(ctx$token,ctx$version,sep=":"),maxdiff_title=e$title,maxdiff_origin=e$origin,maxdiff_rights=e$materials_rights,maxdiff_seed=e$seed,maxdiff_prompt=e$settings$prompt,maxdiff_best=e$settings$best_label,maxdiff_worst=e$settings$worst_label,maxdiff_required=e$settings$required,maxdiff_set_order=e$settings$set_order,maxdiff_item_order=e$settings$item_order,maxdiff_rationale=e$settings$design_rationale,maxdiff_fit=e$settings$analysis$fit_aggregate);for(i in e$items)args[[brohn_maxdiff_field_id(ctx$token,ctx$version,"label",i$id)]]<-i$label;for(s in e$sets)args[[brohn_maxdiff_field_id(ctx$token,ctx$version,"members",s$id)]]<-unlist(s$item_ids);do.call(session$setInputs,args);ctx}
    session$setInputs(study_form_identity=paste(study$id,"Tasks",sep=":"),maxdiff_edit="md-original");ctx<-fill();open()
    check(is.null(editor$dialog())&&!is.null(md$context())&&grepl("Save or cancel",state$error),"An active exercise draft cannot be displaced by a forged saved-item image command")
    session$setInputs(maxdiff_cancel=list(token=ctx$token));token<-open();check(identical(editor$dialog()$target_hash,brohn_hash(d$maxdiff[[1]])),"Saved item editor pins the complete exercise including sets and framing")
    session$setInputs(material_file=list(datapath=bad,name="bad.png"),material_alt="Original exact item image",material_attach=token)
    check(grepl("PNG",output$material_error$html)&&is.null(current$study$body$maxdiff[[1]]$items[[1]]$illustration),"Invalid item PNG preserves the saved exercise and local recovery fields")
    session$setInputs(material_file=list(datapath=first,name="first.png"),material_alt="",material_attach=token);check(grepl("Describe",output$material_error$html),"Item image requires its authored participant description")
    session$setInputs(material_alt="Original exact item image <literal>",material_attach=token);image<-current$study$body$maxdiff[[1]]$items[[1]]$illustration
    check(is.null(editor$dialog())&&image$image_alt=="Original exact item image <literal>","Recovered explicit attachment saves exact item image and description")
    token<-open("preview");response<-registry$filter(registry$data,list(REQUEST_METHOD="GET",QUERY_STRING=paste0("material_key=",registry$data$token)))
    check(response$status==200L&&grepl("Original exact item image &lt;literal&gt;",output$material_saved_preview$html,fixed=TRUE),"Saved item preview streams exact bytes with safely escaped authored alt")
    session$setInputs(material_close=token);session$setInputs(maxdiff_edit="md-original");ctx<-fill();session$setInputs(maxdiff_review=list(token=ctx$token));label<-brohn_maxdiff_field_id(ctx$token,ctx$version,"label","item-1");do.call(session$setInputs,setNames(list("Original revised item label"),label));session$setInputs(maxdiff_save=list(token=ctx$token))
    check(is.null(md$context())&&identical(brohn_json(current$study$body$maxdiff[[1]]$items[[1]]$illustration),brohn_json(image))&&current$study$body$maxdiff[[1]]$items[[1]]$label=="Original revised item label","Ordinary exercise edit and coverage review preserve attached images while changing labels")
    session$setInputs(maxdiff_edit="md-original");ctx<-fill();session$setInputs(maxdiff_review=list(token=ctx$token));newer<-current$study$body;newer<-brohn_material_describe(newer,"maxdiff_item","item-1","md-original",image_alt="Concurrent revised description");current$study<-brohn_save_study(store,newer,current$study$revision);session$setInputs(maxdiff_save=list(token=ctx$token))
    check(!is.null(state$error)&&current$study$body$maxdiff[[1]]$items[[1]]$illustration$image_alt=="Concurrent revised description","A changed saved illustration invalidates an older exercise draft and its coverage review")
    session$setInputs(maxdiff_cancel=list(token=ctx$token));token<-open();session$setInputs(material_remove_illustration=token)
    check(is.null(current$study$body$maxdiff[[1]]$items[[1]]$illustration)&&current$study$body$maxdiff[[1]]$items[[1]]$label=="Original revised item label"&&identical(current$study$body$maxdiff[[1]]$sets,d$maxdiff[[1]]$sets),"Explicit image removal preserves current item label and every offered set")
    token<-open();changed<-current$study$body;changed$maxdiff[[1]]$settings$best_label<-"Concurrent different framing";brohn_save_study(store,changed,current$study$revision);session$setInputs(material_file=list(datapath=first,name="first.png"),material_alt="Stale image",material_attach=token)
    check(grepl("changed",output$material_error$html),"Concurrent exercise framing rejects stale image attachment")
    state$stage<-"Questions";session$flushReact();check(is.null(editor$dialog()),"Leaving Tasks revokes the saved item material context")
  })
  check(!length(brohn_runs(store)),"Choice image authoring does not allocate participant sessions")
  cat("PASS",n,"MaxDiff illustration Shiny checks\n")
})
