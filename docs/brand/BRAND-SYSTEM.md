# Brohn brand system — Soft graphite

Prepared 2026-09-08. Brohn should feel composed, precise and welcoming: a premium
research studio that makes complex work understandable. The direction uses an
original folded-B mark, a restrained Manrope wordmark, soft dark surfaces and
mineral accents. It does not reproduce Apple or QuantumBlack branding.

[Open the visual preview](preview.html), [brand board](brand-board.png) or
[interface direction](interface-direction.png). The interface is a design
specimen; its proposed study features are not newly implemented product behavior.

## Identity and assets

The folded B separates two lobes with a rising open seam: distinct signals held
within one identity. Use the full lockup at first contact and the monogram for
the app icon or a compact persistent shell. The artwork is vector-native and the
wordmark is outlined, so exported logos do not depend on installed fonts.

| Asset | Use |
|---|---|
| [Primary lockup](../../www/brand/brohn-lockup.svg) | Off-white mark and wordmark on dark surfaces. |
| [Ink lockup](../../www/brand/brohn-lockup-ink.svg) | Light documents, print and external embeds. |
| [Mint monogram](../../www/brand/brohn-mark-mint.svg) | Hero, app identity and limited brand emphasis. |
| [Light monogram](../../www/brand/brohn-mark.svg) / [ink monogram](../../www/brand/brohn-mark-ink.svg) | Single-colour uses. |
| [Wordmark](../../www/brand/brohn-wordmark.svg) | Compact typographic signature when the mark is already present. |
| [App icon SVG](../../www/brand/brohn-app-icon.svg) / [256px PNG](../../www/brand/brohn-app-icon-256.png) | Application/install surfaces. |
| [Signal field](../../www/brand/brohn-field.svg) | Decorative introduction/report-cover artwork; never scientific data. |
| [Empty study illustration](../../www/brand/empty-study.svg) | First-study empty state with a clear next action. |
| [Icon sprite](../../www/brand/icons.svg) | 32 original 24px-grid icons; individual files are in `www/brand/icons`. |
| [CSS tokens](../../www/brand/tokens.css) / [JSON tokens](../../www/brand/tokens.json) | Shared implementation values. |

Preserve the mark's aspect ratio and seam. Keep clear space of at least one stem
width around it. Use the full lockup at 110px width or larger; use the monogram
for smaller application placement. Avoid shadows/glows on routine logos,
outlines around the wordmark, gradients inside the mark or rotating it as a
loading indicator. Use a small labelled progress indicator instead.

## Soft dark palette

| Token | Colour | Intended role |
|---|---|---|
| Canvas | `#11171C` | Page background; softer than pure black. |
| Surface | `#192229` | Main cards and panels. |
| Raised | `#222E36` | Nested controls, menus and raised regions. |
| Hover | `#2C3A43` | Subtle interactive surface change. |
| Text / secondary / muted | `#EDF2F2` / `#B7C5CB` / `#99ACB5` | Legible hierarchy without faint grey text. |
| Sea glass | `#97D8C4` | Primary action, selected state and brand accent; action text `#10251F`. |
| Iris | `#BEB7EA` | Secondary emphasis and EEG series. |
| Glacier | `#91BFE6` | Complementary series and informative emphasis. |
| Sand / rose | `#E3C38D` / `#E8A2A8` | Review-needed/error messages when paired with icon and text. |
| Decorative line / control border | `#34454F` / `#718994` | Separate quiet layout dividers from essential control boundaries. |
| Focus | `#C5D5FF` | Visible 3px focus ring with separation from the component. |

Most of a screen should use neutral surfaces. Mint identifies the primary next
action; it should not cover every card. Chart colours and status colours have
separate semantic mappings: a rose cardiac line is not an error. Label series
directly and use line patterns/markers in addition to colour. Control/test
conditions retain their names and fixed visual identity across panels.

**Scope researcher theming separately from participant stimuli.** Do not let dark
mode change experimental background, luminance, colour, geometry, timing or
baseline conditions. The participant renderer receives a frozen appearance
profile from the protocol. Operating-system theme changes must not alter it
mid-run. This is particularly important for pupil and visual-response studies.

## Typography, icons and component behavior

Use locally bundled **Manrope**: body 450, labels 550, headings 650. Default body
size is 16px with 1.55 line height; controls should generally be at least 14px.
Allow zoom/reflow and content growth rather than truncating a research decision.
Use tabular numerals for aligned values, units beside numbers and sentence case.
Display headings can be larger and closely tracked; never apply that tracking to
tables or instructions. The preview contains a scaled interface specimen; the
production token sizes govern the application.

Use the 4/8/12/16/24/32/48/64 spacing scale. Control radius is 10px, cards 18px and
major panels 24px. Favor alignment and whitespace over shadows. A single primary
button sits beside a plain explanation of what happens next. Routine interaction
feedback lasts 120ms; transitions 180ms; reduced motion removes movement.

The original icon set covers the five study stages, signal families, AOIs,
controls, time, linkage and common operations. Use the 24×24 viewBox, 1.7px stroke
and rounded joins. Decorative icons beside text get `aria-hidden="true"`; an
icon-only button needs an accessible name and a visible tooltip. Keep click/tap
targets at least 44px where practical. Never require users to identify a device
or error from a symbol alone.

Empty, loading, partial, failed, stale and complete states must use the same
visual language. Every error explains the affected measure and offers recovery.
Do not dim all results when a single optional sensor fails. A state change moves
focus only when it changes the user's task; background progress uses restrained
announcements. The [unified UX plan](../product/UNIFIED-EXPERIENCE.md) and
[34 journey scenarios](../product/journey-acceptance.json) define behavior.

## Verification and integration

[Verification results](verification.json) record **31 passing colour pairs**,
no axe violations in the 1400px/390px previews, no narrow horizontal overflow
and reduced-motion scroll behavior. Text pair targets are 4.5:1 and essential
control/focus contrasts 3:1. These are specific automated checks, not a complete
product accessibility certification. [W3C text contrast](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html),
[non-text contrast](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html).
Brohn's 44px design target exceeds the WCAG 2.2 minimum in many cases; actual
components must still be evaluated with the criterion's exceptions/spacing.
[Target-size guidance](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html).

Integrate this system in BWP15 through scoped Shiny/bslib styling, shared browser
components and report templates. Map tokens rather than scattering hex values.
Add the logo and icons through semantic components. Then compare implemented
screens against the approved visual specimen at desktop/narrow sizes while
running the actual research journeys. Do not apply brand CSS globally to the
participant runner.

Assets are reproducible with `scripts/readiness/build-brand-assets.py`; preview
screenshots and checks with `scripts/readiness/verify-brand.mjs`. The bundled
[font licence](../../www/brand/fonts/OFL.txt) is SIL OFL 1.1, from a pinned
[Google Fonts commit](https://github.com/google/fonts/tree/fb629caaa15ad25c051089c98f09cf6c8e30a86b/ofl/manrope).
[Asset provenance](../../www/brand/asset-manifest.json) records its hash and the
original artwork inventory. Project licensing still needs a release decision;
the font retains its separate licence.
