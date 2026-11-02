import SwiftUI
import TrustCore

struct FirstShareApprovalSheet: View {
    let request: FirstShareApprovalRequest
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var modeName: String {
        request.mode == .always ? TrustCopy.always : TrustCopy.sealed
    }

    private var confirmationTitle: String {
        request.mode == .always ? TrustCopy.firstShareCTAAlways : TrustCopy.firstShareCTASealed
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    recipientIdentity
                    .padding(.bottom, 18)

                    Text(TrustCopy.firstShareDetails(request.displayName, handle: request.handle, mode: modeName))
                        .trustFont(15)
                        .lineSpacing(3)
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("first-share-details")
                }
                .padding(TrustTheme.gutter)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("first-share-scroll")

            VStack(spacing: 4) {
                Button {
                    model.confirmFirstShareApproval()
                } label: {
                    Text(confirmationTitle)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(TrustFilledButtonStyle())
                .accessibilityHint(TrustCopy.firstShareDetails(request.displayName, handle: request.handle, mode: modeName))
                .accessibilityIdentifier("first-share-confirm")
                Button(TrustCopy.cancel) { model.cancelFirstShareApproval() }
                    .buttonStyle(TrustTextButtonStyle())
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("first-share-cancel")
            }
            .padding(.horizontal, TrustTheme.gutter)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(palette.paper)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.paper.ignoresSafeArea())
    }

    @ViewBuilder
    private var recipientIdentity: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Text(TrustCopy.firstShareTitle(request.displayName))
                    .trustFont(20, weight: .semibold)
                    .foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("first-share-recipient")
                Text("@\(request.handle)")
                    .trustFont(14, weight: .medium)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("first-share-handle")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        } else {
            HStack(spacing: 14) {
                TrustAvatar(name: request.displayName, size: 60, personID: request.personID)
                VStack(alignment: .leading, spacing: 3) {
                    Text(TrustCopy.firstShareTitle(request.displayName))
                        .font(TrustTheme.display(25))
                        .foregroundStyle(palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("first-share-recipient")
                    Text("@\(request.handle)")
                        .trustFont(14, weight: .medium)
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("first-share-handle")
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .contain)
        }
    }
}
