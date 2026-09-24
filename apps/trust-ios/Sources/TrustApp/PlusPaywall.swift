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
        .accessibilityLabel(TrustCopy.trustPlus)
    }

    private var store: some View {
        SubscriptionStoreView(productIDs: productIDs) {
            marketing
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
        .tint(palette.accent)
        .safeAreaInset(edge: .bottom) {
            extras
        }
    }

    private var marketing: some View {
        VStack(alignment: .leading, spacing: 0) {
            TrustEyebrow(text: TrustCopy.trustPlus, color: palette.accent, size: 10)
            Text(TrustCopy.plusHeadline)
                .font(TrustTheme.display(32))
                .tracking(-1)
                .foregroundStyle(palette.ink)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 8) {
                feature(TrustCopy.plusFeatureSeats)
                feature(TrustCopy.plusFeatureModes)
                feature(TrustCopy.plusFeatureMap)
                feature(TrustCopy.plusFeatureLog)
            }
            .padding(.bottom, 14)

            Text(TrustCopy.plusStaysFree)
                .trustFont(13)
                .lineSpacing(3)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 8)
        .trustReadableWidth()
    }

    private var extras: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.store.linkedToAnotherAccount {
                Text(TrustCopy.subscriptionLinked)
                    .trustFont(13)
                    .foregroundStyle(palette.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(TrustCopy.subscriptionLinked)
            }
            if let error = model.store.errorMessage, !error.isEmpty {
                Text(error)
                    .trustFont(13)
                    .foregroundStyle(palette.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.snapshot?.allowsReviewUnlock == true {
                Button(TrustCopy.unlockPlusForReview) { model.unlockPlusForReview() }
                    .buttonStyle(TrustOutlineButtonStyle(compact: true))
            }
            Text(TrustCopy.plusLegal)
                .trustFont(12)
                .lineSpacing(3)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button(TrustCopy.close) { model.showingPaywall = false }
                .buttonStyle(TrustTextButtonStyle())
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 26)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.paper)
        .trustReadableWidth()
    }

    private var covered: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                marketing
                Text(TrustCopy.youHavePlus)
                    .trustFont(15, weight: .semibold)
                    .foregroundStyle(palette.ink)
                    .padding(.horizontal, 26)
                    .padding(.top, 8)
                Text(TrustCopy.plusCoveredBody)
                    .trustFont(13)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 26)
                    .padding(.top, 8)
                Link(TrustCopy.manageSubscription, destination: StoreManager.manageSubscriptionsURL)
                    .trustFont(14, weight: .medium)
                    .foregroundStyle(palette.accent)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 26)
                Button(TrustCopy.restorePurchases) {
                    Task { await model.restorePurchases() }
                }
                .buttonStyle(TrustTextButtonStyle())
                .frame(maxWidth: .infinity)
                .disabled(model.store.isWorking)
                .padding(.horizontal, 26)
                HStack(spacing: 8) {
                    Link(TrustCopy.privacy, destination: AppConfiguration.privacyURL)
                    Text("·")
                    Link(TrustCopy.terms, destination: AppConfiguration.termsURL)
                }
                .trustFont(12, weight: .medium)
                .foregroundStyle(palette.muted)
                .tint(palette.muted)
                .padding(.horizontal, 26)
                .padding(.top, 8)
                Button(TrustCopy.close) { model.showingPaywall = false }
                    .buttonStyle(TrustTextButtonStyle())
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
            }
            .padding(.bottom, 24)
            .trustReadableWidth()
        }
        .background(palette.paper.ignoresSafeArea())
    }

    private func feature(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .trustFont(12, weight: .semibold)
                .foregroundStyle(palette.accent)
                .padding(.top, 2)
                .accessibilityHidden(true)
            Text(text)
                .trustFont(13)
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
