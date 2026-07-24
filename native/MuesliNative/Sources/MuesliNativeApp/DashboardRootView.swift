import SwiftUI
import MuesliCore

struct DashboardRootView: View {
    let appState: AppState
    let controller: MuesliController

    var body: some View {
        detailContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Horizontal only: the right pane's content runs edge-to-edge
            // vertically; the left card keeps its own vertical inset.
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(MuesliTheme.backgroundDeep)
            .ignoresSafeArea()
            .frame(minWidth: 980, minHeight: 600)
        // Suppress macOS's blue keyboard focus ring across the whole dashboard —
        // it appears on tab-bar / control clicks and reads as a stray selection.
        .focusEffectDisabled()
        .preferredColorScheme(appState.config.darkMode ? .dark : .light)
        .alert(
            appState.contributionMilestonePrompt?.title ?? tr("Muesli milestone", "Достижение Muesli"),
            isPresented: Binding(
                get: { appState.contributionMilestonePrompt != nil },
                set: { if !$0 { controller.dismissContributionMilestonePrompt() } }
            )
        ) {
            if appState.contributionMilestonePrompt?.showGitHubStar == true {
                Button(tr("Star on GitHub", "Поставить звезду на GitHub")) {
                    controller.openContributionMilestoneAction(.githubStar)
                }
            }
            if appState.contributionMilestonePrompt?.showBuyMeCoffee == true {
                Button("Buy Me a Coffee") {
                    controller.openContributionMilestoneAction(.buyMeCoffee)
                }
            }
            if appState.contributionMilestonePrompt?.showTweetAboutMuesli == true {
                Button(tr("Tweet about Muesli", "Твитнуть о Muesli")) {
                    controller.openContributionMilestoneAction(.tweetAboutMuesli)
                }
            }
            if appState.contributionMilestonePrompt?.showPostOnLinkedIn == true {
                Button(tr("Post about Muesli on LinkedIn", "Написать о Muesli в LinkedIn")) {
                    controller.openContributionMilestoneAction(.postOnLinkedIn)
                }
            }
            Button(tr("Later", "Позже"), role: .cancel) {
                controller.dismissContributionMilestonePrompt()
            }
        } message: {
            Text(appState.contributionMilestonePrompt?.message ?? "")
        }
        .onAppear {
            controller.recordContributionMilestonePromptSeen()
        }
        .onChange(of: appState.contributionMilestonePrompt?.id) { _, _ in
            controller.recordContributionMilestonePromptSeen()
        }
        .sheet(
            item: Binding<DiagnosticIncident?>(
                get: { appState.pendingDiagnosticIncident },
                set: { if $0 == nil { controller.dismissDiagnosticIncidentPrompt() } }
            )
        ) { incident in
            DiagnosticIncidentReportView(
                incident: incident,
                onOpenIssue: { controller.openDiagnosticIncidentIssue(incident) },
                onDismiss: { controller.dismissDiagnosticIncidentPrompt() }
            )
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if appState.isSearchActive,
           case .document(let id) = appState.meetingsNavigationState {
            MeetingDetailView(
                meeting: appState.selectedMeeting,
                controller: controller,
                appState: appState,
                onBack: {
                    appState.meetingsNavigationState = .browser
                    appState.selectedMeetingID = nil
                    appState.selectedMeetingRecord = nil
                },
                backLabel: tr("Back to Search", "Назад к поиску")
            )
            .id(id)
        } else if appState.isSearchActive {
            SearchResultsView(appState: appState, controller: controller)
        } else {
            switch appState.selectedTab {
            case .home:
                HomeView(appState: appState, controller: controller)
            case .dictations:
                DictationsView(appState: appState, controller: controller)
            case .meetings:
                MeetingsView(appState: appState, controller: controller)
            case .dictionary, .models, .shortcuts, .settings, .about:
                // Dictionary, Models, Shortcuts, and About now live inside Settings.
                SettingsView(appState: appState, controller: controller)
            }
        }
    }
}
