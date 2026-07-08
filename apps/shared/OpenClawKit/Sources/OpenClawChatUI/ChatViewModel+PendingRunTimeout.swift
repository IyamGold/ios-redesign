import Foundation

extension OpenClawChatViewModel {
    func armPendingRunTimeout(runId: String) {
        self.pendingRunTimeoutTasks[runId]?.cancel()
        self.nextPendingRunTimeoutArmID &+= 1
        let armID = self.nextPendingRunTimeoutArmID
        self.pendingRunTimeoutArmIDs[runId] = armID
        self.pendingRunTimeoutTasks[runId] = Task { [weak self] in
            let timeoutMs = await MainActor.run { self?.pendingRunTimeoutMs ?? 0 }
            do {
                try await Task.sleep(nanoseconds: timeoutMs * 1_000_000)
            } catch {
                // Rearming or completing a run cancels this task. Never let the
                // retired timeout clear the still-active replacement owner.
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.pendingRunTimeoutArmIDs[runId] == armID else { return }
                guard self.pendingRuns.contains(runId) else { return }
                self.logDiagnostic(
                    "chat.ui pending timeout sessionKey=\(self.sessionKey) "
                        + "runId=\(runId)")
                self.errorText = "Timed out waiting for a reply; try again or refresh."
                self.clearPendingRun(runId, hapticEvent: .runFailed)
            }
        }
    }

    func clearPendingRun(
        _ runId: String,
        hapticEvent: OpenClawChatHaptics.Event? = nil)
    {
        let wasPending = self.pendingRuns.contains(runId)
        self.pendingRuns.remove(runId)
        self.pendingLocalUserEchoMessageIDsByRunID[runId] = nil
        self.pendingRunTimeoutTasks[runId]?.cancel()
        self.pendingRunTimeoutTasks[runId] = nil
        self.pendingRunTimeoutArmIDs[runId] = nil
        if wasPending {
            self.logDiagnostic(
                "chat.ui pending cleared sessionKey=\(self.sessionKey) "
                    + "runId=\(runId)")
            if self.pendingRuns.isEmpty, let hapticEvent {
                self.haptics.perform(hapticEvent)
            }
        }
    }

    func clearPendingRuns(
        reason: String?,
        hapticEvent: OpenClawChatHaptics.Event? = nil)
    {
        let runIds = Array(pendingRuns)
        for runId in self.pendingRuns {
            self.pendingRunTimeoutTasks[runId]?.cancel()
        }
        self.pendingRunTimeoutTasks.removeAll()
        self.pendingRunTimeoutArmIDs.removeAll()
        self.pendingRuns.removeAll()
        self.pendingLocalUserEchoMessageIDsByRunID.removeAll()
        if !runIds.isEmpty, let hapticEvent {
            self.haptics.perform(hapticEvent)
        }
        if let reason, !reason.isEmpty {
            self.errorText = reason
            for runId in runIds {
                self.logDiagnostic(
                    "chat.ui pending cleared sessionKey=\(self.sessionKey) "
                        + "runId=\(runId) reason=\(reason)")
            }
        }
    }
}
