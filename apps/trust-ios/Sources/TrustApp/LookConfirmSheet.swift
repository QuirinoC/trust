import SwiftUI
import TrustCore

/// Look confirm — consequence before action. "Maya will be notified." leads; the snapshot
/// line follows. One primary button that names both the verb and the receipt.
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
                            .frame(width: 40, height: 40)
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

                (Text(TrustCopy.willBeNotified(name: first)).fontWeight(.semibold).foregroundColor(palette.ink)
                    + Text("\n")
                    + Text(TrustCopy.thenOneSnapshot).foregroundColor(Color(hex: 0x777A6E)))
                    .trustFont(15)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)

                notificationPreview
                    .padding(.vertical, 22)

                HStack(spacing: 7) {
                    Image(systemName: "clock")
                        .font(.system(size: 12, weight: .medium))
                        .accessibilityHidden(true)
                    Text(TrustCopy.receiptNoteSealed)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .trustFont(12)
                .foregroundStyle(Color(hex: 0x858779))
                .padding(.bottom, 22)

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

                Button(TrustCopy.cancel) {
                    model.cancelLook()
                }
                .buttonStyle(TrustTextButtonStyle())
                .frame(maxWidth: .infinity)
                .padding(.top, 6)

                if model.isDemoMode, !model.isScreenshotLaunch {
                    Text(TrustCopy.demoSimulated)
                        .font(TrustTheme.ui(11))
                        .foregroundStyle(palette.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 18)
            .padding(.bottom, 28)
            .trustReadableWidth()
        }
        .background(palette.paper.ignoresSafeArea())
    }

    /// `.notification-preview` — what the subject's lock screen will say.
    private var notificationPreview: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("T")
                .font(TrustTheme.display(24))
                .foregroundStyle(palette.ink)
                .frame(width: 34, height: 34)
                .background(palette.paper)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(TrustCopy.mastheadName.uppercased())
                    Spacer()
                    Text(TrustCopy.now)
                        .fontWeight(.regular)
                        .foregroundStyle(palette.muted)
                }
                .font(TrustTheme.ui(11, weight: .semibold))
                .foregroundStyle(palette.ink)
                Text(TrustCopy.previewLine(viewer: model.you.displayName.trustFirstName))
                    .font(TrustTheme.ui(13))
                    .foregroundStyle(palette.ink)
            }
        }
        .padding(16)
        .background(Color(hex: 0xF0F1EB))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color(hex: 0xE4E6DB), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(TrustCopy.notification): \(TrustCopy.previewLine(viewer: model.you.displayName.trustFirstName))")
    }

    private var seed: Int {
        model.circle.firstIndex { $0.id == subject.id } ?? 0
    }
}
