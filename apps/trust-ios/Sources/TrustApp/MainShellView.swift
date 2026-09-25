import SwiftUI
import TrustCore

/// The selected screen owns its title; the shell supplies navigation and global status.
struct MainShellView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            if model.isOffline, let since = model.snapshot?.fetchedAt {
                TrustOfflineBanner(since: since) { Task { await model.refresh() } }
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
            tabBar
        }
        .background(palette.canvas.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                TrustToastView(toast: toast) { model.toast = nil }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 68)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.22), value: model.toast?.id)
        // Authentication and app startup already refresh before entering the home shell.
        // A second unconditional request here races that first call; when the API is
        // waking up, one request can fail and briefly show the offline banner while
        // the queued request succeeds. Keep the shell lifecycle path freshness-gated.
        .onAppear { Task { await model.refreshIfStale() } }
        .onChange(of: model.selectedTab) { _, _ in
            Task { await model.refreshIfStale() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.refreshIfStale() }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await model.refreshIfStale()
            }
        }
        .sheet(item: $model.lookSubject) { subject in
            LookConfirmSheet(subject: subject)
                .environmentObject(model)
                .environment(\.trustPalette, palette)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(palette.sheet)
                .presentationCornerRadius(28)
                .trustFormSheet()
        }
        .sheet(isPresented: $model.showingPaywall) {
            PlusPaywall()
                .environmentObject(model)
                .environment(\.trustPalette, palette)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(palette.sheet)
                .trustFormSheet()
        }
        .sheet(isPresented: $model.showingAlwaysExplainer) {
            AlwaysExplainerSheet()
                .environmentObject(model)
                .environment(\.trustPalette, palette)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(palette.sheet)
                .trustFormSheet()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(MainTab.allCases) { tab in
                let selected = model.selectedTab == tab
                Button {
                    model.selectedTab = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 19, weight: selected ? .semibold : .regular))
                            .frame(height: 21)
                        Text(tab.title)
                            .font(.system(size: 11, weight: selected ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selected ? palette.accent : palette.muted)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(palette.accentSoft)
                                .padding(.horizontal, 4)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityIdentifier("tab-\(tab.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(palette.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(palette.line).frame(height: 0.7) }
        .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: -4)
    }
}
