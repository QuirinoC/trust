import SwiftUI
import TrustCore
import UserNotifications

/// You — profile, membership, personal location settings, and account.
struct YouView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(TrustAppearance.storageKey) private var appearance = TrustAppearance.system.rawValue
    @AppStorage(TrustAppLanguage.storageKey) private var appLanguage = TrustAppLanguage.system.rawValue
    @State private var showingDeleteAccount = false
    @State private var showingAvatarPicker = false
    @State private var showingLocation = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TrustPageTitle(text: TrustCopy.you)
                        .padding(.top, 20)

                    profileCard
                        .padding(.top, 22)

                    discoveryCard
                        .padding(.top, 16)

                    myLocationRow
                        .padding(.top, 16)
                        .padding(.bottom, 16)

                    plusCard
                        .padding(.bottom, 18)

                    TrustSectionHeading(TrustCopy.preferences)
                        .padding(.bottom, 4)
                    NotificationsSettingsSection(notifier: model.receipts)
                        .environmentObject(model)
                        .padding(.bottom, 18)
                    appearanceRow
                        .padding(.bottom, 18)
                    languageRow
                        .padding(.bottom, 18)

                    TrustSectionHeading(TrustCopy.account)
                        .padding(.bottom, 4)
                    Button(TrustCopy.signOut) { model.signOut() }
                        .buttonStyle(TrustTextButtonStyle())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)
                    Button(TrustCopy.deleteAccount) { showingDeleteAccount = true }
                        .buttonStyle(TrustTextButtonStyle(color: palette.danger))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("delete-account")
                }
                .padding(.horizontal, TrustTheme.gutter)
                .padding(.bottom, 28)
                .trustReadableWidth()
            }
            .accessibilityIdentifier("you-scroll")
            .clipped()
            legalLinks
        }
        .background(palette.paper.ignoresSafeArea())
        .onChange(of: model.selectedTab) { _, tab in
            if tab == .you { model.refreshNotificationStatus() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, model.selectedTab == .you {
                model.refreshNotificationStatus()
            }
        }
        .confirmationDialog(TrustCopy.deleteAccountConfirm, isPresented: $showingDeleteAccount, titleVisibility: .visible) {
            Button(TrustCopy.deleteAccount, role: .destructive) {
                Task { await model.deleteAccount() }
            }
            Button(TrustCopy.cancel, role: .cancel) {}
        }
        .sheet(isPresented: $showingAvatarPicker) {
            ProfileAvatarPicker()
                .environmentObject(model)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingLocation) {
            locationSheet
                .environmentObject(model)
                .presentationDetents([.large])
        }
        .task {
            if model.selectedTab == .you { model.refreshNotificationStatus() }
            guard !model.isDemoMode else { return }
            if let signed = await model.store.refreshEntitlement() {
                await model.syncCircleEntitlement(signedTransactionInfo: signed)
            }
        }
    }

    private var legalLinks: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(palette.line)
                .frame(height: 1)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Link(TrustCopy.privacy, destination: AppConfiguration.privacyURL)
                        .frame(minHeight: 44)
                        .fixedSize(horizontal: true, vertical: false)
                    Text("·")
                    Link(TrustCopy.terms, destination: AppConfiguration.termsURL)
                        .frame(minHeight: 44)
                        .fixedSize(horizontal: true, vertical: false)
                    Text("·")
                    Link(TrustCopy.support, destination: AppConfiguration.supportURL)
                        .frame(minHeight: 44)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityIdentifier("support-link")
                }
                VStack(spacing: 0) {
                    Link(TrustCopy.privacy, destination: AppConfiguration.privacyURL)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    Link(TrustCopy.terms, destination: AppConfiguration.termsURL)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    Link(TrustCopy.support, destination: AppConfiguration.supportURL)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier("support-link")
                }
            }
            .font(TrustTheme.ui(12))
            .foregroundStyle(palette.muted)
            .tint(palette.muted)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, TrustTheme.gutter)
        .padding(.bottom, 8)
        .trustReadableWidth()
        .background(palette.paper)
    }

    // MARK: Profile and personal settings

    private var appearanceRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                appearanceLabel
                Spacer(minLength: 8)
                appearancePicker
            }
            VStack(alignment: .leading, spacing: 4) {
                appearanceLabel
                appearancePicker
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(RoundedRectangle(cornerRadius: TrustTheme.controlRadius, style: .continuous).fill(palette.surface))
    }

    private var appearanceLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 18))
                .foregroundStyle(palette.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(TrustCopy.appearance)
                .trustFont(15, weight: .medium)
                .foregroundStyle(palette.ink)
        }
    }

    private var appearancePicker: some View {
        Picker(TrustCopy.appearance, selection: $appearance) {
            ForEach(TrustAppearance.allCases) { option in
                Text(option.title).tag(option.rawValue)
            }
        }
        .pickerStyle(.menu)
        .tint(palette.muted)
        .accessibilityLabel(TrustCopy.appearance)
        .accessibilityValue((TrustAppearance(rawValue: appearance) ?? .system).title)
        .accessibilityIdentifier("appearance-preference")
    }

    private var languageRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                languageLabel
                Spacer(minLength: 8)
                languagePicker
            }
            VStack(alignment: .leading, spacing: 4) {
                languageLabel
                languagePicker
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(RoundedRectangle(cornerRadius: TrustTheme.controlRadius, style: .continuous).fill(palette.surface))
    }

    private var languageLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 18))
                .foregroundStyle(palette.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(TrustCopy.language)
                .trustFont(15, weight: .medium)
                .foregroundStyle(palette.ink)
        }
    }

    private var languagePicker: some View {
        Picker(TrustCopy.language, selection: Binding(
            get: { appLanguage },
            set: { language in
                let value = TrustAppLanguage(rawValue: language) ?? .system
                model.traceUIInteraction("language callback: \(value.rawValue)")
                appLanguage = language
            }
        )) {
            ForEach(TrustAppLanguage.allCases) { option in
                Text(option.title).tag(option.rawValue)
            }
        }
        .pickerStyle(.menu)
        .tint(palette.muted)
        .accessibilityLabel(TrustCopy.language)
        .accessibilityValue((TrustAppLanguage(rawValue: appLanguage) ?? .system).title)
        .accessibilityIdentifier("language-preference")
        .onChange(of: appLanguage) { _, language in
            let value = TrustAppLanguage(rawValue: language) ?? .system
            model.traceUIInteraction("picker language observed: \(value.rawValue)")
        }
    }

    private var profileCard: some View {
        TrustCard(fill: palette.surface) {
            HStack(spacing: 14) {
                Button { showingAvatarPicker = true } label: {
                    TrustAvatar(name: model.you.displayName, seed: 0, size: 68, avatar: model.you.avatar, personID: model.you.id)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(palette.accentOn)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(palette.accent))
                                .overlay(Circle().stroke(palette.surface, lineWidth: 2))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(TrustCopy.editProfilePicture)
                .accessibilityIdentifier("edit-profile-picture")
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.you.displayName)
                        .font(TrustTheme.display(21))
                        .tracking(-0.5)
                        .foregroundStyle(palette.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let handle = model.you.handle {
                        Button {
                            model.copyOwnHandle()
                        } label: {
                            Label("@\(handle)", systemImage: "doc.on.doc")
                                .labelStyle(.titleAndIcon)
                                .font(TrustTheme.ui(13))
                                .foregroundStyle(palette.muted)
                                .frame(minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(TrustCopy.copyHandle)
                        .accessibilityIdentifier("copy-own-handle")
                        .accessibilityValue("@\(handle)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var discoveryCard: some View {
        TrustCard(fill: palette.surface) {
            VStack(alignment: .leading, spacing: 7) {
                Toggle(TrustCopy.discoveryEnabledLabel, isOn: Binding(
                    get: { model.you.discoveryEnabled == true },
                    set: { model.setDiscoveryEnabled($0) }
                ))
                .tint(palette.accent)
                .disabled(model.isUpdatingDiscovery || model.isDemoMode)
                .accessibilityIdentifier("phone-discovery-toggle")
                Text(TrustCopy.discoveryEnabledExplanation)
                    .trustFont(13)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var myLocationRow: some View {
        Button { showingLocation = true } label: {
            HStack(spacing: 13) {
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 25))
                    .foregroundStyle(palette.accent)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(TrustCopy.myLocation)
                        .trustFont(16, weight: .semibold)
                        .foregroundStyle(palette.ink)
                    Text(model.location.homeIsSet ? TrustCopy.homeSetOnThisPhone : TrustCopy.locationAccessStatus(model.location.statusLabel))
                        .trustFont(12)
                        .foregroundStyle(palette.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.muted)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: TrustTheme.radius, style: .continuous).fill(palette.surface))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("my-location")
    }

    private var locationSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    Text(TrustCopy.homePlacePrivacy)
                        .trustFont(13)
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    locationPermissionSection
                    homePlaceSection
                }
                .padding(TrustTheme.gutter)
                .trustReadableWidth()
            }
            .background(palette.paper.ignoresSafeArea())
            .navigationTitle(TrustCopy.myLocation)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(TrustCopy.done) { showingLocation = false }
                }
            }
        }
    }

    private var locationPermissionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TrustSectionHeading(TrustCopy.locationPermissionHeading)
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
                    .accessibilityIdentifier("location-permission-action")
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
                .accessibilityIdentifier("location-permission-action")
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
            Text(model.location.homeIsOwnedByAnotherDevice
                ? TrustCopy.homeOwnedElsewhereLabel
                : (model.location.homeIsSet ? TrustCopy.homeIsSetLabel : TrustCopy.homeNotSetLabel))
                .trustFont(13, weight: .semibold)
                .foregroundStyle(palette.ink)
                .accessibilityIdentifier("home-place-status")
            if model.location.homeIsOwnedByAnotherDevice {
                Text(TrustCopy.homeOwnedElsewhere)
                    .trustFont(12)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("home-monitoring-elsewhere")
            }
            if model.location.homeIsSet, !model.location.hasAlways {
                Text(TrustCopy.homeNeedsAlways)
                    .trustFont(12)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button(model.location.needsSystemSettings ? TrustCopy.openIOSSettings : TrustCopy.allowAlways) {
                    if model.location.needsSystemSettings { model.openSystemSettings() }
                    else { model.requestAlwaysLocation() }
                }
                    .buttonStyle(TrustOutlineButtonStyle(compact: true))
                    .accessibilityIdentifier("home-permission-action")
            }
            HStack(spacing: 12) {
                Button(TrustCopy.setHomeHere) { model.setHomeFromCurrentLocation() }
                    .buttonStyle(TrustOutlineButtonStyle(compact: true))
                    .disabled(model.isSettingHome)
                    .accessibilityIdentifier("home-set-button")
                if model.isSettingHome {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(TrustCopy.setHomeHere)
                }
                if model.location.homeIsSet {
                    Button(TrustCopy.clearHome) { model.clearHomePlace() }
                        .buttonStyle(TrustTextButtonStyle(color: palette.danger))
                        .accessibilityIdentifier("home-clear-button")
                }
            }
        }
    }

    private var plusCard: some View {
        TrustCard(padding: 14, fill: palette.paper) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    TrustEyebrow(text: TrustCopy.trustPlus, color: palette.accent, size: 10)
                    Text(model.coverage.isCovered ? TrustCopy.youHavePlus : TrustCopy.plusHeadline)
                        .trustFont(13, weight: .medium)
                        .foregroundStyle(palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if model.coverage.isCovered {
                    Link(TrustCopy.manage, destination: StoreManager.manageSubscriptionsURL)
                        .font(TrustTheme.ui(13, weight: .medium))
                        .foregroundStyle(palette.accent)
                        .frame(minHeight: 44)
                        .accessibilityLabel(TrustCopy.manageSubscription)
                } else {
                    Button { model.showingPaywall = true } label: {
                        HStack(spacing: 4) {
                            Text(TrustCopy.seePlus)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .accessibilityHidden(true)
                        }
                    }
                        .buttonStyle(TrustTextButtonStyle(color: palette.accent))
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

private struct NotificationsSettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @ObservedObject var notifier: LookReceiptNotifier

    private var statusLabel: String {
        switch notifier.authorization {
        case .notDetermined: return TrustCopy.notificationsNotEnabled
        case .denied: return TrustCopy.notificationsOffInSettings
        case .authorized: return TrustCopy.notificationsAllowed
        case .provisional: return TrustCopy.notificationsQuietlyAllowed
        case .ephemeral: return TrustCopy.notificationsQuietlyAllowed
        @unknown default: return TrustCopy.notificationsCheckSettings
        }
    }

    private var needsPermissionPrompt: Bool {
        notifier.authorization == .notDetermined
    }

    var body: some View {
        TrustCard(fill: palette.surface) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 19))
                        .foregroundStyle(palette.accent)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    Text(TrustCopy.notificationsHeading)
                        .trustFont(16, weight: .semibold)
                        .foregroundStyle(palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(TrustCopy.notificationsBody)
                    .trustFont(13)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                Text(statusLabel)
                    .trustFont(13, weight: .semibold)
                    .foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("notifications-permission-status")

                Button {
                    if needsPermissionPrompt {
                        Task { await model.requestNotifications() }
                    } else {
                        model.openNotificationSettings()
                    }
                } label: {
                    Text(model.isRequestingNotifications ? TrustCopy.notificationsRequesting :
                            (needsPermissionPrompt ? TrustCopy.enableAlerts : TrustCopy.openIOSSettings))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(TrustOutlineButtonStyle(compact: true))
                .disabled(model.isRequestingNotifications || (needsPermissionPrompt && model.isDemoMode))
                .accessibilityIdentifier(needsPermissionPrompt ? "enable-notifications" : "open-notification-settings")
            }
        }
    }
}

/// `.receipt-row` — one view-log line, both directions.
struct ViewLogRow: View {
    let event: LookEvent
    let youID: UUID
    @Environment(\.trustPalette) private var palette
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.kind == .removed
                  ? "person.crop.circle.badge.minus"
                  : (event.viewerID == youID ? "arrow.up.right" : "arrow.down.left"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.accent)
                .frame(width: 30, height: 30)
                .background(palette.canvas, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.logLine(youID: youID))
                    .font(TrustTheme.ui(14, weight: .medium))
                    .foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(event.at.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale))) · \(event.logKindLabel)")
                    .font(TrustTheme.ui(12))
                    .foregroundStyle(palette.muted)
                    .accessibilityLabel("\(event.at.formatted(Date.FormatStyle(date: .complete, time: .shortened, locale: locale))) · \(event.logKindLabel)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
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
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TrustPageTitle(text: asTab ? TrustCopy.log : TrustCopy.viewLog)
                    .padding(.top, asTab ? 20 : 4)
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
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = TrustAppLanguage.currentLocale
            formatter.doesRelativeDateFormatting = true
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
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
