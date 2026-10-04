import SwiftUI
import TrustCore

/// You — profile, membership, personal location settings, and account.
struct YouView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(TrustAppearance.storageKey) private var appearance = TrustAppearance.system.rawValue
    @AppStorage(TrustAppLanguage.storageKey) private var appLanguage = TrustAppLanguage.system.rawValue
    @State private var showingDeleteAccount = false
    @State private var showingAvatarPicker = false
    @State private var showingLocation = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        TrustPageTitle(text: TrustCopy.you)
                            .padding(.top, 20)

                        profileCard
                            .padding(.top, 22)

                        myLocationRow
                            .padding(.top, 20)
                            .padding(.bottom, 22)

                        plusCard
                            .padding(.bottom, 22)

                        TrustSectionHeading(TrustCopy.preferences)
                            .padding(.bottom, 4)
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
                            .accessibilityIdentifier("sign-out")
                        Button(TrustCopy.deleteAccount) { showingDeleteAccount = true }
                            .buttonStyle(TrustTextButtonStyle(color: palette.danger))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("delete-account")
                    }
                    .padding(.horizontal, TrustTheme.gutter)
                    .padding(.bottom, 28)
                    .trustReadableWidth()
                }
                .clipped()
                .accessibilityIdentifier("you-content")
                legalLinks
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .background(palette.paper.ignoresSafeArea())
        .confirmationDialog(TrustCopy.deleteAccountConfirm, isPresented: $showingDeleteAccount, titleVisibility: .visible) {
            Button(TrustCopy.deleteAccount, role: .destructive) {
                Task { await model.deleteAccount() }
            }
            .accessibilityIdentifier("delete-account-confirm")
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
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 0))
                : AnyLayout(HStackLayout(spacing: 16))
            layout {
                legalLink(TrustCopy.privacy, url: AppConfiguration.privacyURL, identifier: "privacy-link")
                legalLink(TrustCopy.terms, url: AppConfiguration.termsURL, identifier: "terms-link")
                legalLink(TrustCopy.support, url: AppConfiguration.supportURL, identifier: "support-link")
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, TrustTheme.gutter)
        .padding(.bottom, 8)
        .trustReadableWidth()
        .background(palette.paper)
    }

    private func legalLink(_ title: String, url: URL, identifier: String) -> some View {
        Link(title, destination: url)
            .font(.body)
            .foregroundStyle(Color.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityIdentifier(identifier)
            .accessibilityRemoveTraits(.isButton)
            .accessibilityAddTraits(.isLink)
    }

    // MARK: Profile and personal settings

    private var appearanceRow: some View {
        let usesStackedLayout = dynamicTypeSize.isAccessibilitySize
        let layout = usesStackedLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            HStack(spacing: 12) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 18))
                    .foregroundStyle(palette.accent)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                Text(TrustCopy.appearance)
                    .trustFont(15, weight: .medium)
                    .foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !usesStackedLayout {
                Spacer(minLength: 8)
            }
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
            .frame(maxWidth: usesStackedLayout ? .infinity : nil, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(RoundedRectangle(cornerRadius: TrustTheme.controlRadius, style: .continuous).fill(palette.surface))
    }

    private var languageRow: some View {
        let usesStackedLayout = dynamicTypeSize.isAccessibilitySize
        let layout = usesStackedLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.system(size: 18))
                    .foregroundStyle(palette.accent)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                Text(TrustCopy.language)
                    .trustFont(15, weight: .medium)
                    .foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !usesStackedLayout {
                Spacer(minLength: 8)
            }
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
            .frame(maxWidth: usesStackedLayout ? .infinity : nil, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(RoundedRectangle(cornerRadius: TrustTheme.controlRadius, style: .continuous).fill(palette.surface))
    }

    private var profileCard: some View {
        TrustCard(fill: palette.surface) {
            VStack(spacing: 7) {
                Button { showingAvatarPicker = true } label: {
                    TrustAvatar(name: model.you.displayName, seed: 0, size: 96, avatar: model.you.avatar, personID: model.you.id)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.accentOn)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(palette.accent))
                                .overlay(Circle().stroke(palette.surface, lineWidth: 3))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(TrustCopy.editProfilePicture)
                .accessibilityIdentifier("edit-profile-picture")
                Text(model.you.displayName)
                    .font(TrustTheme.display(23))
                    .tracking(-0.6)
                    .foregroundStyle(palette.ink)
                if let handle = model.you.handle {
                    Button {
                        model.copyOwnHandle()
                    } label: {
                        Label("@\(handle)", systemImage: "doc.on.doc")
                            .labelStyle(.titleAndIcon)
                            .font(TrustTheme.ui(13))
                            .foregroundStyle(palette.muted)
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel(TrustCopy.copyHandle)
                    .accessibilityIdentifier("copy-own-handle")
                    .accessibilityValue("@\(handle)")
                }
                VStack(alignment: .leading, spacing: 5) {
                    Toggle(TrustCopy.discoveryEnabledLabel, isOn: Binding(
                        get: { model.you.discoveryEnabled == true },
                        set: { model.setDiscoveryEnabled($0) }
                    ))
                    .tint(palette.accent)
                    .disabled(model.isUpdatingDiscovery || model.isDemoMode)
                    .accessibilityIdentifier("phone-discovery-toggle")
                    Text(TrustCopy.discoveryEnabledExplanation)
                        .trustFont(12)
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
                Text(TrustCopy.changePictureTip)
                    .trustFont(12)
                    .foregroundStyle(palette.muted)
            }
            .frame(maxWidth: .infinity)
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
                Button(TrustCopy.allowAlways) { model.requestAlwaysLocation() }
                    .buttonStyle(TrustOutlineButtonStyle(compact: true))
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
                .fixedSize(horizontal: false, vertical: true)
            Text("\(event.at.formatted(date: .abbreviated, time: .shortened)) · \(event.logKindLabel)")
                .font(TrustTheme.ui(12))
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
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
                        .accessibilityHidden(true)
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
                    .accessibilityIdentifier("export-log")
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
