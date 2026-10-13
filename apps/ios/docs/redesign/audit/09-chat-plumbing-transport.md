# Audit — 09-chat-plumbing-transport.md

## Scorecard

| metric | value |
|---|---|
| precision | 0.966 |
| recall | 0.467 |
| F | 0.629 |
| critical | 0 |
| major | 15 |
| minor | 19 |
| certified | false |
| claims | 53 |

## Defects (fix these)

### Wrong / Unsupported Claims

**major** — Doc says dedupeKey fallback includes toolCallId and toolName in format `<role>|<timestamp>|<toolCallId>|<toolName>|<contentFingerprint>`. Actual fallback (lines 778-782) is `"\(message.role)|\(timestamp)|\(text)"` — role, timestamp, and plain joined text only; no toolCallId, toolName, or content fingerprint. — `ChatViewModel+HistoryReconciliation.swift:748-783`

### Omissions

**major** — dedupeKey fallback (section 4.3): spec says fallback key uses "timestamp + text" but actual fallback uses `role|timestamp|text` where text is content items' text joined by newline (not a content fingerprint). Critically, a message with nil timestamp returns nil (passes through unconditionally) — the spec says "rows with no computable key pass through unconditionally" but omits that nil timestamp alone causes pass-through even when text is present. — `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatViewModel+HistoryReconciliation.swift:768-783`

**minor** — messageIdentityKey fallback key format (section 4.2): the nil-return condition checks timestamp AND contentFingerprint AND toolCallId AND toolName all empty simultaneously, which is not documented. Also omits that timestamp is formatted as `%.3f` only when finite. — `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatViewModel+HistoryReconciliation.swift:141-153`

**major** — sessionTarget resolution table (section 1.6) is missing a critical sub-case: when rawSessionKey begins with `agent:` prefix and has a parseable agentID segment, the output agentID is overrideAgentID only (not selected). When the key has `agent:` prefix with no parseable agent segment, the output agentID is nil. The spec collapses these but the code checks `agentID(fromSessionKey)` first, then `hasPrefix("agent:")` for the no-embedded-agent case. The distinction matters for overrideAgentID injection. — `Sources/Chat/IOSGatewayChatTransport.swift:418-434`

**minor** — globalAgentId normalization on init: spec says "lowercased, trimmed" but omits the nil-if-empty guard — if the trimmed/lowercased result is empty string, globalAgentId is stored as nil (not empty string). Same nil-if-empty guard applies to outboxGatewayID (only trimmed, no lowercase). — `Sources/Chat/IOSGatewayChatTransport.swift:148-151`

**minor** — models.list decoding (section 1.8): spec says "empty names fall back to model.id" but actual logic is: the name is trimmed, and if the trimmed name is empty then model.id is used, otherwise the original model.name (not the trimmed version) is used. A rebuilder using the trimmed name when non-empty would differ from the code. — `Sources/Chat/IOSGatewayChatTransport.swift:322-327`

**minor** — commands.list agentId extraction (section 1.8): spec summarizes "agentId extracted from sessionKey or falls back to globalAgentId" but does not document that agentID extraction reads parts[1] when parts.count >= 3 and parts[0] == "agent" from the canonical key structure. — `Sources/Chat/IOSGatewayChatTransport.swift:591-598`

**major** — commandsListParamsJSON command ID format (section 1.8): the `mapCommandChoice` function constructs `OpenClawChatCommandChoice.id` from `[source.rawValue, name, aliases.first ?? ""].joined(separator: ":")`, producing a non-obvious compound ID. The spec does not document this ID construction at all, only the Source mapping. — `Sources/Chat/IOSGatewayChatTransport.swift:720-732`

**major** — `openClawChatCommandChoice.preferredInvocation` logic: chooses the first textAlias that starts with `/`, falling back to `/name`. `displayInvocation` trims whitespace. These computed properties affect how slash commands are inserted into the composer and are not documented in the spec. — `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatModels.swift:53-60`

**minor** — baseThinkingLevelOptions actual label values: spec lists only IDs `['off','minimal','low','medium','high']` but each `OpenClawChatThinkingLevelOption` has both id and label fields, and the labels are identical to the ids (e.g., id:'off', label:'off'). A rebuilder needs to know the label values to render the picker correctly. — `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatViewModel.swift:564-570`

**major** — canSend gate (section 5.2): spec says gate is `!isSubmittingDraft && !isSending && pendingRuns.isEmpty && hasDraftToSend`. Actual `canSend` checks `pendingRunCount == 0` (not `pendingRuns.isEmpty` directly). `hasDraftToSend` is computed as `(!trimmedInput.isEmpty || !attachments.isEmpty)`. A separate `canSendDraft` also exists that omits the `pendingRunCount == 0` check — these are different predicates. The spec does not document `hasDraftToSend`'s definition or `canSendDraft`. — `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatViewModel.swift:593-599`

**major** — isCurrentSession check (section 2.2): spec documents 4 conditions, but the actual check for the `sessionRoutingContract` condition uses `usesMutableContractRouting` for both the snapshot's contract AND the current contract (either being mutable triggers the check). The spec says only "if usesMutableContractRouting: sessionRoutingContract == snapshot.sessionRoutingContract", which undersells the bidirectional check. — `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatViewModel.swift:673-680`

