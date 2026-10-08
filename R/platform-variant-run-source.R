# Inactive researcher-only original saved1.2 source wrapper.
# No loader, participant, delivery, store-schema, export or worker activation.
brohn_open_variant_run_protocol <- function(store, run_id, study_id, project_id) {
  .brohn_epr_open(store, run_id, study_id, project_id, "1.2")
}
