# Windows-qualified object preparation; publisher metadata remains separately
# fenced by the caller's short store transaction. No deployment or worker starts
# merely by sourcing this module.
if(!exists(".brohn_publication_handles",inherits=FALSE)) .brohn_publication_handles <- new.env(parent=emptyenv())
if(!exists(".brohn_publication_native_cache",inherits=FALSE)) .brohn_publication_native_cache <- new.env(parent=emptyenv())
.brohn_publication_r_hash<-digest::digest(file="R/platform-publication.R",algo="sha256")
.brohn_publication_native <- function() {
  manifest_path<-Sys.getenv("BROHN_PUBLICATION_NATIVE_MANIFEST","../../work/tooling/brohn-native/publication-guard.json")
  brohn_require(file.exists(manifest_path),"Build the parent publication guard with scripts/build-publication-guard.R before publishing reports on Windows.")
  manifest_path<-normalizePath(manifest_path,winslash="/",mustWork=TRUE)
  manifest<-.brohn_publication_read(manifest_path)
  brohn_require(identical(manifest$schema,"brohn-native-publication-build/1.0") && identical(manifest$source,"src/publication_guard.c") &&
    identical(manifest$r_version,as.character(getRversion())) && identical(manifest$architecture,R.version$arch) &&
    identical(manifest$source_sha256,digest::digest(file=manifest$source,algo="sha256")) &&
    brohn_text(manifest$dll,128) && identical(basename(manifest$dll),manifest$dll) && grepl("^publication_guard-[a-f0-9]{64}\\.dll$",manifest$dll),
    "Rebuild the native publication guard for this source and R runtime.")
  inputs_json<-jsonlite::toJSON(manifest$build_inputs,auto_unbox=TRUE,null="null",digits=NA)
  brohn_require(is.list(manifest$build_inputs) && identical(manifest$build_inputs$source_sha256,manifest$source_sha256) &&
    identical(manifest$build_inputs$r_version,manifest$r_version) && identical(manifest$build_inputs$architecture,manifest$architecture) &&
    identical(manifest$build_key,digest::digest(charToRaw(enc2utf8(inputs_json)),algo="sha256",serialize=FALSE)) &&
    identical(manifest$dll,paste0("publication_guard-",manifest$build_key,".dll")),"The native guard is missing its exact compiler, headers and R ABI build identity. Rebuild it.")
  path<-normalizePath(file.path(dirname(manifest_path),manifest$dll),winslash="/",mustWork=TRUE)
  brohn_require(identical(dirname(path),dirname(manifest_path)) && identical(digest::digest(file=path,algo="sha256"),manifest$dll_sha256),
    "The native publication guard does not match its verified local build.")
  key<-manifest$dll_sha256
  if(!exists(key,envir=.brohn_publication_native_cache,inherits=FALSE)) {
    brohn_require(identical(manifest$build_inputs$r_dll_sha256,digest::digest(file=file.path(R.home("bin"),"R.dll"),algo="sha256")),
      "The native guard was compiled for another R ABI. Rebuild it for this runtime.")
    dll<-dyn.load(path,local=TRUE)
    value<-list(identity=manifest,open=getNativeSymbolInfo("brohn_guard_open",PACKAGE=dll),
      check=getNativeSymbolInfo("brohn_guard_check",PACKAGE=dll),close=getNativeSymbolInfo("brohn_guard_close",PACKAGE=dll))
    assign(key,value,envir=.brohn_publication_native_cache)
  }
  get(key,envir=.brohn_publication_native_cache,inherits=FALSE)
}
.brohn_publication_native_close <- function(handle) {
  if(!is.null(handle$native_pointer)) {
    .Call(handle$native$close,handle$native_pointer);handle$native_pointer<-NULL
  }
  invisible(TRUE)
}
brohn_publication_readiness <- function() {
  if(.Platform$OS.type!="windows")return(list(ready=TRUE,mode="legacy-transactional-copy",native_seal=FALSE,
    message="This operating system uses the existing transactional copy path; large files can hold the writer lock."))
  native<-tryCatch(.brohn_publication_native(),error=function(e)e)
  if(inherits(native,"error"))return(list(ready=FALSE,component="native_guard",mode="staged-windows-parent-read-seal/1.0",native_seal=FALSE,
    message=conditionMessage(native),action="Run Rscript scripts/build-publication-guard.R using this Brohn R library and its prepared local TinyCC toolchain."))
  tryCatch({
    python<-.brohn_publication_python()
    process<-processx::run(python,c("-B","-c","import sys,os,json,ctypes;from ctypes import wintypes;print(json.dumps({'schema':'brohn-publication-python/1.0','version':list(sys.version_info[:3]),'platform':os.name,'pointer_bytes':ctypes.sizeof(ctypes.c_void_p),'windows_api':bool(getattr(ctypes,'WinDLL',None))}))"),
      timeout=10,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE)
    brohn_require(!isTRUE(process$timeout) && identical(process$status,0L) && nchar(process$stdout,type="bytes")<=4096,"The publication Python probe failed or exceeded its ten-second deadline.")
    probe<-brohn_parse(process$stdout,4096);version<-unlist(probe$version)
    brohn_require(identical(probe$schema,"brohn-publication-python/1.0") && identical(probe$platform,"nt") &&
      identical(as.integer(probe$pointer_bytes),8L) && isTRUE(probe$windows_api) && length(version)==3L &&
      version[[1]]==3 && version[[2]]>=10,"Publication requires a working 64-bit Windows Python 3.10 or newer in the Python 3 series.")
    list(ready=TRUE,mode="staged-windows-parent-read-seal/1.0",native_seal=TRUE,native_build=native$identity,
      python=python,python_version=paste(version,collapse="."),python_probe=probe)
  },error=function(e)list(ready=FALSE,component="publication_python",mode="staged-windows-parent-read-seal/1.0",native_seal=FALSE,
    message=conditionMessage(e),action="Set BROHN_PUBLICATION_PYTHON to a working 64-bit Windows Python 3.10+ executable, or restore the prepared local methods environment."))
}
.brohn_publication_read <- function(path) {
  brohn_require(file.exists(path) && !dir.exists(path) && file.info(path)$size<=1024^2,"Publication control document is missing or oversized.")
  raw<-readBin(path,"raw",n=1024^2+1L);brohn_require(length(raw)<=1024^2,"Publication document exceeds its bound.")
  text<-rawToChar(raw);Encoding(text)<-"UTF-8";brohn_parse(text,1024^2)
}
.brohn_publication_write <- function(value,path) {
  bytes<-charToRaw(enc2utf8(brohn_json(value)));brohn_require(length(bytes)<=1024^2,"Publication document exceeds its bound.")
  brohn_require(!file.exists(path),"Publication control file already exists.");writeBin(bytes,path);invisible(path)
}
.brohn_publication_job <- function(store,job) {
  current<-brohn_get_job(store,job$id)
  brohn_require(!is.null(current) && identical(current$status,"running") && identical(current$worker,job$worker) &&
    identical(current$token,job$token) && identical(as.numeric(current$attempt),as.numeric(job$attempt)) &&
    identical(brohn_hash(current$request),brohn_hash(job$request)) && is.numeric(current$lease_until) && current$lease_until>as.numeric(Sys.time()),
    "This publication attempt no longer holds its original job lease.")
  current
}
.brohn_publication_python <- function() {
  configured<-Sys.getenv("BROHN_PUBLICATION_PYTHON",Sys.getenv("BROHN_PYTHON_METHODS",""))
  path<-if(nzchar(configured)) configured else "../../work/tooling/methods-venv/Scripts/python.exe"
  brohn_require(file.exists(path),"The local publication Python environment is unavailable.")
  normalizePath(path,winslash="/",mustWork=TRUE)
}
.brohn_publication_probe_guard <- function(handle) {
  if(!isTRUE(handle$guard_owned))return("unknown")
  tryCatch({
    process<-ps::ps_handle(handle$guard_pid,as.POSIXct(handle$guard_created,origin="1970-01-01",tz="UTC"))
    if(!ps::ps_is_running(process))return("absent")
    if(abs(as.numeric(ps::ps_create_time(process))-handle$guard_created)>.001)return("absent")
    if(!identical(tail(ps::ps_cmdline(process),length(handle$args)),handle$args))return("unknown")
    "owned_alive"
  },no_such_process=function(e)"absent",error=function(e)"unknown")
}
.brohn_publication_observe_guard <- function(handle) {
  if(isTRUE(handle$guard_owned) || is.null(handle$child) || !handle$child$is_alive())return(invisible(NULL))
  tryCatch({
    launcher<-ps::ps_handle(handle$pid,as.POSIXct(handle$created,origin="1970-01-01",tz="UTC"))
    candidates<-ps::ps_children(launcher,recursive=TRUE)
    for(process in candidates)if(identical(tail(ps::ps_cmdline(process),length(handle$args)),handle$args)) {
      # A launcher can share the same argv before it spawns the interpreter.
      # Do not mistake it for the guard; direct interpreters bind at receipt.
      handle$guard_pid<-ps::ps_pid(process);handle$guard_created<-as.numeric(ps::ps_create_time(process))
      handle$guard_owned<-TRUE
    }
  },error=function(e)NULL)
  invisible(NULL)
}
.brohn_publication_cleanup_pending <- function(handle) {
  # Only complete process shutdown permits removal of private copy fragments.
  # Shared hash-addressed orphan bytes and small diagnostic/control files remain.
  directory<-.brohn_store_contained(list(root=handle$workspace_root),handle$directory)
  expected<-normalizePath(file.path(handle$workspace_root,"scratch","publication"),winslash="/",mustWork=TRUE)
  brohn_require(identical(dirname(directory),expected) && startsWith(basename(directory),"attempt-"),"Publication cleanup directory is not this owned attempt.")
  paths<-list.files(directory,pattern="^[a-f0-9]{32}\\.object-pending$",full.names=TRUE)
  for(path in paths) {
    path<-.brohn_store_contained(list(root=handle$workspace_root),path)
    brohn_require(identical(dirname(path),directory) && !dir.exists(path),"Publication copy fragment leaves this attempt.")
    brohn_require(unlink(path,force=TRUE)==0L,"Cannot remove this stopped attempt's copy fragment.")
  }
  invisible(TRUE)
}
.brohn_publication_terminate <- function(handle) {
  if(is.null(handle$child)){.brohn_publication_cleanup_pending(handle);return(invisible(TRUE))}
  .brohn_publication_observe_guard(handle)
  try(handle$child$write_input(paste0(brohn_json(list(request_sha256=handle$request_hash,nonce=handle$owner$nonce,operation="release")),"\n")),silent=TRUE)
  handle$child$wait(2000)
  if(handle$child$is_alive()){handle$child$kill_tree();handle$child$wait(2000)}
  # Killing only a venv launcher can leave its proven interpreter alive. A
  # remembered creation time + frozen argv remains valid after reparenting.
  probe<-.brohn_publication_probe_guard(handle)
  if(identical(probe,"owned_alive")) {
    process<-ps::ps_handle(handle$guard_pid,as.POSIXct(handle$guard_created,origin="1970-01-01",tz="UTC"))
    ps::ps_kill(process)
    until<-as.numeric(Sys.time())+2
    repeat {probe<-.brohn_publication_probe_guard(handle);if(probe!="owned_alive"||as.numeric(Sys.time())>=until)break;Sys.sleep(.01)}
  }
  stopped<-!handle$child$is_alive() && identical(probe,"absent")
  if(stopped).brohn_publication_cleanup_pending(handle)
  invisible(stopped)
}
brohn_prepare_publication <- function(store,job,specifications,timeout_seconds=1900) {
  .brohn_store_ready(store)
  brohn_require(identical(digest::digest(file="R/platform-publication.R",algo="sha256"),.brohn_publication_r_hash),"Restart local services to use the changed publication implementation.")
  brohn_require(.Platform$OS.type=="windows","Immutable publication sealing is currently qualified only on Windows.")
  brohn_require(!RSQLite::sqliteIsTransacting(store$con),"Prepare publication bytes before entering any store transaction.")
  brohn_require(brohn_number(timeout_seconds,1,7200),"Declare a bounded publication preparation timeout.")
  .brohn_publication_job(store,job)
  brohn_require(brohn_array(specifications) && length(specifications)>=1L && length(specifications)<=1024L,"Prepare one to 1,024 explicit artifacts.")
  specifications<-lapply(specifications,function(item) {
    brohn_fields(item,c("key","kind","path","sha256","bytes","media_type"),label="Publication artifact")
    brohn_require(brohn_text(item$key,256) && brohn_text(item$kind,96) && brohn_text(item$media_type,256) &&
      brohn_text(item$sha256,64) && grepl("^[a-f0-9]{64}$",item$sha256) && brohn_number(item$bytes,0,4*1024^3,TRUE),"Publication artifact identity, type or bounds are invalid.")
    item$path<-.brohn_store_contained(store,item$path)
    brohn_require(file.exists(item$path) && !dir.exists(item$path),"Publication source is unavailable.");item
  })
  brohn_require(!anyDuplicated(vapply(specifications,`[[`,character(1),"key")) && sum(vapply(specifications,`[[`,numeric(1),"bytes"))<=16*1024^3,
    "Publication keys must be unique and total bytes bounded.")
  parent<-file.path(store$root,"scratch","publication");dir.create(parent,recursive=TRUE,showWarnings=FALSE)
  parent<-.brohn_store_contained(store,parent)
  directory<-tempfile("attempt-",tmpdir=parent);brohn_require(dir.create(directory),"Cannot create a private publication attempt.")
  directory<-.brohn_store_contained(store,directory)
  handle<-new.env(parent=emptyenv());handle$id<-brohn_id("publication");handle$closed<-FALSE
  handle$workspace_id<-store$workspace_id;handle$workspace_root<-store$root;handle$job<-job;handle$directory<-directory;handle$r_hash<-.brohn_publication_r_hash
  handle$con<-store$con;handle$native<-.brohn_publication_native();handle$native_pointer<-NULL
  handle$owner<-list(job_id=job$id,worker=job$worker,attempt=as.integer(job$attempt),token=job$token,nonce=brohn_token())
  handle$specifications<-specifications;handle$child<-NULL;handle$registered<-FALSE;handle$guard_owned<-FALSE
  handle$begin_acknowledged<-FALSE
  request<-list(schema="brohn-publication-request/1.0",workspace_root=store$root,workspace_id=store$workspace_id,owner=handle$owner,specifications=specifications)
  request_path<-file.path(directory,"request.json");receipt_path<-file.path(directory,"receipt.json")
  .brohn_publication_write(request,request_path)
  handle$request_hash<-digest::digest(file=request_path,algo="sha256")
  script<-normalizePath("scripts/workers/publication.py",winslash="/",mustWork=TRUE)
  handle$script<-script;handle$implementation_hash<-digest::digest(file=script,algo="sha256")
  successful<-FALSE
  on.exit(if(!successful){.brohn_publication_terminate(handle);.brohn_publication_native_close(handle)},add=TRUE)
  brohn_renew_job(store,job$id,job$worker,job$token,60)
  handle$args<-c(script,"--request",request_path,"--receipt",receipt_path,"--status",file.path(directory,"status.json"))
  handle$child<-processx::process$new(.brohn_publication_python(),handle$args,
    stdin="|",stdout=file.path(directory,"stdout.txt"),stderr=file.path(directory,"stderr.txt"),cleanup_tree=TRUE,windows_hide_window=TRUE)
  handle$pid<-handle$child$get_pid();handle$created<-as.numeric(ps::ps_create_time(ps::ps_handle(handle$pid)))
  began<-as.numeric(Sys.time());renewed<-began
  repeat {
    .brohn_publication_observe_guard(handle)
    .brohn_publication_job(store,job)
    now<-as.numeric(Sys.time())
    brohn_require(now-began<=timeout_seconds,"Publication preparation exceeded its declared time bound; the source remains preserved.")
    if(now-renewed>=15) {brohn_renew_job(store,job$id,job$worker,job$token,60);renewed<-now}
    status_path<-file.path(directory,"status.json")
    if(!handle$begin_acknowledged && file.exists(status_path)) {
      status<-.brohn_publication_read(status_path)
      if(identical(status$phase,"awaiting_owner")) {
        brohn_require(identical(status$schema,"brohn-publication-status/1.0") && identical(status$request_sha256,handle$request_hash),
          "The publication process did not return its exact start identity.")
        if(!isTRUE(handle$guard_owned)) {
          handle$guard_pid<-as.integer(status$pid);handle$guard_created<-as.numeric(ps::ps_create_time(ps::ps_handle(handle$guard_pid)))
          brohn_require(.brohn_publication_guard(handle),"The publication interpreter is not this parent's exact child.")
          handle$guard_owned<-TRUE
        }
        brohn_require(identical(as.integer(status$pid),as.integer(handle$guard_pid)) && .brohn_publication_guard(handle),"Publication start process ownership changed.")
        handle$child$write_input(paste0(brohn_json(list(request_sha256=handle$request_hash,nonce=handle$owner$nonce,operation="begin")),"\n"))
        handle$begin_acknowledged<-TRUE
      }
    }
    if(file.exists(receipt_path)) break
    if(!handle$child$is_alive()) {
      error_path<-file.path(directory,"stderr.txt")
      message<-if(file.exists(error_path))paste(head(readLines(error_path,warn=FALSE),8),collapse=" ") else "No preparation receipt was returned."
      brohn_stop(paste("Publication preparation failed.",substr(message,1,2400)))
    }
    handle$child$wait(50)
  }
  handle$receipt_path<-receipt_path;handle$receipt_hash<-digest::digest(file=receipt_path,algo="sha256")
  handle$receipt<-.brohn_publication_read(receipt_path)
  if(!isTRUE(handle$guard_owned)) {
    handle$guard_pid<-as.integer(handle$receipt$pid)
    handle$guard_created<-as.numeric(ps::ps_create_time(ps::ps_handle(handle$guard_pid)))
    brohn_require(.brohn_publication_guard(handle),"The receipt process was not observed as an owned guard.")
    handle$guard_owned<-TRUE
  }
  assign(handle$id,handle,envir=.brohn_publication_handles)
  registered_handle<-FALSE
  on.exit(if(!registered_handle && exists(handle$id,envir=.brohn_publication_handles,inherits=FALSE))rm(list=handle$id,envir=.brohn_publication_handles),add=TRUE)
  items<-.brohn_publication_validate(store,handle,require_native=FALSE)
  # The helper still holds every fully hashed identity while the parent opens
  # its own compatible read-only sharing handles. They survive helper death.
  handle$native_pointer<-.Call(handle$native$open,
    vapply(items,`[[`,character(1),"path"),
    vapply(items,function(item)item$file_identity$volume,character(1)),
    vapply(items,function(item)item$file_identity$file_index,character(1)),
    vapply(items,function(item)sprintf("%.0f",item$bytes),character(1)))
  .brohn_publication_validate(store,handle)
  successful<-TRUE;registered_handle<-TRUE;handle
}
.brohn_publication_guard <- function(prepared) {
  # Windows virtual environments may use a launcher plus the actual interpreter.
  # The receipt PID must be that exact owned descendant with the frozen argv,
  # never a process accepted merely because it happens to use the same script.
  tryCatch({
    guard<-ps::ps_handle(prepared$guard_pid,as.POSIXct(prepared$guard_created,origin="1970-01-01",tz="UTC"))
    if(!ps::ps_is_running(guard) || !identical(tail(ps::ps_cmdline(guard),length(prepared$args)),prepared$args))return(FALSE)
    cursor<-guard;seen<-integer()
    for(i in seq_len(8L)) {
      pid<-ps::ps_pid(cursor)
      if(pid==prepared$pid)return(abs(as.numeric(ps::ps_create_time(cursor))-prepared$created)<.001)
      if(pid %in% seen)return(FALSE)
      seen<-c(seen,pid);cursor<-ps::ps_handle(ps::ps_ppid(cursor))
    }
    FALSE
  },error=function(e)FALSE)
}
.brohn_publication_validate <- function(store,prepared,require_native=TRUE) {
  brohn_require(is.environment(prepared) && !is.null(prepared$id) && exists(prepared$id,envir=.brohn_publication_handles,inherits=FALSE) &&
    identical(get(prepared$id,envir=.brohn_publication_handles,inherits=FALSE),prepared) && !isTRUE(prepared$closed),"Publication handle is closed or not owned by this R process.")
  brohn_require(identical(prepared$workspace_id,store$workspace_id) && identical(prepared$workspace_root,store$root),"Publication handle belongs to another workspace.")
  brohn_require(identical(prepared$r_hash,.brohn_publication_r_hash) && identical(digest::digest(file="R/platform-publication.R",algo="sha256"),prepared$r_hash),
    "Publication R implementation changed during this attempt.")
  .brohn_publication_job(store,prepared$job)
  brohn_require(prepared$child$is_alive() && identical(as.integer(prepared$pid),as.integer(prepared$child$get_pid())),"The process holding immutable publication seals has exited.")
  observed<-tryCatch(ps::ps_create_time(ps::ps_handle(prepared$pid)),error=function(e)NULL)
  brohn_require(!is.null(observed) && abs(as.numeric(observed)-prepared$created)<.001,"The publication seal process identity changed.")
  brohn_require(.brohn_publication_guard(prepared),"The immutable-file guard is not the exact owned publication process.")
  brohn_require(identical(digest::digest(file=prepared$receipt_path,algo="sha256"),prepared$receipt_hash) &&
    identical(digest::digest(file=prepared$script,algo="sha256"),prepared$implementation_hash),"Publication receipt or implementation changed after preparation.")
  r<-prepared$receipt
  checks<-c(schema=identical(r$schema,"brohn-publication-ready/1.0"),status=identical(r$status,"sealed"),
    seal=identical(r$seal,"windows-share-read-deny-write-delete/1.0"),request=identical(r$request_sha256,prepared$request_hash),
    implementation=identical(r$implementation_sha256,prepared$implementation_hash),workspace=identical(r$workspace_id,store$workspace_id),
    root=identical(normalizePath(r$workspace_root,winslash="/",mustWork=TRUE),store$root),owner=identical(brohn_hash(r$owner),brohn_hash(prepared$owner)),
    process=identical(as.integer(r$pid),as.integer(prepared$guard_pid)),items=brohn_array(r$items) && length(r$items)==length(prepared$specifications))
  brohn_require(all(checks),paste("Publication receipt does not match its exact",paste(names(checks)[!checks],collapse=", "),"binding."))
  if(isTRUE(require_native)) {
    brohn_require(!is.null(prepared$native_pointer),"The parent R process does not hold this publication's file guards.")
    brohn_require(identical(.brohn_publication_native()$identity,prepared$native$identity),"Native publication implementation changed during this attempt.")
    .Call(prepared$native$check,prepared$native_pointer)
  }
  lapply(seq_along(r$items),function(index) {
    item<-r$items[[index]];spec<-prepared$specifications[[index]]
    for(key in c("key","kind","sha256","media_type"))brohn_require(identical(item[[key]],spec[[key]]),"Publication receipt changed an artifact identity.")
    expected<-file.path(store$root,"objects","sha256",substr(spec$sha256,1,2),spec$sha256)
    path<-.brohn_store_contained(store,item$path)
    brohn_require(identical(path,normalizePath(expected,winslash="/",mustWork=TRUE)) && !dir.exists(path) &&
      identical(as.numeric(item$bytes),as.numeric(spec$bytes)) && identical(as.numeric(file.info(path)$size),as.numeric(spec$bytes)) &&
      is.list(item$file_identity) && brohn_text(item$file_identity$volume,32) && brohn_text(item$file_identity$file_index,32) &&
      identical(as.numeric(item$file_identity$bytes),as.numeric(spec$bytes)),"A sealed artifact path or file identity is inconsistent.")
    item
  })
}
brohn_commit_prepared_objects <- function(store,prepared) {
  .brohn_store_ready(store)
  brohn_require(RSQLite::sqliteIsTransacting(store$con),"Commit prepared objects only inside the final fenced publication transaction.")
  items<-.brohn_publication_validate(store,prepared)
  brohn_renew_job(store,prepared$job$id,prepared$job$worker,prepared$job$token,60)
  result<-lapply(items,function(item) {
    row<-.brohn_store_object_row(store,item$sha256)
    if(nrow(row)) {
      brohn_require(identical(as.numeric(row$size[[1]]),as.numeric(item$bytes)),"Existing object catalog size conflicts with its held immutable bytes.")
      media_type<-row$media_type[[1]]
    } else {
      media_type<-item$media_type
      DBI::dbExecute(store$con,"INSERT INTO objects (hash,size,media_type,created_at) VALUES (?,?,?,?)",params=list(item$sha256,item$bytes,media_type,.brohn_store_stamp()))
      .brohn_store_audit(store,"object.stored",item$sha256,list(size=item$bytes,media_type=media_type,publication_job_id=prepared$job$id,attempt=prepared$job$attempt))
    }
    list(key=item$key,kind=item$kind,hash=item$sha256,size=item$bytes,media_type=media_type)
  })
  # Caller must save report/dataset records and brohn_complete_job in this SAME
  # transaction. Any failure rolls back all registration; the sealed bytes stay
  # as safe unregistered orphans until this owner explicitly releases the guards.
  prepared$registered<-TRUE
  result
}
brohn_close_publication <- function(prepared,committed=FALSE) {
  brohn_require(is.environment(prepared) && !is.null(prepared$id),"An owned publication handle is required.")
  if(isTRUE(prepared$closed))return(invisible(TRUE))
  brohn_require(exists(prepared$id,envir=.brohn_publication_handles,inherits=FALSE) &&
    identical(get(prepared$id,envir=.brohn_publication_handles,inherits=FALSE),prepared),"This publication handle is not owned by this process.")
  brohn_require(is.logical(committed) && length(committed)==1L && !is.na(committed),"Declare whether the publication transaction committed.")
  brohn_require(!DBI::dbIsValid(prepared$con) || !RSQLite::sqliteIsTransacting(prepared$con),"Retain parent publication guards until the final transaction has committed or rolled back.")
  stopped<-.brohn_publication_terminate(prepared)
  brohn_require(isTRUE(stopped),"Publication guard ownership or shutdown is unresolved; its attempt files were retained.")
  .brohn_publication_native_close(prepared)
  prepared$closed<-TRUE;prepared$committed<-committed
  rm(list=prepared$id,envir=.brohn_publication_handles)
  invisible(TRUE)
}

