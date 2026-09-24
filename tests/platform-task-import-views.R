source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
local({
  checks<-0L;check<-function(ok,label){if(!isTRUE(ok))stop(label,call.=FALSE);checks<<-checks+1L}
  rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
  fixture<-brohn_read_json_file("tests/fixtures/task-import/manifest.json")$fixtures$iat
  registry_path<-normalizePath(file.path("tests/fixtures/task-import",fixture$registry),winslash="/")
  registry<-brohn_read_json_file(registry_path);m<-fixture$metadata
  store<-brohn_open_store(tempfile("brohn-task-mapping-ui-"));on.exit(brohn_close_store(store),add=TRUE);brohn_initialise_library(store)
  study<-brohn_create_study(store,"Original imported task UI","blank");d<-study$body;d$blocks<-list(registry$task)
  study<-brohn_save_study(store,d,study$revision)
  dataset<-brohn_ingest_dataset(store,file.path("tests/fixtures/task-import",fixture$csv),"Original IAT CSV",modality="implicit",origin="sample")
  server<-function(input,output,session){
    state<-shiny::reactiveValues(page="dataset",dataset_id=dataset$id,error=NULL,status="")
    attempt<-function(fn){state$error<-NULL;tryCatch(fn(),error=function(e){state$error<-conditionMessage(e);NULL})}
    message<-function(text)state$status<-text
    api<-brohn_install_task_import_ui(input,output,session,store,state,attempt,message)
  }
  shiny::testServer(server,{
    session$setInputs(dataset_form_identity=paste(dataset$id,dataset$revision,sep=":"),map_study=study$id,map_study_revision=as.character(study$revision),map_task_task_id=registry$task$id)
    check(rejects(api$selection()),"Unbound task panel cannot attach or save a mapping")
    identity<-api$selection(FALSE)$identity;session$setInputs(task_registry_identity=identity)
    selected<-api$selection()
    check(identical(selected$study$revision,study$revision)&&identical(selected$task$id,registry$task$id),"Mapping pins the exact saved task and study version")
    responses_ui<-output$task_mapping_responses$html
    check(grepl("What do the response-time columns measure?",responses_ui,fixed=TRUE)&&grepl("Unknown; retain evidence without a score",responses_ui,fixed=TRUE),"Selected task renders source timing as a visible explicit decision")
    check(grepl("Trial was presented",responses_ui,fixed=TRUE)&&grepl("First-response milliseconds",responses_ui,fixed=TRUE)&&grepl("Final-correct milliseconds",responses_ui,fixed=TRUE),"Existing IAT response form keeps presentation and corrections separate")
    inputs<-setNames(lapply(names(m),function(name)m[[name]]),paste0("map_task_",names(m)))
    inputs$map_task_protocol_registry<-NULL;inputs$map_task_evidence_level<-NULL;inputs$map_task_source_software<-""
    do.call(session$setInputs,inputs)
    check(rejects(api$mapping()),"A familiar column layout alone cannot bypass original protocol registry attachment")
    file<-data.frame(name=fixture$registry,size=file.info(registry_path)$size,type="application/json",datapath=registry_path,stringsAsFactors=FALSE)
    session$setInputs(task_registry_upload=file,attach_task_registry=1L)
    check(is.null(state$error)&&grepl("checked and retained",state$status,fixed=TRUE),"Explicit use-file action validates and retains original raw registry bytes")
    mapped<-api$mapping();ref<-mapped$metadata$protocol_registry
    check(identical(ref$hash,fixture$registry_sha256)&&identical(ref$canonical_hash,brohn_hash(registry)),"Bound mapping retains distinct raw-byte and canonical registry identities")
    check(is.null(mapped$metadata$source_software)&&"source_software"%in%names(mapped$metadata),"Unknown software is explicit null without losing its required field")
    check(identical(mapped$metadata$evidence_level,"declared_trial_summary"),"Imported form cannot claim a replayed journal")
    check(brohn_get_entity(store,"dataset",dataset$id)$revision==dataset$revision,"Registry attachment alone does not silently accept or revise trial mapping")
    bad<-file;bad$datapath<-tempfile(fileext=".json");writeLines("{}",bad$datapath);on.exit(unlink(bad$datapath),add=TRUE)
    session$setInputs(task_registry_upload=bad,attach_task_registry=2L)
    check(!is.null(state$error)&&identical(api$mapping()$metadata$protocol_registry,ref),"Invalid replacement retains the last explicitly accepted registry")
    session$setInputs(task_registry_identity="previous-task-panel")
    check(rejects(api$mapping()),"Stale task context cannot confirm the current mapping")
    session$setInputs(task_registry_identity=identity)
    state$page<-"studies";check(rejects(api$mapping()),"Hidden dataset form cannot save after navigation")
    state$page<-"dataset"
    changed<-brohn_get_entity(store,"dataset",dataset$id);body<-changed$body;body$title<-"Concurrent original source label"
    brohn_put_entity(store,"dataset",changed$id,body,changed$revision,changed$project_id)
    check(rejects(api$mapping()),"Concurrent dataset revision invalidates its old attachment context")
  })
  ui<-as.character(brohn_task_import_dataset_ui(store,brohn_get_entity(store,"dataset",dataset$id)))
  check(grepl("task_mapping_responses",ui,fixed=TRUE),"Dataset binds response fields to its selected original task")
  cat(sprintf("PASS: %d task-import Shiny selection and mapping checks\n",checks))
})
