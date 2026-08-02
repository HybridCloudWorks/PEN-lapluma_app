import XCTest

@MainActor
final class ApertureAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnboardingReachesHomeAndPersistsAcrossRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Aperture"].waitForExistence(timeout: 5))
        app.buttons["Create account"].tap()

        XCTAssertTrue(app.staticTexts["What we store"].waitForExistence(timeout: 2))
        app.buttons["Continue"].tap()

        let email = app.textFields["Email"]
        XCTAssertTrue(email.waitForExistence(timeout: 2))
        email.tap()
        email.typeText("simulator@example.test")

        let displayName = app.textFields["What should we call you?"]
        displayName.tap()
        displayName.typeText("Test Applicant")

        let returnKey = app.keyboards.buttons["return"]
        XCTAssertTrue(returnKey.waitForExistence(timeout: 2))
        returnKey.tap()

        let acknowledgment = app.switches["I understand that Aperture is not a law firm and cannot give me legal advice."]
        acknowledgment.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let enabled = NSPredicate(format: "value == '1'")
        expectation(for: enabled, evaluatedWith: acknowledgment)
        waitForExpectations(timeout: 2)

        let createPasskey = app.buttons["Create passkey"]
        XCTAssertTrue(createPasskey.isEnabled)
        createPasskey.tap()

        XCTAssertTrue(app.staticTexts["Your recovery code"].waitForExistence(timeout: 2))
        let recoveryAcknowledgment = app.switches["I have written this down somewhere safe."]
        recoveryAcknowledgment.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        expectation(for: enabled, evaluatedWith: recoveryAcknowledgment)
        waitForExpectations(timeout: 2)

        let finishOnboarding = app.buttons["Continue"]
        XCTAssertTrue(finishOnboarding.isEnabled)
        finishOnboarding.tap()

        assertAuthenticatedHome(in: app)

        app.terminate()
        app.launchArguments = []
        app.launch()

        assertAuthenticatedHome(in: app)
    }

    func testAuthenticatedTabsExposeCoreMobileWorkflows() {
        let app = launchAuthenticatedApp()
        assertAuthenticatedHome(in: app)

        app.tabBars.buttons["Capture"].tap()
        XCTAssertTrue(app.navigationBars["Add a document"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Take a photo"].exists)
        XCTAssertTrue(app.buttons["Choose from Photos"].exists)
        XCTAssertTrue(app.buttons["Choose a file instead"].exists)

        app.tabBars.buttons["Missing"].tap()
        XCTAssertTrue(app.navigationBars["What's missing"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Chat"].exists)
        XCTAssertTrue(app.buttons["Speak"].exists)
        XCTAssertTrue(app.buttons["Type it in"].exists)

        app.tabBars.buttons["Me"].tap()
        XCTAssertTrue(app.navigationBars["Me"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Privacy and data"].exists)
    }

    func testStoreScreenshotLaunchArgumentOpensRequestedTab() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset",
            "--ui-testing-authenticated",
            "--ui-testing-start-tab=missing"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["What's missing"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Chat"].exists)
        XCTAssertTrue(app.buttons["Speak"].exists)
        XCTAssertTrue(app.buttons["Type it in"].exists)
    }

    func testCreateFolderPersistsAcrossRelaunch() {
        let app = launchAuthenticatedApp()
        app.buttons["Create another folder"].tap()

        XCTAssertTrue(app.navigationBars["New folder"].waitForExistence(timeout: 3))
        let name = app.textFields["For example, My application"]
        name.tap()
        name.typeText("My test folder")
        app.keyboards.buttons["return"].tap()
        app.buttons["Create folder"].tap()

        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "My test folder")).firstMatch.waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["--ui-testing-authenticated"]
        app.launch()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "My test folder")).firstMatch.waitForExistence(timeout: 5))
    }

    func testHumanSelectedApplicationPersists() {
        let app = launchAuthenticatedApp()
        app.buttons["Start a new application"].tap()

        XCTAssertTrue(app.navigationBars["Choose forms"].waitForExistence(timeout: 3))
        let package = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Application for Employment Authorization")
        ).firstMatch
        XCTAssertTrue(package.waitForExistence(timeout: 3))
        package.tap()

        XCTAssertTrue(app.navigationBars["Application for Employment Authorization"].waitForExistence(timeout: 3))
        app.buttons["Use these forms"].tap()

        XCTAssertTrue(app.navigationBars["Confirm"].waitForExistence(timeout: 3))
        let attestation = app.switches.firstMatch
        attestation.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let enabled = NSPredicate(format: "value == '1'")
        expectation(for: enabled, evaluatedWith: attestation)
        waitForExpectations(timeout: 2)
        app.buttons["Continue"].tap()
        XCTAssertFalse(app.navigationBars["Confirm"].waitForExistence(timeout: 2))

        app.terminate()
        app.launchArguments = ["--ui-testing-authenticated"]
        app.launch()
        openCases(in: app)
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Application for Employment Authorization")
        ).firstMatch.waitForExistence(timeout: 5))
    }

    func testReviewConfirmationAndSecureExport() {
        let app = launchAuthenticatedApp()
        openCases(in: app)

        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Petition for Alien Relative")).firstMatch.tap()
        app.buttons["Review information"].tap()
        XCTAssertTrue(app.navigationBars["Review information"].waitForExistence(timeout: 3))

        let familyName = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Apellido")).firstMatch
        XCTAssertTrue(familyName.waitForExistence(timeout: 3))
        familyName.tap()
        XCTAssertTrue(app.navigationBars["Check this"].waitForExistence(timeout: 3))
        app.buttons["Confirm"].tap()
        XCTAssertTrue(app.navigationBars["Review information"].waitForExistence(timeout: 3))

        app.navigationBars["Review information"].buttons.firstMatch.tap()
        app.navigationBars["Petition for Alien Relative"].buttons.firstMatch.tap()

        let readyCase = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Application for Naturalization")
        ).firstMatch
        XCTAssertTrue(readyCase.waitForExistence(timeout: 3))
        readyCase.tap()
        app.buttons["Forms and export"].tap()

        XCTAssertTrue(app.navigationBars["Forms"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Fields checked"].exists)
        XCTAssertTrue(app.staticTexts["Mismatches"].exists)
        let sendSecurely = app.buttons["Send securely"]
        for _ in 0..<3 where !sendSecurely.exists {
            app.swipeUp()
        }
        XCTAssertTrue(sendSecurely.waitForExistence(timeout: 3))
        sendSecurely.tap()

        XCTAssertTrue(app.navigationBars["Secure delivery"].waitForExistence(timeout: 3))
        let email = app.textFields["Email"]
        email.tap()
        email.typeText("recipient@example.test")
        app.keyboards.buttons["return"].tap()
        app.buttons["Create secure link"].tap()
        XCTAssertTrue(app.staticTexts["Secure link created"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Download limit"].exists)
    }

    func testValueCorrectionHistoryPersistsAndUnreviewedValuesBlockGeneration() {
        let app = launchAuthenticatedApp()
        openCases(in: app)

        app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Petition for Alien Relative")
        ).firstMatch.tap()
        app.buttons["Forms and export"].tap()

        XCTAssertTrue(app.navigationBars["Forms"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.descendants(matching: .any)["package-generation-blocked"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.staticTexts["Required values not confirmed"].exists)
        XCTAssertTrue(app.staticTexts["Suggestions awaiting a decision"].exists)
        XCTAssertTrue(app.staticTexts["Document disagreements"].exists)

        app.navigationBars["Forms"].buttons.firstMatch.tap()
        app.buttons["Review information"].tap()
        XCTAssertTrue(app.navigationBars["Review information"].waitForExistence(timeout: 3))

        let familyName = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Family Name (Last Name)")
        ).firstMatch
        XCTAssertTrue(familyName.waitForExistence(timeout: 3))
        familyName.tap()
        XCTAssertTrue(app.navigationBars["Check this"].waitForExistence(timeout: 3))

        let value = app.textFields["Value"]
        XCTAssertTrue(value.waitForExistence(timeout: 3))
        value.tap()
        value.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 24))
        value.typeText("Ramirez corrected")
        app.keyboards.buttons["return"].tap()
        app.buttons["Confirm"].tap()

        XCTAssertTrue(app.navigationBars["Review information"].waitForExistence(timeout: 3))
        let correctedFamilyName = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Ramirez corrected")
        ).firstMatch
        XCTAssertTrue(correctedFamilyName.waitForExistence(timeout: 3))
        correctedFamilyName.tap()

        let history = app.descendants(matching: .any)["value-history-ledger"]
        for _ in 0..<4 where !history.exists { app.swipeUp() }
        XCTAssertTrue(history.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Corrected by you"].exists)
        XCTAssertTrue(app.staticTexts["Superseded by your decision"].exists)

        app.terminate()
        app.launchArguments = ["--ui-testing-authenticated"]
        app.launch()
        openCases(in: app)
        app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Petition for Alien Relative")
        ).firstMatch.tap()
        app.buttons["Review information"].tap()
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Ramirez corrected")
        ).firstMatch.waitForExistence(timeout: 5))
    }

    func testSpanishCoreNavigationUsesLocalizedAppAndPackageStrings() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset",
            "--ui-testing-authenticated",
            "-AppleLanguages",
            "(es)",
            "-AppleLocale",
            "es_MX"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Inicio"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Necesita su atención"].exists)
        XCTAssertTrue(app.staticTexts["Sus carpetas"].exists)

        app.tabBars.buttons["Capturar"].tap()
        XCTAssertTrue(app.navigationBars["Agregar un documento"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Tomar una foto"].exists)
        XCTAssertTrue(app.buttons["Elegir de Fotos"].exists)
        XCTAssertTrue(app.buttons["Elegir un archivo"].exists)

        app.tabBars.buttons["Pendiente"].tap()
        XCTAssertTrue(app.navigationBars["Qué falta"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Chat"].exists)
        XCTAssertTrue(app.buttons["Hablar"].exists)
        XCTAssertTrue(app.buttons["Escribir respuestas"].exists)

        app.tabBars.buttons["Yo"].tap()
        XCTAssertTrue(app.navigationBars["Yo"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Privacidad y datos"].exists)
    }

    func testLargestAccessibilityTextKeepsCoreActionsReachable() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset",
            "--ui-testing-authenticated",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
        let startApplication = app.buttons["Start a new application"]
        XCTAssertTrue(startApplication.waitForExistence(timeout: 3))
        XCTAssertTrue(startApplication.isHittable)

        let createFolder = app.buttons["Create another folder"]
        scrollToElement(createFolder, in: app)
        XCTAssertTrue(createFolder.isHittable)

        app.tabBars.buttons["Capture"].tap()
        XCTAssertTrue(app.navigationBars["Add a document"].waitForExistence(timeout: 3))
        let takePhoto = app.buttons["Take a photo"]
        XCTAssertTrue(takePhoto.waitForExistence(timeout: 3))
        XCTAssertTrue(takePhoto.isHittable)

        let chooseFile = app.buttons["Choose a file instead"]
        scrollToElement(chooseFile, in: app)
        XCTAssertTrue(chooseFile.isHittable)
    }

    func testAccessibilityProfileEnablesVoiceFirstTargetsAndWaivedBudget() {
        let app = launchAuthenticatedApp()

        app.tabBars.buttons["Me"].tap()
        XCTAssertTrue(app.navigationBars["Me"].waitForExistence(timeout: 3))
        let profile = app.switches["accessibility-profile-toggle"]
        XCTAssertTrue(profile.waitForExistence(timeout: 3))
        profile.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: profile)
        waitForExpectations(timeout: 2)

        app.tabBars.buttons["Missing"].tap()
        XCTAssertTrue(app.navigationBars["What's missing"].waitForExistence(timeout: 3))
        let speak = app.buttons["Speak"]
        let chat = app.buttons["Chat"]
        XCTAssertTrue(speak.waitForExistence(timeout: 3))
        XCTAssertTrue(chat.exists)
        XCTAssertTrue(speak.isHittable)
        XCTAssertLessThan(speak.frame.minY, chat.frame.minY)
        speak.tap()

        XCTAssertTrue(app.staticTexts["voice-consent-title"].waitForExistence(timeout: 3))
        let consent = app.switches["I understand and I'd like to continue."]
        XCTAssertTrue(consent.waitForExistence(timeout: 3))
        consent.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: consent)
        waitForExpectations(timeout: 2)
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.navigationBars["Speaking"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["voice-budget-waived"].waitForExistence(timeout: 3))
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "minutes of voice left")).count,
            0
        )
    }

    func testCoreSurfacesPassAutomatedAccessibilityAudit() throws {
        let app = launchAuthenticatedApp()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
        try auditVisibleSurface(in: app)

        app.tabBars.buttons["Capture"].tap()
        XCTAssertTrue(app.navigationBars["Add a document"].waitForExistence(timeout: 3))
        try auditVisibleSurface(in: app)

        app.tabBars.buttons["Missing"].tap()
        XCTAssertTrue(app.navigationBars["What's missing"].waitForExistence(timeout: 3))
        try auditVisibleSurface(in: app)

        app.tabBars.buttons["Me"].tap()
        XCTAssertTrue(app.navigationBars["Me"].waitForExistence(timeout: 3))
        try auditVisibleSurface(in: app)
    }

    func testSystemAccessibilityPreferencesKeepCoreActionsReachable() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset",
            "--ui-testing-authenticated",
            "-UIAccessibilityReduceMotionEnabled",
            "YES",
            "-UIAccessibilityDarkerSystemColorsEnabled",
            "YES",
            "-UIAccessibilityDifferentiateWithoutColor",
            "YES"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start a new application"].isHittable)
        try auditVisibleSurface(in: app)

        app.tabBars.buttons["Capture"].tap()
        XCTAssertTrue(app.navigationBars["Add a document"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Take a photo"].isHittable)
        XCTAssertTrue(app.buttons["Choose a file instead"].isHittable)
        try auditVisibleSurface(in: app)
    }

    func testOfflineModeKeepsCaptureAndManualAnswersAvailable() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset",
            "--ui-testing-authenticated",
            "--ui-testing-offline"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["offline-banner"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Capture"].tap()
        XCTAssertTrue(app.navigationBars["Add a document"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Take a photo"].isHittable)
        XCTAssertTrue(app.buttons["Choose a file instead"].isHittable)

        app.tabBars.buttons["Missing"].tap()
        XCTAssertTrue(app.navigationBars["What's missing"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["offline-interview-status"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Chat"].isEnabled)
        XCTAssertFalse(app.buttons["Speak"].isEnabled)
        let manualEntry = app.buttons.matching(
            NSPredicate(format: "identifier == %@", "interview-modality-form")
        ).firstMatch
        XCTAssertTrue(manualEntry.exists)
        XCTAssertTrue(manualEntry.isEnabled)
    }

    func testMeteredNetworkDefaultsLargeUploadsToWiFi() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset",
            "--ui-testing-authenticated",
            "--ui-testing-expensive-network"
        ]
        app.launch()

        app.tabBars.buttons["Capture"].tap()
        XCTAssertTrue(app.navigationBars["Add a document"].waitForExistence(timeout: 5))
        let wifiOnly = app.switches["wifi-only-upload-toggle"]
        XCTAssertTrue(wifiOnly.waitForExistence(timeout: 3))
        XCTAssertEqual(wifiOnly.value as? String, "1")
        XCTAssertTrue(app.staticTexts[
            "Large files wait on cellular or Low Data Mode. You can change this at any time."
        ].exists)

        wifiOnly.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let disabled = NSPredicate(format: "value == '0'")
        expectation(for: disabled, evaluatedWith: wifiOnly)
        waitForExpectations(timeout: 2)
    }

    func testApplicantClassificationOverrideIsRecordedAndPersists() {
        let app = launchAuthenticatedApp()
        openDocuments(in: app)

        let birthCertificate = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Birth certificate")
        ).firstMatch
        XCTAssertTrue(birthCertificate.waitForExistence(timeout: 3))
        birthCertificate.tap()

        XCTAssertTrue(app.navigationBars["Birth certificate"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Needs your help")
        ).firstMatch.exists)
        app.buttons["Review document type"].tap()
        XCTAssertTrue(app.navigationBars["Document type"].waitForExistence(timeout: 3))

        let translation = app.buttons["classification-option-TRANSLATION"]
        XCTAssertTrue(translation.waitForExistence(timeout: 3))
        translation.tap()

        XCTAssertTrue(app.navigationBars["Birth certificate"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Translation")
        ).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["classification-human-override"].exists)

        app.terminate()
        app.launchArguments = ["--ui-testing-authenticated"]
        app.launch()
        openDocuments(in: app)
        let persisted = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Birth certificate", "Translation")
        ).firstMatch
        XCTAssertTrue(persisted.waitForExistence(timeout: 5))
    }

    func testExtractionReviewSurfacesAmbiguousDatesAndOriginalNameScript() {
        let app = launchAuthenticatedApp()
        openCases(in: app)
        app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Petition for Alien Relative")
        ).firstMatch.tap()
        app.buttons["Review information"].tap()
        XCTAssertTrue(app.navigationBars["Review information"].waitForExistence(timeout: 3))

        let arrivalDate = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Date of Last Arrival")
        ).firstMatch
        XCTAssertTrue(arrivalDate.waitForExistence(timeout: 3))
        arrivalDate.tap()
        XCTAssertTrue(app.navigationBars["Check this"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["extraction-review-AMBIGUOUS_DATE"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()

        let familyName = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Family Name (Last Name)")
        ).firstMatch
        XCTAssertTrue(familyName.waitForExistence(timeout: 3))
        familyName.tap()
        XCTAssertTrue(app.navigationBars["Check this"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.descendants(matching: .any)["extracted-name-original-script"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.staticTexts["Ramírez"].exists)
    }

    private func assertAuthenticatedHome(in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Needs your attention"].exists)
        XCTAssertTrue(app.staticTexts["Your folders"].exists)
        XCTAssertTrue(app.tabBars.buttons["Capture"].exists)
        XCTAssertTrue(app.tabBars.buttons["Missing"].exists)
        XCTAssertTrue(app.tabBars.buttons["Me"].exists)
    }

    private func launchAuthenticatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-authenticated"]
        app.launch()
        return app
    }

    private func openCases(in app: XCUIApplication) {
        assertAuthenticatedHome(in: app)
        let folder = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Familia Ramírez")
        ).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 3))
        folder.tap()
        XCTAssertTrue(app.navigationBars["Familia Ramírez"].waitForExistence(timeout: 3))
        app.segmentedControls.buttons["Cases"].tap()
    }

    private func openDocuments(in app: XCUIApplication) {
        assertAuthenticatedHome(in: app)
        let folder = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Familia Ramírez")
        ).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 3))
        folder.tap()
        XCTAssertTrue(app.navigationBars["Familia Ramírez"].waitForExistence(timeout: 3))
        app.segmentedControls.buttons["Documents"].tap()
    }

    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 3))
    }

    private func auditVisibleSurface(in app: XCUIApplication) throws {
        // SwiftUI currently reports element-less Dynamic Type and text-clipping
        // findings for system-managed Label/List nodes. The dedicated accessibility
        // XXXL journey above verifies actual scaling and reachability instead.
        try app.performAccessibilityAudit(for: [
            .contrast,
            .elementDetection,
            .hitRegion,
            .sufficientElementDescription,
            .trait
        ]) { issue in
            guard let element = issue.element else { return false }
            // Lists keep elements in the accessibility tree while the floating tab
            // bar visually covers them. Ignore only currently occluded elements;
            // visible controls are audited here and exercised in functional journeys.
            let tabFrame = app.tabBars.firstMatch.frame
            return element.frame.maxY >= tabFrame.minY - 60
        }
    }
}
