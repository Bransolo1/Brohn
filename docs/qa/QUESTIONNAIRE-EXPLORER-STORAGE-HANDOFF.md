# Historical questionnaire explorer storage handoff

**20 September 2026:** this draft was resumed and qualified with 59 storage checks
and actual supervised worker publication. See [current acceptance](QUESTIONNAIRE-EXPLORER-ACCEPTANCE.md).
The stopped-state account below records 8 September only.

Development stopped at the user's request on 8 September 2026. This is an
unfinished handoff, not release or qualification evidence. No explorer loader,
worker dispatch, runtime or application hooks were added by the storage agent.

`R/platform-questionnaire-explorer.R` contains the parent's original scaffold
and the storage agent's unregistered implementation draft. The file parses in
the prepared R runtime. **No storage tests, actual explorer workers, publication
acceptance tests or connected browser tests have run.** The planned
`tests/platform-questionnaire-explorer-storage.R` was not created before stop.
The independent pure index module's 49 checks are a separate agent's evidence;
they do not qualify this adapter. The storage agent has no active processes.

The draft API is:

```r
brohn_prepare_questionnaire_index(store, report_id, report_revision,
                                expected_report_hash, project_id)
brohn_queue_questionnaire_index(store, report_id, report_revision,
                              expected_report_hash, project_id, rebuild = FALSE)
brohn_cancel_questionnaire_index(store, job_id, project_id)
brohn_retry_questionnaire_index(store, job_id, project_id)
brohn_questionnaire_index_input(store, job)
brohn_analyse_questionnaire_index(input, scratch)
brohn_publish_questionnaire_index(store, output, scratch, job, input, output_path)
brohn_open_questionnaire_index(store, index_id, expected_index_hash,
                              report_id, report_revision,
                              expected_report_hash, project_id)
brohn_check_questionnaire_index_context(store, opened, report_id,
                                      report_revision, expected_report_hash,
                                      project_id)
brohn_close_questionnaire_index(opened)
```

The proposed opener returns `list(record, handle, guard, context)`. The UI owner
would own session lifetime and close it; `handle` is the pure index reader used
by the page, record and value APIs. This is not a registered UI contract yet.

The draft freezes report revision/body hash, original catalog hash, retained
result reference, provenance, source support and implementation hashes. It
selects the latest matching job so an explicit rebuild can supersede the first
cache. It proposes a `questionnaire_index` derived entity and one SQLite artifact
plus a small publication document, with Windows native guards retained across
the existing fenced metadata transaction. It does not publish a scientific
report or recalculate questionnaire outcomes.

These paths still require independent qualification: exact project authority,
historical inline sources without retained worker envelopes, artifact/source
mutation, latest-rebuild reuse, retry/cancel races, SQL rollback, stale leases,
typed publication metadata, reopened read authorization and cleanup. Review the
inline Python Windows path-prefix string escaping in `.brohn_qexplorer_hold`
before attempting to enable it; that probe has not executed. Also review that
context checks reject mismatched opened handles/records as well as a mismatched
report or project. File lifecycle, resource limits, repeated source loading and
non-Windows behavior are not qualified by this draft.

Do not register this module or describe Explore all answers as delivered until
the remaining storage, actual worker and researcher browser acceptance is
complete. Existing complete questionnaire downloads and the earlier separately
qualified large-history worker implementation remain unaffected.
