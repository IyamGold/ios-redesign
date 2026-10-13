# Chat State, Data & Transport

This document specifies the full behavior layer behind the iOS chat surface. It covers every gateway RPC issued by `IOSGatewayChatTransport`, the lifecycle owned by `OpenClawChatViewModel` and its extensions (history reconciliation, reply dedupe, gateway-seq ordering, pending-run timeout, transcript cache, attachment staging), and all invariants that govern session routing, derived titles, and the thinking-level omission rule. A competent engineer should be able to rebuild this layer exactly from this document without reading the source.

---

## 1. Transport Layer: `IOSGatewayChatTransport`

File: `Sources/Chat/IOSGatewayChatTransport.swift`

`IOSGatewayChatTransport` is a `struct` conforming to the `OpenClawChatTransport` protocol. It wraps a `GatewayNodeSession` and encodes every RPC as a typed `Codable` params object before calling `gateway.request(method:paramsJSON:timeoutSeconds:)`.

### 1.1 Initialization

| Property | Type | Description |
|---|---|---|
| `gateway` | `GatewayNodeSession` | The active WebSocket gateway session. |
| `globalAgentId` | `String?` | Lowercased, trimmed agent id injected at construction; `nil` when empty. Used as the `agentId` field for alias keys (e.g., `"main"`, `"global"`). |
| `outboxGatewayID` | `String?` | When set, all outbox-route lease acquisition is gated on this specific gateway identity so stale routes never replay durable commands. |

`outboxRequiresSessionRoutingContract` returns `true` unconditionally, meaning every outbox lease requires the gateway to support `chatSendRoutingContract`. (`IOSGatewayChatTransport.swift:15-17`)

### 1.2 Constants

| Constant | Value | Meaning |
|---|---|---|
| `defaultChatSendTimeoutMs` | `30000` | Passed as `timeoutMs` in every `ChatSendParams` payload. |
| `compactionRequestTimeoutSeconds` | `0` | Zero = no timeout on `sessions.compact`. |
| Logger subsystem | `ai.openclawfoundation.app` | OSLog subsystem for this transport. |
| Logger category | `ios.chat.transport` | OSLog category. |

### 1.3 Session RPCs

#### `sessions.create`

Method: `sessions.create`  
Timeout: 15 s  
Params struct: `CreateSessionParams`

| Field | Type | Notes |
|---|---|---|
| `key` | `String` | The resolved session key from `sessionTarget(for:)`. |
| `agentId` | `String?` | From target or parent target's agentId. |
| `label` | `String?` | User-supplied label, can be `nil`. |
| `parentSessionKey` | `String?` | Resolved parent key, can be `nil`. |
| `worktree` | `Bool?` | `true` for worktree sessions, omitted otherwise. |

Returns `OpenClawChatCreateSessionResponse` (`ok: Bool?`, `key: String`, `sessionId: String?`).

#### `sessions.list`

Method: `sessions.list`  
Timeout: 15 s  
Params struct: `ListSessionsParams`

| Field | Value |
|---|---|
| `includeGlobal` | `true` (always) |
| `includeUnknown` | `false` (always) |
| `limit` | caller-supplied or `nil` |
| `search` | trimmed search string or `nil` if empty |
| `archived` | `true` only when fetching archived; omitted (`nil`) for normal fetch |
| `includeDerivedTitles` | `true` (always) |

**`includeDerivedTitles` is critical.** Without it, the gateway does not read the transcript file and `derivedTitle` returns `nil`, so untitled sessions fall back to a generic dated placeholder. The flag triggers a file-I/O read on the gateway side. (`IOSGatewayChatTransport.swift:39-43`)

Returns `OpenClawChatSessionsListResponse` which contains the `defaults` object (`OpenClawChatSessionsDefaults`) including `mainSessionKey`, as well as the session array.

#### `sessions.patch`

Method: `sessions.patch`  
Timeout: 15 s

The patch method accepts an open `[String: Any]` dictionary (not a closed struct) so `NSNull` can express explicit `nil` for `label` and `category`. Any field that is not provided is not sent. Called for:

- Renaming a session (`label`)
- Pinning / unpinning (`pinned`)
- Archiving / restoring (`archived`)
- Marking read/unread (`unread`)
- Changing model (`model`, uses `SessionPatchModelParams` which force-encodes `nil` as JSON `null`)

For the `"global"` session key, `agentId` is set to `globalAgentId`; for all other keys it is omitted. (`IOSGatewayChatTransport.swift:399-403`)

#### `sessions.delete`

Method: `sessions.delete`  
Timeout: 15 s  
`deleteTranscript: true` always. `agentId` is set only for the `"global"` key.

#### `sessions.messages.subscribe`

Method: `sessions.messages.subscribe`  
Timeout: 10 s

Sends `{ key: resolvedSessionKey, agentId? }`. This is the "set active session" call. The gateway then pushes `session.message` events for that session over the existing WebSocket. (`IOSGatewayChatTransport.swift:536-548`)

#### `sessions.reset`

Method: `sessions.reset`  
Timeout: 10 s  
Params: `{ key, agentId? }` via `SessionKeyParams`.

#### `sessions.compact`

Method: `sessions.compact`  
Timeout: `compactionRequestTimeoutSeconds` = 0 (no timeout)  
Params: `{ key, agentId? }` via `SessionKeyParams`. Callers use a 60 s cooldown guard on the UI side.

#### `sessions.create` (fork path)

Called via `forkSession(parentKey:)`. Uses `ForkSessionParams`:

| Field | Value |
|---|---|
| `parentSessionKey` | resolved parent key |
| `fork` | `true` (always) |
| `agentId` | extracted from parent key or `selectedGlobalAgentId` |

