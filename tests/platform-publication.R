# Isolated Windows seals and metadata fencing using the actual owned Python
# helper. No production publishers call this new module until reviewed.
for(module in c("platform-core","platform-store","platform-publication"))source(paste0("R/",module,".R"),encoding="UTF-8")
local({
  root<-tempfile("brohn-publication-qa-");dir.create(root);root<-normalizePath(root,winslash="/")
  store<-brohn_open_store(file.path(root,"workspace"));handles<-list();checks<-0L
  on.exit({
    for(h in handles)try(brohn_close_publication(h),silent=TRUE)
    brohn_close_store(store)
    actual<-normalizePath(root,winslash="/",mustWork=FALSE)
    stopifnot(startsWith(tolower(actual),paste0(tolower(normalizePath(tempdir(),winslash="/")),"/")),startsWith(basename(actual),"brohn-publication-qa-"))
    Sys.chmod(list.files(actual,recursive=TRUE,full.names=TRUE,all.files=TRUE),"0666");unlink(actual,recursive=TRUE,force=TRUE)
  },add=TRUE)
  check<-function(name,ok){if(!isTRUE(ok))stop("Publication QA: ",name);checks<<-checks+1L}
  fails<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
  source_file<-function(label,bytes=charToRaw(paste(rep("Original publication fixture\n",1024),collapse=""))) {
    path<-file.path(store$root,paste0(label,".bin"));writeBin(bytes,path)
    list(key=label,kind="original-fixture",path=normalizePath(path,winslash="/"),sha256=digest::digest(file=path,algo="sha256"),bytes=as.numeric(file.info(path)$size),media_type="application/octet-stream")
  }
  job<-function(label) {
    q<-brohn_enqueue_job(store,"original-publication-fixture",list(label=label,origin="sample"),label)
    claim<-brohn_claim_job(store,paste0("fixture-",label),60);stopifnot(identical(q$id,claim$id));claim
  }
  prepare<-function(j,specs) {h<-brohn_prepare_publication(store,j,specs,timeout_seconds=30);handles[[length(handles)+1L]]<<-h;h}
  count<-function()DBI::dbGetQuery(store$con,"SELECT count(*) AS n FROM objects")$n[[1]]
  complete<-function(j,h,id)brohn_store_batch(store,function(){objects<-brohn_commit_prepared_objects(store,h);brohn_put_entity(store,"fixture_report",id,list(objects=objects));brohn_complete_job(store,j$id,j$worker,j$token,list(report_id=id));objects})
  original<-source_file("original");j<-job("original")
  check("preparation refuses an enclosing writer transaction",fails(brohn_store_batch(store,function()brohn_prepare_publication(store,j,list(original)))))
  check("refused staging creates no metadata",count()==0L)
  h<-prepare(j,list(original));sealed<-h$receipt$items[[1]]$path
  check("actual helper returns a held exact-content seal",h$child$is_alive() && identical(h$receipt$seal,"windows-share-read-deny-write-delete/1.0") &&
    h$receipt$items[[1]]$sha256==original$sha256 && h$receipt$items[[1]]$bytes==original$bytes)
  check("preparing alone registers no object or report",count()==0L && length(brohn_list_entities(store,"fixture_report"))==0L && fails(brohn_object_path(store,original$sha256)))
  # Remove the read-only attribute first: denial below must come from the held
  # native share mode, not an attribute that another program could change.
  mutate<-function(operation,target=sealed)processx::run(.brohn_publication_python(),c("-c",
    "import os,sys,stat; p=sys.argv[1]; op=sys.argv[2]; os.chmod(p,stat.S_IREAD|stat.S_IWRITE); replacement=p+'.replacement';\ntry:\n if op=='write':\n  f=open(p,'r+b'); f.write(b'X'); f.close()\n elif op=='replace':\n  open(replacement,'wb').write(b'original replacement'); os.replace(replacement,p)\n elif op=='delete': os.unlink(p)\n else: raise ValueError('unsupported')\nexcept PermissionError: print('denied'); sys.exit(0)\nfinally:\n if os.path.exists(replacement): os.unlink(replacement)\nprint('unexpected mutation');sys.exit(3)",target,operation),timeout=10,error_on_status=FALSE,windows_hide_window=TRUE)
  check("same-size overwrite denied despite writable attributes",mutate("write")$status==0L)
  check("path substitution denied by native seal",mutate("replace")$status==0L)
  check("deletion denied by native seal",mutate("delete")$status==0L)
  directory_probe<-processx::run(.brohn_publication_python(),c("-c",
    "import os,sys; p=os.path.dirname(sys.argv[1]); moved=p+'.original-rename-probe';\ntry:\n os.rename(p,moved)\nexcept PermissionError: print('directory rename denied');sys.exit(0)\nelse:\n os.rename(moved,p);print('directory rename was allowed');sys.exit(3)",sealed),timeout=10,error_on_status=FALSE,windows_hide_window=TRUE)
  check("sealed file prevents swapping its parent hash directory",directory_probe$status==0L)
  check("registration refuses absence of final transaction",fails(brohn_commit_prepared_objects(store,h)))
  foreign<-brohn_open_store(file.path(root,"another-workspace"))
  check("sealed handle cannot register into another workspace",fails(brohn_store_batch(foreign,function()brohn_commit_prepared_objects(foreign,h))) &&
    DBI::dbGetQuery(foreign$con,"SELECT count(*) AS n FROM objects")$n[[1]]==0L)
  brohn_close_store(foreign)
  objects<-complete(j,h,"original-report")
  check("short metadata transaction publishes exact handle and completes job",count()==1L && identical(objects[[1]]$hash,original$sha256) && brohn_get_job(store,j$id)$status=="succeeded")
  brohn_close_publication(h,committed=TRUE)
  check("committed release stops only its guard process",!h$child$is_alive() && isTRUE(h$closed) && fails(brohn_store_batch(store,function()brohn_commit_prepared_objects(store,h))))
  check("registered bytes remain independently readable after release",identical(digest::digest(file=brohn_object_path(store,original$sha256),algo="sha256"),original$sha256))
  # Two exact-byte publishers hold compatible read seals and deduplicate their
  # metadata without releasing one another's protection.
  a<-job("same-a");b<-job("same-b");ha<-prepare(a,list(original));hb<-prepare(b,list(original))
  complete(a,ha,"same-a-report");brohn_close_publication(ha,committed=TRUE)
  check("one publisher closing does not release another publisher's seal",hb$child$is_alive() && mutate("write",hb$receipt$items[[1]]$path)$status==0L)
  complete(b,hb,"same-b-report");brohn_close_publication(hb,committed=TRUE)
  check("two identical publishers share one registered object",count()==1L && length(brohn_list_entities(store,"fixture_report"))==3L)
  other<-source_file("cancelled",charToRaw("Original cancelled artifact"));cancel<-job("cancelled");hc<-prepare(cancel,list(other))
  brohn_cancel_job(store,cancel$id)
  check("cancellation after staging refuses all metadata publication",fails(complete(cancel,hc,"cancelled-report")) && count()==1L && is.null(brohn_get_entity(store,"fixture_report","cancelled-report")))
  brohn_close_publication(hc)
  check("cancelled original is retained as unregistered verified orphan",file.exists(file.path(store$root,"objects","sha256",substr(other$sha256,1,2),other$sha256)) && fails(brohn_object_path(store,other$sha256)))
  # Expire the recorded lease, then reclaim through the real store API. No
  # publication or claim function is mocked and the new fencing token is real.
  stale<-job("stale");hs<-prepare(stale,list(other));DBI::dbExecute(store$con,"UPDATE jobs SET lease_until=? WHERE id=?",params=list(as.numeric(Sys.time())-1,stale$id))
  fresh<-brohn_claim_job(store,"new-owner",60)
  check("reclaim creates a new fencing token and attempt",fresh$id==stale$id && fresh$attempt==stale$attempt+1L && fresh$token!=stale$token)
  check("superseded guard cannot publish despite live held file",fails(complete(stale,hs,"stale-report")) && count()==1L)
  brohn_close_publication(hs);brohn_cancel_job(store,fresh$id)
  retry_job<-job("orphan-reconcile");hr<-prepare(retry_job,list(other));complete(retry_job,hr,"reconciled-report");brohn_close_publication(hr,committed=TRUE)
  check("verified orphan can be reconciled by a new fenced attempt",count()==2L && identical(digest::digest(file=brohn_object_path(store,other$sha256),algo="sha256"),other$sha256))
  first<-source_file("rollback-a",charToRaw("Original rollback A"));second<-source_file("rollback-b",charToRaw("Original rollback B"))
  rollback<-job("rollback");hh<-prepare(rollback,list(first,second));before<-count()
  check("multi-object registration rolls back with the enclosing report",fails(brohn_store_batch(store,function(){brohn_commit_prepared_objects(store,hh);brohn_put_entity(store,"fixture_report","rolled-back",list(original=TRUE));stop("Original controlled rollback")})) && count()==before && is.null(brohn_get_entity(store,"fixture_report","rolled-back")))
  brohn_close_publication(hh);brohn_cancel_job(store,rollback$id)
  check("rollback leaves complete unregistered objects rather than partial catalog",all(vapply(c(first$sha256,second$sha256),function(hash)file.exists(file.path(store$root,"objects","sha256",substr(hash,1,2),hash)) && fails(brohn_object_path(store,hash)),logical(1))))
  crash<-job("guard-crash");hg<-prepare(crash,list(first));hg$child$kill_tree();hg$child$wait(2000)
  check("a crashed seal owner cannot register metadata",fails(complete(crash,hg,"crashed-report")) && count()==before)
  brohn_close_publication(hg);brohn_cancel_job(store,crash$id)
  launcher_job<-job("launcher-only-crash");hl<-prepare(launcher_job,list(first))
  check("Windows venv guard is tracked independently of launcher",hl$guard_pid!=hl$pid && .brohn_publication_probe_guard(hl)=="owned_alive")
  ps::ps_kill(ps::ps_handle(hl$pid,as.POSIXct(hl$created,origin="1970-01-01",tz="UTC")))
  Sys.sleep(.02)
  remaining_guard<-.brohn_publication_probe_guard(hl)
  check("launcher-only exit cannot make sealed bytes publishable",remaining_guard %in% c("owned_alive","absent") && fails(complete(launcher_job,hl,"launcher-crashed-report")))
  cat("Launcher-only native termination left guard:",remaining_guard,"\n")
  brohn_close_publication(hl)
  check("close releases the exact remembered orphan guard",.brohn_publication_probe_guard(hl)=="absent" && isTRUE(hl$closed))
  brohn_cancel_job(store,launcher_job$id)
  receipt_job<-job("receipt-change");hp<-prepare(receipt_job,list(first));writeLines("{}",hp$receipt_path)
  check("changed sealed receipt cannot register metadata",fails(complete(receipt_job,hp,"tampered-receipt-report")) && count()==before)
  brohn_close_publication(hp);brohn_cancel_job(store,receipt_job$id)
  bad<-source_file("wrong-hash",charToRaw("Original hash mismatch"));bad$sha256<-paste(rep("0",64),collapse="");bad_job<-job("wrong-hash")
  check("unmatched source hash fails before any metadata",fails(brohn_prepare_publication(store,bad_job,list(bad),30)) && count()==before)
  brohn_cancel_job(store,bad_job$id)
  # Cancellation from another original process arrives during real copying.
  # The parent remains able to observe it because preparation holds no SQL lock.
  large_path<-file.path(store$root,"original-cancel-during-copy.bin");chunk<-rep(as.raw(0:255),4096)
  con<-file(large_path,"wb");for(i in seq_len(64))writeBin(chunk,con);close(con)
  large<-list(key="cancel-during-copy",kind="original-fixture",path=normalizePath(large_path,winslash="/"),
    sha256=digest::digest(file=large_path,algo="sha256"),bytes=as.numeric(file.info(large_path)$size),media_type="application/octet-stream")
  during<-job("cancel-during-copy");observer_request<-list(operation="cancel",workspace=store$root,job_id=during$id,
    ready=file.path(root,"cancel-observer-ready"),output=file.path(root,"cancel-observer-result"))
  observer_path<-file.path(root,"cancel-observer.rds");saveRDS(observer_request,observer_path)
  observer<-processx::process$new(file.path(R.home("bin"),"Rscript.exe"),c("--vanilla","tests/fixtures/platform-publication-observer.R",observer_path),
    env=c("current",R_LIBS_USER=paste(.libPaths(),collapse=.Platform$path.sep)),stdout="|",stderr="|",cleanup_tree=TRUE,windows_hide_window=TRUE)
  on.exit(if(observer$is_alive())observer$kill_tree(),add=TRUE)
  deadline<-as.numeric(Sys.time())+15
  while(!file.exists(observer_request$ready)){if(as.numeric(Sys.time())>deadline||!observer$is_alive())stop(observer$read_all_error());Sys.sleep(.01)}
  denied<-fails(brohn_prepare_publication(store,during,list(large),30));observer$wait(5000)
  check("cancellation during real preparation is observed without metadata publication",denied && identical(observer$get_exit_status(),0L) &&
    readRDS(observer_request$output)$status=="cancelled" && brohn_get_job(store,during$id)$status=="cancelled" && count()==before)
  check("cancelled preparation preserves the whole original input",identical(digest::digest(file=large_path,algo="sha256"),large$sha256))
  check("stopped cancellation leaves no attempt-owned bulk copy fragment",length(list.files(file.path(store$root,"scratch","publication"),pattern="\\.object-pending$",recursive=TRUE))==0L)
  crash_path<-file.path(store$root,"original-crash-during-copy.bin")
  con<-file(crash_path,"wb");for(i in seq_len(256))writeBin(chunk,con);close(con)
  crash_spec<-list(key="crash-during-copy",kind="original-fixture",path=normalizePath(crash_path,winslash="/"),
    sha256=digest::digest(file=crash_path,algo="sha256"),bytes=as.numeric(file.info(crash_path)$size),media_type="application/octet-stream")
  copying<-job("crash-during-copy");observer_request<-list(operation="crash",workspace=store$root,job_id=copying$id,
    ready=file.path(root,"crash-observer-ready"),output=file.path(root,"crash-observer-result"))
  observer_path<-file.path(root,"crash-observer.rds");saveRDS(observer_request,observer_path)
  observer<-processx::process$new(file.path(R.home("bin"),"Rscript.exe"),c("--vanilla","tests/fixtures/platform-publication-observer.R",observer_path),
    env=c("current",R_LIBS_USER=paste(.libPaths(),collapse=.Platform$path.sep)),stdout="|",stderr="|",cleanup_tree=TRUE,windows_hide_window=TRUE)
  deadline<-as.numeric(Sys.time())+15
  while(!file.exists(observer_request$ready)){if(as.numeric(Sys.time())>deadline||!observer$is_alive())stop(observer$read_all_error());Sys.sleep(.01)}
  denied<-fails(brohn_prepare_publication(store,copying,list(crash_spec),30));observer$wait(5000)
  if(!identical(observer$get_exit_status(),0L))stop(observer$read_all_error())
  crash_evidence<-readRDS(observer_request$output)
  check("owned process crash occurs with a real partial copy",denied&&identical(crash_evidence$status,"owned_guard_killed")&&crash_evidence$fragment_bytes_before>0&&count()==before)
  check("confirmed crashed copy removes only its owned partial bytes",!length(list.files(crash_evidence$directory,pattern="\\.object-pending$"))&&
    file.exists(file.path(crash_evidence$directory,"request.json"))&&identical(digest::digest(file=crash_path,algo="sha256"),crash_spec$sha256))
  brohn_cancel_job(store,copying$id)
  # The adversarial failure occurs after registration, inside the real outer
  # transaction. Child liveness polling cannot protect this interval: parent
  # native handles must deny mutation through the eventual SQLite COMMIT.
  mid_job<-job("helper-exits-after-registration");mid<-prepare(mid_job,list(first))
  mid_objects<-brohn_store_batch(store,function(){
    objects<-brohn_commit_prepared_objects(store,mid)
    mid$child$kill_tree();mid$child$wait(2000)
    check("helper exit after registration leaves parent guard alive",!mid$child$is_alive() && isTRUE(.Call(mid$native$check,mid$native_pointer)))
    check("parent guard alone denies same-size overwrite inside transaction",mutate("write",mid$receipt$items[[1]]$path)$status==0L)
    check("parent guard alone denies path substitution inside transaction",mutate("replace",mid$receipt$items[[1]]$path)$status==0L)
    check("public close cannot release parent guards inside transaction",fails(brohn_close_publication(mid)))
    brohn_put_entity(store,"fixture_report","parent-held-report",list(objects=objects))
    brohn_complete_job(store,mid_job$id,mid_job$worker,mid_job$token,list(report_id="parent-held-report"))
    objects
  })
  check("helper death after registration commits only protected exact bytes",brohn_get_job(store,mid_job$id)$status=="succeeded" &&
    identical(digest::digest(file=brohn_object_path(store,first$sha256),algo="sha256"),first$sha256))
  brohn_close_publication(mid,committed=TRUE)
  check("parent native guard closes exactly once after commit",is.null(mid$native_pointer) && isTRUE(brohn_close_publication(mid,committed=TRUE)))
  saved<-brohn_get_entity(store,"fixture_report","original-report")$body
  brohn_close_store(store);store<-brohn_open_store(file.path(root,"workspace"))
  check("reopen preserves frozen report and full object bytes",identical(brohn_get_entity(store,"fixture_report","original-report")$body,saved) &&
    identical(digest::digest(file=brohn_object_path(store,original$sha256),algo="sha256"),original$sha256))
  cat("Prepared publication:",checks,"scoped checks passed.\n")
})
