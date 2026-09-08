# Original CSV cells and separately saved study; no generated scientific scores.
args<-commandArgs(trailingOnly=TRUE);mode<-args[[1L]]
source('R/platform-load.R');brohn_load(ui=TRUE)
folder<-normalizePath(args[[2L]],winslash='/',mustWork=TRUE)
stopifnot(grepl('^brohn-maxdiff-import-ui-',basename(folder)))
workspace<-file.path(folder,'workspace');config_path<-file.path(folder,'fixture.json')
if(mode=='serve') {
  config<-brohn_read_json_file(config_path)
  Sys.setenv(BROHN_WORKSPACE=workspace,BROHN_APP_MODE='platform')
  stop_path<-file.path(folder,'stop.request');if(file.exists(stop_path))unlink(stop_path)
  check_stop<-function(){if(file.exists(stop_path))shiny::stopApp() else later::later(check_stop,.2)}
  later::later(check_stop,.2);shiny::runApp('.',host='127.0.0.1',port=config$port,launch.browser=FALSE)
} else local({
  store<-brohn_open_store(workspace);on.exit(brohn_close_store(store),add=TRUE)
  if(mode=='create') {
    stopifnot(!file.exists(config_path));brohn_initialise_library(store)
    exercise<-brohn_maxdiff_new('Original refill-pack feature importance','original-import-required')
    exercise$items<-list(list(id='refillable',label='Refillable container'),list(id='clear-label',label='Clear ingredient label'),list(id='easy-open',label='Easy opening'))
    exercise$sets<-list(list(id='original-feature-triple',item_ids=as.list(brohn_ids(exercise$items))))
    exercise$settings$prompt<-'Which refill-pack feature matters most and least?'
    exercise$settings$best_label<-'Matters most';exercise$settings$worst_label<-'Matters least'
    exercise$materials_rights<-'Original synthetic consumer feature text, authored for independent Brohn QA.'
    optional<-brohn_maxdiff_clone(exercise);optional$title<-'Original optional refill-pack preference'
    optional$settings$prompt<-'Which refill-pack feature do you like most and least?'
    optional$settings$best_label<-'Like most';optional$settings$worst_label<-'Like least';optional$settings$required<-FALSE
    design<-brohn_new_design('Original CSV refill-pack comparison','survey',id='original-maxdiff-import-study')
    design$maxdiff<-list(exercise,optional);saved<-brohn_put_entity(store,'study',design$id,design)
    pairs<-list(c(1L,2L),c(1L,3L),c(2L,1L),c(2L,3L),c(3L,1L),c(3L,2L));ids<-brohn_ids(exercise$items)
    rows<-lapply(seq_along(pairs),function(i)list(participant_id='001',session_id='visit-01',participant_linkage='true',
      exposure_id=paste0('original-pair-',i),exercise_id=exercise$id,design_hash=brohn_hash(exercise),set_id=exercise$sets[[1L]]$id,
      item_order=brohn_json(as.list(if(i%%2L)ids else rev(ids))),presented='true',status='answered',
      best_id=ids[[pairs[[i]][[1L]]]],worst_id=ids[[pairs[[i]][[2L]]]],missing_reason='',origin='sample'))
    partial<-rows[[1L]];partial$exposure_id<-'original-partial';partial$status<-'missing';partial$worst_id<-'';partial$missing_reason<-'Only the best was answered'
    unseen<-partial;unseen$exposure_id<-'original-unseen';unseen$status<-'not_presented';unseen$presented<-'false';unseen$best_id<-'';unseen$missing_reason<-'The set was not reached'
    other<-rows[[1L]];other$exposure_id<-'original-other-exercise';other$exercise_id<-optional$id;other$design_hash<-brohn_hash(optional)
    other$set_id<-optional$sets[[1L]]$id;other$item_order<-brohn_json(optional$sets[[1L]]$item_ids)
    other$status<-'missing';other$best_id<-'';other$worst_id<-'';other$missing_reason<-'Optional exercise skipped'
    rows<-c(rows,list(partial,unseen,other));columns<-names(rows[[1L]])
    table<-as.data.frame(stats::setNames(lapply(columns,function(name)vapply(rows,`[[`,character(1),name)),columns),stringsAsFactors=FALSE,check.names=FALSE)
    write<-function(data,name){file<-file.path(folder,name);utils::write.table(data,file,sep=',',row.names=FALSE,quote=TRUE,qmethod='double',fileEncoding='UTF-8');list(path=file,sha256=digest::digest(file=file,algo='sha256'))}
    files<-list(valid=write(table,'original-multiple-exercises.csv'))
    bad<-table;bad$design_hash[[1L]]<-strrep('e',64);files$bad_hash<-write(bad,'original-wrong-hash.csv')
    bad<-table;bad$origin[[1L]]<-'live';files$bad_origin<-write(bad,'original-wrong-origin.csv')
    brohn_write_json_file(list(port=httpuv::randomPort(min=19000L,max=49000L),workspace=workspace,
      study_id=design$id,study_title=design$title,study_revision=saved$revision,study_hash=brohn_hash(design),
      required=exercise,optional=optional,files=files,rows=rows,columns=as.list(columns)),config_path)
  }
  config<-brohn_read_json_file(config_path)
  if(mode=='edit-current') {
    study<-brohn_study(store,config$study_id);stopifnot(study$revision==config$study_revision)
    study$body$maxdiff[[1L]]$settings$best_label<-'Later draft framing - not the collected question'
    brohn_save_study(store,study$body,study$revision)
  }
  datasets<-brohn_list_entities(store,'dataset',limit=10000L)
  result<-list(study=brohn_study(store,config$study_id),
    datasets=lapply(datasets,function(d)list(id=d$id,revision=d$revision,body=d$body,body_hash=brohn_hash(d$body),source_sha256=digest::digest(file=brohn_object_path(store,d$body$source$hash),algo='sha256'))),
    reports=brohn_list_entities(store,'report',limit=10000L),
    ingestions=brohn_list_entities(store,'ingestion',limit=10000L),
    jobs=lapply(brohn_list_jobs(store,limit=10000L),function(j)j[intersect(c('id','operation','request','status','result','error'),names(j))]))
  brohn_write_json_file(result,file.path(folder,'snapshot.json'))
})