Returns the new session key from `OpenClawChatCreateSessionResponse.key`.

### 1.4 Chat RPCs

#### `chat.send`

Method: `chat.send`  
Timeout: **35 s** (note: different from the 30 s `timeoutMs` sent in the payload)  
Params struct: `ChatSendParams`

| Field | Type | Notes |
|---|---|---|
| `sessionKey` | `String` | Resolved by `sessionTarget(for:overrideAgentID:)`. |
| `agentId` | `String?` | From the resolved target; nil if already embedded in key. |
| `expectedSessionRoutingContract` | `String?` | Set when `supportsRoutingContract` capability is confirmed. Omitted on legacy gateways. |
| `message` | `String` | The user text. |
| `thinking` | `String?` | **Omitted entirely when the client sends `""`** — which is the signal for "no explicit user choice." This omission lets the gateway apply the model's default. Reasoning-mandatory models such as `xai/grok-4.6` reject an explicit `"off"`. (`IOSGatewayChatTransport.swift:103-105`) |
| `attachments` | `[OpenClawChatAttachmentPayload]?` | Omitted (nil) when empty. |
| `timeoutMs` | `Int` | `defaultChatSendTimeoutMs` = 30 000. |
| `idempotencyKey` | `String` | The local run UUID, used for at-least-once deduplication. |

Returns `OpenClawChatSendResponse` (`runId: String`, `status: String`).

When a `GatewayNodeSessionRequestError` is thrown (meaning the captured route changed before dispatch), the error is re-thrown as `OpenClawChatTransportSendError.notDispatched` so the caller knows the message was never sent and can retry cleanly. (`IOSGatewayChatTransport.swift:692-695`)

Diagnostic strings are written to both `OSLog` and `GatewayDiagnostics.log` at start, success, and failure.

#### `chat.history`

Method: `chat.history`  
Timeout: 15 s  
Params: `{ sessionKey, agentId? }` resolved via `sessionTarget(for:overrideAgentID:)`.

Returns `OpenClawChatHistoryPayload`:

| Field | Type | Notes |
|---|---|---|
| `sessionKey` | `String` | Echo of the requested key. |
| `sessionId` | `String?` | Opaque session identity, stored on the view model. |
| `messages` | `[AnyCodable]?` | Raw decoded message array. |
| `thinkingLevel` | `String?` | Gateway's current thinking level for this session. |
| `sessionInfo` | `OpenClawChatSessionInfo?` | Contains `hasActiveRun: Bool?`. |
| `inFlightRun` | `OpenClawChatInFlightRun?` | Contains `runId` and buffered `text` for the currently streaming run. |

#### `chat.abort`

Method: `chat.abort`  
Timeout: 10 s  
Best-effort. Errors are silently swallowed.

### 1.5 Agent Wait RPC

Method: `agent.wait`  
Timeout: `max(1, ceil(timeoutMs / 1000)) + 5` seconds (always 5 s above the payload timeout).

Params: `{ runId, timeoutMs }` where `timeoutMs` is `pendingRunTimeoutMs` (120 000 ms).

Returns `AgentWaitCompletion`. Terminal statuses: `"ok"`, `"completed"`, `"success"`, `"succeeded"` (case-insensitive, whitespace-trimmed). (`IOSGatewayChatTransport.swift:133-140`)

### 1.6 Session Routing and Key Resolution

`sessionTarget(for:selectedAgentID:overrideAgentID:)` is the canonical key resolver.

| Input pattern | Output `sessionKey` | Output `agentID` |
|---|---|---|
| `"agent:<agent>:<key>"` (already canonical) | unchanged | `overrideAgentID` only |
| `"agent:..."` prefix but no embedded agent segment | unchanged | `nil` |
| `"unknown"` | unchanged | `nil` |
| `"global"` | `"global"` | `override ?? selected` |
| Any other alias when `targetAgentID` is known | `"agent:<targetAgentID>:<key>"` | `nil` |
| Any other alias when no agent known | unchanged | `nil` |

(`IOSGatewayChatTransport.swift:410-435`)

When the resolved `sessionKey` is exactly `"global"`, `selectedGlobalAgentId(for:)` also injects `globalAgentId` as the `agentId` for patch/delete calls.

### 1.7 Event Subscription

`events()` returns an `AsyncStream<OpenClawChatTransportEvent>` that maps `EventFrame` events from `gateway.subscribeServerEvents()`.

| `evt.event` | Mapped to |
|---|---|
| `"tick"` | `.tick` |
| `"seqGap"` | `.seqGap` |
| `"health"` | `.health(ok:)` (decoded from payload) |
| `"chat"` | `.chat(OpenClawChatEventPayload)` |
| `"session.message"` | `.sessionMessage(OpenClawSessionMessageEventPayload)` |
| `"agent"` | `.agent(OpenClawAgentEventPayload)` |
| anything else | dropped (`nil`) |

(`IOSGatewayChatTransport.swift:798-840`)

### 1.8 Model and Command Catalog RPCs

| Method | Timeout | Notes |
|---|---|---|
| `models.list` | 15 s | No params. Returns `ModelsListResponse.models` decoded to `[OpenClawChatModelChoice]`. Empty names fall back to `model.id`. |
| `commands.list` | 15 s | `{ scope: "text", includeArgs: true, agentId? }`. `agentId` is extracted from `sessionKey` or falls back to `globalAgentId`. |

Command source mapping from the `"source"` field: `"native"` → `.command`, `"skill"` → `.skill`, `"plugin"` → `.plugin`, anything else → `.unknown`. (`IOSGatewayChatTransport.swift:706-712`)

