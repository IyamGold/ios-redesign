# Re-verify — 09-chat-plumbing-transport.md

## Scorecard

| metric | value |
|---|---|
| originalDefectCount | 34 (15 major + 19 minor) |
| resolvedCount | 34 |
| unresolved | 0 |
| newErrors | 0 |
| remainingOmissions | 0 |
| certified | true |

## Unresolved Defects

None.

All 34 original defects were resolved in the repaired doc, verified against the live source files. Key verifications:

- **dedupeKey fallback format** (`ChatViewModel+HistoryReconciliation.swift:778-782`): repaired doc §4.3 correctly states fallback is `"<role>|<timestamp>|<text>"` (plain joined text, no toolCallId/toolName/fingerprint).
- **dedupeKey nil-timestamp pass-through** (same location): repaired doc §4.3 explicitly states nil timestamp alone causes pass-through even when text is present.
- **messageIdentityKey nil condition** (`ChatViewModel+HistoryReconciliation.swift:149`): repaired doc §4.2 states nil returned only when all four fields empty simultaneously.
- **sessionTarget rows 1 vs 2** (`IOSGatewayChatTransport.swift:418-422`): repaired doc §1.6 table correctly distinguishes canonical-key path (agentID = override) from bare `agent:`-prefix path (agentID = nil).
- **globalAgentId nil-if-empty guard** (`IOSGatewayChatTransport.swift:148-151`): documented in §1.1 with code snippet.
- **models.list un-trimmed name** (`IOSGatewayChatTransport.swift:322-327`): repaired doc §1.8 correctly specifies original un-trimmed `model.name` used when non-empty after trim.
- **commandsListParamsJSON compound ID** (`IOSGatewayChatTransport.swift:720-724`): repaired doc §1.8 documents `[source.rawValue, trimmedName, aliases.first ?? ""].joined(separator: ":")`.
- **preferredInvocation/displayInvocation** (`ChatModels.swift:53-60`): repaired doc §1.8 documents both computed properties.
- **canSend / canSendDraft** (`ChatViewModel.swift:593-603`): repaired doc §5.2 distinguishes `pendingRunCount == 0`, `hasDraftToSend`, and sibling `canSendDraft`.
- **isCurrentSession bidirectional contract check** (`ChatViewModel.swift:673-680`): repaired doc §2.2 shows exact code snippet.
- **SessionSnapshot location** (`ChatViewModel+TranscriptCache.swift:8-14`): repaired doc §2.2 correctly cites this file. Grep-confirmed: struct is at line 8 of that file (original audit's claim it was in `ChatViewModel.swift` was itself wrong about current code).
- **reconcileRunRefreshMessages algorithm** (`ChatViewModel+HistoryReconciliation.swift:651-746`): repaired doc §4.5 contains the detailed 8-step algorithm matching the code.
- **adoptProvisionalFinalMessage repositioning** (`ChatViewModel+HistoryReconciliation.swift:603-618`): repaired doc §4.6 correctly states row is removed then appended at end.
- **pruneRunMessageScopes 64-entry bounds** (`ChatViewModel+HistoryReconciliation.swift:473-488`): documented in §4.8.
- **OpenClawChatUsageCost nested struct** (`ChatModels.swift:63-110`): repaired doc §3 documents cost as nested struct with five Double? fields.
- **OpenClawChatSessionEntry additional fields** (`ChatSessions.swift:82-201`): repaired doc §2.5 lists all additional fields.
- **pinnedAt nil + isPinned false → 0** (`ChatSessions.swift:207-220`): repaired doc §2.5 explicitly covers all three cases.
- **OpenClawChatSessionListOrganizer.filter** (`ChatSessions.swift:225-239`): documented in §2.5.
- **OpenClawChatSessionsListResponse ts/path/count fields** (`ChatSessions.swift:242-262`): documented in §2.5.
- **audio attachment fileName derivation** (`ChatModels.swift:340-352`): documented in §3.
- **compactSession requireSuccess** (`IOSGatewayChatTransport.swift:559-564`): documented in §1.3.
- **agents.list RPC** (`IOSGatewayChatTransport.swift:190-209`): fully documented in §1.2.1.
- **health RPC** (`IOSGatewayChatTransport.swift:772-776`): documented in §1.4.
- **forkSession selectedGlobalAgentId fallback** (`IOSGatewayChatTransport.swift:528-534`): documented in §1.3.

## New Errors

None found. Sampled claims in newly-added sections verified against source:

- `agents.list` route-pinned call: `ifCurrentRoute: route` confirmed at `IOSGatewayChatTransport.swift:196`.
- `canSend` gate: exact `!isSubmittingDraft && !isSending && pendingRunCount == 0 && hasDraftToSend` confirmed at `ChatViewModel.swift:593-594`.
- `hasDraftToSend` definition: confirmed at `ChatViewModel.swift:597-600`.
- `canSendDraft` omits `pendingRunCount` check: confirmed at `ChatViewModel.swift:602-603`.
- bidirectional `contractSensitive` snippet: confirmed at `ChatViewModel.swift:673-675`.
- `dedupeKey` fallback nil conditions (nil timestamp or empty text): confirmed at `ChatViewModel+HistoryReconciliation.swift:778-782`.
- `messageIdentityKey` returns nil when all four fields empty: confirmed at `ChatViewModel+HistoryReconciliation.swift:149`.
- Compound command choice id format: confirmed at `IOSGatewayChatTransport.swift:720-724`.
- `preferredInvocation` picks first alias starting with `/`, fallback `/name`: confirmed at `ChatModels.swift:53-56`.
- `OpenClawChatUsageCost` five Double? fields: confirmed at `ChatModels.swift:63-69`.
- Session list sort: `pinnedAt ?? (isPinned ? .greatestFiniteMagnitude : 0)` confirmed at `ChatSessions.swift:209`.
- `forkSession` agentId: `agentID(fromSessionKey:) ?? selectedGlobalAgentId(for:)` confirmed at `IOSGatewayChatTransport.swift:531`.

## Remaining Omissions

None with replication-critical severity.

---

**CERTIFIED** — zero critical or major issues remain across unresolved defects, new errors, and remaining omissions.
