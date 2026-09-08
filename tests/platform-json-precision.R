# Exact JSON transport is distinct from numerical-method tolerance. Persisted
# catalog values must equal the values in the independently retained report.
source("R/platform-core.R");source("R/platform-store.R");source("R/platform-data-views.R")
local({
  checks<-0L;check<-function(label,value){if(!isTRUE(value))stop("JSON precision QA: ",label,call.=FALSE);checks<<-checks+1L}
  fails<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
  root<-tempfile("brohn-json-precision-");dir.create(root);root<-normalizePath(root,winslash="/")
  store<-brohn_open_store(root)
  on.exit({brohn_close_store(store);actual<-normalizePath(root,winslash="/",mustWork=FALSE)
    stopifnot(identical(dirname(actual),normalizePath(tempdir(),winslash="/")),startsWith(basename(actual),"brohn-json-precision-"));unlink(actual,recursive=TRUE,force=TRUE)},add=TRUE)
  values<-c(1/6,21.50111363073666,1.9999999999999982,.1,1+.Machine$double.eps,1-.Machine$double.eps,
    .Machine$double.xmin,.Machine$double.xmax,5e-324,1e-30,1e30,0,-1/6)
  randomized<-brohn_seeded(3129,function()stats::runif(512,-1,1)*10^stats::runif(512,-300,300))
  body<-list(values=as.list(c(values,randomized)),nested=list(list(probability=1/6,omitted=NULL,clock="9007199254740993")))
  decoded<-.brohn_store_decode(.brohn_store_json(body))
  actual<-vapply(decoded$values,as.double,numeric(1))
  check("525 ordinary extreme subnormal and random binary64 values survive exactly",identical(actual,c(values,randomized)))
  check("protocol and catalog encode the same numerical values",identical(brohn_hash(decoded),brohn_hash(brohn_parse(brohn_json(body)))))
  csv<-file.path(root,"original-numeric-observations.csv")
  brohn_export_report_csv(list(analysis=list(observations=lapply(c(values,randomized),function(v)list(value=v)))),csv)
  csv_values<-utils::read.csv(csv,colClasses="character",na.strings=character(),check.names=FALSE)$value
  check("machine observations CSV retains all525 exact numeric values",identical(as.numeric(csv_values),c(values,randomized)))
  check("adjacent representable numbers never collapse into the same JSON",length(unique(vapply(as.list(c(1-.Machine$double.eps,1,1+.Machine$double.eps)),.brohn_store_json,character(1))))==3L)
  created<-brohn_put_entity(store,"original_precision","original-report",body,operation_id="original-precision-save")
  envelope<-file.path(root,"original-envelope.json");writeLines(brohn_json(body),envelope)
  check("real catalog report equals the retained report envelope",identical(brohn_hash(created$body),brohn_hash(brohn_parse(paste(readLines(envelope),collapse="\n")))))
  check("new entity replay retains exact values and original revision",identical(created,brohn_put_entity(store,"original_precision","original-report",body,operation_id="original-precision-save")))
  changed<-body;changed$nested[[1]]$probability<-.166666666666667
  check("formerly rounded neighboring value is a different entity request",fails(brohn_put_entity(store,"original_precision","original-report",changed,operation_id="original-precision-save")))
  job<-brohn_enqueue_job(store,"original-precision",body,"original-precision-job")
  check("job request retains exact values",identical(brohn_hash(job$request),brohn_hash(body)))
  check("identical new job request deduplicates",brohn_enqueue_job(store,"original-precision",body,"original-precision-job")$id==job$id)
  check("rounded neighbor cannot reuse a new job identity",fails(brohn_enqueue_job(store,"original-precision",changed,"original-precision-job")))
  claimed<-brohn_claim_job(store,"precision-qa",60);finished<-brohn_complete_job(store,claimed$id,claimed$worker,claimed$token,body)
  check("completed job payload retains exact numerical evidence",identical(brohn_hash(finished$result),brohn_hash(body)))
  # Seed exact pre-correction bytes and hashes without replacing any existing
  # row. The immutable-row triggers remain active throughout this fixture.
  legacy_json<-'{"probability":0.166666666666667,"value":0.1}'
  legacy_hash<-.brohn_store_hash(charToRaw(legacy_json));stamp<-.brohn_store_stamp()
  legacy_request_hash<-.brohn_store_hash(charToRaw(.brohn_store_json(list(kind="original_precision",id="legacy-report",project_id="default",expected_revision=0L,body_hash=legacy_hash))))
  brohn_store_batch(store,function(){
    DBI::dbExecute(store$con,"INSERT INTO entities VALUES (?,?,?,?,?,?)",params=list("original_precision","legacy-report","default",1L,stamp,stamp))
    DBI::dbExecute(store$con,"INSERT INTO entity_versions VALUES (?,?,?,?,?,?,?,?)",params=list("original_precision","legacy-report",1L,"default",legacy_json,legacy_hash,stamp,stamp))
    DBI::dbExecute(store$con,"INSERT INTO entity_operations VALUES (?,?,?,?,?)",params=list("legacy-save",legacy_request_hash,"original_precision","legacy-report",1L))
    DBI::dbExecute(store$con,"INSERT INTO jobs (id,operation,request_json,request_hash,idempotency_key,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)",
      params=list("legacy-job","legacy-precision",legacy_json,legacy_hash,"legacy-precision-job","queued",stamp,stamp))
  })
  legacy<-brohn_get_entity(store,"original_precision","legacy-report")
  check("legacy JSON remains readable with its original stored hash",identical(legacy$body$probability,.166666666666667) && identical(legacy$body$value,.1))
  check("legacy entity replay accepts its exact retained values",identical(legacy,brohn_put_entity(store,"original_precision","legacy-report",legacy$body,operation_id="legacy-save")))
  brohn_put_entity(store,"original_precision","other-same-body",legacy$body)
  DBI::dbExecute(store$con,"INSERT INTO entity_operations VALUES (?,?,?,?,?)",params=list("original-misdirected-receipt",legacy_request_hash,"original_precision","other-same-body",1L))
  check("a redirected same-body operation receipt cannot return another record",fails(brohn_put_entity(store,"original_precision","legacy-report",legacy$body,operation_id="original-misdirected-receipt")))
  check("legacy replay cannot target a different record project or revision",fails(brohn_put_entity(store,"original_precision","new-id",legacy$body,operation_id="legacy-save")) &&
    fails(brohn_put_entity(store,"original_precision","legacy-report",legacy$body,project_id="another",operation_id="legacy-save")) &&
    fails(brohn_put_entity(store,"original_precision","legacy-report",legacy$body,expected_revision=1L,operation_id="legacy-save")))
  different<-legacy$body;different$probability<-1/6
  check("precision lost by historical serialization is never reconstructed or aliased",fails(brohn_put_entity(store,"original_precision","legacy-report",different,operation_id="legacy-save")))
  check("legacy queued job deduplicates its exact retained request",brohn_enqueue_job(store,"legacy-precision",legacy$body,"legacy-precision-job")$id=="legacy-job")
  check("legacy job replay refuses changed operation and formerly rounded values",fails(brohn_enqueue_job(store,"another-operation",legacy$body,"legacy-precision-job")) &&
    fails(brohn_enqueue_job(store,"legacy-precision",different,"legacy-precision-job")))
  # A single 0.1 spelling gains sixteen bytes. Keep a valid legacy request just
  # below the limit so its exact replay exceeds the NEW-write encoded limit.
  near_limit<-function(limit){base<-'{"padding":"","value":0.1}';sub('"padding":""',paste0('"padding":"',strrep("x",limit-nchar(base,type="bytes")-8L),'"'),base,fixed=TRUE)}
  near_job_json<-near_limit(4*1024^2);near_job_body<-.brohn_store_decode(near_job_json)
  near_job_hash<-.brohn_store_hash(charToRaw(near_job_json))
  DBI::dbExecute(store$con,"INSERT INTO jobs (id,operation,request_json,request_hash,idempotency_key,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)",
    params=list("legacy-limit-job","legacy-limit",near_job_json,near_job_hash,"legacy-limit-key","queued",stamp,stamp))
  check("near-limit historical job replay tolerates expanded decimal spelling without a new write",brohn_enqueue_job(store,"legacy-limit",near_job_body,"legacy-limit-key")$id=="legacy-limit-job" &&
    fails(brohn_enqueue_job(store,"legacy-limit",near_job_body,"new-limit-key")))
  near_entity_json<-near_limit(16*1024^2);near_entity_body<-.brohn_store_decode(near_entity_json);near_entity_hash<-.brohn_store_hash(charToRaw(near_entity_json))
  near_request_hash<-.brohn_store_hash(charToRaw(.brohn_store_json(list(kind="original_precision",id="legacy-limit-entity",project_id="default",expected_revision=0L,body_hash=near_entity_hash))))
  brohn_store_batch(store,function(){
    DBI::dbExecute(store$con,"INSERT INTO entities VALUES (?,?,?,?,?,?)",params=list("original_precision","legacy-limit-entity","default",1L,stamp,stamp))
    DBI::dbExecute(store$con,"INSERT INTO entity_versions VALUES (?,?,?,?,?,?,?,?)",params=list("original_precision","legacy-limit-entity",1L,"default",near_entity_json,near_entity_hash,stamp,stamp))
    DBI::dbExecute(store$con,"INSERT INTO entity_operations VALUES (?,?,?,?,?)",params=list("legacy-limit-save",near_request_hash,"original_precision","legacy-limit-entity",1L))
  })
  check("near-limit historical entity replay retains its old bytes",brohn_put_entity(store,"original_precision","legacy-limit-entity",near_entity_body,operation_id="legacy-limit-save")$revision==1L &&
    identical(DBI::dbGetQuery(store$con,"SELECT body_json FROM entity_versions WHERE id='legacy-limit-entity'")$body_json[[1]],near_entity_json))
  check("comparison allowance cannot create oversized new revisions or operations",fails(brohn_put_entity(store,"original_precision","legacy-limit-entity",near_entity_body,expected_revision=1L,operation_id="new-large-save")) &&
    fails(brohn_put_entity(store,"original_precision","new-large-entity",near_entity_body,operation_id="new-large-record")))
  row<-DBI::dbGetQuery(store$con,"SELECT body_json,body_hash FROM entity_versions WHERE id='legacy-report'")
  check("compatibility replay never rewrites legacy JSON or hashes",identical(row$body_json[[1]],legacy_json) && identical(row$body_hash[[1]],legacy_hash) && length(brohn_entity_history(store,"original_precision","legacy-report"))==1L)
  latest<-brohn_put_entity(store,"original_precision","legacy-report",different,expected_revision=1L)
  check("deliberate new revision preserves new precision and historical evidence",latest$revision==2L && identical(latest$body$probability,1/6) && identical(brohn_get_entity(store,"original_precision","legacy-report",1L)$body,legacy$body))
  brohn_close_store(store);store<-brohn_open_store(root)
  check("mixed precision history and exact new reports survive reopen",identical(brohn_hash(brohn_get_entity(store,"original_precision","original-report")$body),brohn_hash(body)) &&
    identical(brohn_get_entity(store,"original_precision","legacy-report",1L)$body,legacy$body) && identical(brohn_get_entity(store,"original_precision","legacy-report")$body$probability,1/6))
  cat(sprintf("PASS: %d exact numeric transport and legacy record/replay checks.\n",checks))
})
