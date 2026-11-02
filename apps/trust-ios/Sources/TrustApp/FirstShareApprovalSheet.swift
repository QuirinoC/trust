import SwiftUI
import TrustCore

struct FirstShareApprovalSheet: View {
    let request: FirstShareApprovalRequest
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette

    private var modeName: String {
        request.mode == .always ? TrustCopy.always : TrustCopy.sealed
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 14) {
                        TrustAvatar(name: request.displayName, size: 60, personID: request.personID)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(TrustCopy.firstShareTitle(request.displayName))
                                .font(TrustTheme.display(25))
                                .foregroundStyle(palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)
                            Text("@\(request.handle)")
                                .trustFont(14, weight: .medium)
                                .foregroundStyle(palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 18)

                    Text(TrustCopy.firstShareDetails(request.displayName, handle: request.handle, mode: modeName))
                        .trustFont(15)
                        .lineSpacing(3)
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(TrustTheme.gutter)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 4) {
                Button(TrustCopy.shareWithPerson(request.displayName)) {
                    model.confirmFirstShareApproval()
                }
                .buttonStyle(TrustFilledButtonStyle())
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
}
