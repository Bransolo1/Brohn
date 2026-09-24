# Local facial AU and native-category acceptance

Status: the complete researcher route passed on 24 September 2026, with the evidence and scope below. A separately qualified installation-status wording correction is joined below; it does not change processing. This is a bounded optional Windows CPU profile, not a whole-platform or scientific-validity sign-off.

## Product route

Import a saved video into Data, choose **Native facial action units and expression categories**, record the collection source and permission for facial processing, confirm that permission, and choose an explicit time window/stride. The normal immutable dataset job runs the pinned local provider and publishes the original-source-bound report plus complete frame JSONL and face-wise CSV. Readable reports separate coverage, native category labels and AU outputs; exact values and complete original PTS remain available. Earlier reports survive subsequent mapping changes.

The profile processes 2 to 300 selected frames from a recording up to 600 seconds and 512 MiB. A larger selection needs an explicit window/stride. It does not silently subsample. Native identity, gaze and pose outputs are disabled and rejected if unexpectedly populated. Multiple-face and no-face frames remain visible and do not enter single-face summaries.

See [provider, model terms and installation](../methods/FACIAL-AU-NATIVE-PROFILE.md) for exact assets, licence sources, dependency pins, optional setup and construct limits. No model weights or fixture videos are checked into Git.

## Independent executed evidence

Evidence is retained outside the repository under `../../work/test-runs/`.

| Evidence | Executed scope | Receipt SHA-256 |
| --- | --- | --- |
| `brohn-facial-contract-20260924-01/results.json` | 12 stdlib worker checks: strict inputs, native states, exact PTS/decimal selection, missing/zero, disabled branches and support | `3d4a7940fa5ce83ebfa207f268af4f6d825265f44985b17ade17f576f7680d89` |
| `brohn-facial-native-20260924-01/results.json` | 9 actual worker/native checks; separately instantiated public Detectorv1 calls, all AU/category/bbox/detection values, independent PTS/RGB and aggregate support | `e41c071fcee9c644b15fc68ac2a5e84631e6631f57cc92e6fe5a552204e9e18e` |
| `brohn-facial-domain-20260924-04/results.json` | 34 R checks using hand-authored source bytes and native-output records; exact decimal boundaries, pins, permission, disabled outputs, complete JSONL and every CSV cell, missing-versus-zero and accessible native-result markup | `c66fe055f9ca6bc399b9ac08510c0ceac70806e83b09b5ece09333e9846e4d60` |
| `brohn-facial-r-native-20260924-01/results.json` | 5 actual R-to-native adapter checks: existing video dispatch, all 27 summaries and complete coverage, byte-identical artifacts, permission preservation and unchanged source/implementation identities | `d32882748efc9b85eaf74546a66a439d85190b8c327d51da697bf3d3697a2866` |
| `brohn-facial-source-guards-20260924-01/results.json` | 7 independent actual-job checks: native Windows source write denial before child launch, real two-frame native processing and guarded publication, no-face/null outcomes, actual CSV media type, unchanged original hash and released guard afterwards | `5e8913d545277aa661c604709ff5710cf2838bc4b503ea0b40b1e4236bab5c65` |

The R domain fixture is deliberately not a decodable video and never calls inference. A separate R validation invocation successfully checked the actual six-frame native result and every complete CSV cell. These two evidence scopes are distinct.

The original six-frame browser source is a lossless composed software fixture derived from the existing Apache-2.0 MediaPipe test still. Original integer PTS are 2000, 2040, 2110, 2310, 2710 and 2910 with time base 1/1000. States are blank/single/single/multiple/blank/single; three eligible frames support exactly 7/100 seconds of adjacent eligible time. Its source SHA-256 is `251248e52a49b17a258e59ce31b27b5a05ff0bdc39f116e355c1959a09f0bf6c`. The native fixture records the upstream URL/commit/image hash and every composed RGB hash. There is no newly captured participant.

## Connected browser gate

The actual harness is `tests/researcher-facial-expression.mjs`, with isolated service fixture `tests/fixtures/researcher-facial-expression.R`. Ports are 3945/3946. It ran after coordinated shared-source freeze against a fresh isolated workspace and a verified copy of the original media. All owned services are now stopped.

