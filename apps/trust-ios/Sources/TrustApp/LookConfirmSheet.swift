import SwiftUI
import TrustCore

/// Look confirm — one snapshot and a requested notification, stated before the action.
struct LookConfirmSheet: View {
    let subject: TrustedPerson
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette

    private var first: String { subject.firstName }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    TrustAvatar(name: subject.person.displayName, seed: seed, size: 70)
                    Spacer()
                    Button {
                        model.cancelLook()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.ink)
                            .frame(width: 44, height: 44)
                            .background(Circle().stroke(palette.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(TrustCopy.close)
                }
                .padding(.bottom, 22)

                TrustEyebrow(text: TrustCopy.confirm, size: 10)
                Text(TrustCopy.lookAtTitle(name: first))
                    .font(TrustTheme.display(34))
                    .tracking(-1)
                    .foregroundStyle(palette.ink)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
                    .accessibilityAddTraits(.isHeader)

                (Text(TrustCopy.thenOneSnapshot).fontWeight(.semibold).foregroundColor(palette.ink)
                    + Text("\n")
                    + Text("Trust records this Look. A notification may be delivered.").foregroundColor(palette.muted))
                    .trustFont(15)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .padding(.bottom, 24)

            }
            .padding(.horizontal, 26)
            .padding(.top, 18)
            .padding(.bottom, 16)
            .trustReadableWidth()
        }
        .background(palette.paper.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 6) {
                Button {
                    model.confirmLook()
                } label: {
                    HStack(spacing: 8) {
                        if model.isLooking {
                            ProgressView().tint(palette.accentOn)
                        } else {
                            Image(systemName: "eye")
                                .font(.system(size: 15, weight: .medium))
                                .accessibilityHidden(true)
                        }
                        Text(TrustCopy.lookNotify(name: first))
                    }
                }
                .buttonStyle(TrustFilledButtonStyle())
                .disabled(model.isLooking)
                .accessibilityLabel(TrustCopy.lookNotify(name: first))
                .accessibilityIdentifier("confirm-look-notify")

                Button(TrustCopy.cancel) { model.cancelLook() }
                    .buttonStyle(TrustTextButtonStyle())
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("cancel-look")

                if model.isDemoMode, !model.isScreenshotLaunch {
                    Text(TrustCopy.demoSimulated)
                        .font(TrustTheme.ui(11))
                        .foregroundStyle(palette.muted)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(palette.paper)
            .trustReadableWidth()
        }
    }

    private var seed: Int {
        model.circle.firstIndex { $0.id == subject.id } ?? 0
    }
}
