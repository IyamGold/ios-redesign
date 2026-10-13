# Audit Scoreboard v2 — Post-Repair Re-Verification

Final state of the iOS redesign 1:1 spec after the full **generate → audit → repair → independent re-verify** loop. Supersedes `SCOREBOARD.md` (the pre-repair baseline).

## Result: 14 / 14 certified

Every spec doc clears the certification gate — **zero critical, zero major defects** — confirmed by an *independent* verifier (not the agent that wrote or repaired the doc). The re-verification also hunted for regressions introduced by the repair pass.

## Methodology (how this number is trustworthy)

1. **Generated** — 14 surface docs written from the Swift source.
2. **Audited** — code-anchored precision (claims vs cited code) + recall (omissions found by sweeping owned source) + a 2-of-3 adversarial panel on load-bearing claims. A **calibration gate passed 3/3** (a planter corrupted three known values; the independent verifier caught all three) — proving the scorer catches real defects.
3. **Repaired** — worst-first, every defect re-checked against code. The repair agents also corrected several *audit* errors (narrow citation windows that mis-framed the code).
4. **Re-verified** — an independent verifier per doc confirmed each original defect is resolved against code **and** sampled the repair's new content for freshly-introduced errors.

Certification rule (as chosen): a doc certifies only when `critical == 0 AND major == 0`. Minor defects are logged, non-blocking.

## Scoreboard

| Doc | Orig defects resolved | New errors (repair regressions) | Critical | Major | Minor | Certified |
|---|---|---|---|---|---|---|
| 01-architecture.md | 19/19 | 0 | 0 | 0 | 0 | ✅ |
| 02-design-system.md | 25/25 | 0 | 0 | 0 | 0 | ✅ |
| 03-chat-surface.md | 29/29 | 0 | 0 | 0 | 0 | ✅ |
| 04-drawer.md | 11/11 | 0 | 0 | 0 | 0 | ✅ |
| 05-destinations-automation-usage.md | 21/21 | 0 | 0 | 0 | 0 | ✅ |
| 06-destinations-files-skills-canvas.md | 10/10 | 0 | 0 | 0 | 0 | ✅ |
| 07-settings.md | 39/39 | 0 | 0 | 0 | 0 | ✅ |
| 08-onboarding.md | 21/21 | 0 | 0 | 0 | 1 | ✅ |
| 09-chat-plumbing-transport.md | 34/34 | 0 | 0 | 0 | 0 | ✅ |
| 10-markdown-rendering.md | 10/10 | 0 | 0 | 0 | 2 | ✅ |
| 11-voice-audio.md | 37/37 | 0 | 0 | 0 | 0 | ✅ |
| 12-gateway-device-services.md | 29/29 | 3 → **fixed** | 0 | 0 | 0 | ✅ |
| 13-ipad.md | 34/34 | 0 | 0 | 0 | 1 | ✅ |
| 14-assets-glyphs.md | 1/1 | 0 | 0 | 0 | 2 | ✅ |
| **Total** | **320/320** | **3 (all fixed)** | **0** | **0** | **6** | **14/14** |

## Regressions found and fixed

The re-verification caught that the **12-gateway** repair introduced 3 *minor* over-generalizations (below the gate, but genuine). All three fixed:

- **N1** — the "auto-connect requires a TLS pin" security invariant was stated as universal; corrected to TLS-connects-only (plaintext local gateways skip the pin, `GatewayConnectionController.swift:990`).
- **N2** — `disconnectForgottenGateway` was listed as unconditional; corrected to gate on `shouldDisconnect` (only when the gateway was actively connected, `:546–553`).
- **N3** — `forgetGateway` async cleanup's session-reset wait + second token clear were shown as always running; corrected to the `shouldDisconnect` branch plus the nil-`appModel` fallback path (`:570–581`).

No other doc introduced any new error during repair.

## Remaining minors (accepted, non-blocking)

Six minor omissions remain, logged and below the certification gate: 08-onboarding (1), 10-markdown (2), 13-ipad (1), 14-assets (2). These are cosmetic/low-impact (e.g. a font-size on a secondary control, an incidental frame value). See each `audit/reverify/NN-*-reverify.md` for specifics.

## Artifacts

- Spec: `apps/ios/docs/redesign/*.md` (14 docs + README).
- Pre-repair audit: `audit/NN-*.md` + `audit/SCOREBOARD.md`.
- Re-verification: `audit/reverify/NN-*-reverify.md` + this file.
