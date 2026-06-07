import SwiftUI

@MainActor
public final class AppSettingsStore: ObservableObject {
    @AppStorage("settings.academicYear")
    public var academicYear: String = "2024-2025"
    
    @AppStorage("settings.centerName")
    public var centerName: String = ""
    
    @AppStorage("settings.defaultGradeScale")
    public var defaultGradeScale: String = "10"
    
    // Average Rounding Mode (wrapped for @AppStorage enum support)
    @AppStorage("settings.averageRoundingMode")
    private var averageRoundingModeRaw: String = AverageRoundingMode.roundHalfUp.rawValue
    
    public var averageRoundingMode: AverageRoundingMode {
        get { AverageRoundingMode(rawValue: averageRoundingModeRaw) ?? .roundHalfUp }
        set { averageRoundingModeRaw = newValue.rawValue }
    }
    
    // Notebook Density (wrapped)
    @AppStorage("settings.notebookDensity")
    private var notebookDensityRaw: String = NotebookDensity.compact.rawValue
    
    public var notebookDensity: NotebookDensity {
        get { NotebookDensity(rawValue: notebookDensityRaw) ?? .compact }
        set { notebookDensityRaw = newValue.rawValue }
    }
    
    @AppStorage("settings.showRawPhysicalValues")
    public var showRawPhysicalValues: Bool = true
    
    @AppStorage("settings.showAverageExplanation")
    public var showAverageExplanation: Bool = true
    
    // Backup Frequency (wrapped)
    @AppStorage("settings.backupFrequency")
    private var backupFrequencyRaw: String = BackupFrequency.weekly.rawValue
    
    public var backupFrequency: BackupFrequency {
        get { BackupFrequency(rawValue: backupFrequencyRaw) ?? .weekly }
        set { backupFrequencyRaw = newValue.rawValue }
    }
    
    @AppStorage("settings.createEmergencyBackupBeforeRestore")
    public var createEmergencyBackupBeforeRestore: Bool = true
    
    @AppStorage("settings.syncAutoStart")
    public var syncAutoStart: Bool = true
    
    // Device Display Name
    private static var defaultDeviceName: String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mi Mac"
        #else
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "Mi dispositivo Apple"
        #endif
        #endif
    }
    
    @AppStorage("settings.deviceDisplayName")
    public var deviceDisplayName: String = defaultDeviceName

    @AppStorage("teacher.enabledSubjectProfiles.v1")
    private var enabledSubjectProfilesRaw: String = TeacherSubjectProfile.general.rawValue

    public var enabledSubjectProfiles: Set<TeacherSubjectProfile> {
        get { TeacherSubjectProfile.decodeSet(enabledSubjectProfilesRaw) }
        set { enabledSubjectProfilesRaw = TeacherSubjectProfile.encodeSet(newValue) }
    }
    
    // Apple AI Feature Flags
    @AppStorage("settings.appleAIReportsEnabled")
    public var appleAIReportsEnabled: Bool = true
    
    @AppStorage("settings.appleAIRadarEnabled")
    public var appleAIRadarEnabled: Bool = true
    
    // Appearance settings
    @AppStorage("theme_mode")
    public var themeModeRawValue: String = AppThemeMode.system.rawValue
    
    @AppStorage("mac_reduce_motion")
    public var reduceMotion: Bool = false
    
    @AppStorage("mac_compact_density")
    public var compactDensity: Bool = false

    public init() {}
    
    public func resetVisualSettings() {
        notebookDensity = .compact
        showRawPhysicalValues = true
        showAverageExplanation = true
        themeModeRawValue = AppThemeMode.system.rawValue
        reduceMotion = false
        compactDensity = false
    }
}
