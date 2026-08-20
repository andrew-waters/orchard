import AppKit
import Foundation

struct SelectionHandler {
    static func handleSelection<T: Hashable>(
        clickedId: T,
        orderedIds: [T],
        selectedSet: inout Set<T>,
        lastSelectedId: inout T?
    ) {
        let isShiftPressed = NSEvent.modifierFlags.contains(.shift)
        let isCommandPressed = NSEvent.modifierFlags.contains(.command)

        if isShiftPressed, let lastId = lastSelectedId,
           let lastIndex = orderedIds.firstIndex(of: lastId),
           let currentIndex = orderedIds.firstIndex(of: clickedId) {
            let start = min(lastIndex, currentIndex)
            let end = max(lastIndex, currentIndex)
            let rangeItems = orderedIds[start...end]
            
            // If shift-selecting, replace or extend the selection
            // In standard macOS behavior, shift-select from lastSelectedId selection anchor selects the range
            selectedSet = Set(rangeItems)
        } else if isCommandPressed {
            if selectedSet.contains(clickedId) {
                selectedSet.remove(clickedId)
                if lastSelectedId == clickedId {
                    lastSelectedId = selectedSet.first
                }
            } else {
                selectedSet.insert(clickedId)
                lastSelectedId = clickedId
            }
        } else {
            selectedSet = [clickedId]
            lastSelectedId = clickedId
        }
    }
}
