import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showStartOverConfirm = false
    @State private var showDeleteConfirm = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    HStack {
                        Text("Settings")
                            .textCase(.uppercase)
                            .font(.yoursHeading(26))
                            .foregroundStyle(Theme.foregroundHeading)
                        Spacer()
                        Button("Done") { dismiss() }
                            .font(.yoursMono(14))
                            .foregroundStyle(Theme.accent)
                    }

                    section("Display") {
                        HStack(spacing: 12) {
                            ForEach(ThemePreference.allCases, id: \.self) { preference in
                                Button(preference.label) {
                                    model.themePreference = preference
                                }
                                .buttonStyle(WebButtonStyle(
                                    color: model.themePreference == preference ? Theme.accentActive : Theme.accent
                                ))
                            }
                        }
                    }

                    section("Subscription") {
                        subscriptionBody
                    }

                    section("Start over") {
                        startOverBody
                    }

                    section("Delete account") {
                        deleteAccountBody
                    }
                }
                .padding(24)
            }
        }
        .task { await model.loadSettingsSubscription() }
        .confirmationDialog("Start over?", isPresented: $showStartOverConfirm, titleVisibility: .visible) {
            Button("Start over", role: .destructive) {
                Task {
                    await model.startOver()
                    dismiss()
                }
            }
        } message: {
            Text("There is no undo. This does not affect your subscription.")
        }
        .confirmationDialog("Delete your account?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) {
                Task {
                    await model.deleteAccount()
                    dismiss()
                }
            }
        } message: {
            Text("This permanently deletes your account and all its data. There is no undo. If you have a subscription, cancel it separately in Settings › Apple Account.")
        }
    }

    @ViewBuilder
    private var deleteAccountBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Permanently delete your account and everything in it — the whole pocket universe, gone.")
                .font(.yoursBody(16))
                .foregroundStyle(Theme.foreground)
            Button("Delete account") { showDeleteConfirm = true }
                .font(.yoursMono(14))
                .foregroundStyle(Theme.error)
            Text("There is no undo.")
                .font(.yoursBody(14))
                .foregroundStyle(Theme.warning)
        }
    }

    @ViewBuilder
    private var subscriptionBody: some View {
        if let subscription = model.settingsSubscription {
            VStack(alignment: .leading, spacing: 10) {
                detailRow("Status:", subscription.status.capitalized
                    + (subscription.cancelAtPeriodEnd ? " (canceling at period end)" : ""))
                detailRow("Amount:", "$\(subscription.amount / 100) / \(subscription.interval)")
                if let end = subscription.currentPeriodEnd {
                    detailRow(
                        subscription.cancelAtPeriodEnd ? "Access ends:" : "Next billing date:",
                        end.formatted(date: .long, time: .omitted)
                    )
                }
                Text("Manage or cancel in Settings › Apple Account › Subscriptions.")
                    .font(.yoursBody(15))
                    .foregroundStyle(Theme.foreground.opacity(0.6))
                    .padding(.top, 6)
                Button("Manage in Settings") {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        openURL(url)
                    }
                }
                .buttonStyle(WebButtonStyle())
            }
        } else if model.state?.subscriptionActive == true {
            Text("Active. Manage or cancel in Settings › Apple Account › Subscriptions.")
                .font(.yoursBody(15))
                .foregroundStyle(Theme.foreground)
        } else {
            SubscribeOptions()
        }
    }

    @ViewBuilder
    private var startOverBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Begin at the beginning, at the dawn of \(UniverseState.dayWithUnits(1)), with no trace of what was.")
                .font(.yoursBody(16))
                .foregroundStyle(Theme.foreground)

            if model.state?.subscriptionActive == true {
                Button("Start over") { showStartOverConfirm = true }
                    .font(.yoursMono(14))
                    .foregroundStyle(Theme.accentActive)
                Text("There is no undo.")
                    .font(.yoursBody(14))
                    .foregroundStyle(Theme.warning)
            } else {
                Text("This unlocks for subscribers.")
                    .font(.yoursBody(14))
                    .foregroundStyle(Theme.warning)
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .textCase(.uppercase)
                .font(.yoursHeading(18))
                .foregroundStyle(Theme.foregroundHeading)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 24)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.yoursBody(15))
                .foregroundStyle(Theme.foreground.opacity(0.6))
            Text(value)
                .font(.yoursBody(15))
                .foregroundStyle(Theme.foreground)
        }
    }
}
