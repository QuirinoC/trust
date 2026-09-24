import SwiftUI
import TrustCore

/// You — account, presence, Plus, delete.
struct YouView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @State private var showingDeleteAccount = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TrustPageTitle(text: TrustCopy.you)
                    .padding(.top, 4)

                profileCard
                    .padding(.top, 22)

                presenceSection
                    .padding(.bottom, 22)

                locationPermissionSection
                    .padding(.bottom, 18)

                homePlaceSection
                    .padding(.bottom, 22)

                plusCard
                    .padding(.bottom, 22)

                TrustSectionHeading("Account")
                    .padding(.bottom, 4)
                Button(TrustCopy.signOut) { model.signOut() }
                    .buttonStyle(TrustTextButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
                Button(TrustCopy.deleteAccount) { showingDeleteAccount = true }
                    .buttonStyle(TrustTextButtonStyle(color: palette.danger))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("delete-account")

                TrustSectionHeading("Legal")
                    .padding(.top, 16)
                HStack(spacing: 8) {
                    Link(TrustCopy.privacy, destination: AppConfiguration.privacyURL)
                    Text("·")
                    Link(TrustCopy.terms, destination: AppConfiguration.termsURL)
                    Text("·")
                    Link(TrustCopy.support, destination: AppConfiguration.supportURL)
                        .accessibilityIdentifier("support-link")
                }
                .font(TrustTheme.ui(12))
                .foregroundStyle(palette.muted)
                .tint(palette.muted)
                .padding(.top, 18)
            }
            .padding(.horizontal, TrustTheme.gutter)
            .padding(.bottom, 28)
            .trustReadableWidth()
        }
        .background(palette.paper.ignoresSafeArea())
        .confirmationDialog(TrustCopy.deleteAccountConfirm, isPresented: $showingDeleteAccount, titleVisibility: .visible) {
            Button(TrustCopy.deleteAccount, role: .destructive) {
                Task { await model.deleteAccount() }
            }
            Button(TrustCopy.cancel, role: .cancel) {}
        }
        .task {
            guard !model.isDemoMode else { return }
            if let signed = await model.store.refreshEntitlement() {
                await model.syncCircleEntitlement(signedTransactionInfo: signed)
            }
        }
    }

    // MARK: Profile / status

    private var profileCard: some View {
        HStack(spacing: 14) {
            TrustAvatar(name: model.you.displayName, seed: 0, size: 70)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.you.displayName)
                    .font(TrustTheme.display(24))
                    .tracking(-0.6)
                    .foregroundStyle(palette.ink)
                Text([model.you.handle.map { "@\($0)" }, model.coverage.planLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(TrustTheme.ui(13))
                    .foregroundStyle(palette.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Presence triad (free, manual, global)

    private var presenceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TrustSectionHeading(TrustCopy.status)
            TrustModeControl<HomePresenceKind>(
                items: HomePresenceKind.triad.map { .init(id: $0, label: $0.label) },
                selection: model.myPresence == .unknown ? nil : model.myPresence
            ) { kind in
                model.setPresence(kind)
            }
        }
    }

    private var locationPermissionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TrustSectionHeading("Location permission")
            Text("\(model.location.statusLabel) · \(model.location.accuracyLabel)")
                .trustFont(13, weight: .semibold)
                .foregroundStyle(palette.ink)
                .accessibilityIdentifier("location-permission-status")
            if model.location.isDenied {
                Text(TrustCopy.locationDeniedBody)
                    .trustFont(12)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button(TrustCopy.openIOSSettings) { model.openSystemSettings() }
                    .buttonStyle(TrustOutlineButtonStyle(compact: true))
            } else if !model.location.hasAlways {
                Text(model.location.isPrecise ? TrustCopy.keptWhileUsing : TrustCopy.locationReducedAccuracy)
                    .trustFont(12)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button(model.location.needsSystemSettings ? TrustCopy.openIOSSettings : TrustCopy.allowAlways) {
                    if model.location.needsSystemSettings { model.openSystemSettings() }
                    else { model.requestAlwaysLocation() }
                }
                .buttonStyle(TrustOutlineButtonStyle(compact: true))
            }
        }
    }

    // MARK: Home place (on-device coords; server gets presence only)

    private var homePlaceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TrustSectionHeading(TrustCopy.homePlace)
            Text(TrustCopy.homePlaceNote)
                .trustFont(12)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.location.homeIsSet ? TrustCopy.homeIsSetLabel : TrustCopy.homeNotSetLabel)
                .trustFont(13, weight: .semibold)
                .foregroundStyle(palette.ink)
            if model.location.homeIsSet, !model.location.hasAlways {
                Text(TrustCopy.homeNeedsAlways)
                    .trustFont(12)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button(TrustCopy.allowAlways) { model.requestAlwaysLocation() }
                    .buttonStyle(TrustOutlineButtonStyle(compact: true))
            }
            HStack(spacing: 12) {
                Button(TrustCopy.setHomeHere) { model.setHomeFromCurrentLocation() }
                    .buttonStyle(TrustOutlineButtonStyle(compact: true))
                if model.location.homeIsSet {
                    Button(TrustCopy.clearHome) { model.clearHomePlace() }
                        .buttonStyle(TrustTextButtonStyle(color: palette.danger))
                }
            }
        }
    }

    private var plusCard: some View {
        TrustCard(fill: palette.paper) {
            VStack(alignment: .leading, spacing: 10) {
                TrustEyebrow(text: TrustCopy.trustPlus, color: palette.accent, size: 10)
                if model.coverage.isCovered {
                    Text(TrustCopy.youHavePlus)
                        .font(TrustTheme.ui(16, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Link(TrustCopy.manageSubscription, destination: StoreManager.manageSubscriptionsURL)
                        .font(TrustTheme.ui(13, weight: .medium))
                        .foregroundStyle(palette.accent)
                        .frame(minHeight: 44)
                } else {
                    Text(TrustCopy.plusHeadline)
                        .font(TrustTheme.display(22))
                        .tracking(-0.5)
                        .foregroundStyle(palette.ink)
                    Button(TrustCopy.seePlus) { model.showingPaywall = true }
                        .buttonStyle(TrustOutlineButtonStyle(compact: true))
                        .accessibilityIdentifier("plus-cta")
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: TrustTheme.radius, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
    }
}

/// `.receipt-row` — one view-log line, both directions.
struct ViewLogRow: View {
    let event: LookEvent
    let youID: UUID
    @Environment(\.trustPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.logLine(youID: youID))
                .font(TrustTheme.ui(14))
                .foregroundStyle(palette.ink)
            Text("\(event.at.formatted(date: .omitted, time: .shortened)) · \(event.logKindLabel)")
                .font(TrustTheme.ui(12))
                .foregroundStyle(palette.muted)
                .accessibilityLabel("\(event.at.formatted(date: .complete, time: .shortened)) · \(event.logKindLabel)")
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// D3 View log — chronological, both directions. Free keeps 30 days; Plus keeps a year + export.
struct ViewLogView: View {
    var inSheet: Bool
    var asTab: Bool = false
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TrustPageTitle(text: asTab ? TrustCopy.log : TrustCopy.viewLog)
                    .padding(.top, 4)
                if !asTab {
                    Text(TrustCopy.viewLogIntro)
                        .font(TrustTheme.ui(13))
                        .foregroundStyle(palette.muted)
                        .padding(.top, 6)
                    Text(TrustCopy.viewLogRetention(freeDays: CircleCoverage.freeLookLogDays))
                        .font(TrustTheme.ui(12))
                        .foregroundStyle(palette.muted)
                        .padding(.top, 4)
                        .padding(.bottom, 18)
                } else {
                    Color.clear.frame(height: 12)
                }

                if model.lookLog.isEmpty {
                    Text(TrustCopy.noViewsYet)
                        .font(TrustTheme.ui(13))
                .foregroundStyle(palette.muted)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    ForEach(dayGroups) { group in
                        TrustSectionHeading(group.title)
                            .padding(.top, 14)
                        ForEach(group.events) { event in
                            ViewLogRow(event: event, youID: model.you.id)
                                .accessibilityIdentifier("activity-event-\(event.id.uuidString)")
                            TrustRowDivider()
                        }
                    }
                }

                if let retained = model.snapshot?.retainedLookLogCount, retained > 0 {
                    Text(TrustCopy.olderEntriesHeld(retained))
                        .font(TrustTheme.ui(12))
                        .foregroundStyle(palette.accent)
                        .padding(.top, 14)
                }

                if model.coverage.canExportLookLog, !model.lookLog.isEmpty {
                    ShareLink(item: model.lookLogExportText) {
                        Label(TrustCopy.exportLog, systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TrustOutlineButtonStyle(compact: true))
                    .padding(.top, 18)
                }
            }
            .padding(.horizontal, TrustTheme.gutter)
            .padding(.bottom, 28)
            .trustReadableWidth()
        }
        .background(palette.paper.ignoresSafeArea())
        .toolbar(asTab ? .hidden : .visible, for: .navigationBar)
        .toolbarBackground(palette.paper, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if !asTab {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if inSheet { model.showingViewLog = false } else { dismiss() }
                    } label: {
                        HStack(spacing: 4) {
                            if !inSheet {
                                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                            }
                            Text(inSheet ? TrustCopy.close : TrustCopy.you)
                        }
                        .font(TrustTheme.ui(15, weight: .medium))
                        .foregroundStyle(palette.ink)
                    }
                }
            }
        }
    }

    private struct EventDay: Identifiable {
        let date: Date
        let events: [LookEvent]
        var id: Date { date }
        var title: String {
            let calendar = Calendar.current
            if calendar.isDateInToday(date) { return "Today" }
            if calendar.isDateInYesterday(date) { return "Yesterday" }
            return date.formatted(date: .complete, time: .omitted)
        }
    }

    private var dayGroups: [EventDay] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: model.lookLog) { calendar.startOfDay(for: $0.at) }
        return groups.keys.sorted(by: >).map { day in
            EventDay(date: day, events: (groups[day] ?? []).sorted { $0.at > $1.at })
        }
    }
}
