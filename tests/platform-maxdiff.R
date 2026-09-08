source("R/platform-core.R", encoding = "UTF-8")
source("R/platform-maxdiff.R", encoding = "UTF-8")
local({
  checks <- 0L
  check <- function(name, value) {if (!isTRUE(value)) stop("MaxDiff QA: ", name, call. = FALSE); checks <<- checks+1L}
  rejects <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  close <- function(a, b, tolerance = 1e-7) isTRUE(all.equal(a, b, tolerance = tolerance, check.attributes = FALSE))
  d <- brohn_maxdiff_new(id = "choice-example")
  review <- brohn_maxdiff_design_review(d)
  check("original four-item design has exact balanced item/pair counts", review$connected && review$equal_item_frequency && review$equal_pair_frequency &&
    all(vapply(review$item_coverage, function(i) i$presentations == 3L, logical(1))) && all(vapply(review$pair_coverage, function(i) i$cooccurrences == 2L, logical(1))))
  set.seed(17); previous <- .Random.seed; a <- brohn_maxdiff_compile(d, 17); b <- brohn_maxdiff_compile(d, 17)
  check("allocation is reproducible without mutating global random state", identical(a, b) && identical(previous, .Random.seed))
  check("actual frozen order retains every set and original member", setequal(vapply(a$trials, `[[`, character(1), "set_id"), brohn_ids(d$sets)) &&
    all(vapply(a$trials, function(t) setequal(unlist(t$item_order), unlist(brohn_find(d$sets, t$set_id)$item_ids)), logical(1))))
  fixed <- d; fixed$settings$set_order <- "fixed"; fixed$settings$item_order <- "fixed"
  check("fixed order stays explicit with position warning", identical(brohn_maxdiff_compile(fixed)$trials[[1L]]$item_order, fixed$sets[[1L]]$item_ids) &&
    any(grepl("Fixed item positions", unlist(brohn_maxdiff_design_review(fixed)$warnings), fixed = TRUE)))
  bad <- d; bad$sets[[1L]]$item_ids[[1L]] <- bad$sets[[1L]]$item_ids[[2L]]
  check("duplicate offered item rejected", rejects(brohn_maxdiff_validate(bad)))
  bad <- d; bad$sets[[1L]]$item_ids[[1L]] <- "unknown"
  check("unknown offered item rejected", rejects(brohn_maxdiff_validate(bad)))
  bad <- d; bad$sets[[1L]]$item_ids <- head(bad$sets[[1L]]$item_ids, 2)
  check("two-item shortcut is outside the object-case serving profile", rejects(brohn_maxdiff_compile(bad)))
  missing <- d; missing$sets <- list(d$sets[[1L]])
  check("missing design item stays diagnosed and cannot be served", !brohn_maxdiff_design_review(missing)$all_items_present && rejects(brohn_maxdiff_compile(missing)))
  d$items <- head(d$items, 3); d$sets <- list(list(id = "all-three", item_ids = as.list(brohn_ids(d$items))))
  response <- function(design, index, best, worst, set_id = design$sets[[1L]]$id, person = paste0("p-", ceiling(index/3)), session = "visit", exposure = paste0("occurrence-", index))
    list(id = paste0("response-", index), participant_id = person, participant_linkage = TRUE, session_id = session, exposure_id = exposure,
      design_hash = brohn_hash(design), set_id = set_id, item_order = brohn_find(design$sets, set_id)$item_ids,
      presented = TRUE, status = "answered", best_id = best, worst_id = worst, missing_reason = NULL)
  # Independent exact multinomial oracle: u=(log2,0,-log2) produces ordered
  # pair weights(8,16,2,8,1,2), denominator37. Repeat each pair that many times.
  pairs <- list(c(1,2), c(1,3), c(2,1), c(2,3), c(3,1), c(3,2)); counts <- c(8L,16L,2L,8L,1L,2L)
  rows <- list()
  for (i in seq_along(pairs)) for (j in seq_len(counts[[i]])) rows[[length(rows)+1L]] <- response(d, length(rows)+1L, paste0("item-", pairs[[i]][[1L]]), paste0("item-", pairs[[i]][[2L]]))
  source <- list(hash = paste(rep("a", 64), collapse = ""), origin = "sample")
  result <- brohn_maxdiff_analysis(d, rows, source)
  check("best-worst count oracle is21,0,-21 over37actual answered exposures", identical(vapply(result$items, `[[`, numeric(1), "best_minus_worst"), c(21,0,-21)) &&
    close(vapply(result$items, `[[`, numeric(1), "exposure_adjusted_score"), c(21,0,-21)/37))
  likelihood <- brohn_maxdiff_likelihood(d, rows, c(2*log(2),log(2)), TRUE)
  expected_nll <- 37*log(37)-sum(counts*log(counts))
  check("exact paired likelihood agrees with independent37-outcome arithmetic", close(likelihood$negative_log_likelihood, expected_nll) && max(abs(likelihood$gradient)) < 1e-10)
  check("paired denominator has six distinct ordered alternatives", length(likelihood$probabilities[[1L]]$alternatives) == 6L &&
    close(sum(vapply(likelihood$probabilities[[1L]]$alternatives, `[[`, numeric(1), "probability")), 1))
  check("aggregate MLE recovers independent sum-zero log2,0,-log2 utilities", result$model$status == "estimated" &&
    close(vapply(result$model$utilities, `[[`, numeric(1), "utility"), c(log(2),0,-log(2)), 1e-6))
  permuted <- d; permuted$items <- rev(permuted$items)
  pr <- lapply(rows,function(r){r$design_hash<-brohn_hash(permuted);r})
  check("reference/item storage order does not change named relative utilities", close(rev(vapply(brohn_maxdiff_analysis(permuted,pr)$model$utilities,`[[`,numeric(1),"utility")),
    vapply(result$model$utilities,`[[`,numeric(1),"utility"),1e-6))
  check("fit reports no individual utility or independent-trial population uncertainty", !result$quality$participant_inference_performed &&
    !result$quality$individual_utilities && all(vapply(result$model$utilities, function(u) is.null(u$standard_error), logical(1))))
  check("source design and full responses remain hash-bound and unchanged", identical(result$source, source) && identical(result$design_hash, brohn_hash(d)) &&
    identical(result$responses_hash, brohn_hash(rows)) && identical(result$exposures, rows))
  check("multiple choices from one person are not counted as new participants", result$quality$participant_count == 13L && result$quality$session_count == 13L && result$quality$repeated_set_exposures == 24L)
  anonymous <- lapply(rows,function(r){r$participant_linkage<-FALSE;r})
  ar <- brohn_maxdiff_analysis(d,anonymous)
  check("anonymous runner identifiers cannot become unique-person counts", is.null(ar$quality$participant_count) && ar$quality$participant_linkage == "unavailable" &&
    ar$quality$session_count == 13L && ar$model$status == "estimated")
  mixed <- rows; mixed[[1L]]$participant_linkage <- FALSE
  check("partial linkage withholds a whole-source person count", is.null(brohn_maxdiff_analysis(d,mixed)$quality$participant_count) && brohn_maxdiff_analysis(d,mixed)$quality$participant_linkage == "mixed")
  invalid_link <- rows; invalid_link[[1L]]$participant_linkage <- 1L
  check("linkage is a strict source boolean rather than a coerced numeric flag", rejects(brohn_maxdiff_analysis(d,invalid_link)))
  extreme <- brohn_maxdiff_likelihood(d, rows, c(700,-700))
  check("log-sum-exp remains finite at extreme utilities", is.finite(extreme$negative_log_likelihood) && all(is.finite(extreme$gradient)))
  beta <- c(.3,-.4); h <- 1e-5; grad <- brohn_maxdiff_likelihood(d, rows, beta)$gradient
  numerical <- vapply(1:2, function(i) {offset <- c(0,0); offset[[i]] <- h
    (brohn_maxdiff_likelihood(d,rows,beta+offset)$negative_log_likelihood-brohn_maxdiff_likelihood(d,rows,beta-offset)$negative_log_likelihood)/(2*h)}, numeric(1))
  check("analytic paired gradient agrees with independently differenced likelihood", close(grad, numerical, 1e-7))
  check("iteration exhaustion is explicit with no fallback utility", identical(brohn_maxdiff_fit(d,rows,maximum_iterations=1L)$reason,"nonconvergence"))
  lost <- response(d, 38, "item-1", NULL); lost$status <- "missing"; lost$missing_reason <- "participant_left_after_best"
  skipped <- response(d, 39, NULL, NULL); skipped$status <- "not_presented"; skipped$presented <- FALSE; skipped$missing_reason <- "session_withdrawal_before_presentation"
  partial <- brohn_maxdiff_analysis(d, c(rows,list(lost,skipped)), source)
  check("incomplete pairs preserve evidence without scoring a partial best or treating missing as zero", all(vapply(partial$items, function(i)
    i$presented_exposures == 38L && i$answered_exposures == 37L && i$missing_exposures == 1L, logical(1))) &&
    identical(vapply(partial$items, `[[`, numeric(1), "exposure_adjusted_score"), vapply(result$items, `[[`, numeric(1), "exposure_adjusted_score")) && partial$exposures[[38L]]$best_id == "item-1")
  check("unpresented rows remain separate from actual presentation denominators", partial$quality$exposure_records == 39 && partial$quality$presented_exposures == 38)
  unequal <- brohn_maxdiff_new(); unequal$settings$analysis$fit_aggregate <- FALSE
  ur <- list(response(unequal,1,"item-2","item-4","set-1"),response(unequal,2,"item-2","item-4","set-1"),response(unequal,3,"item-1","item-4","set-2"))
  un <- brohn_maxdiff_analysis(unequal,ur)
  check("unequal actual item exposure uses each item's own denominator", identical(vapply(un$items,`[[`,numeric(1),"answered_exposures"),c(1,2,3,3)) &&
    close(vapply(un$items,`[[`,numeric(1),"exposure_adjusted_score"),c(1,1,0,-1)))
  for (value in list(1,TRUE,"unknown")) {bad <- rows; bad[[1L]]$best_id <- value; check("best ID cannot coerce numeric boolean or unknown values", rejects(brohn_maxdiff_analysis(d,bad)))}
  bad <- rows; bad[[1L]]$worst_id <- bad[[1L]]$best_id
  check("same item cannot be both best and worst", rejects(brohn_maxdiff_analysis(d,bad)))
  bad <- rows; bad[[1L]]$design_hash <- source$hash
  check("wrong frozen source design refused", rejects(brohn_maxdiff_analysis(d,bad)))
  bad <- rows; bad[[1L]]$item_order <- list("item-1","item-2","item-4")
  check("wrong offered set cannot be silently repaired", rejects(brohn_maxdiff_analysis(d,bad)))
  check("duplicate response cannot double-count", rejects(brohn_maxdiff_analysis(d,c(rows,rows[1L]))))
  dupe <- rows[[1L]]; dupe$id <- "distinct-id"
  check("new event ID cannot duplicate the same person/session/exposure", rejects(brohn_maxdiff_analysis(d,c(rows,list(dupe)))))
  dupe$session_id <- "another-visit"
  check("a declared repeated visit remains valid separate evidence", brohn_maxdiff_analysis(d,c(rows,list(dupe)))$quality$session_count == 14L)
  separated <- lapply(1:4, function(i) response(d,i,"item-1","item-3"))
  check("complete separation has no finite unpenalised utility", grepl("separation",brohn_maxdiff_analysis(d,separated)$model$reason) && !length(brohn_maxdiff_analysis(d,separated)$model$utilities))
  quasi <- c(separated,list(response(d,5,"item-2","item-3")))
  check("quasi-separation also withholds finite utilities", grepl("separation",brohn_maxdiff_analysis(d,quasi)$model$reason))
  cycle <- lapply(1:3,function(i) response(d,i,paste0("item-",i),paste0("item-",i%%3+1)))
  check("strongly connected cyclic observations have a finite balanced optimum", brohn_maxdiff_analysis(d,cycle)$model$status == "estimated" &&
    close(vapply(brohn_maxdiff_analysis(d,cycle)$model$utilities,`[[`,numeric(1),"utility"),c(0,0,0)))
  empty <- brohn_maxdiff_analysis(d,list())
  check("no answers yield unavailable counts and no zero utilities", all(vapply(empty$items,function(i)is.null(i$exposure_adjusted_score),logical(1))) && empty$model$reason == "no_complete_pairs")
  disconnected <- d; disconnected$items <- lapply(1:6,function(i)list(id=paste0("item-",i),label=paste("Original",i)))
  disconnected$sets <- list(list(id="first",item_ids=as.list(paste0("item-",1:3))),list(id="second",item_ids=as.list(paste0("item-",4:6))))
  dr <- list(response(disconnected,1,"item-1","item-3","first"),response(disconnected,2,"item-4","item-6","second"))
  check("disconnected design cannot be served but imported counts remain explicit", rejects(brohn_maxdiff_compile(disconnected)) && brohn_maxdiff_analysis(disconnected,dr)$model$reason == "disconnected_answered_item_design")
  onlycounts <- d; onlycounts$settings$analysis$fit_aggregate <- FALSE; cr <- lapply(rows,function(r){r$design_hash<-brohn_hash(onlycounts);r})
  check("explicit count-only choice never silently fits utilities", brohn_maxdiff_analysis(onlycounts,cr)$model$status == "not_requested")
  live <- source; live$origin <- "live"
  check("synthetic origin cannot silently upgrade to live research", rejects(brohn_maxdiff_analysis(d,rows,live)))
  check("JSON roundtrip preserves original missingness and typed identifiers", identical(brohn_hash(brohn_parse(brohn_json(partial))$exposures), brohn_hash(partial$exposures)) &&
    is.null(brohn_parse(brohn_json(partial))$exposures[[38L]]$worst_id))

  # Optional upstream GPL reference remains outside this repository/runtime.
  # Its source archive was downloaded explicitly; no package is installed here.
  reference <- "../../work/method-references/maxdiff/support.BWS"
  if (dir.exists(reference)) {
    archive <- paste0(reference, "_0.4-6.tar.gz")
    check("upstream reference archive identity is pinned", identical(digest::digest(file=archive,algo="sha256",serialize=FALSE),"041cf69fa7cc8a250d83b2de7ca9e5801d9d4359f0230e9fbbcbab4c29518750"))
    ref <- new.env(parent=globalenv()); source(file.path(reference,"R","bws.dataset.R"),local=ref); source(file.path(reference,"R","bws.count.R"),local=ref)
    original <- data.frame(ID=seq_along(rows),B1=vapply(rows,function(r)match(r$best_id,brohn_ids(d$items)),integer(1)),W1=vapply(rows,function(r)match(r$worst_id,brohn_ids(d$items)),integer(1)))
    check("upstream one-question2:1loop limitation is recorded without duplicating Brohn data", rejects(ref$bws.dataset(data=original,response.type=2,choice.sets=matrix(1:3,nrow=1),design.type=2,item.names=c("A","B","C"),id="ID",response=c("B1","W1"),model="maxdiff")))
    prior <- .libPaths(); .libPaths(c(prior,normalizePath("../../work/r-library-platform"))); on.exit(.libPaths(prior),add=TRUE)
    if (requireNamespace("survival",quietly=TRUE)) {
      suppressPackageStartupMessages(library("survival",character.only=TRUE))
      strata <- survival::strata
      alternatives <- expand.grid(best=1:3,worst=1:3); alternatives <- alternatives[alternatives$best!=alternatives$worst,]
      expanded <- do.call(rbind,lapply(seq_len(nrow(original)),function(i)data.frame(STR=i,
        RES=alternatives$best==original$B1[[i]] & alternatives$worst==original$W1[[i]],
        A=as.integer(alternatives$best==1)-as.integer(alternatives$worst==1),B=as.integer(alternatives$best==2)-as.integer(alternatives$worst==2))))
      fitted <- survival::clogit(RES ~ A+B+strata(STR),data=expanded,method="exact")
      check("independent conditional-logit implementation matches paired utility oracle", close(as.numeric(stats::coef(fitted)),c(2*log(2),log(2)),1e-6) && close(-fitted$loglik[[2L]],expected_nll))
      load(file.path(reference,"data","fruit.rda"),envir=ref)
      sets <- cbind(c(1,2,2,1,1,3,1),c(4,3,4,2,3,5,2),c(6,4,5,5,4,6,3),c(7,6,7,6,5,7,7))
      fd <- d; fd$items <- lapply(1:7,function(i)list(id=paste0("item-",i),label=paste("Reference item",i)))
      fd$sets <- lapply(1:7,function(i)list(id=paste0("set-",i),item_ids=as.list(paste0("item-",sets[i,]))))
      fruit <- ref$fruit; fr <- list()
      for (i in seq_len(nrow(fruit))) for(j in 1:7) fr[[length(fr)+1L]] <- response(fd,length(fr)+1L,
        paste0("item-",sets[j,fruit[[paste0("B",j)]][[i]]]),paste0("item-",sets[j,fruit[[paste0("W",j)]][[i]]]),set_id=paste0("set-",j),person=paste0("reference-",i))
      ours <- brohn_maxdiff_analysis(fd,fr)
      expanded <- ref$bws.dataset(data=fruit,response.type=1,choice.sets=sets,design.type=2,item.names=paste0("I",1:7),id="ID",response=names(fruit)[-1],model="maxdiff")
      baseline <- survival::clogit(RES ~ I1+I2+I3+I4+I5+I6+strata(STR),data=expanded,method="exact")
      utilities <- c(as.numeric(stats::coef(baseline)),0); utilities <- utilities-mean(utilities)
      check("upstream100-person700-pair synthetic reference reproduces all aggregate utilities", ours$model$status == "estimated" && close(vapply(ours$model$utilities,`[[`,numeric(1),"utility"),utilities,1e-5))
      check("upstream paired reference likelihood and count normalization reproduce", close(ours$model$diagnostics$negative_log_likelihood,-baseline$loglik[[2L]],1e-7) &&
        close(vapply(ours$items,`[[`,numeric(1),"exposure_adjusted_score"),ref$bws.count(expanded)$aggregate$stdBW))
      cat("Reference: support.BWS0.4-6 archive SHA-256 pinned; survival",as.character(utils::packageVersion("survival")),"paired conditional logit; no runtime dependency added\n")
    } else cat("SKIP: optional survival conditional-logit reference unavailable\n")
  } else cat("SKIP: optional downloaded support.BWS reference unavailable\n")
  cat(sprintf("PASS: %d MaxDiff design, paired likelihood, missingness, separation and reference checks\n",checks))
})