# Adapters validate domain-specific rows against these already sealed paths,
# outside SQL. Their small final JSON receives a second independently held guard.
.brohn_publication_output_identity <- function(output, loaded_hashes = list()) {
  expected<-c(list("R/platform-publication.R"=.brohn_publication_r_hash),loaded_hashes)
  expected[["scripts/workers/publication.py"]]<-digest::digest(file="scripts/workers/publication.py",algo="sha256")
  expected[["src/publication_guard.c"]]<-digest::digest(file="src/publication_guard.c",algo="sha256")
  brohn_require(all(vapply(names(expected),function(path)identical(output$code_identity[[path]],expected[[path]]) &&
    identical(digest::digest(file=path,algo="sha256"),expected[[path]]),logical(1))),
    "Publication requires the same frozen implementation that produced this output. Restart services after source changes.")
  invisible(TRUE)
}
.brohn_publication_stage <- function(store,job,specifications) {
  descriptors<-.brohn_publication_descriptors(store,specifications)
  guard<-brohn_prepare_publication(store,job,specifications)
  list(guard=guard,descriptors=descriptors,paths=setNames(vapply(guard$receipt$items,`[[`,character(1),"path"),
    vapply(guard$receipt$items,`[[`,character(1),"key")))
}
.brohn_publication_stage_json <- function(store,job,value,path) {
  brohn_require(!file.exists(path),"The final publication document already exists in this attempt.")
  brohn_write_json_file(value,path)
  .brohn_publication_stage(store,job,list(list(key="publication-result",kind="publication-result",path=normalizePath(path,winslash="/"),
    sha256=digest::digest(file=path,algo="sha256"),bytes=as.numeric(file.info(path)$size),media_type="application/json")))
}
.brohn_publication_register <- function(store,context) {
  observed<-brohn_commit_prepared_objects(store,context$guard)
  brohn_require(identical(brohn_hash(observed),brohn_hash(context$descriptors)),"Concurrent object registration changed frozen publication descriptors; retry with the current catalog.")
  observed
}
.brohn_publication_processing <- function(context) list(mode="staged-windows-parent-read-seal/1.0",native_seal=TRUE,
  native_build=context$guard$native$identity,artifact_count=length(context$descriptors),
  artifact_bytes=sum(vapply(context$descriptors,`[[`,numeric(1),"size")))
.brohn_publication_checkpoint <- function(store,job) {
  last_check<-as.numeric(Sys.time());last_renew<-last_check
  function(force=FALSE) {
    now<-as.numeric(Sys.time())
    if(force || now-last_check>=.25){.brohn_publication_job(store,job);last_check<<-now}
    if(now-last_renew>=15){brohn_renew_job(store,job$id,job$worker,job$token,60);last_renew<<-now}
    invisible(TRUE)
  }
}