---

## 2. View Model: `OpenClawChatViewModel`

File: `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatViewModel.swift` (and extensions)

`@MainActor @Observable public final class OpenClawChatViewModel`. All state reads and mutations happen on the MainActor. Background fetches jump back to MainActor before touching any stored property.

### 2.1 Key Observable Properties

| Property | Access | Description |
|---|---|---|
| `messages` | `internal(set)` | Ordered `[OpenClawChatMessage]` — the live transcript. Mutated only through `replaceMessages(_:)`. |
| `input` | `public var` | Composer text. Cleared immediately on send before any network await. |
| `thinkingLevel` | `private(set)` | Current thinking level string. `"off"` when no gateway metadata forces otherwise. |
| `thinkingLevelOptions` | `internal(set)` | Array of `OpenClawChatThinkingLevelOption` for the picker. Base set: `["off","minimal","low","medium","high"]`. |
| `showsThinkingPicker` | `internal(set)` | Whether the picker is visible; `false` when gateway metadata allows only `"off"` or the model reports `reasoning: false`. |
| `modelSelectionID` | `private(set)` | Provider-qualified model ID or `"__default__"`. |
| `modelChoices` | `private(set)` | `[OpenClawChatModelChoice]` from `models.list`. |
| `sessions` | `internal(set)` | `[OpenClawChatSessionEntry]` organized by `OpenClawChatSessionListOrganizer`. |
| `sessionKey` | `private(set)` | Active session key. Changing it calls `syncContextUsageFraction()`. |
| `sessionId` | `private(set)` | Opaque id from history payload. |
| `pendingRunCount` | `private(set)` | Count of in-flight run IDs; drives "thinking" indicator. |
| `streamingAssistantText` | `private(set)` | Accumulated text from the current `chat.delta` stream. |
| `isLoading` | `private(set)` | True during bootstrap. |
| `isSending` | `private(set)` | True between send initiation and transport return. |
| `isAborting` | `private(set)` | True while `chat.abort` RPCs are in flight. |
| `isShowingCachedTranscript` | `internal(set)` | `true` while the transcript came from the offline SQLite cache and has not yet been replaced by a live response. |
| `hasAppliedLiveHistory` | `internal` | Guard preventing a late cache read from overwriting a live response. |
| `contextUsageFraction` | `internal(set)` | `totalTokens / contextTokens`, clamped to `[0,1]`, or `nil` when not computable. |
| `healthOK` | `internal(set)` | Reflects the most recent gateway health event. |
| `errorText` | `public var` | User-visible error string; nil on success. |
| `attachments` | `public var` | Staged `[OpenClawPendingAttachment]`. |

Constants:

| Constant | Value |
|---|---|
| `defaultModelSelectionID` | `"__default__"` |
| `maxAttachmentBytes` | 5 000 000 (5 MB) |
| `sessionListFetchLimit` | 200 |
| `pendingRunTimeoutMs` | 120 000 ms (2 minutes) |
| `postSendRefreshDelaysMs` | `[1500, 4000, 9000, 20000, 45000, 90000]` ms |
| `compactCooldown` | 60 s |
| `maxOutboxSendAttempts` | 3 |

### 2.2 Session Generation and Snapshot

Every switch to a new session increments `sessionGeneration: UInt64`. Every async operation captures `currentSessionSnapshot()` at the moment it starts. Before applying any result the operation calls `isCurrentSession(snapshot)`, which checks:

1. `sessionKey == snapshot.key`
2. `sessionGeneration == snapshot.generation`
3. If `usesMutableAgentRouting`: `activeAgentId == snapshot.agentID`
4. If `usesMutableContractRouting`: `sessionRoutingContract == snapshot.sessionRoutingContract`

This prevents stale network responses from overwriting a session the user has already navigated away from.

`SessionSnapshot` (inner struct in `ChatViewModel+TranscriptCache.swift:8-14`):
```swift
struct SessionSnapshot {
    var key: String
    var generation: UInt64
    var agentID: String?
    var deliveryAgentID: String?
    var sessionRoutingContract: String?
}
```

`deliveryAgentID` is the agent used on the wire: extracted from the session key if canonical (`"agent:<id>:<key>"`), otherwise `activeAgentId`.

### 2.3 Bootstrap Flow

Called on `load()`, `refresh()`, and after any session switch.

```
startBootstrap()
  ↓ increment bootstrapGeneration, cancel previous bootstrapTask
  ↓ isLoading = true, healthOK = false, clear pending runs / streaming text / sessionId
  ↓ paintFromCacheIfNeeded(session)   [async, non-blocking]
  ↓ restoreOutboxMessages(session)
  ↓ Task: bootstrap(context)
       ↓ syncActiveSessionSubscription(sessionKey)   [sends sessions.messages.subscribe, retrying on key drift]
       ↓ transport.requestHistory(sessionKey)        [chat.history RPC]
       ↓ applyHistoryPayload(preservingOptimisticLocalMessages: false, syncThinkingOptions: true)
       ↓ pollHealthIfNeeded(force: true)
       ↓ fetchSessions(limit: 50)     [sessions.list with includeDerivedTitles: true]
       ↓ fetchModels()                [models.list]
       ↓ isLoading = false
```

`syncActiveSessionSubscription` loops until the session key that was subscribed matches the current session key, retrying when it detects drift. This ensures that if the user switches sessions while the subscribe RPC is in flight, the final state is consistent. (`ChatViewModel.swift:943-963`)

### 2.4 Session Switching