Receipt: `brohn-facial-browser-20260924-01/browser-1790232761706/results.json`, SHA-256 `f568473b237bc63336feead23cb4b40530a7c2d88beee2646d39152f631bc7c6`. The uninterrupted run passed **16 assertion groups**, including **five clean axe/reflow/SVG-label-spacing scans** and no browser errors. These are not separate additional counts. Fifteen implementation-file hashes were captured before service launch and checked at completion; each actual worker report also retains its normal code identity and source provenance.

Executed behaviour:

- Actual transfer review and immutable import; permission confirmation and reversed-window failures are refused before another job is queued.
- Normal queued native processing and guarded publication of all six frames. Every complete browser-downloaded native AU/category/bbox/detector value agrees with the separately checked public native calls. Original PTS strings and independently authored decoded-RGB hashes agree; the seven CSV rows preserve missing scores as blanks.
- All 27 aggregate features match the independently checked native result, with three eligible frames and exactly 0.07 seconds of supported time.
- The authored start `0.040000000000000001` and end `0.31` survive the real UI/R/Python path. The resulting selected source indices are exactly 2 and 3, excluding the frame at exact0.04 seconds. Its single eligible frame provides no fabricated supported interval.
- A separately authored window0 to0.71 and stride4 selects actual blank frames0 and4. All 27 summaries are unavailable, rather than neutral or numeric zero.
- Complete CSV downloads have `.csv` names and preserved content identities. The standalone HTML report includes native interpretation and coverage. Navigating away refuses the earlier artifact request.
- Desktop1440 and mobile390 report views, expanded exact-value/frame disclosures, mapping and no-face state passed automated checks. Actual desktop/full mobile pages and mobile category/AU/empty-category image crops were visually inspected for readable labels, spacing, missing values and displayed interpretation. The retained full-page captures include the focused keyboard skip link; isolated chart captures show the complete chart text.
- Real service restart reopens the original report and byte-identical complete CSV. All three original reports remain unchanged after later mapping revisions; reopening/restart creates no analysis.

Exactly **four new jobs** succeeded: one source import and three native analyses. There were **zero inherited jobs**. The original upstream fixture and copied source remain byte-identical to the source hash above. No browser failure or continuation was needed in this run.

After that browser run, one setup-status sentence was corrected to distinguish selected model/shared-FFmpeg/Py-Feat file-byte checks from checks of dependency versions. `brohn-facial-wording-20260924-01/results.json`, SHA-256 `5da1e2018f893a45c88cff72b4c5cde5277c6a1f90a4602a1e5ac5d6f5552ef7`, records **four focused continuation checks**: the exact single-line change from the browser-qualified view hash, truthful configured-state text, the unchanged missing-installation state, and byte-identical native result rendering. The receipt links the original browser receipt. No inference, queue work or full browser traversal was repeated; this is a labelled display-only delta, not an uninterrupted new full-run claim.

Reproduction requires the prepared optional profile and original native fixture evidence; the six-frame test source is deliberately outside Git. Run the native fixture preparation/agreement test first, create a fresh `brohn-facial-browser-*` evidence directory, run the R fixture's `setup` mode, and invoke the browser harness with that directory. This is not a clean-machine restoration claim.

## Retained failures and limits

The first Py-Feat import failed because the existing static FFmpeg9 could not satisfy TorchCodec's shared-DLL dependency. The separately pinned LGPL shared8.1.3 runtime resolved that failure; the original log is retained in `../../work/tooling/facial-provider-investigation/`.

The first R hand-fixture run (`brohn-facial-domain-20260924-01`) failed because its canonical JSON reordered native category map keys. Object-key ordering is not scientific identity; the domain validator now checks the exact key set, while named measurements and array order remain explicit. Fresh runs02,03 and04 passed after that repair; the failed fixture was not deleted or relabelled.

Software agreement does not establish model accuracy, demographic fairness, FACS intensity, internal emotion, attention, preference, participant identity or synchronization to external study events. The selected current native binaries need empirical qualification for a given research context. This slice also does not demonstrate 300-frame capacity, live inference or hardware timing.

## Follow-on product work

Add plain-language AU movement names and help, checked against primary terminology, alongside the preserved native AU codes. This improves comprehension for undergraduate researchers without relabelling model scores as FACS intensities. A later saved-frame/timeline review can reuse the preserved PTS and complete values, with the same source/download authority; it must not invent participant tracking, synchronization or model validity.
