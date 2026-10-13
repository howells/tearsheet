import Testing
@testable import TearsheetCore

struct OnboardingTests {
    let fresh = OnboardingRecord()
    let mac = Onboarding.Facts(canRecordScreen: false, macOSClaimsShortcut: true)

    @Test func freshMacStartsWithScreenRecording() {
        #expect(Onboarding.resumeStep(fresh, facts: mac) == .screenRecording)
    }

    @Test func grantedMovesOnToTheShortcut() {
        let facts = Onboarding.Facts(canRecordScreen: true, macOSClaimsShortcut: true)
        #expect(Onboarding.resumeStep(fresh, facts: facts) == .shortcut)
    }

    @Test func shortcutIsDoneOnceMacOSLetsGo() {
        let facts = Onboarding.Facts(canRecordScreen: true, macOSClaimsShortcut: false)
        #expect(Onboarding.resumeStep(fresh, facts: facts) == .firstCapture)
    }

    @Test func keepingTheMacOSShortcutCountsAsDecided() {
        var record = fresh
        record.keptMacOSShortcut = true
        let facts = Onboarding.Facts(canRecordScreen: true, macOSClaimsShortcut: true)
        #expect(Onboarding.resumeStep(record, facts: facts) == .firstCapture)
    }

    @Test func pastTheCaptureLeavesOnlyReady() {
        var record = fresh
        record.passedFirstCapture = true
        let facts = Onboarding.Facts(canRecordScreen: true, macOSClaimsShortcut: false)
        #expect(Onboarding.resumeStep(record, facts: facts) == .ready)
    }

    @Test func finishedIsNeverShownAgain() {
        var record = fresh
        record.isFinished = true
        #expect(Onboarding.resumeStep(record, facts: mac) == nil)
    }

    @Test func permissionWithdrawnMidwayGoesBackToIt() {
        var record = fresh
        record.passedFirstCapture = true
        let facts = Onboarding.Facts(canRecordScreen: false, macOSClaimsShortcut: false)
        #expect(Onboarding.resumeStep(record, facts: facts) == .screenRecording)
    }

    @Test func existingInstallCountsAsFinished() {
        #expect(Onboarding.record(stored: nil, hasPriorUse: true).isFinished)
        #expect(Onboarding.record(stored: nil, hasPriorUse: false) == OnboardingRecord())
    }

    @Test func aStartedRecordOutlivesLaterUse() {
        var started = fresh
        started.passedFirstCapture = true
        // The first capture stores a last region; that mustn't end an unfinished run.
        #expect(Onboarding.record(stored: started, hasPriorUse: true) == started)
    }

    @Test func numbersStepsFromOne() {
        #expect(OnboardingStep.screenRecording.number == 1)
        #expect(OnboardingStep.ready.number == OnboardingStep.allCases.count)
    }

    @Test func screenRecordingWaitsForAWorkingCapture() {
        #expect(ScreenRecordingStatus(granted: false, captureWorked: nil) == .notAllowed)
        #expect(ScreenRecordingStatus(granted: true, captureWorked: nil) == .checking)
        #expect(ScreenRecordingStatus(granted: true, captureWorked: true) == .allowed)
        #expect(ScreenRecordingStatus(granted: true, captureWorked: false) == .needsReopen)
    }
}
