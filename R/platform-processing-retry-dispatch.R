# Source after the ordinary jobs module and registered variant worker modules.
# Preserve the old implementation as a closure-bound function, including every
# existing operation-specific admission, frozen-input retry and audit rule.
brohn_retry_processing <- local({
  legacy_retry <- brohn_retry_processing
  stopifnot(is.function(legacy_retry), is.function(.brohn_worker_route),
    is.function(brohn_retry_variant_analysis))
  function(store, id) {
    job <- brohn_get_job(store, id)
    if (!is.null(job)) {
      route <- .brohn_worker_route(job$operation, job$request)
      if (identical(route, "variant")) return(brohn_retry_variant_analysis(store, id))
      brohn_require(!identical(route, "unsupported"),
        "This worker cannot retry that saved analysis profile. Use a worker that supports the original profile; the original request is preserved.")
    }
    legacy_retry(store, id)
  }
})
