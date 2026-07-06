import Foundation
import Observation
import SwiftUI
import MuesliCore

enum DashboardTab: String, CaseIterable {
    case home
    case dictations
    case meetings
    case dictionary
    case models
    case shortcuts
    case settings
    case about
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case sync
    case dictation
    case computerUse
    case meetings
    case templates
    case appearance
    case dictionary
    case models
    case shortcuts
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return tr("General", "Общие")
        case .sync: return tr("Sync", "Синхронизация")
        case .dictation: return tr("Dictation", "Диктовка")
        case .computerUse: return tr("Computer Use", "Компьютер")
        case .meetings: return tr("Meetings", "Встречи")
        case .templates: return tr("Templates", "Шаблоны")
        case .appearance: return tr("Appearance", "Оформление")
        case .dictionary: return tr("Dictionary", "Словарь")
        case .models: return tr("Models", "Модели")
        case .shortcuts: return tr("Shortcuts", "Горячие клавиши")
        case .about: return tr("About", "О программе")
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .sync: return "arrow.triangle.2.circlepath.icloud.fill"
        case .dictation: return "mic.fill"
        case .computerUse: return "desktopcomputer"
        case .meetings: return "person.2.fill"
        case .templates: return "square.text.square.fill"
        case .appearance: return "paintbrush.fill"
        case .dictionary: return "character.book.closed.fill"
        case .models: return "square.and.arrow.down.fill"
        case .shortcuts: return "keyboard.fill"
        case .about: return "info.circle.fill"
        }
    }

    /// Telegram-style distinct icon tile color per section.
    var iconColor: Color {
        switch self {
        case .general: return Color(hex: 0x8E8E93)      // gray
        case .sync: return Color(hex: 0x34AADC)         // cyan
        case .dictation: return Color(hex: 0xFF3B30)    // red
        case .computerUse: return Color(hex: 0x5856D6)  // indigo
        case .meetings: return Color(hex: 0x34C759)     // green
        case .templates: return Color(hex: 0xAF52DE)    // purple
        case .appearance: return Color(hex: 0xFF9500)   // orange
        case .dictionary: return Color(hex: 0x00C7BE)   // teal
        case .models: return Color(hex: 0x007AFF)       // blue
        case .shortcuts: return Color(hex: 0xFF2D55)    // pink
        case .about: return Color(hex: 0x8E8E93)        // gray
        }
    }
}

enum MeetingsNavigationState: Equatable {
    case browser
    case document(Int64)
}

enum SparkleUpdateStatus: Equatable {
    case idle
    case checking
    case busy(message: String)
    case available(version: String)
    case downloaded(version: String)
    case installing(version: String)
    case upToDate
    case disabled(message: String)
    case failed(message: String)
}

enum GoogleCalendarListLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

enum ICloudBridgeState: Equatable {
    case notConfigured
    case checkingICloud
    case syncing
    case active
    case needsICloud
    case error
}

struct ActiveMeetingAudioWarning: Equatable {
    let meetingID: Int64
    let message: String
}

@MainActor
@Observable
final class AppState {
    // Dashboard data
    var dictationRows: [DictationRecord] = []
    var meetingRows: [MeetingRecord] = []
    var totalMeetingCount: Int = 0
    var meetingCountsByFolder: [Int64: Int] = [:]
    var directMeetingCountsByFolder: [Int64: Int] = [:]
    var selectedMeetingID: Int64?
    var selectedMeetingRecord: MeetingRecord?
    var folders: [MeetingFolder] = []
    var selectedFolderID: Int64?  // nil = "All Meetings"
    var meetingsNavigationState: MeetingsNavigationState = .browser
    /// Non-AI Overview dashboard dataset (computed off-main, lazily).
    var overviewAnalytics: OverviewAnalytics?
    var overviewAnalyticsLoading = false

    /// AI Insights results, cached per period for the session; generated on demand.
    var meetingInsights: [InsightsPeriod: InsightsResult] = [:]
    var insightsGenerating: Set<InsightsPeriod> = []
    /// Folder filter for the Insights page (nil = all folders).
    var insightsFolderID: Int64? = nil