`switchSession(to:)` calls `applySessionSwitch(to:intent:.userInitiated)`.  
`syncSession(to:)` calls `applySessionSwitch(to:intent:.externalSync)`.

Switching is blocked when `blocksAttachmentOwnerChange` is true (camera/mic active, attachment staging in progress, or non-empty attachment list, or `isSendingAttachmentDraft`). User-initiated switches surface an error; external syncs are deferred into `deferredExternalSessionKey` and applied once the block clears.

On switch:
1. `advanceSessionGeneration()`
2. `sessionKey = next`
3. Fire `onSessionChanged?(next)` (user-initiated only)
4. `clearSessionOwnedState()` — zeroes messages, pending runs, provisional finals, streaming text, model selection, slash catalog, outbox presentation state, etc.
5. `startBootstrap(sessionKey: next)`

### 2.5 Session Model (`OpenClawChatSessionEntry`)

Key fields relevant to behavior:

| Field | Type | Notes |
|---|---|---|
| `key` | `String` | Unique session key; used as `id`. |
| `derivedTitle` | `String?` | Gateway-derived first-message title, only present when `includeDerivedTitles: true` was sent in `sessions.list`. |
| `displayName` | `String?` | User-set label or gateway display name. |
| `label` | `String?` | Explicit user-set label. |
| `pinnedAt` | `Double?` | Epoch ms; used for sort order. |
| `updatedAt` | `Double?` | Epoch ms; secondary sort key. |
| `model` | `String?` | Currently active model ID. |
| `modelProvider` | `String?` | Currently active provider. |
| `thinkingLevel` | `String?` | Per-session thinking level from gateway. |
| `thinkingLevels` | `[OpenClawChatThinkingLevelOption]?` | Gateway-supplied thinking options (authoritative when present). |
| `totalTokens` | `Int?` | Used for context usage fraction. |
| `contextTokens` | `Int?` | Token budget; denominator for usage fraction. |
| `totalTokensFresh` | `Bool?` | When `false`, usage fraction is not computed (stale data). |

Session list ordering (`OpenClawChatSessionListOrganizer.organize`): `pinnedAt desc → updatedAt desc → key asc`. When `pinnedAt` is nil and `isPinned` is true, `pinnedAt` is treated as `Double.greatestFiniteMagnitude`.

`resolvedMainSessionKey` reads `sessionDefaults?.mainSessionKey`, trimmed; falls back to `"main"` if nil or empty.

### 2.6 Main Session Aliasing

Sessions `"main"`, `"global"`, `"agent:main:main"`, and the gateway-supplied `mainSessionKey` from `OpenClawChatSessionsDefaults` are treated as aliases of each other by `matchesCurrentSessionKey`. The routing match logic (`ChatViewModel+SessionKeys.swift:84-141`) handles:

- Exact key equality (with optional agent-id cross-check)
- `matchesMainAlias`: `"main"` ↔ `mainSessionKey`, and `"main"` ↔ `"agent:main:main"`
- `matchesSelectedAgentWrapper`: `"agent:<id>:<key>"` ↔ `"<key>"` for the same underlying key
- `matchesSelectedAgentGlobal`: incoming `"global"` + an `agentId` matches `"agent:<agentId>:global"`

This prevents gateway events published with a canonical key from being dropped when the client is tracking an alias key, which would otherwise leave the UI permanently stuck in "thinking."

---

## 3. Message Model (`OpenClawChatMessage`)

File: `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatModels.swift:190`

| Field | Wire key | Notes |
|---|---|---|
| `id` | (local UUID, not encoded) | Client-only stable bubble identity; survives all reconciliation. |
| `role` | `role` | `"user"` or `"assistant"`. |
| `content` | `content` | `[OpenClawChatMessageContent]` or a plain string on some log formats. |
| `timestamp` | `timestamp` | Epoch ms as `Double?`. |
| `idempotencyKey` | `idempotencyKey` or `__openclaw.idempotencyKey` | Present on user turns (the run UUID) and on some assistant turns. |
| `serverMessageId` | `__openclaw.id` (wire) / `serverMessageId` (cache) | Durable gateway-assigned row id; nil until canonical row arrives. |
| `serverSeq` | `__openclaw.seq` (wire) / `serverSeq` (cache) | Session-global monotonic transcript position; nil on transient rows. |
| `stopReason` | `stopReason` | `"error"`, `"aborted"`, or nil. |
| `errorMessage` | `errorMessage` | Non-nil only when `stopReason == "error"`. |
| `toolCallId` | `toolCallId` or `tool_call_id` | Both forms decoded. |
| `toolName` | `toolName` or `tool_name` | Both forms decoded. |
| `usage` | `usage` | `OpenClawChatUsage` with `input`, `output`, `cacheRead`, `cacheWrite`, `cost`, `total` (also reads `totalTokens`). |

Audio attachments: when `MediaPaths`/`MediaPath` and `MediaTypes`/`MediaType` fields are present, audio-type MIME entries are appended as `type: "file"` content items unless the `content` array already contains audio items.

---

## 4. History Reconciliation

File: `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatViewModel+HistoryReconciliation.swift`

All mutations to the `messages` array funnel through `replaceMessages(_:)`, which first calls `orderedBySequence(_:)` and then assigns the result.

### 4.1 Gateway-Seq Ordering (`orderedBySequence`)

`orderedBySequence` sorts by `serverSeq`, which is a session-global monotonic counter the gateway assigns to every persisted row. (`ChatViewModel+HistoryReconciliation.swift:86-103`)

