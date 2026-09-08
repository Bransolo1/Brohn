# Independent checks of the parent's task clone/package extension. Original
# synthetic materials only; no downloaded task exemplars or participant data.
.libPaths(c(normalizePath("../../work/r-library-brohn",winslash="/",mustWork=FALSE),.libPaths()))
for(module in c("platform-core","platform-methods","platform-store","platform-library","platform-portability"))source(paste0("R/",module,".R"))
local({
  n<-0L;check<-function(name,ok){if(!isTRUE(ok))stop("FAIL: ",name);n<<-n+1L}
  stage<-.brohn_port_temp();a<-brohn_open_store(file.path(stage,"a"));b<-brohn_open_store(file.path(stage,"b"))
  on.exit({brohn_close_store(a);brohn_close_store(b);.brohn_port_cleanup(stage)},add=TRUE)
  brohn_initialise_library(a);brohn_initialise_library(b)
  profiles<-c("iat-gnb2003-d1/1.0","biat-nosek2014-goodfocal/1.0","aat-keyboard-cue-balanced/1.0","rt-deary-liewald-simple/1.0","rt-deary-liewald-choice/1.0")
  expected_counts<-list(c(20,20,20,40,20,20,40),c(16,20,20,20,20),c(16,80),c(8,20),c(8,40))
  design<-brohn_new_design("Original portable implicit procedures","blank",id="implicit-portability")
  design$blocks<-lapply(seq_along(profiles),function(i)brohn_task_new(profiles[i],id=paste0("original-task-",i)))
  png<-file.path(stage,"original-task.png");png::writePNG(array(rep(c(.2,.8,.3),each=4*6),c(4,6,3)),png)
  object<-brohn_store_object(a,path=png,media_type="image/png")
  design$blocks[[1]]$materials[[1]]$type<-"image";design$blocks[[1]]$materials[[1]]$asset<-object
  brohn_put_entity(a,"study",design$id,design)
  brohn_put_entity(a,"participant","private-person",list(fictional_alias="Never export"))
  brohn_put_entity(a,"report","private-report",list(fictional_result=99))
  original_hash<-brohn_hash(design)
  package<-brohn_export_design(a,design$id,file.path(stage,"implicit.brohn-study.zip"))
  imported<-brohn_import_design(b,package)$body
  check("all registered task profiles survive actual ZIP import",identical(vapply(imported$blocks,`[[`,character(1),"profile"),profiles))
  check("new study identity is assigned",imported$id!=design$id&&imported$lineage$operation=="import_design")
  check("source design remains byte-semantically unchanged",identical(original_hash,brohn_hash(brohn_get_entity(a,"study",design$id)$body)))
  check("no participant or result entities cross the package boundary",!length(brohn_list_entities(b,"participant"))&&!length(brohn_list_entities(b,"report")))
  check("task image hash is preserved across workspaces",identical(imported$blocks[[1]]$materials[[1]]$asset$hash,object$hash)&&file.exists(brohn_object_path(b,object$hash,verify=TRUE)))
  for(i in seq_along(profiles)){
    before<-design$blocks[[i]];after<-imported$blocks[[i]]
    check(paste("new task identity",profiles[i]),before$id!=after$id)
    check(paste("category and material references remapped",profiles[i]),
      !any(brohn_ids(after$categories)%in%brohn_ids(before$categories))&&!any(brohn_ids(after$materials)%in%brohn_ids(before$materials))&&
      all(vapply(after$materials,function(m)m$category_id%in%brohn_ids(after$categories),logical(1))))
    check(paste("material text and category semantics retained",profiles[i]),
      identical(vapply(before$categories,`[[`,character(1),"role"),vapply(after$categories,`[[`,character(1),"role"))&&
      identical(vapply(before$materials,`[[`,character(1),"content"),vapply(after$materials,`[[`,character(1),"content")))
    old<-brohn_task_compile(before,2L);new<-brohn_task_compile(after,2L)
    check(paste("independent procedure counts retained",profiles[i]),identical(as.numeric(vapply(new$blocks,`[[`,integer(1),"trial_count")),expected_counts[[i]]))
    trials<-function(t)Filter(function(s)s$type=="task_trial",t$timeline)
    check(paste("fixed allocation key and scoring assignment retained",profiles[i]),
      identical(vapply(trials(old),`[[`,character(1),"correct_code"),vapply(trials(new),`[[`,character(1),"correct_code"))&&
      identical(vapply(trials(old),`[[`,logical(1),"scored"),vapply(trials(new),`[[`,logical(1),"scored"))&&identical(old$assignment,new$assignment))
  }
  clone<-brohn_clone_study(b,imported$id)$body
  check("cloning an imported task design makes another distinct graph",clone$id!=imported$id&&!any(brohn_ids(clone$blocks)%in%brohn_ids(imported$blocks)))
  second<-brohn_export_design(b,clone$id,file.path(stage,"reexport.brohn-study.zip"))
  check("cloned registered task package can be exported again",file.exists(second)&&file.info(second)$size>0)
  protocol<-brohn_compile(imported,2L)
  check("imported tasks compile into the complete main study protocol",sum(vapply(protocol$timeline,function(s)s$type=="task",logical(1)))==5L&&
    identical(vapply(Filter(function(s)s$type=="task",protocol$timeline),function(s)s$task$profile,character(1)),profiles))
  rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
  bad<-imported;bad$blocks[[1]]$materials[[1]]$asset$filename<-"C:/private/researcher/material.png"
  check("private task asset display paths cannot enter a package",rejects(.brohn_port_validate(bad)))
  bad<-imported;bad$blocks[[1]]$materials[[1]]$asset$width<-0
  check("task image width must be valid",rejects(.brohn_port_validate(bad)))
  bad<-imported;bad$blocks[[1]]$materials[[1]]$asset$height<-32769
  check("task image height must fit the supported profile",rejects(.brohn_port_validate(bad)))
  cat(sprintf("platform-task-portability: %d checks passed\n",n))
})