    /// In-memory AI chat conversations per meeting (not persisted to disk):
    /// survive tab switches and page toggles within the app session.
    var meetingChatHistories: [Int64: [MeetingChatMessage]] = [:]
    /// Meetings with an AI chat reply currently in flight.
    var meetingChatAwaiting: Set<Int64> = []
    var isMeetingTemplatesManagerPresented: Bool = false
    var meetingTemplatesManagerStartsCreating: Bool = false
    /// When set, the templates manager opens with this template (built-in or
    /// custom) already loaded into the editor.
    var meetingTemplatesManagerStartsEditingID: String?
    var dictationStats: DictationStats = DictationStats(
        totalWords: 0, totalSessions: 0, averageWordsPerSession: 0,
        averageWPM: 0, currentStreakDays: 0, longestStreakDays: 0
    )
    var meetingStats: MeetingStats = MeetingStats(totalWords: 0, totalMeetings: 0, averageWPM: 0)

    // Config-driven state
    var selectedBackend: BackendOption = .whisper
    var selectedMeetingTranscriptionBackend: BackendOption = .whisper
    var selectedMeetingSummaryBackend: MeetingSummaryBackendOption = .chatGPT
    var selectedPostProcessorBackend: TranscriptCleanupBackendOption = .local
    var activePostProcessor: PostProcessorOption = PostProcessorOption.defaultOption
    var config: AppConfig = AppConfig()
    var launchAtLoginRegistrationState: LaunchAtLoginRegistrationState = .disabled

    // Live status
    var isMeetingRecording: Bool = false
    var isMeetingRecordingPaused: Bool = false
    var isMeetingStarting: Bool = false
    var meetingStartStatus: String?
    var liveMeetingTranscript: String = ""
    var liveMeetingTranscriptOwnerID: Int64? = nil
    var activeMeetingAudioWarning: ActiveMeetingAudioWarning?
    var dictationState: DictationState = .idle
    var isVoiceNoteRecording: Bool = false
    var isChatGPTAuthenticated: Bool = false
    var isGoogleCalendarAvailable: Bool = false
    var isGoogleCalendarVerified: Bool = false
    var isGoogleCalendarAuthenticated: Bool = false
    var upcomingCalendarEvents: [UnifiedCalendarEvent] = []
    var hiddenCalendarEventIDs: Set<String> = []
    var availableEventKitCalendars: [AvailableCalendar] = []
    var availableGoogleCalendars: [GoogleCalendarSummary] = []
    var googleCalendarListLoadState: GoogleCalendarListLoadState = .idle
    var sparkleUpdateStatus: SparkleUpdateStatus = .idle
    var sparkleLastCheckedAt: Date?
    var iCloudSyncStatus: String?
    var isICloudSyncInProgress: Bool = false
    var isICloudBridgeActivationPending: Bool = false
    var iCloudBridgeState: ICloudBridgeState = .notConfigured
    var iCloudBridgeMessage: String?
    var iCloudBridgeRemoteDeviceName: String?
    var iCloudBridgeRemoteDevicePlatform: String?
    var iCloudBridgeCompanionDeviceName: String? {
        guard isICloudBridgeCompanionPlatform else { return nil }
        return iCloudBridgeRemoteDeviceName
    }
    var isICloudBridgeCompanionPlatform: Bool {
        guard let platform = iCloudBridgeRemoteDevicePlatform else { return false }
        switch platform.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ios", "ipados":
            return true
        default:
            return false
        }
    }
    var iCloudLastSyncSummary: String?
    var iCloudLastSyncedAt: Date?
    var contributionMilestonePrompt: ContributionMilestonePrompt?
    var pendingDiagnosticIncident: DiagnosticIncident?
    var modelPreparationTitle: String?
    var modelPreparationDetail: String?
    var modelPreparationProgress: Double?
    var isModelPreparingAfterDownload: Bool = false
    var modelPreparationIsComplete: Bool = false

    // Dictation pagination & filtering
    var dictationPageSize: Int = 50
    var dictationFromDate: String? = nil
    var dictationToDate: String? = nil
    var hasMoreDictations: Bool = true

    // Search
    var searchQuery: String = ""
    var searchResultDictations: [DictationRecord] = []
    var searchResultMeetings: [MeetingRecord] = []
    var focusSearchField: Bool = false
    var isSearchActive: Bool { !searchQuery.isEmpty }

    // Navigation
    var selectedTab: DashboardTab = .home
    var settingsSection: SettingsSection = .general

    // Computed
    var selectedMeeting: MeetingRecord? {
        guard let id = selectedMeetingID else { return nil }
        if let row = meetingRows.first(where: { $0.id == id }) {
            return row
        }
        guard selectedMeetingRecord?.id == id else { return nil }
        return selectedMeetingRecord
    }
}