- If **no** message has a `serverSeq`, the array is returned unchanged (order preserved).
- Otherwise, a "carried seq" is propagated forward: each message's sort key is its own `serverSeq` if present, or the `serverSeq` of the immediately preceding message in the original array. Tie-breaks go by original array index.
- This ensures transient rows (optimistic user echo, in-flight streaming text) hold their position relative to adjacent canonical rows rather than jumping to the end.
- The algorithm is idempotent: an already-ordered, fully-seq'd list returns unchanged.

**Why this matters:** A `sessions_send`-routed reply from another surface can arrive at the client with an earlier `serverSeq` than a message already displayed. Without this sort, it would appear at the bottom of the transcript instead of its true chronological position.

### 4.2 Message Identity Key (`messageIdentityKey`)

Priority order for message deduplication and reconciliation:

1. **`serverMessageId`** — uniquely identifies a persisted gateway row; preferred above all. Key format: `"<role>|serverid|<serverMessageId>"`.
2. **`idempotencyKey`** — the client's run UUID (user turns) or gateway-stamped assistant key. Key format: `"<role>|idempotency|<key>"`.
3. **Timestamp + content fingerprint + tool fields** — last resort for rows with neither. Key format: `"<role>|<timestamp>|<toolCallId>|<toolName>|<contentFingerprint>"`. A message with all empty fields returns `nil` (never deduped).

Content fingerprint joins `type`, `text`, `id`, `name`, `fileName` with unit separator `\u{001F}` for each content item, joined by record separator `\u{001E}`.

### 4.3 Reply Dedupe (`dedupeMessages` / `dedupeKey`)

`dedupeKey` follows the same priority: `serverMessageId` → `idempotencyKey` → `timestamp + text`. Rows with no computable key pass through unconditionally. The first occurrence of a key in the array wins; later duplicates are dropped. (`ChatViewModel+HistoryReconciliation.swift:748-783`)

### 4.4 ID Reconciliation (`reconcileMessageIDs`)

