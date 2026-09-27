# Complete clock overview renderer

27 September 2026. Accepted external presentation component, separate from application/controller acceptance.

Source: `../clock-plot-next-20260925/platform-clock-plot-views.R`, SHA256 **`f85b62448ea354da08099ee9db13d34a3ae38ad5461d2dbcb0cd771ed716fad8`**.

Call `brohn_clock_plot_view(qualified_plot, id_prefix = "clock-plot-view")` with the decoded, currently authorized and byte-verified `brohn-clock-plot/0.1` artifact. It returns pure HTML/SVG tags and performs no reads, jobs, scoring or writes. Its caller must maintain current saved-window authority and resources. Use a unique ID prefix when rendering more than one figure.

Signal lanes share the same horizontal window but retain separate channel names, units and ranges. Each original continuity run is its own shape. The retained first/minimum/maximum/last representatives stay in original order; extrema and singleton observations remain visible. Screen coordinates use the component's bounded `display_x`/`display_y`. Exact values, the reference-relative base and rational axis values remain strings. No subtraction of large binary64 epochs occurs in R.

Event lanes display individual original marks up to 2,000 events, and complete counts across the component's 512 time bins above that threshold. They explicitly identify the mode. Empty, all-unavailable, export-only, constant and unplaced states are explained. Original exports remain the complete numerical evidence; the collapsible tables summarize every lane and expose all five retained exact axis coordinates. Scoped dark styling, labelled SVG titles/descriptions and keyboard-reachable horizontal table regions provide the numerical alternative. Text is escaped by HTML tools, including original event labels.

## Evidence

- `render-03/results.json`: **25 pure-R checks** over 11 separately qualified component fixtures. Numerical-page offsets 0, 100 and 6,600 produce identical overview HTML. The original source row 778 spike remains visible. Empty, marker-only, all-unavailable, signed-zero constant, context-gap, export-only and tiny-window states pass. Input model and fixture bytes remain unchanged. Receipt SHA256 `a21d3349cf8c69c7494f7c2ebea89c6fe992d8cd0344e729d46cabd6b0b1a9ef`.
- `render-03/oracle-results.json`: **17 independent oracle checks**, including all **1,379 representative coordinates** against exact `Fraction` arithmetic on the complete original 6,700-row CSV. The first 100 CSV rows contain no signals. Source row 778 maps to SVG `(282.396,12)`; all 2,401 events in each marker lane contribute to its bin totals. All eight continuity runs remain separate. The genuine `2e-20` second-window singleton remains centered. Receipt SHA256 `d683ddbea0f543c0b1bb75098ae027cd1c4f392d6c2ad8fa8a3c311b7f4cbaf0`.
- `browser-03/results.json`: **53 actual Chrome checks and six clean accessibility scans** at 390 and 1,280 pixels. Static page content only; real Tab, Enter and ArrowRight reach, open and horizontally explore the numerical alternative. No document overflow, unreadable headings, unnamed SVG or browser page error was observed. Full-window mobile/desktop and tiny-span mobile screenshots were visually inspected. Receipt SHA256 `aeae0857ef347287d4b7fb09a3af9477f87e3043a261b344cb09830210b720b1`.
- `boundary-01/results.json`: **five focused R checks** using additional genuine component windows at exactly 2,000 and 2,001 events per lane. The first retains 4,000 individual marks; the second changes to declared count bins. Declared presentation-only variants also check malicious lane/marker/base text escaping and distinct units. Receipt SHA256 `09b096ff98d9bdb0bcf0954824d62d2af1ea7a641cc95804407f5409a06be89c`.
- `boundary-browser-01/results.json`: **seven actual Chrome DOM checks**, confirming both threshold modes, complete 4,002-event bin totals, no page overflow and no execution of injected source text. Both event-lane screenshots were inspected. Receipt SHA256 `0b2b307b2679b88252e05ffa80da860bbded214086a5951b8f0df609c7b117f1`.

The tiny span tests numerical representation only; it makes no claim about a device's physical timing resolution. Signal line connections are explicitly display guides, never interpolated measurements. Physical synchronization remains unestablished and timing uncertainty unknown.

## Preserved attempts and limits

`render-01` failed when Windows R's C locale could not source literal non-ASCII characters with the requested encoding. The source now uses explicit Unicode escapes; `render-02` passed 23 checks, and `render-03` adds the qualified tiny-span case. `browser-01` encountered the accessibility tool's requirement for an explicit browser context. `browser-02` found the standalone fixture lacked its host page's h1. `browser-03` supplies visible recording/alignment headings and an explicit context; the renderer source did not change for these harness corrections.

No HTTP or application service was started. This evidence does not qualify current-reader checks, supervised publication, native file seals or controller races; those have separate tests. All browser processes are terminal. Raw QA workspaces should not be published. Test harnesses live beside the external renderer and currently reference the local qualified component fixtures; portable packaging needs a self-contained fixture set.
