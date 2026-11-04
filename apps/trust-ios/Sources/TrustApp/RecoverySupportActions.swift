import SwiftUI
import TrustCore

enum RecoverySupportKind: String, Equatable {
    case phoneConflict = "phone_ownership_conflict"
    case purchase = "purchase"

    var actionTitle: String {
        self == .phoneConflict ? TrustCopy.recoveryGetHelp : TrustCopy.recoveryRestoreHelp
    }

    var actionIdentifier: String {
        self == .phoneConflict ? "phone-conflict-get-help" : "purchase-restoration-help"
    }
}

struct RecoverySupportActions: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @State private var didCopyReference = false
    let kind: RecoverySupportKind

    private var matchingReference: String? {
        guard model.recoveryRequestKind == kind.rawValue else { return nil }
        return model.recoveryRequestReference
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kind == .phoneConflict ? TrustCopy.recoveryPhoneNotice : TrustCopy.recoveryPurchaseNotice)
                .trustFont(12)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let reference = matchingReference {
                Text(TrustCopy.recoveryRequestPending)
                    .trustFont(12)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(TrustCopy.recoveryRequestReference(reference))
                    .trustFont(12, weight: .medium)
                    .foregroundStyle(palette.ink)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("recovery-request-reference")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        emailLink(reference)
                        copyButton
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        emailLink(reference)
                        copyButton
                    }
                }
                .trustFont(13, weight: .medium)
                .foregroundStyle(palette.accent)
                if didCopyReference {
                    Text(TrustCopy.recoveryReferenceCopied)
                        .trustFont(12)
                        .foregroundStyle(palette.positive)
                        .accessibilityIdentifier("recovery-reference-copied")
                }
            } else {
                Button {
                    Task {
                        switch kind {
                        case .phoneConflict:
                            await model.submitPhoneConflictRecoveryRequest()
                        case .purchase:
                            await model.submitPurchaseRecoveryRequest()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if model.isSubmittingRecoveryRequest { ProgressView().tint(palette.accent) }
                        Text(kind.actionTitle)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.accent)
                .disabled(model.isSubmittingRecoveryRequest)
                .accessibilityIdentifier(kind.actionIdentifier)
                if let error = model.recoveryRequestError {
                    Text(error)
                        .trustFont(12)
                        .foregroundStyle(palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("recovery-request-error")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emailLink(_ reference: String) -> some View {
        Link(TrustCopy.recoveryEmailSupport, destination: AppConfiguration.supportEmailURL(reference: reference))
            .frame(minHeight: 44)
            .accessibilityIdentifier("recovery-email-support")
    }

    private var copyButton: some View {
        Button(TrustCopy.recoveryCopyReference) {
            model.copyRecoveryRequestReference()
            didCopyReference = true
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier("recovery-copy-reference")
    }
}