When incoming messages and previous messages share an identity key but different `UUID`s, the incoming message is "adopted" over the existing one: `id` is taken from the existing message (preserving SwiftUI's stable identity for animations), while all other fields come from the incoming (canonical) message. (`ChatViewModel+HistoryReconciliation.swift:621-649`)

Adoption also carries over `serverMessageId` and `serverSeq` from the incoming if present, upgrading the optimistic row so future reconciliation keys on the canonical id.

Audio attachment `durationSeconds` is preserved from the local row if the canonical row omits it (the gateway does not return local-computed durations). (`ChatViewModel+HistoryReconciliation.swift:227-257`)

### 4.5 Run-Refresh Reconciliation (`reconcileRunRefreshMessages`)

Used when `preservingOptimisticLocalMessages: true` — i.e., all post-send history refreshes where the user echo must survive until canonical history confirms it.

1. Applies `reconcileMessageIDs` first.
2. Builds counts of user-refresh identity keys in the incoming list.
3. Pending local user echo rows whose idempotency key appears in incoming are removed (adopted). Ambiguous ones (no metadata) that are not in the incoming and trail the last canonical row are preserved. (`ChatViewModel+HistoryReconciliation.swift:651-746`)

### 4.6 Provisional Final Messages

When `chat.final` arrives from the gateway, the view model appends a "provisional final" assistant bubble (the optimistic streamed text made permanent) and stores metadata in `provisionalFinalMessagesByID`. Later, when the canonical `session.message` arrives (which may carry different text, a different timestamp, or no idempotency key), `adoptProvisionalFinalMessage` correlates it to the provisional row by:

1. Run-identity key set (`runId` and `"<runId>:assistant"` both match).
2. Fallback: `finalMessageReconciliationKey` (content fingerprint, tool fields) within the same user-turn boundary.

The canonical row's content replaces the provisional row's content while the original `UUID` is preserved (no layout jump). The provisional marker is then removed from `provisionalFinalMessagesByID`. (`ChatViewModel+HistoryReconciliation.swift:581-619`)

**Why this is necessary:** `chat.final` and `session.message` represent the same row but may serialize it differently (different timestamps, different content id fields). Without the provisional final correlation, the UI would show two bubbles for one reply.

### 4.7 Canonical Reply Tracking

When a `session.message` event arrives carrying an assistant message with a `serverMessageId`, and there is exactly one pending run, that run is inserted into:

- `runsWithDeliveredCanonicalReply` — consumed once to prevent the subsequent `chat.final` optimistic append from duplicating the bubble.
- `runsAnsweredViaLiveStream` — retained for the life of the session so both `chat.final` and agent-terminal lifecycle handlers can skip their post-run history refetch (avoiding a redundant full transcript replacement). (`ChatViewModel.swift:2233-2239`)

Runs absent from `runsAnsweredViaLiveStream` still trigger a refetch, preserving the fallback for silent gateways.

---

## 5. Pending Run Lifecycle

File: `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatViewModel+PendingRunTimeout.swift`

`pendingRuns: Set<String>` holds active run IDs. `pendingRunCount` is a derived count updated each time `pendingRuns` changes.

### 5.1 Timeout

`armPendingRunTimeout(runId:)` starts a `Task` that sleeps for `pendingRunTimeoutMs` (120 000 ms = 2 minutes). Each arm call increments `nextPendingRunTimeoutArmID`; the sleeping task checks its `armID` before firing and does nothing if a newer arm superseded it. On timeout:

1. `errorText = "Timed out waiting for a reply; try again or refresh."`
2. `clearPendingRun(runId, hapticEvent: .runFailed)`

`clearPendingRun` cancels the timeout task, removes the run from `pendingRuns`, clears `pendingLocalUserEchoMessageIDsByRunID[runId]`, and fires the haptic if the run was actually pending and no other runs remain. (`ChatViewModel+PendingRunTimeout.swift:4-51`)

`clearPendingRuns` (plural) bulk-clears all runs and their timeout tasks at once (used on bootstrap, seqGap, and session switch).

### 5.2 Send Flow

1. Gate: `!isSubmittingDraft && !isSending && pendingRuns.isEmpty && hasDraftToSend`.
2. Set `isSubmittingDraft = true` (gate against duplicate enqueues during slash catalog lookup).
3. Handle local slash commands (`/new`, `/reset`, `/clear`, `/compact`) before network.
4. Validate slash command draft (blocks commands with attachments).
5. Set `isSending = true`, `isSendingAttachmentDraft` if attachments present.
6. If offline, poll health; if still offline and outbox exists, enqueue durably and return.
7. FIFO ordering: if outbox has un-failed queued rows (or restore has not yet completed), route even live sends through the outbox to maintain ordering.
8. Generate local run UUID (`runId = UUID().uuidString`).
9. Insert into `pendingRuns`, arm timeout.
10. Append optimistic user echo message with `idempotencyKey: "\(runId):user"`.
11. Clear input and sent attachments immediately.
12. Await any pending model patches (`waitForPendingModelPatches`).
13. Resolve `effectiveThinkingLevelForSend` for the stored level.
14. Call `transport.sendMessage(...)`.
15. On response: if `response.runId != runId`, re-key local state to the gateway's run id (gateway may reuse an active identical run). Fire haptic `messageSent` on non-error/timeout status.
16. On `status == "ok"`: refresh history, then `finishPendingRunAfterTerminalOkSendAck`.
17. On other statuses: probe history, arm fallback refresh timers and `agent.wait` completion refresh if no in-flight run snapshot confirms the run is still active.
18. On transport error: attempt to move the message to the offline outbox (`preserveFailedLiveSend`). If preserved, mark health bad and return. Otherwise restore draft text.

### 5.3 Post-Send Refresh Fallback

If the gateway does not deliver either `chat.final` or a confirmed `session.message` for the run, the fallback arms two parallel paths:

- **Timed retries** at `[1500, 4000, 9000, 20000, 45000, 90000]` ms delays, each calling `refreshHistoryAfterRun`.
- **`agent.wait` completion refresh**: calls `transport.waitForRunCompletion(runId:timeoutMs:)` which issues `agent.wait` and on confirmed completion triggers one more history refresh.

Each fallback refresh checks `pendingRuns.contains(runId)` before fetching and stops as soon as the run is no longer pending.

---

## 6. Thinking-Level Omission Rule

File: `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatViewModel+Thinking.swift`

### 6.1 `effectiveThinkingLevelForSend`

```swift
func effectiveThinkingLevelForSend(_ storedLevel: String, sessionKey: String? = nil) -> String {
    let showsPicker: Bool = ...   // from thinkingPickerIsAvailable
    return showsPicker ? storedLevel : "off"
}
```

When `showsThinkingPicker` is `false` (model metadata disallows reasoning), the effective level sent is `"off"`.

### 6.2 Wire Omission (`makeChatSendParamsJSON`)

```swift
thinking: thinking.isEmpty ? nil : thinking
```

The `thinking` field on `ChatSendParams` is `String?`. An empty string becomes `nil`, which `JSONEncoder` omits entirely from the JSON body. (`IOSGatewayChatTransport.swift:282-286`)

**Invariant:** An empty string signals "no user choice → omit the field → gateway applies model default." Reasoning-mandatory models (`xai/grok-4.6` and similar) will reject `"off"` and must receive the omitted field to work. (`IOSGatewayChatTransport.swift:103-105`, CLAUDE.md architecture section)

### 6.3 Thinking Level From History

When a history response contains `thinkingLevel` and the view model was not constructed with an explicit initial thinking level (`prefersExplicitThinkingLevel == false`), `applyHistoryPayload` applies the gateway's value and syncs the picker options. (`ChatViewModel.swift:779-787`)

Base thinking options: `["off", "minimal", "low", "medium", "high"]`. Gateway-supplied `thinkingLevels` on a session or the `sessionDefaults` override the base set when present and non-empty.

---

## 7. Transcript Cache

File: `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatTranscriptCache.swift` (SQLite implementation), `ChatViewModel+TranscriptCache.swift` (integration)

`OpenClawChatSQLiteTranscriptCache` is a Swift `actor` backed by a SQLite database file (one file per gateway identity). It also implements `OpenClawChatCommandOutbox`.

### 7.1 Cache Bounds

| Constant | Value |
|---|---|
| `maxCachedSessions` | 50 |
| `maxCachedTranscripts` | 50 |
| `maxCachedMessagesPerSession` | 200 |
| `maxQueuedCommands` | 50 (outbox) |
| `maxAttachmentBytesPerCommand` | 40 000 000 (40 MB) |
| `maxQueuedAttachmentBytes` | 50 000 000 (50 MB) |
| `outboxCommandMaxAge` | 172 800 s (48 hours) |

### 7.2 Schema Version

Schema version 6 (as of this branch). Earlier versions: v2 adds durable outbox; v3 adds delivery ownership; v4 binds replay to main-routing contract; v5 persists routing identity; v6 keeps bounded attachment bytes inside the same command owner.

Three main tables:
- `cached_sessions` — single JSON payload row per gateway.
- `cached_transcripts` — keyed by `(gateway_id, session_key, agent_id)`.
- `outbox_commands` — durable send queue.
- `gateway_routing_identity` — persisted routing contract (scope, main key, default agent).

### 7.3 Cache-First Cold Open (`paintFromCacheIfNeeded`)

Called at bootstrap start. Two parallel async reads:

1. If `sessions.isEmpty && !hasAppliedLiveSessions`: load cached session list. Apply only if still empty and live has not arrived.
2. If `messages.isEmpty && !hasAppliedLiveHistory`: load cached transcript. Apply only if still empty, still the same session, and live has not arrived.

When cached rows are displayed, `isShowingCachedTranscript = true`. Live history always clears this flag. (`ChatViewModel+TranscriptCache.swift:66-90`)

**Guard:** `hasAppliedLiveHistory` is set to `true` the moment any live history response is applied. A delayed cache read that fires after this is unconditionally discarded, preventing stale cache rows from overwriting live content. (`ChatViewModel.swift:789-792`)

### 7.4 Write Path

`persistTranscriptToCache` chains writes through `pendingCacheWriteTask` (a serial task chain) so older snapshots cannot land after newer ones despite Swift concurrency's lack of ordering guarantees across awaits. (`ChatViewModel+TranscriptCache.swift:33-51`)

Cached messages strip binary attachment/tool argument payloads (`content` field, `thinkingSignature`, `arguments`), keeping only scalars (`text`, `mimeType`, `fileName`, `durationSeconds`, `id`, `name`, `serverMessageId`, `serverSeq`). The last 200 messages per session are kept.

Cache entries are evicted when the count exceeds 50 transcripts, keeping the 50 most recently written by `updated_at DESC, rowid DESC` (rowid tie-breaks equal timestamps, and `INSERT OR REPLACE` mints a fresh rowid, so the latest write always survives).

### 7.5 Agent ID Scoping in the Cache

`transcriptCacheAgentID(sessionKey:agentID:)` returns `nil` for canonical agent keys (`"agent:<id>:<key>"`) because the session key already disambiguates the owner. For alias keys (e.g., `"main"`), the `agentID` dimension is preserved to prevent cross-agent cache pollution when multiple agents share the same alias. (`ChatViewModel+TranscriptCache.swift:92-97`)

### 7.6 Cancellation Safety

`CanonicalMessageProofHub` (inside the SQLite cache actor, thread-safe via `NSLock`) records idempotency keys from canonical gateway history. When the user cancels an outbox command, the cancellation decision is made inside the SQLite transaction using `withProofDecision(for:)` which synchronously checks whether canonical evidence arrived before the cancellation. This closes the race window where a delivered message could be scrubbed by a concurrent cancel. (`ChatTranscriptCache.swift:53-79`)

---

## 8. Attachments

File: `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatViewModel+Attachments.swift`

### 8.1 Size Limit

`maxAttachmentBytes = 5_000_000` (5 MB). Applied before staging for images (after JPEG re-encoding) and after reading for voice notes and file attachments.

### 8.2 Image Attachments

Photos and images go through `addImageAttachment(url:data:fileName:mimeType:)`:
1. Requires MIME conformance to `.image` UTType; rejects non-images with an error.
2. Re-encodes via `ChatImageProcessor.processForUpload(data:)` on a detached high-priority task (JPEG normalization and resizing).
3. Output MIME is always `"image/jpeg"`. Filename extension is changed to `.jpg`.
4. Preview thumbnail generated via `UIImage(data:)`.

### 8.3 File Attachments

`addFileAttachment(data:fileName:mimeType:)` stages raw bytes verbatim. Used for documents and animated GIFs that must reach the gateway unmodified. A thumbnail preview is generated only for MIME types conforming to `.image`. Type field is `"file"`.

### 8.4 Voice Notes

`addVoiceNoteAttachment(fileURL:durationSeconds:)` reads the m4a file, removes the temp file, caps duration at `OpenClawVoiceNoteRecorder.maximumDurationSeconds`, normalizes finite-only durations, and stages as `mimeType: "audio/mp4"`.

### 8.5 Attachment Staging Guard

`attachmentStagingCount` is incremented for each async staging operation and decremented on completion via `beginAttachmentStaging()` / `endAttachmentStaging()`. While non-zero, `blocksAttachmentOwnerChange` is `true`, which prevents session switches and delivery identity changes from racing with an attachment that is still being loaded. When staging completes, `applyDeferredExternalStateIfReady()` is called to flush any deferred state.

### 8.6 Wire Encoding

Each `OpenClawPendingAttachment` is encoded as `OpenClawChatAttachmentPayload`:
- `type`: from the attachment (usually `"file"`)
- `mimeType`: from the attachment
- `fileName`: from the attachment
- `content`: `data.base64EncodedString()`

The `attachments` field on `ChatSendParams` is omitted entirely when the array is empty.

---

## 9. Event Handling

### 9.1 `chat` Events

State machine on `chat.state`:

| State | Action |
|---|---|
| `"delta"` | `adoptRun(runId:bufferedText:)` — adopts the run into `pendingRuns` if not already present, updates `streamingAssistantText` only when the buffered text is longer than current (to prevent stale snapshots from regressing a mid-stream reply). |
| `"final"` | Appends provisional final message, clears streaming text, triggers `refetchHistoryUnlessAnsweredLive`. |
| `"aborted"` | Same as final. |
| `"error"` | Sets `errorText`, clears streaming text, triggers refetch. |

Session key matching for `chat` events uses `matchesCurrentSessionKey`. The event is not dropped if `isOurRun` is true even on a session key mismatch, preventing the UI from getting stuck in "thinking" when the gateway publishes a canonical key that differs from the alias the client tracks. (`ChatViewModel.swift:2276-2285`)

### 9.2 `session.message` Events

Processes a fully durable message record pushed by the gateway:

1. Strips inbound metadata from user messages (`stripInboundMetadata`).
2. Attaches `serverMessageId` and `serverSeq` from the envelope (top-level fields in the event payload).
3. Confirms any matching outbox command (cross-session, before the session-key guard).
4. If assistant with `serverMessageId` and exactly one pending run: mark `runsWithDeliveredCanonicalReply` and `runsAnsweredViaLiveStream`.
5. Invalidates history snapshots.
6. Try `adoptCorrelatedUserMessage` — if the incoming is the gateway echo of the user turn the client just sent (matched by `idempotencyKey`), update in-place and return early.
7. Try `adoptProvisionalFinalMessage` — if the incoming is the canonical version of a provisional assistant reply, replace in-place.
8. Otherwise append, reconcile IDs, and dedupe.

### 9.3 `agent` Events

Routes on `evt.stream`:

| Stream | Action |
|---|---|
| `"assistant"` | Accumulates `streamingAssistantText` from `data["text"]`. |
| `"lifecycle"` | Checks phase/status for terminal/failure signals; on terminal clears pending run and streaming text, fires appropriate haptic, triggers history refetch. |
| `"tool"` | `phase == "start"`: adds to `pendingToolCallsById` (sorted by `startedAt`). `phase == "result"`: removes. |

Legacy session-stream mode: if `pendingRuns.isEmpty && sessionId == evt.runId`, the event is still processed. (`ChatViewModel.swift:2438-2440`)

### 9.4 `seqGap` Events

Indicates a gap in the gateway's WebSocket sequence numbers — possible missed events. Immediately:
1. Clears all pending runs (without a haptic or error text).
2. Invalidates history and run snapshots.
3. Clears streaming text and tool calls.
4. Triggers a full history refresh.
5. Polls health.

### 9.5 `tick` Events

Triggers `pollHealthIfNeeded(force: false)`. The health poll uses a cooldown to avoid hammering the gateway.

---

## 10. Session Management Operations

| Operation | Transport RPC | Side Effects |
|---|---|---|
| New session (`/new`) | `sessions.create` | Falls back to `sessions.reset` if the transport does not support create. New key follows pattern `"ios-<uuid>"` or `"agent:<id>:ios-<uuid>"`. |
| Reset (`/reset`, `/clear`) | `sessions.reset` | Clears run scopes and provisional finals, then bootstraps. |
| Compact (`/compact`) | `sessions.compact` | 60 s cooldown guard. Sets `isLoading = true`, then bootstraps on success. |
| Rename | `sessions.patch(label:)` | Optimistically updates `sessions[i].label` and `displayName`. Rolls back on error. Refreshes sessions on success. |
| Pin/Unpin | `sessions.patch(pinned:)` | Optimistically re-organizes sessions list. Rolls back on error. |
| Archive | `sessions.patch(archived:true)` | Removes from list immediately. If archiving the active session, switches to `resolvedMainSessionKey`. |
| Restore (unarchive) | `sessions.patch(archived:false)` | Refreshes sessions. Returns `Bool` so callers avoid switching to still-archived sessions. |
| Delete | `sessions.delete` | Removes from list. If deleting active session and a different main session exists, switches to it. If deleting the active main session, re-bootstraps in place. |
| Fork | `sessions.create(fork:true)` | Returns new session key. |

---

## 11. Model and Thinking Selection

### 11.1 Model Selection

`selectModel(_:selectionID:)` optimistically sets `modelSelectionID` and calls `sessions.patch(model:)`. In-flight patches are tracked per session by `inFlightModelPatchCountsBySession`. The live send path and outbox flush path both call `waitForPendingModelPatches(in:)` before dispatching, ensuring the model patch has landed on the server before the next message is sent. (`ChatViewModel.swift:1994-1999`)

Multiple rapid model changes within one session produce sequential requests, each tagged with a request ID. A stale response (request ID mismatch) does not overwrite the latest desired state. On failure, the model reverts to the last successful selection for that session.

Model selection ID format: `"<provider>/<modelID>"` (e.g., `"anthropic/claude-sonnet-4-6"`). The sentinel `"__default__"` means "no explicit model; gateway chooses."

### 11.2 Context Usage Fraction

Computed as `min(max(totalTokens / contextTokens, 0), 1)`. Only computed when `totalTokensFresh != false`. Synced whenever `sessionKey` or `sessions` changes.

---

## 12. Key Data Flow Summary

```
User taps Send
  → performSend()
  → effectiveThinkingLevelForSend() → "" if picker hidden, stored level otherwise
  → transport.sendMessage(thinking: "" → omit field on wire)
  → gateway issues chat.send RPC (timeoutMs: 30000, HTTP timeout: 35s)
  → response.runId adopted into pendingRuns
  → arm pendingRunTimeout (120s)

Gateway sends events (WebSocket):
  chat.delta  → streamingAssistantText grows
  session.message (user echo) → adoptCorrelatedUserMessage (reuse bubble UUID)
  session.message (assistant) → mark runsWithDeliveredCanonicalReply
                              → adoptProvisionalFinalMessage
  chat.final  → appendFinalChatMessageIfPresent (provisional)
              → refetchHistoryUnlessAnsweredLive
                  (skipped if runsAnsweredViaLiveStream contains runId)
  agent.lifecycle terminal → clearPendingRun → haptic
                           → refetchHistoryUnlessAnsweredLive

All history responses:
  → decodeMessages → stripInboundMetadata → dedupeMessages
  → orderedBySequence (by serverSeq, carry-forward for transient rows)
  → reconcile IDs (preserve local UUIDs, adopt canonical fields)
  → persistTranscriptToCache (chained writes, strips binary payloads)
```