**major** — SessionSnapshot struct location: spec says it is defined in `ChatViewModel+TranscriptCache.swift:8-14` but the actual struct is defined inside `ChatViewModel.swift` (a private struct inside `OpenClawChatViewModel`). This incorrect sourceRef would send a rebuilder to the wrong file. — `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatViewModel.swift:664-671`

**major** — reconcileRunRefreshMessages trailing local user preservation logic (section 4.5): spec says ambiguous rows "that are not in the incoming and trail the last canonical row are preserved". Actual code has a more nuanced algorithm: it counts refresh identity keys in the incoming set, deducts canonical matches, and deducts pending-send adoptions, only preserving trailing rows whose count exceeds what the incoming can explain. Identical-text sends are specifically handled to avoid consuming canonical rows twice. — `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatViewModel+HistoryReconciliation.swift:651-745`

**major** — adoptProvisionalFinalMessage (section 4.6): spec says "the canonical row's content replaces the provisional row's content while the original UUID is preserved". Actual code REMOVES the provisional row from its position and APPENDS at the end (to honor the session.message transcript position), then calls `replaceMessages`/`dedupeMessages`. The spec does not clarify that the row moves to the end. — `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatViewModel+HistoryReconciliation.swift:603-618`

**minor** — pruneRunMessageScopes bounded cleanup: when `runMessageScopesByRunID` exceeds 64 entries it is pruned to only entries referenced by `pendingRuns` or `provisionalFinalMessages`. When `runsAnsweredViaLiveStream` exceeds 64 entries it is intersected with `pendingRuns`. Neither bound nor the pruning behavior is mentioned in the spec. — `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatViewModel+HistoryReconciliation.swift:473-488`

**major** — OpenClawChatUsage.total field decoding: the spec mentions "total (also reads totalTokens)" in section 3, which is correct, but the `OpenClawChatUsageCost` fields (input, output, cacheRead, cacheWrite, total as Doubles) are a separate nested struct not documented. A rebuilder needs to know cost is a nested object, not a scalar. — `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatModels.swift:63-110`

**minor** — OpenClawChatSessionEntry fields omitted from spec (section 2.5): the actual struct has many fields not mentioned: kind, category, archived, archivedAt, unread, surface, subject, room, space, lastReadAt, lastActivityAt, sessionId, systemSent, abortedLastRun, verboseLevel, inputTokens, outputTokens, thinkingOptions, thinkingDefault. Fields archivedAt, unread, lastActivityAt, inputTokens, and outputTokens affect sort/display logic. — `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatSessions.swift:82-201`

**minor** — OpenClawChatSessionListOrganizer.organize fallback when pinnedAt is nil but isPinned is false: pinnedAt is treated as 0 (not greatestFiniteMagnitude). Only isPinned==true gets greatestFiniteMagnitude treatment. The spec only mentions "when pinnedAt is nil and isPinned is true", missing that nil+false = 0 so unpinned sessions without pinnedAt sort normally by updatedAt. — `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatSessions.swift:207-220`

**minor** — OpenClawChatSessionListOrganizer has a local `filter()` function for offline search not mentioned in the spec. It searches displayName, label, subject, sessionId, and key fields (case-insensitive contains). This matters for offline cache search behavior. — `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatSessions.swift:225-239`

**minor** — OpenClawChatSessionsListResponse fields: spec says it "contains the defaults object and the session array" but omits ts (Double?), path (String?), and count (Int?) fields from the response struct. — `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatSessions.swift:242-262`

**minor** — audio attachment construction from MediaPaths/MediaTypes (section 3): spec says audio-type MIME entries are appended as "type: file" content items. Actual code also sets fileName from `(mediaPath as NSString).lastPathComponent` — the filename derivation is not mentioned in the spec. — `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatModels.swift:340-352`

**minor** — compactSession response handling: after the `gateway.request` call, code calls `OpenClawSessionsCompactResponse.requireSuccess(from: response)`. The spec documents no response structure or success check for sessions.compact; it only says timeout=0. — `Sources/Chat/IOSGatewayChatTransport.swift:559-564`

**major** — agents.list RPC (outbox route lease): the transport calls `agents.list` with params `{}` and timeout 15s to acquire the session routing contract. This RPC is entirely absent from the spec, which skips the `acquireOutboxRouteLease` flow entirely. — `Sources/Chat/IOSGatewayChatTransport.swift:190-209`

**minor** — health RPC (section 1 missing): the transport implements `requestHealth(timeoutMs:)` which calls the `health` method and decodes `OpenClawGatewayHealthOK`. The health polling on tick events calls this. The spec mentions health events in section 9.5 but does not document the `transport.requestHealth` RPC itself. — `Sources/Chat/IOSGatewayChatTransport.swift:772-776`

**major** — forkSession agentId extraction: uses `Self.agentID(fromSessionKey: parentKey) ?? self.selectedGlobalAgentId(for: parentKey)`. Spec section 1.3 fork path says "agentId: extracted from parentKey" without documenting the `selectedGlobalAgentId` fallback or its logic. — `Sources/Chat/IOSGatewayChatTransport.swift` (forkSession path)

## Verdict

NEEDS-REPAIR — 15 major blocking defects.
