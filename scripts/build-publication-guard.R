# Explicit local build. No toolchain installation or download occurs here.
local({
  args<-commandArgs(trailingOnly=TRUE)
  compiler<-normalizePath(if(length(args))args[[1]] else "../../work/tooling/tinycc-0.9.27/tcc/tcc.exe",winslash="/",mustWork=TRUE)
  directory<-if(length(args)>1L)args[[2]] else "../../work/tooling/brohn-native"
  stopifnot(.Platform$OS.type=="windows",.Machine$sizeof.pointer==8L)
  dir.create(directory,recursive=TRUE,showWarnings=FALSE)
  directory<-normalizePath(directory,winslash="/",mustWork=TRUE)
  source_path<-normalizePath("src/publication_guard.c",winslash="/",mustWork=TRUE)
  sha<-function(path)digest::digest(file=path,algo="sha256")
  inventory<-function(root) {
    root<-normalizePath(root,winslash="/",mustWork=TRUE)
    paths<-sort(list.files(root,recursive=TRUE,full.names=TRUE,all.files=TRUE,no..=TRUE))
    paths<-paths[!dir.exists(paths)]
    stopifnot(length(paths)>0L,length(paths)<10000L)
    setNames(lapply(paths,sha),substring(paths,nchar(root)+2L))
  }
  source_hash<-sha(source_path)
  canonical<-function(x) {
    if(!is.list(x))return(x)
    if(!is.null(names(x)))x<-x[order(names(x),method="radix")]
    lapply(x,canonical)
  }
  inputs<-list(source_sha256=source_hash,r_version=as.character(getRversion()),architecture=R.version$arch,
    pointer_bytes=.Machine$sizeof.pointer,r_dll_sha256=sha(file.path(R.home("bin"),"R.dll")),
    r_headers=inventory(R.home("include")),compiler_sha256=sha(compiler),compiler_distribution=inventory(dirname(compiler)))
  inputs<-canonical(inputs)
  encoded<-jsonlite::toJSON(inputs,auto_unbox=TRUE,null="null",digits=NA)
  build_key<-digest::digest(charToRaw(enc2utf8(encoded)),algo="sha256",serialize=FALSE)
  target<-file.path(directory,paste0("publication_guard-",build_key,".dll"))
  record_path<-file.path(directory,paste0("publication_guard-",build_key,".json"))
  pointer_path<-file.path(directory,"publication-guard.json")
  read_manifest<-function(path) {
    stopifnot(file.exists(path),file.info(path)$size<=1024^2)
    jsonlite::fromJSON(path,simplifyVector=FALSE)
  }
  same_inputs<-function(manifest) identical(jsonlite::toJSON(manifest$build_inputs,auto_unbox=TRUE,null="null",digits=NA),encoded)
  verify_load<-function(path) {
    dll<-dyn.load(path,local=TRUE);on.exit(dyn.unload(path),add=TRUE)
    for(symbol in c("brohn_guard_open","brohn_guard_check","brohn_guard_close"))getNativeSymbolInfo(symbol,PACKAGE=dll)
  }
  if(file.exists(target)||file.exists(record_path)) {
    # Never relabel old or partial bytes with a new build identity.
    manifest<-read_manifest(record_path)
    stopifnot(file.exists(target),identical(manifest$build_key,build_key),same_inputs(manifest),
      identical(manifest$dll,basename(target)),identical(manifest$dll_sha256,sha(target)))
    verify_load(target)
  } else {
    pending<-tempfile(".publication-build-",tmpdir=directory);stopifnot(dir.create(pending))
    pending<-normalizePath(pending,winslash="/",mustWork=TRUE)
    on.exit({
      actual<-normalizePath(pending,winslash="/",mustWork=FALSE)
      stopifnot(identical(dirname(actual),directory),startsWith(basename(actual),".publication-build-"))
      unlink(actual,recursive=TRUE,force=TRUE)
    },add=TRUE)
    temporary_dll<-file.path(pending,"publication_guard.dll")
    build<-processx::run(compiler,c("-shared",paste0("-I",R.home("include")),paste0("-L",R.home("bin")),paste0("-o",temporary_dll),source_path,"-lR","-lkernel32"),
      timeout=60,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE)
    if(isTRUE(build$timeout)||build$status!=0L)stop("Native guard build failed: ",build$stderr)
    stopifnot(file.exists(temporary_dll));verify_load(temporary_dll)
    # A concurrently edited compiler, header or C source cannot acquire this
    # frozen build identity.
    stopifnot(identical(sha(source_path),source_hash),identical(canonical(inventory(R.home("include"))),inputs$r_headers),
      identical(canonical(inventory(dirname(compiler))),inputs$compiler_distribution),identical(sha(file.path(R.home("bin"),"R.dll")),inputs$r_dll_sha256))
    archive<-"../../work/tooling/tcc-0.9.27-win64-bin.zip"
    manifest<-list(schema="brohn-native-publication-build/1.0",source="src/publication_guard.c",source_sha256=source_hash,
      dll=basename(target),dll_sha256=sha(temporary_dll),r_version=as.character(getRversion()),architecture=R.version$arch,
      build_key=build_key,build_inputs=inputs,compiler="TinyCC 0.9.27 win64",compiler_sha256=sha(compiler),
      compiler_archive_sha256=if(file.exists(archive))sha(archive) else NULL,
      compiler_source="https://download.savannah.gnu.org/releases/tinycc/tcc-0.9.27-win64-bin.zip")
    temporary_manifest<-file.path(pending,"publication_guard.json")
    jsonlite::write_json(manifest,temporary_manifest,auto_unbox=TRUE,pretty=TRUE,null="null",digits=NA)
    # Windows file.rename refuses an existing destination. Never replace a
    # concurrently built or currently loaded DLL.
    stopifnot(!file.exists(target),!file.exists(record_path),file.rename(temporary_dll,target),file.rename(temporary_manifest,record_path))
  }
  # The small active pointer is advisory. The immutable per-build manifest and
  # DLL are complete first; interruption here makes readiness fail safely.
  pointer_pending<-tempfile(".publication-pointer-",tmpdir=directory)
  on.exit(if(file.exists(pointer_pending))unlink(pointer_pending),add=TRUE)
  jsonlite::write_json(manifest,pointer_pending,auto_unbox=TRUE,pretty=TRUE,null="null",digits=NA)
  if(file.exists(pointer_path))stopifnot(unlink(pointer_path)==0L)
  stopifnot(file.rename(pointer_pending,pointer_path))
  cat("Verified parent-owned publication guard build:",target,"\n")
})
