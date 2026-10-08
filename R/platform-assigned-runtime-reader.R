# Reader implementation0.2 adds one trusted immutable runtime profile. It does
# not install a participant renderer, load JS, create releases or open a store.
brohn_install_assigned_runtime_reader <- function(envir = environment(brohn_install_assigned_runtime_reader)) {
  distribution <- .brohn_assigned_runtime_distribution()
  .brohn_assigned_runtime_manifest(distribution)
  identity <- list(profile = "brohn-assigned-runtime-reader/0.2", runtime_manifest_hash = brohn_hash(distribution))
  if (exists(".brohn_assigned_runtime_reader", envir, inherits = FALSE)) {
    prior <- get(".brohn_assigned_runtime_reader", envir, inherits = FALSE)
    .brohn_runner_require(identical(prior$identity, identity), "Restart with the matching runtime source reader.", 503L)
    return(invisible(identity))
  }
  .brohn_runner_require(exists(".brohn_runner_manifest", envir, inherits = FALSE),
    "Install the original runtime reader before the assigned source profile.", 503L)
  legacy <- get(".brohn_runner_manifest", envir, inherits = FALSE)
  validate <- .brohn_assigned_runtime_manifest
  dispatch <- local({original <- legacy; assigned <- validate
    function(manifest, expected_hash = NULL) {
      if (is.list(manifest) && identical(manifest[["schema", exact = TRUE]], "brohn-assigned-runtime/0.1"))
        return(assigned(manifest, expected_hash))
      original(manifest, expected_hash)
    }})
  assign(".brohn_runner_manifest", dispatch, envir)
  assign(".brohn_assigned_runtime_reader", list(identity = identity, original_manifest = legacy), envir)
  invisible(identity)
}
