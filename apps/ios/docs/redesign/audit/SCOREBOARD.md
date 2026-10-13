# Audit Scoreboard — iOS Redesign 1:1 Spec

Code-anchored accuracy audit of the 14 spec docs in `apps/ios/docs/redesign/`. Every claim was adjudicated against the Swift source; omissions were found by sweeping the owned source files; load-bearing/contested claims went through a 2-of-3 adversarial panel.

**The scorer is trusted:** the calibration gate passed **3/3** — a planter corrupted three known values in a scratch copy of the design-system doc and the independent verifier (same prompt the real audit uses) caught all three before any doc was scored.

## How to read this

- **Precision** = of the factual claims the doc makes, the fraction that match the code (severity-weighted). High precision = the doc rarely says anything *wrong*.
- **Recall** = of the replication-critical facts in the code, the fraction the doc actually captures. Low recall = the doc *omits* things a rebuilder needs.
- **F** = harmonic mean of the two.
- **Certified** = the gate you chose: `critical == 0 AND major == 0`. Minor defects are logged, non-blocking.

## Headline

- **Certified: 0 / 14.** No doc is blocker-free yet.
- **Precision is excellent everywhere (0.88–0.99).** The docs almost never state a *wrong* value — very few hallucinations.
- **Recall is the weak axis (0.44–0.86).** The dominant defect is **omission**, not error. Repairs are mostly *backfilling missing facts*, not correcting wrong ones.
- **Totals:** 10 critical, 126 major, 251 minor defects across the set.

## Scoreboard

| Doc | Precision | Recall | F | Critical | Major | Minor | Certified |
|---|---|---|---|---|---|---|---|
| 01-architecture.md | 0.978 | 0.700 | 0.816 | 0 | 9 | 10 | ❌ |
| 02-design-system.md ★ | 0.968 | 0.633 | 0.766 | 1 | 17 | 7 | ❌ |
| 03-chat-surface.md ★ | 0.988 | 0.789 | 0.878 | 0 | 7 | 22 | ❌ |
| 04-drawer.md ★ | 0.949 | 0.825 | 0.883 | 1 | 7 | 4 | ❌ |
| 05-destinations-automation-usage.md | 0.993 | 0.773 | 0.869 | 1 | 4 | 16 | ❌ |
| 06-destinations-files-skills-canvas.md | 0.992 | 0.846 | 0.913 | 0 | 6 | 4 | ❌ |
| 07-settings.md | 0.981 | 0.855 | 0.914 | 2 | 7 | 30 | ❌ |
| 08-onboarding.md | 0.882 | 0.754 | 0.813 | 3 | 7 | 11 | ❌ |
| 09-chat-plumbing-transport.md | 0.966 | 0.467 | 0.629 | 0 | 15 | 19 | ❌ |
| 10-markdown-rendering.md | 0.984 | 0.626 | 0.765 | 0 | 10 | 32 | ❌ |
| 11-voice-audio.md | 0.968 | 0.708 | 0.818 | 0 | 12 | 47 | ❌ |
| 12-gateway-device-services.md | 0.912 | 0.439 | 0.593 | 0 | 12 | 29 | ❌ |
| 13-ipad.md | 0.944 | 0.643 | 0.765 | 2 | 12 | 20 | ❌ |
| 14-assets-glyphs.md | 0.968 | 1.000 | 0.984 | 0 | 1 | 0 | ❌ |

★ = load-bearing doc (also slated for blind-reconstruction sufficiency testing).

## Repair priority (worst blockers first)

Ordered by critical, then major defect count.

| Rank | Doc | Critical | Major | Note |
|---|---|---|---|---|
| 1 | 08-onboarding.md | 3 | 7 | Most criticals; also lowest precision (0.882) — the one doc with real *wrong* claims, not just gaps. |
| 2 | 13-ipad.md | 2 | 12 | High omission load; iPad twins poorly covered. |
| 3 | 07-settings.md | 2 | 7 | Criticals plus 30 minors (largest minor pile). |
| 4 | 02-design-system.md ★ | 1 | 17 | Most majors (17) — token/value omissions; load-bearing, so highest downstream impact. |
| 5 | 04-drawer.md ★ | 1 | 7 | Load-bearing. |
| 6 | 05-destinations-automation-usage.md | 1 | 4 | One critical to clear. |
| 7 | 09-chat-plumbing-transport.md | 0 | 15 | Worst recall (0.467) — behavior layer under-documented. |
| 8 | 12-gateway-device-services.md | 0 | 12 | Second-worst recall (0.439). |
| 9 | 11-voice-audio.md | 0 | 12 | 47 minors (largest). |
| 10 | 10-markdown-rendering.md | 0 | 10 | Pipeline stages partially covered. |
| 11 | 01-architecture.md | 0 | 9 | — |
| 12 | 03-chat-surface.md ★ | 0 | 7 | Load-bearing; precision 0.988 (best among big docs). |
| 13 | 06-destinations-files-skills-canvas.md | 0 | 6 | — |
| 14 | 14-assets-glyphs.md | 0 | 1 | Nearly clean (recall 1.0); one major to clear. |

## Status of the audit run

- **Verification (precision + recall + adversarial panel):** complete for all 14 docs.
- **Per-doc defect reports (`NN-*.md` in this folder):** being written (the account session limit repeatedly killed the writer burst; retrying in small batches).
- **Blind reconstruction (02/03/04, Tier C):** deferred — the precision+recall pass already yields the full repair list; reconstruction is the sufficiency cross-check and can run once limits allow.

## Next

Repair → re-verify loop, worst-first. Because precision is already high, most repairs are additive (fill omissions) rather than corrective — lower risk of introducing new errors. Each doc re-verifies against code after repair; a doc certifies only at zero critical + major.
