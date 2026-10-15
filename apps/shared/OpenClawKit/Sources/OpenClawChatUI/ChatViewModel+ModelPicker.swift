import Foundation

/// Model-picker surface, extracted from `ChatViewModel.swift` to keep that file under its size cap.
/// Pure derivations over the picker store + selection state; no streaming/transport logic.
extension OpenClawChatViewModel {
    public var modelPickerSections: ChatModelPickerSections {
        ChatModelPickerStore.sections(
            choices: self.modelChoices,
            favorites: self.modelPickerFavorites,
            recents: self.modelPickerRecents)
    }

    public var isSelectedModelPinned: Bool {
        self.modelSelectionID != Self.defaultModelSelectionID &&
            self.modelPickerFavorites.contains(self.modelSelectionID)
    }

    public func toggleSelectedModelPinned() {
        guard self.modelSelectionID != Self.defaultModelSelectionID else { return }
        self.modelPickerStore.toggleFavorite(self.modelSelectionID)
        self.modelPickerFavorites = self.modelPickerStore.favorites
    }
}
