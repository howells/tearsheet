/// The first run, in order: permission, the ⇧⌘4 decision, one real capture, then the last settings.
public enum OnboardingStep: Int, CaseIterable, Sendable {
    case screenRecording, shortcut, firstCapture, ready

    /// 1-based, for "1 of 4".
    public var number: Int { rawValue + 1 }
}

/// What the first run has stored. Facts the Mac can answer live (permission,
/// the macOS shortcut) are not stored, so a change made elsewhere is picked up.
public struct OnboardingRecord: Codable, Equatable, Sendable {
    public var isFinished = false
    /// Chose to leave ⇧⌘4 with macOS.
    public var keptMacOSShortcut = false
    /// Captured something, or moved on without.
    public var passedFirstCapture = false

    public init() {}
}

public enum Onboarding {
    public struct Facts: Sendable {
        public var canRecordScreen: Bool
        public var macOSClaimsShortcut: Bool

        public init(canRecordScreen: Bool, macOSClaimsShortcut: Bool) {
            self.canRecordScreen = canRecordScreen
            self.macOSClaimsShortcut = macOSClaimsShortcut
        }
    }

    /// The step to open on: the first one not yet settled. Nil once finished.
    public static func resumeStep(_ record: OnboardingRecord, facts: Facts) -> OnboardingStep? {
        guard !record.isFinished else { return nil }
        return OnboardingStep.allCases.first { !isSettled($0, record: record, facts: facts) }
    }

    public static func isSettled(_ step: OnboardingStep, record: OnboardingRecord, facts: Facts) -> Bool {
        switch step {
        case .screenRecording: facts.canRecordScreen
        case .shortcut: !facts.macOSClaimsShortcut || record.keptMacOSShortcut
        case .firstCapture: record.passedFirstCapture
        case .ready: record.isFinished
        }
    }

    /// The stored record, or for a Mac that has never stored one: finished if
    /// Tearsheet was already in use before onboarding existed, otherwise fresh.
    public static func record(stored: OnboardingRecord?, hasPriorUse: Bool) -> OnboardingRecord {
        if let stored { return stored }
        var record = OnboardingRecord()
        record.isFinished = hasPriorUse
        return record
    }
}

/// macOS can report the permission before capture actually works; until
/// Tearsheet is reopened, a capture fails. Only a capture that worked counts.
public enum ScreenRecordingStatus: Equatable, Sendable {
    case notAllowed, checking, allowed, needsReopen

    public init(granted: Bool, captureWorked: Bool?) {
        switch (granted, captureWorked) {
        case (false, _): self = .notAllowed
        case (true, nil): self = .checking
        case (true, true?): self = .allowed
        case (true, false?): self = .needsReopen
        }
    }
}

/// Whether Tearsheet can capture: macOS's answer, proved by a real screenshot. A few
/// failures in a row mean Tearsheet needs reopening, and then it stops trying. Any change
/// of permission means capture has to be proved again.
public struct CaptureCheck: Equatable, Sendable {
    public private(set) var granted: Bool
    public private(set) var worked: Bool?
    public private(set) var attempts = 0
    public let limit: Int

    public init(granted: Bool, limit: Int = 3) {
        self.granted = granted
        self.limit = limit
    }

    public var status: ScreenRecordingStatus { ScreenRecordingStatus(granted: granted, captureWorked: worked) }

    public var shouldProbe: Bool { granted && worked == nil && attempts < limit }

    public mutating func update(granted: Bool) {
        if granted != self.granted {
            worked = nil
            attempts = 0
        }
        self.granted = granted
    }

    public mutating func probeStarted() { attempts += 1 }

    public mutating func probe(succeeded: Bool) {
        if succeeded {
            worked = true
        } else if attempts >= limit {
            worked = false
        }
    }
}

extension Onboarding {
    /// A later step without working capture goes back to Screen Recording, where it can be put right.
    public static func needsScreenRecordingStep(_ step: OnboardingStep, status: ScreenRecordingStatus) -> Bool {
        step != .screenRecording && (status == .notAllowed || status == .needsReopen)
    }
}
