# Three arguments: exact source16 checkout, this overlay packet, NEW output dir.
# Actual isolated stores/portable APIs; no scientific jobs, servers or delivery.
local({
  args <- commandArgs(TRUE);stopifnot(length(args)==3L)
  base <- normalizePath(args[[1L]],winslash="/",mustWork=TRUE)
  packet <- normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
  output <- args[[3L]];stopifnot(!file.exists(output));dir.create(output,recursive=TRUE)
  output <- normalizePath(output,winslash="/",mustWork=TRUE)
  previous <- getwd();setwd(base);on.exit(setwd(previous),add=TRUE)
  env <- new.env(parent=.GlobalEnv)
  source("R/platform-load.R",local=env,encoding="UTF-8");env$brohn_load(envir=env,ui=FALSE)
  source(file.path(packet,"R/platform-stimulus-versions.R"),local=env,encoding="UTF-8")
  env$qa_output<-output;env$qa_packet<-packet;env$qa_base<-base
  evalq(local({
    started<-proc.time()[["elapsed"]];checks<-character();passed<-FALSE;stores<-list();closed<-FALSE
    check<-function(label,ok){if(!isTRUE(ok))stop(label,call.=FALSE);checks<<-c(checks,label);cat("PASS",label,"\n")}
    refuse<-function(label,expr){error<-tryCatch({force(expr);NULL},error=identity);check(label,inherits(error,"error"));invisible(error)}
    equal<-function(a,b)identical(brohn_json(a),brohn_json(b))
    hash<-function(p)digest::digest(file=p,algo="sha256")
    paths<-c(file.path(qa_packet,"R/platform-stimulus-versions.R"),file.path(qa_base,"R/platform-core.R"),
      file.path(qa_base,"R/platform-library.R"),file.path(qa_base,"R/platform-materials.R"),file.path(qa_base,"R/platform-portability.R"),
      "examples/stimuli/sample-design-a.png","examples/stimuli/sample-design-b.png")
    inputs<-lapply(paths,function(p)list(path=normalizePath(p,winslash="/",mustWork=TRUE),sha256=hash(p)))
    on.exit({
      errors<-character();for(s in stores)tryCatch(brohn_close_store(s),error=function(e)errors<<-c(errors,conditionMessage(e)))
      closed<-!length(errors);exact<-all(vapply(inputs,function(x)identical(hash(x$path),x$sha256),logical(1)))
      writeLines(jsonlite::toJSON(list(passed=passed&&closed&&exact,checks=as.list(checks),
        elapsed_s=proc.time()[["elapsed"]]-started,inputs=inputs,inputs_exact_after=exact,
        stores_closed=closed,close_errors=as.list(errors),
        scope="Stimulus-version pure/domain/store/compiler/portable checks on new owned stores; no UI controller or live-app acceptance, scientific jobs, services or participant sessions."),
        auto_unbox=TRUE,null="null",pretty=TRUE),file.path(qa_output,"RESULTS.json"),useBytes=TRUE)
    },add=TRUE)
    store<-brohn_open_store(file.path(qa_output,"workspace"));stores[[1L]]<-store;brohn_initialise_library(store)
    other<-brohn_open_store(file.path(qa_output,"import-workspace"));stores[[2L]]<-other;brohn_initialise_library(other)
    study<-brohn_create_study(store,"Original shelf material and alternative")
    d<-study$body;for(i in seq_along(d$stimuli))d$stimuli[[i]]$content<-paste("Original concept",i)
    sid<-d$stimuli[[1L]]$id
    d<-brohn_material_attach_png(store,d,"stimulus",sid,path=paths[[6L]],image_alt="Original shelf with two package areas")
    asset<-d$stimuli[[1L]]$asset
    d$stimuli[[1L]]$aois<-list(
      list(id="region-price",label="Price",x=.1,y=.2,width=.2,height=.1,asset_hash=asset$hash,source="manual"),
      list(id="region-package",label="Package",x=.5,y=.2,width=.2,height=.4,asset_hash=asset$hash))
    study<-brohn_save_study(store,d,study$revision);original<-study$body;original_json<-brohn_json(original)
    raw_original<-DBI::dbGetQuery(store$con,"SELECT hex(CAST(body_json AS BLOB)) AS bytes,body_hash FROM entity_versions WHERE kind='study' AND id=? AND revision=?",params=list(study$id,study$revision))
    object_before<-DBI::dbGetQuery(store$con,"SELECT * FROM objects ORDER BY hash")
    condition_count<-length(d$conditions);stimulus_count<-length(d$stimuli)
    version<-brohn_add_stimulus_version(d,sid,"Caf\u00e9 control variant",new_condition_role="control")
    copied<-version$stimuli[[length(version$stimuli)]]
    check("pure add leaves original full design and source stimulus unchanged",identical(brohn_json(d),original_json)&&equal(version$stimuli[seq_len(stimulus_count)],d$stimuli))
    check("one version and one named control condition appended together",length(version$stimuli)==stimulus_count+1L&&length(version$conditions)==condition_count+1L&&
      identical(tail(version$conditions,1L)[[1L]],list(id=copied$condition_id,label="Caf\u00e9 control variant",role="control")))
    check("fresh stimulus condition and AOI identities do not reuse the source",!copied$id%in%brohn_ids(d$stimuli)&&!copied$condition_id%in%brohn_ids(d$conditions)&&
      !any(brohn_ids(copied$aois)%in%brohn_ids(d$stimuli[[1L]]$aois))&&!anyDuplicated(brohn_ids(copied$aois)))
    clean<-function(s){s$id<-NULL;s$title<-NULL;s$condition_id<-NULL;s$aois<-lapply(s$aois,function(a){a$id<-NULL;a});s}
    check("exact material duration geometry optional fields and AOI annotations retained",equal(clean(copied),clean(d$stimuli[[1L]])))
    check("pure copy neither registers objects nor changes exact source PNG",identical(object_before,DBI::dbGetQuery(store$con,"SELECT * FROM objects ORDER BY hash"))&&
      identical(hash(brohn_object_path(store,asset$hash,verify=TRUE)),asset$hash))
    for(role in c("test","neutral","other")) {
      v<-brohn_add_stimulus_version(d,sid,paste("Role",role),new_condition_role=role)
      check(paste("explicit new condition role",role),identical(tail(v$conditions,1L)[[1L]]$role,role))
    }
    shared<-brohn_add_stimulus_version(d,sid,"Same condition version",condition_id=d$conditions[[1L]]$id)
    check("explicit existing-condition choice preserves all original conditions",equal(shared$conditions,d$conditions)&&identical(tail(shared$stimuli,1L)[[1L]]$condition_id,d$conditions[[1L]]$id))
    texts<-brohn_add_stimulus_version(d,d$stimuli[[2L]]$id,"Text control",condition_id=d$conditions[[2L]]$id)
    check("text/null asset/empty AOIs and optional-field absence retained",equal(clean(tail(texts$stimuli,1L)[[1L]]),clean(d$stimuli[[2L]])))
    for(case in list(list(id="missing",title="Valid",condition=NULL,role="test"),list(id=sid,title="",condition=NULL,role="test"),
      list(id=sid,title=paste(rep("\u00e9",121),collapse=""),condition=NULL,role="test"),list(id=sid,title="Valid",condition="missing",role="test"),
      list(id=sid,title="Valid",condition=NULL,role="invalid"))) {
      before<-brohn_json(d)
      refuse("invalid add refuses without mutating either collection",brohn_add_stimulus_version(d,case$id,case$title,case$condition,case$role))
      check("refused input remains exact",identical(before,brohn_json(d)))
    }
    archived<-d;archived$archived<-TRUE;refuse("archived original requires restoration",brohn_add_stimulus_version(archived,sid,"Refused"))
    max_conditions<-d;max_conditions$conditions<-c(d$conditions,lapply(seq_len(100L-length(d$conditions)),function(i)list(id=paste0("extra-",i),label=paste("Extra",i),role="other")))
    refuse("100-condition design refuses an additional condition",brohn_add_stimulus_version(max_conditions,sid,"Beyond limit"))
    check("100-condition design still permits explicit existing condition",length(brohn_add_stimulus_version(max_conditions,sid,"Existing",d$conditions[[1L]]$id)$conditions)==100L)
    maximum<-d;maximum$stimuli<-lapply(seq_len(500L),function(i){s<-d$stimuli[[2L]];s$id<-paste0("many-",i);s})
    refuse("500-stimulus design refuses a501st version",brohn_add_stimulus_version(maximum,"many-1","Beyond limit"))
    name_source<-d$stimuli[[1L]];name_source$title<-paste(rep("\U0001f9ea",60),collapse="")
    proposed<-brohn_stimulus_version_name(name_source,list(name_source));check("generated Unicode version title stays inside UTF8 byte limit",validUTF8(proposed)&&brohn_text(proposed,240))
    another<-name_source;another$title<-proposed
    check("generated name advances after an existing proposed name",!identical(brohn_stimulus_version_name(name_source,list(name_source,another)),proposed))
    saved<-brohn_save_study(store,version,study$revision)
    check("one save persists complete version and original revision bytes unchanged",equal(saved$body,version)&&
      identical(raw_original,DBI::dbGetQuery(store$con,"SELECT hex(CAST(body_json AS BLOB)) AS bytes,body_hash FROM entity_versions WHERE kind='study' AND id=? AND revision=?",params=list(study$id,study$revision))))
    for(order in c("fixed","counterbalanced","randomized")) {
      compiled_design<-version;compiled_design$order<-order;p<-brohn_compile(compiled_design,3L)
      shown<-Filter(function(s)identical(s$type,"stimulus"),p$timeline)
      check(paste(order,"compile shows each saved stimulus exactly once with original descriptors"),length(shown)==length(version$stimuli)&&
        setequal(vapply(shown,`[[`,character(1),"stimulus_id"),brohn_ids(version$stimuli))&&
        all(vapply(shown,function(s)equal(s$stimulus,brohn_find(version$stimuli,s$stimulus_id)),logical(1))))
    }
    package<-brohn_export_design(store,study$id,file.path(qa_output,"versions.brohn-study.zip"))
    entries<-utils::unzip(package,list=TRUE)$Name
    check("portable archive contains only one object for shared exact material",sum(startsWith(entries,"assets/"))==1L)
    imported<-brohn_import_design(other,package)
    imported_versions<-imported$body$stimuli
    check("actual portable import retains both copies exact material AOIs duration and condition roles",length(imported_versions)==length(version$stimuli)&&
      all(vapply(seq_along(imported_versions),function(i)equal(clean(imported_versions[[i]]),clean(version$stimuli[[i]])),logical(1)))&&
      identical(vapply(imported$body$conditions,`[[`,character(1),"role"),vapply(version$conditions,`[[`,character(1),"role"))&&
      identical(hash(brohn_object_path(other,asset$hash,verify=TRUE)),asset$hash))
    replaced<-brohn_material_attach_png(store,version,"stimulus",copied$id,path=paths[[7L]],image_alt="Different shelf version")
    check("different material clears only copied version areas and retains original source",length(tail(replaced$stimuli,1L)[[1L]]$aois)==0L&&
      equal(replaced$stimuli[[1L]],version$stimuli[[1L]])&&!identical(tail(replaced$stimuli,1L)[[1L]]$asset$hash,asset$hash))
    same<-brohn_material_attach_png(store,version,"stimulus",copied$id,path=paths[[6L]],image_alt="Same retained image")
    check("reattaching exact original bytes keeps copied AOIs",equal(tail(same$stimuli,1L)[[1L]]$aois,copied$aois))
    check("no science jobs or participant sessions allocated",DBI::dbGetQuery(store$con,"SELECT count(*) AS n FROM jobs")$n==0L&&
      DBI::dbGetQuery(other$con,"SELECT count(*) AS n FROM jobs")$n==0L&&!DBI::dbExistsTable(store$con,"delivery_runs")&&!DBI::dbExistsTable(other$con,"delivery_runs"))
    check("original source design input remains exact at end",identical(brohn_json(d),original_json))
    passed<-TRUE
  }),envir=env)
})
