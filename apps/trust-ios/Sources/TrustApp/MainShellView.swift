import SwiftUI
import TrustCore

/// People owns the map. Sharing, Log, and You keep the Trust. masthead.
struct MainShellView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            if showsMasthead {
                masthead
            }
            if model.isOffline, let since = model.snapshot?.fetchedAt {
                TrustOfflineBanner(since: since) {
                    Task { await model.refresh() }
                }
            }
            ZStack {
                CircleView()
                    .opacity(model.selectedTab == .circle ? 1 : 0)
                    .allowsHitTesting(model.selectedTab == .circle)
                    .accessibilityHidden(model.selectedTab != .circle)
                SharingView()
                    .opacity(model.selectedTab == .sharing ? 1 : 0)
                    .allowsHitTesting(model.selectedTab == .sharing)
                    .accessibilityHidden(model.selectedTab != .sharing)
                ViewLogView(inSheet: false, asTab: true)
                    .opacity(model.selectedTab == .log ? 1 : 0)
                    .allowsHitTesting(model.selectedTab == .log)
                    .accessibilityHidden(model.selectedTab != .log)
                YouView()
                    .opacity(model.selectedTab == .you ? 1 : 0)
                    .allowsHitTesting(model.selectedTab == .you)
                    .accessibilityHidden(model.selectedTab != .you)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            paperTabBar
        }
        .background(palette.paper.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                TrustToastView(toast: toast) { model.toast = nil }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 62)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.22), value: model.toast?.id)
        .onAppear {
            Task { await model.refresh() }
        }
        .sheet(item: $model.lookSubject) { subject in
            LookConfirmSheet(subject: subject)
                .environmentObject(model)
                .environment(\.trustPalette, palette)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(palette.paper)
                .presentationCornerRadius(28)
                .trustFormSheet()
        }
        .sheet(isPresented: $model.showingPaywall) {
            PlusPaywall()
                .environmentObject(model)
                .environment(\.trustPalette, palette)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(palette.paper)
                .trustFormSheet()
        }
        .sheet(isPresented: $model.showingAlwaysExplainer) {
            AlwaysExplainerSheet()
                .environmentObject(model)
                .environment(\.trustPalette, palette)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(palette.paper)
                .trustFormSheet()
        }
    }

    /// Opaque paper bar in the safe area. The system tab bar on iOS 26 is a glass pill
    /// whose content inset is taller than the pill, which clipped the People list.
    private var paperTabBar: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases) { tab in
                let selected = model.selectedTab == tab
                Button {
                    model.selectedTab = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 20, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(selected ? palette.accent : palette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityIdentifier("tab-\(tab.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .background(palette.paper.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.ink.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    /// Map owns the top on People; masthead stays on Sharing / Log / You.
    private var showsMasthead: Bool {
        model.selectedTab != .circle
    }

    /// `.app-header`: wordmark left, route caption right.
    private var masthead: some View {
        HStack(alignment: .center) {
            TrustWordmarkTitle(size: 34)
            if model.isDemoMode, !model.isScreenshotLaunch {
                TrustEyebrow(text: TrustCopy.demoBannerTitle, color: palette.accent, size: 9)
                    .padding(.leading, 8)
            }
            Spacer(minLength: 0)
            Text(caption.uppercased())
                .font(TrustTheme.folio(9))
                .tracking(1.2)
                .foregroundStyle(palette.muted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, TrustTheme.gutter)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(palette.paper)
    }

    private var caption: String {
        switch model.selectedTab {
        case .circle:
            if model.circlePath.last == .map { return TrustCopy.map }
            return TrustCopy.people
        case .sharing: return TrustCopy.sharing
        case .log: return TrustCopy.log
        case .you: return TrustCopy.you
        }
    }
}
