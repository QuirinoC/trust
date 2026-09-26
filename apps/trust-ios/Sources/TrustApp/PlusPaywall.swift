import StoreKit
import SwiftUI
import TrustCore

/// Plus — StoreKit 2 `SubscriptionStoreView`. Guideline 3.1.2: price, period, and trial
/// come from the store; Restore, Terms, and Privacy are explicit store buttons. A completed
/// purchase (or restore / `Transaction.updates`) submits the JWS through StoreManager →
/// `AppModel.syncCircleEntitlement`.
struct PlusPaywall: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette

    private var productIDs: [String] {
        [AppConfiguration.monthlyProductID, AppConfiguration.annualProductID]
    }

    /// StoreKit's purchase button uses white text, so keep its blue dark enough in dark mode.
    private let storeKitButtonTint = Color(hex: 0x245CE7)

    var body: some View {
        Group {
            if model.coverage.isCovered {
                covered
            } else {
                store
            }
        }
        .background(palette.paper.ignoresSafeArea())
        .task { await model.store.loadProducts() }
    }

    private var store: some View {
        SubscriptionStoreView(productIDs: productIDs) {
            marketing(showsClose: true)
        }
        .subscriptionStoreButtonLabel(.multiline)
        .storeButton(.visible, for: .restorePurchases)
        .storeButton(.visible, for: .policies)
        .subscriptionStorePolicyDestination(url: AppConfiguration.termsURL, for: .termsOfService)
        .subscriptionStorePolicyDestination(url: AppConfiguration.privacyURL, for: .privacyPolicy)
        .subscriptionStorePolicyForegroundStyle(palette.muted)
        .subscriptionStorePickerItemBackground(palette.surface)
        .inAppPurchaseOptions { _ in
            guard let token = model.store.appAccountToken else { return [] }
            return [.appAccountToken(token)]
        }
        .onInAppPurchaseCompletion { _, result in
            await model.handleStorePurchase(result)
        }
        .containerBackground(palette.paper, for: .subscriptionStore)
        .tint(storeKitButtonTint)
        .accessibilityIdentifier("plus-subscription-store")
    }

    private func marketing(showsClose: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                TrustEyebrow(text: TrustCopy.trustPlus, color: palette.accent, size: 10)
                Spacer(minLength: 8)
                if showsClose {
                    Button(TrustCopy.close) { model.showingPaywall = false }
                        .buttonStyle(TrustTextButtonStyle())
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("plus-close")
                }
            }

            Text(TrustCopy.plusHeadline)
                .font(TrustTheme.display(25))
                .tracking(-1)
                .foregroundStyle(palette.ink)
                .padding(.top, 2)
                .padding(.bottom, 7)
                .accessibilityAddTraits(.isHeader)

            Text("\(TrustCopy.plusFeatureSeats) · \(TrustCopy.plusFeatureModes)\n\(TrustCopy.plusFeatureSummary(TrustCopy.plusFeatureLog))")
                .trustFont(13)
                .lineSpacing(2)
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)

            Text(TrustCopy.plusStaysFree)
                .trustFont(12)
                .lineSpacing(2)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)

            Text(TrustCopy.plusLegal)
                .trustFont(11)
                .lineSpacing(1)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)

            if let error = model.store.errorMessage, !error.isEmpty, showsClose {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .trustFont(12)
                    .foregroundStyle(palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .accessibilityLabel(TrustCopy.subscriptionError(error))
                    .accessibilityIdentifier("plus-store-error")
            }

            if model.store.linkedToAnotherAccount {
                Text(TrustCopy.subscriptionLinked)
                    .trustFont(12)
                    .foregroundStyle(palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .accessibilityLabel(TrustCopy.subscriptionLinked)
            }

            if showsClose, model.snapshot?.allowsReviewUnlock == true {
                Button(TrustCopy.unlockPlusForReview) { model.unlockPlusForReview() }
                    .buttonStyle(TrustOutlineButtonStyle(compact: true))
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TrustTheme.gutter)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .trustReadableWidth()
    }

    private var covered: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                marketing()
                Text(TrustCopy.youHavePlus)
                    .trustFont(15, weight: .semibold)
                    .foregroundStyle(palette.ink)
                    .padding(.horizontal, TrustTheme.gutter)
                    .padding(.top, 8)
                if let error = model.store.errorMessage, !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .trustFont(13)
                        .foregroundStyle(palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, TrustTheme.gutter)
                        .padding(.top, 12)
                        .accessibilityLabel(TrustCopy.subscriptionError(error))
                        .accessibilityIdentifier("plus-store-error")
                }
                Text(TrustCopy.plusCoveredBody)
                    .trustFont(13)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, TrustTheme.gutter)
                    .padding(.top, 8)
                Link(TrustCopy.manageSubscription, destination: StoreManager.manageSubscriptionsURL)
                    .trustFont(14, weight: .medium)
                    .foregroundStyle(palette.accent)
                    .frame(minHeight: 44)
                    .padding(.horizontal, TrustTheme.gutter)
                Button(TrustCopy.restorePurchases) {
                    Task { await model.restorePurchases() }
                }
                .buttonStyle(TrustTextButtonStyle())
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(model.store.isWorking)
                .accessibilityIdentifier("plus-restore-purchases")
                .padding(.horizontal, TrustTheme.gutter)
                HStack(spacing: 8) {
                    Link(TrustCopy.privacy, destination: AppConfiguration.privacyURL)
                    Text("·")
                    Link(TrustCopy.terms, destination: AppConfiguration.termsURL)
                }
                .frame(minHeight: 44)
                .trustFont(12, weight: .medium)
                .foregroundStyle(palette.muted)
                .tint(palette.muted)
                .padding(.horizontal, TrustTheme.gutter)
                .padding(.top, 8)
                Button(TrustCopy.close) { model.showingPaywall = false }
                    .buttonStyle(TrustOutlineButtonStyle(compact: true))
                    .accessibilityLabel(TrustCopy.close)
                    .accessibilityIdentifier("plus-close")
                    .padding(.top, 10)
            }
            .padding(.bottom, 24)
            .trustReadableWidth()
        }
        .background(palette.paper.ignoresSafeArea())
    }

}
