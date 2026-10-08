# Share saved ECG and PPG findings

This guide describes the implemented saved-report workflow. Native package and reader checks have passed; complete cardiac browser/cold-reopen qualification and report responsiveness remain open. See the [scoped QA record](../qa/CARDIAC-EVIDENCE-ACCEPTANCE.md).

1. Open the supported saved findings and use **Prepare report**. Select the exact sources to include. Brohn assembles their existing calculations and can prepare missing descriptive views; it does not rerun the scientific analysis.
2. Review the contents, required parent evidence and optional figures. Focused windows and smaller figures do not discard the complete included numerical evidence. Keep unavailable outcomes and their reasons visible when interpreting results.
3. Review source identifiers and free text before acknowledging their inclusion. That acknowledgement is not de-identification. Prepare once and use the ordinary preparation status/cancellation controls; use explicit Retry for failed work.
4. Download standalone HTML for readable findings and the ZIP for included tables, source evidence and its manifest. Download original recording files separately when needed. Complete saved analytical evidence and all original raw input are different exports.

Saved history retains the original choices and artifacts. Editing those choices creates a draft; preparing it creates a new saved intent. An offline copy cannot subsequently be revoked. Old downloaded files keep their original rendering, including any documented historical presentation defect.

ECG output here describes **detected RR intervals**, not confirmed normal-to-normal HRV. PPG output describes **PRV**, which is not interchangeable with HRV. Source exclusions retain their parent/decision evidence. A shorter display does not change physiological support or turn an unavailable value into zero. The package adds no claim about happiness, stress, preference or clinical status.

Large packages are currently slow. One native mixed package took about **289 seconds**; a separate saved-reader check took about **80 seconds** to open history. These are observations of particular workloads, not performance guarantees. The normal worker limits remain in force.

Other physiological report adapters and device/scientific qualification remain separate work. See the [package contract](../architecture/SAVED-CARDIAC-REPORT-PACKAGES.md) and [current references and limits](../research/METHOD-EVIDENCE-RUNTIME.md).
