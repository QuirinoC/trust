import SwiftUI
import TrustCore

struct AccountHelpSheet: View {
    let onSignOut: () -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.trustPalette) private var palette

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(TrustCopy.accountHelpBody)
                        .trustFont(14)
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Link(TrustCopy.support, destination: AppConfiguration.supportURL)
                        .buttonStyle(TrustOutlineButtonStyle(compact: true))
                        .frame(minHeight: 44)
                    Link(TrustCopy.manageSubscription, destination: StoreManager.manageSubscriptionsURL)
                        .buttonStyle(TrustOutlineButtonStyle(compact: true))
                        .frame(minHeight: 44)
                    Button(TrustCopy.signOut) { dismissAndPerform(onSignOut) }
                        .buttonStyle(TrustOutlineButtonStyle(compact: true))
                        .frame(minHeight: 44)
                    Button(TrustCopy.deleteAccount) { dismissAndPerform(onDelete) }
                        .buttonStyle(TrustTextButtonStyle(color: palette.danger))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier("account-help-delete")
                }
                .padding(TrustTheme.gutter)
            }
            .scrollIndicators(.hidden)
            .background(palette.paper.ignoresSafeArea())
            .navigationTitle(TrustCopy.accountHelp)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(TrustCopy.done) { dismiss() }
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
    }

    private func dismissAndPerform(_ action: @escaping () -> Void) {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            action()
        }
    }
}
