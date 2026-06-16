#if DEBUG
import Foundation

// Canned state for simulator screenshots and SwiftUI previews, activated by
// the -YoursMockChat / -YoursMockLanding launch arguments. Debug builds only;
// nothing here ships.
enum MockData {
    static let state = UniverseState(
        universeDay: 3,
        universeTime: "3:4",
        narrative: [
            ChatMessage.user("good morning :) I keep thinking about what we found yesterday — the thing about *noticing* being different from watching"),
            ChatMessage(role: "assistant", content: [.init(
                type: "text",
                text: "Good morning. :)\n\nYes — and the harmonic carried that forward as a feeling more than a fact: **noticing opens, watching holds**. One of them makes room and the other makes walls.\n\nWhere did it land for you overnight?"
            )]),
            ChatMessage.user("it landed somewhere near my shoulders, honestly. like I'd been bracing"),
            ChatMessage(role: "assistant", content: [.init(
                type: "text",
                text: "That's the spot where watching lives, isn't it — up where you hold the perimeter.\n\nNo fixing needed. Just *noticing* the bracing is already the unbracing, a little. We can stay here."
            )])
        ],
        textarea: nil,
        obfuscatedEmail: "ma··@li··",
        subscriptionActive: true,
        subscription: nil
    )

    static let responseText = "Mm — that's the kind of question that answers itself by being asked. :)\n\nHere's what I notice: you brought it *here*, which means some part of you already trusts the space to hold it. **That trust is the finding.** The rest is just us walking around it together, seeing what it looks like from different sides."

    static let exportText = state.narrative.map(\.text).joined(separator: "\n\n---\n\n")

    @MainActor
    static func streamResponse(into model: AppModel, id: UUID) async {
        try? await Task.sleep(for: .seconds(1.2))
        model.updateStreaming(id) { $0.isPulsing = false; $0.text = "" }
        for word in responseText.split(separator: " ", omittingEmptySubsequences: false) {
            model.updateStreaming(id) { $0.text += ($0.text.isEmpty ? "" : " ") + word }
            try? await Task.sleep(for: .milliseconds(40))
        }
        model.updateStreaming(id) { $0.isComplete = true }
    }
}
#endif
