import SwiftUI

struct ChatScreen: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var composerFocused: Bool
    @State private var showSettings = false
    @State private var showExitConfirm = false
    @State private var showSleepConfirm = false
    @State private var export: ExportedNarrative?

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(model.messages) { message in
                            MessageView(message: message)
                        }
                        if let notice = model.notice {
                            NoticeView(notice: notice) { model.noticeAction() }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 20)
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.messages.count) {
                    // Mirrors the web's scrollIntoView on message add; deltas
                    // in between ride the bottom anchor
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: model.messages.last?.text) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onChange(of: composerFocused) {
                    guard composerFocused else { return }
                    Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }

            composer
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(item: $export) { exported in
            ShareSheet(items: [exported.fileURL])
        }
        .confirmationDialog("Exit?", isPresented: $showExitConfirm, titleVisibility: .visible) {
            Button("Exit", role: .destructive) { model.signOut() }
        } message: {
            Text("Your universe stays right where it is — sign back in any time.")
        }
        .confirmationDialog(
            "Ready to move to \(UniverseState.dayWithUnits(nextDay))?",
            isPresented: $showSleepConfirm,
            titleVisibility: .visible
        ) {
            Button("Move to \(UniverseState.dayWithUnits(nextDay))") {
                Task { await model.beginSleep() }
            }
        }
    }

    private var nextDay: Int {
        (model.state?.universeDay ?? 1) + 1
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Yours: \(model.state?.dayWithUnits ?? "")")
                .font(.yoursMono(14))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 8)

            Button {
                showSettings = true
            } label: {
                Text(model.state?.obfuscatedEmail ?? "Settings")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .buttonStyle(TextActionButtonStyle(color: Theme.accent))
            .frame(maxWidth: 100, alignment: .trailing)
            .accessibilityIdentifier("settings-button")

            exportButton

            Button("Exit") { showExitConfirm = true }
                .buttonStyle(TextActionButtonStyle(color: Theme.accentActive))
                .accessibilityIdentifier("exit-button")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Theme.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            TextField("Type your message...", text: $model.composerText, axis: .vertical)
                .lineLimit(1...8)
                .font(.yoursMono(16))
                .foregroundStyle(Theme.foreground)
                .tint(Theme.accentActive)
                .padding(12)
                .background(Theme.userMessageBg)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(composerFocused ? Theme.accentActive : .clear)
                        .frame(width: 3)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .focused($composerFocused)
                .accessibilityIdentifier("composer-field")
                .disabled(model.isWaiting)
                .opacity(model.isWaiting ? 0.5 : 1)
                .onChange(of: model.composerText) {
                    model.composerChanged()
                }

            composerActions
                .frame(maxWidth: .infinity)
                .opacity(model.isWaiting ? 0.5 : 1)
                .disabled(model.isWaiting)
        }
        .padding(16)
        .background(Theme.background)
    }

    private var composerActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                nextDayButton
                Spacer(minLength: 8)
                sendButton
            }

            VStack(alignment: .leading, spacing: 12) {
                nextDayButton
                HStack(spacing: 12) {
                    Spacer()
                    sendButton
                }
            }
        }
    }

    private var sendButton: some View {
        Button("Send") {
            composerFocused = false
            model.send()
        }
            .buttonStyle(WebButtonStyle())
            .accessibilityIdentifier("send-button")
            .disabled(model.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @ViewBuilder
    private var nextDayButton: some View {
        if model.state?.subscriptionActive == true {
            Button("Move to \(UniverseState.dayWithUnits(nextDay))") {
                showSleepConfirm = true
            }
            .buttonStyle(TextActionButtonStyle(color: Theme.accentActive))
            .accessibilityIdentifier("next-day-button")
        } else {
            // Day 1 visitor — same words as the web; the path runs
            // through settings, which explains the web step
            Button("Subscribe for \(UniverseState.dayWithUnits(nextDay))") {
                showSettings = true
            }
            .buttonStyle(TextActionButtonStyle(color: Theme.accent))
            .accessibilityIdentifier("next-day-button")
        }
    }

    private var exportButton: some View {
        Button {
            exportNarrative()
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 17, weight: .regular))
                .frame(width: 44, height: 44)
        }
            .foregroundStyle(Theme.foreground.opacity(0.65))
            .contentShape(Rectangle())
            .accessibilityLabel("Export narrative")
            .accessibilityIdentifier("save-button")
    }

    private func exportNarrative() {
        Task {
            guard let (text, filename) = try? await model.exportNarrative() else { return }
            let url = FileManager.default.temporaryDirectory.appending(path: filename)
            try? text.write(to: url, atomically: true, encoding: .utf8)
            export = ExportedNarrative(fileURL: url)
        }
    }
}

private struct ExportedNarrative: Identifiable {
    let id = UUID()
    let fileURL: URL
}

struct MessageView: View {
    let message: AppModel.DisplayMessage
    @State private var pulseDim = false
    @State private var dotCount = 1

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        Group {
            if message.isPulsing {
                Text(String(repeating: ".", count: dotCount))
                    .font(.yoursMono(15))
                    .foregroundStyle(Theme.foreground)
                    .frame(minHeight: 24)
                    .opacity(pulseDim ? 0.4 : 1)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                            pulseDim = true
                        }
                    }
                    .task {
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .milliseconds(500))
                            dotCount = (dotCount % 3) + 1
                        }
                    }
            } else {
                Text(message.isComplete ? MarkdownLite.rendered(message.text) : MarkdownLite.streaming(message.text))
                    .font(.yoursMono(15))
                    .lineSpacing(3)
                    .foregroundStyle(message.isError ? Theme.warning : Theme.foreground)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(isUser ? Theme.userMessageBg : Theme.assistantMessageBg)
        .overlay(alignment: .leading) {
            if isUser {
                Rectangle()
                    .fill(Theme.accent)
                    .frame(width: 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct NoticeView: View {
    let notice: AppModel.Notice
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(notice.message)
                .font(.yoursMono(14))
                .foregroundStyle(Theme.foreground)
            Button(notice.actionLabel, action: action)
                .buttonStyle(WebButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(Theme.assistantMessageBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
