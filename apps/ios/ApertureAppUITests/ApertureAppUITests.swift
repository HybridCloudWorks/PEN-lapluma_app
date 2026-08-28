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

        XCTAssertTrue(app.staticTexts["LaPluma"].waitForExistence(timeout: 5))
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

        let acknowledgment = app.switches["I understand that LaPluma is not a law firm and cannot give me legal advice."]
        flipSwitch(
            in: app,
            identifier: "registration-acknowledgment-toggle",
            fallbackRowLabel: "I understand that LaPluma is not a law firm and cannot give me legal advice."
        )
        let enabled = NSPredicate(format: "value == '1'")
        expectation(for: enabled, evaluatedWith: acknowledgment)
        waitForExpectations(timeout: 2)

        let createPasskey = app.buttons["Create passkey"]
        XCTAssertTrue(createPasskey.isEnabled)
        createPasskey.tap()

        XCTAssertTrue(app.staticTexts["Your recovery code"].waitForExistence(timeout: 2))
        let recoveryAcknowledgment = app.switches["I have written this down somewhere safe."]
        flipSwitch(
            in: app,
            identifier: "recovery-code-acknowledgment-toggle",
            fallbackRowLabel: "I have written this down somewhere safe."
        )
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

    func testSignInRequiresEmailAndWorkspaceBeforePasskey() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset"]
        app.launch()

        let signIn = app.buttons["Sign in"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        signIn.tap()
        XCTAssertTrue(app.navigationBars["Secure sign in"].waitForExistence(timeout: 3))

        let continueWithPasskey = app.buttons["Continue with passkey"]
        XCTAssertFalse(continueWithPasskey.isEnabled)

        let email = app.textFields["Work email"]
        XCTAssertTrue(email.waitForExistence(timeout: 3))
        email.tap()
        email.typeText("caseworker@example.test")

        let workspace = app.textFields["Workspace or location code"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 3))
        workspace.tap()
        workspace.typeText("nyc-01")
        app.keyboards.buttons["done"].tap()

        XCTAssertTrue(continueWithPasskey.isEnabled)
        continueWithPasskey.tap()
        XCTAssertTrue(app.navigationBars["Clients"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["NYC-01"].exists)
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

    func testMissingDocumentResolutionUsesTheExistingNavigationStack() {
        let app = launchAuthenticatedApp()

        app.tabBars.buttons["Missing"].tap()
        XCTAssertTrue(app.navigationBars["What's missing"].waitForExistence(timeout: 3))

        let resolution = app.buttons["Take a photo of your green card"]
        for _ in 0..<3 where !resolution.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(resolution.waitForExistence(timeout: 3))
        resolution.tap()

        XCTAssertTrue(app.navigationBars["Add a document"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Take a photo"].isHittable)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["What's missing"].waitForExistence(timeout: 3))
    }

    func testGuidedFinishDefaultsToTenMinutesAndPersistsWaitingRelay() {
        let app = launchAuthenticatedApp()
        app.tabBars.buttons["Missing"].tap()
        XCTAssertTrue(app.navigationBars["What's missing"].waitForExistence(timeout: 3))

        app.descendants(matching: .any)["missing-guided-finish"].tap()
        XCTAssertTrue(app.navigationBars["Guided Finish"].waitForExistence(timeout: 3))
        let budget = app.segmentedControls["guided-finish-budget"].firstMatch
        XCTAssertTrue(budget.waitForExistence(timeout: 3))
        XCTAssertTrue(budget.buttons["10 minutes"].isSelected)
        budget.buttons["5 minutes"].tap()
        budget.buttons["10 minutes"].tap()
        app.descendants(matching: .any)["guided-finish-start"].tap()

        let relayAction = app.descendants(matching: .any)["guided-action-private_relay"].firstMatch
        scrollToElement(relayAction, in: app)
        relayAction.tap()
        XCTAssertTrue(app.navigationBars["Private Relay"].waitForExistence(timeout: 3))
        app.descendants(matching: .any)["private-relay-create"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["private-relay-access-code"].waitForExistence(timeout: 5))

        app.navigationBars["Private Relay"].buttons.firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["guided-relay-status"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["--ui-testing-authenticated", "--ui-testing-start-tab=missing"]
        app.launch()
        XCTAssertTrue(app.navigationBars["What's missing"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["missing-guided-finish"].tap()
        app.descendants(matching: .any)["guided-finish-start"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["guided-relay-status"].waitForExistence(timeout: 5))
    }

    func testProofMapShowsSyntheticSourceAndMultipleFormDestinations() {
        let app = launchAuthenticatedApp()
        openCases(in: app)
        app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Petition for Alien Relative")
        ).firstMatch.tap()
        XCTAssertTrue(app.buttons["Proof Map"].waitForExistence(timeout: 5))
        app.buttons["Proof Map"].tap()
        XCTAssertTrue(app.navigationBars["Proof Map"].waitForExistence(timeout: 3))

        let familyName = app.descendants(matching: .any)["proof-map-field-person.name.family"]
        scrollToElement(familyName, in: app)
        familyName.tap()
        XCTAssertTrue(app.navigationBars["Answer proof"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["proof-source-preview"].waitForExistence(timeout: 5))
        let secondDestination = app.descendants(matching: .any)["proof-destination-i-130a"].firstMatch
        scrollToElement(secondDestination, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["proof-destination-i-130"].firstMatch.exists)
    }

    func testPrivateRelayRequiresCodeAndHumanAcceptanceBeforeResolution() {
        let app = launchAuthenticatedApp()
        app.tabBars.buttons["Missing"].tap()
        XCTAssertTrue(app.navigationBars["What's missing"].waitForExistence(timeout: 3))
        let relayResolution = app.buttons["Ask someone to send it"].firstMatch
        scrollToElement(relayResolution, in: app)
        relayResolution.tap()
        app.descendants(matching: .any)["private-relay-create"].tap()

        let shownCode = app.descendants(matching: .any)["private-relay-access-code"]
        XCTAssertTrue(shownCode.waitForExistence(timeout: 5))
        let wrongCode = shownCode.label == "000000" ? "999999" : "000000"
        app.descendants(matching: .any)["private-relay-preview-recipient"].tap()
        XCTAssertTrue(app.navigationBars["Private upload"].waitForExistence(timeout: 3))

        let codeField = app.textFields["relay-harness-code"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 3))
        codeField.tap()
        codeField.typeText(wrongCode)
        app.buttons["relay-harness-unlock"].tap()
        XCTAssertTrue(app.staticTexts["That code did not match"].waitForExistence(timeout: 3))
        app.buttons["relay-harness-use-code"].tap()
        app.buttons["relay-harness-unlock"].tap()
        let submit = app.buttons["relay-harness-submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        submit.tap()
        XCTAssertTrue(
            app.staticTexts["Upload received. The requester must review it before it is used."]
                .waitForExistence(timeout: 5)
        )

        app.terminate()
        app.launchArguments = ["--ui-testing-authenticated", "--ui-testing-start-tab=missing"]
        app.launch()
        XCTAssertTrue(app.navigationBars["What's missing"].waitForExistence(timeout: 5))
        let existingResolution = app.buttons["Ask someone to send it"].firstMatch
        scrollToElement(existingResolution, in: app)
        existingResolution.tap()
        let received = app.buttons["private-relay-status-received"].firstMatch
        XCTAssertTrue(received.waitForExistence(timeout: 5))
        received.tap()
        app.buttons["requested-document.pdf"].tap()
        app.buttons["Review document type"].tap()
        app.buttons["classification-option-CIVIL"].tap()
        XCTAssertTrue(app.navigationBars["requested-document.pdf"].waitForExistence(timeout: 5))
        app.navigationBars["requested-document.pdf"].buttons.firstMatch.tap()
        let accept = app.buttons["private-relay-accept"]
        XCTAssertTrue(accept.waitForExistence(timeout: 5))
        XCTAssertTrue(accept.isEnabled)
        accept.tap()
        XCTAssertTrue(accept.waitForNonExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["--ui-testing-authenticated", "--ui-testing-start-tab=missing"]
        app.launch()
        XCTAssertTrue(app.navigationBars["What's missing"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["missing-guided-finish"].waitForExistence(timeout: 5))
        let resolvedItem = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "Proof of your U.S. citizenship")
        ).firstMatch
        XCTAssertFalse(resolvedItem.exists)
    }

    func testWorkforceFinishTogetherCapabilitiesRespectPreparerAndReviewerRoles() {
        let preparer = XCUIApplication()
        preparer.launchArguments = [
            "--ui-testing-reset", "--ui-testing-authenticated", "--ui-testing-role=preparer"
        ]
        preparer.launch()
        openCases(in: preparer)
        preparer.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Petition for Alien Relative")
        ).firstMatch.tap()
        XCTAssertTrue(preparer.buttons["Guided Finish"].waitForExistence(timeout: 5))
        XCTAssertTrue(preparer.buttons["Proof Map"].exists)
        preparer.terminate()

        let reviewer = XCUIApplication()
        reviewer.launchArguments = [
            "--ui-testing-reset", "--ui-testing-authenticated", "--ui-testing-role=reviewer"
        ]
        reviewer.launch()
        openCases(in: reviewer)
        reviewer.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Petition for Alien Relative")
        ).firstMatch.tap()
        XCTAssertTrue(reviewer.buttons["Proof Map"].waitForExistence(timeout: 5))
        XCTAssertFalse(reviewer.buttons["Guided Finish"].exists)
        reviewer.buttons["Overview"].tap()
        XCTAssertTrue(reviewer.buttons["Proof Map"].waitForExistence(timeout: 3))
        XCTAssertFalse(reviewer.buttons["What's missing"].exists)
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

    // One test per route: a failure in an early route used to hide the results of
    // every later one, and each route is an independent launch anyway.
    func testMarketingWelcomeRouteUsesSafeFixture() {
        let app = launchMarketingRoute("welcome")
        XCTAssertTrue(app.staticTexts["LaPluma"].waitForExistence(timeout: 5))
        assertNoInternalPersonas(in: app)
    }

    func testMarketingHomeRouteUsesSafeFixture() {
        let app = launchMarketingRoute("home")
        XCTAssertTrue(app.navigationBars["Clients"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sample paperwork"].waitForExistence(timeout: 3))
        assertNoInternalPersonas(in: app)
    }

    func testMarketingCaptureRouteUsesSafeFixture() {
        let app = launchMarketingRoute("capture")
        XCTAssertTrue(app.navigationBars["Add a document"].waitForExistence(timeout: 5))
        assertNoInternalPersonas(in: app)
    }

    func testMarketingMissingRouteUsesSafeFixture() {
        let app = launchMarketingRoute("missing")
        XCTAssertTrue(app.navigationBars["What's missing"].waitForExistence(timeout: 5))
        assertNoInternalPersonas(in: app)
        app.descendants(matching: .any)["missing-guided-finish"].tap()
        XCTAssertTrue(app.navigationBars["Guided Finish"].waitForExistence(timeout: 3))
        assertNoInternalPersonas(in: app)
    }

    func testMarketingReviewRouteUsesSafeFixture() {
        let app = launchMarketingRoute("review")
        XCTAssertTrue(app.navigationBars["Review information"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sample family member"].waitForExistence(timeout: 3))
        assertNoInternalPersonas(in: app)
    }

    func testMarketingPackageRouteUsesSafeFixture() {
        let app = launchMarketingRoute("package")
        XCTAssertTrue(app.navigationBars["Forms"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Fields checked"].waitForExistence(timeout: 3))
        assertNoInternalPersonas(in: app)
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
        let category = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Federal forms")
        ).firstMatch
        XCTAssertTrue(category.waitForExistence(timeout: 3))
        category.tap()

        XCTAssertTrue(app.navigationBars["Federal forms"].waitForExistence(timeout: 3))
        let package = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Adjustment of Status with Affidavit of Support")
        ).firstMatch
        XCTAssertTrue(package.waitForExistence(timeout: 3))
        package.tap()

        XCTAssertTrue(app.navigationBars["Adjustment of Status with Affidavit of Support"].waitForExistence(timeout: 3))
        app.buttons["Use these forms"].tap()

        let attestation = app.switches.matching(
            NSPredicate(format: "label CONTAINS %@", "I understand")
        ).firstMatch
        XCTAssertTrue(attestation.waitForExistence(timeout: 5))
        flipSwitch(
            in: app,
            identifier: "attestation-toggle",
            fallbackRowLabel: "I understand. I chose these forms myself, or my legal representative chose them for me."
        )
        let enabled = NSPredicate(format: "value == '1'")
        expectation(for: enabled, evaluatedWith: attestation)
        waitForExpectations(timeout: 2)
        app.buttons["Continue"].tap()
        XCTAssertTrue(attestation.waitForNonExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["--ui-testing-authenticated"]
        app.launch()
        openCases(in: app)
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Adjustment of Status with Affidavit of Support")
        ).firstMatch.waitForExistence(timeout: 5))
    }

    func testMultiPageScanEncoderPreservesPageCountOrderAndDimensions() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-multipage-scan"]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["scan-pdf-pages-3-widths-100-200-300"]
                .waitForExistence(timeout: 5)
        )
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

        let saveToFiles = app.descendants(matching: .any)["package-export-files"]
        scrollToElement(saveToFiles, in: app)
        saveToFiles.tap()
        // The document picker titles itself with the selected location (for example
        // "On My iPhone"), not the initiating action. Its Save control is the stable
        // proof that the app handed a file to the Files export flow.
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))

        // The system document picker is hosted out of process and its Cancel
        // control is not reliably hittable in the simulator. Relaunching closes
        // it deterministically before exercising the independent print channel.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Clients"].waitForExistence(timeout: 5))
        openCases(in: app)
        XCTAssertTrue(readyCase.waitForExistence(timeout: 3))
        readyCase.tap()
        app.buttons["Forms and export"].tap()
        XCTAssertTrue(app.navigationBars["Forms"].waitForExistence(timeout: 3))

        let printPackage = app.descendants(matching: .any)["package-export-print"]
        scrollToElement(printPackage, in: app)
        printPackage.tap()
        XCTAssertTrue(app.navigationBars["Options"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Printer"].exists)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.navigationBars["Forms"].waitForExistence(timeout: 3))

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

    func testFullyReviewedCaseGeneratesPackage() {
        let app = launchAuthenticatedApp()
        openCases(in: app)
        app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Petition for Alien Relative")
        ).firstMatch.tap()
        app.buttons["Review information"].tap()
        XCTAssertTrue(app.navigationBars["Review information"].waitForExistence(timeout: 3))

        confirmReviewField("Date of Birth", in: app, chooseCurrentDiscrepancy: true)
        confirmReviewField("Family Name (Last Name)", in: app)
        confirmReviewField("Date of Last Arrival", in: app)
        confirmReviewField("Passport Number", in: app)
        confirmReviewField("City/Town/Village of Birth", value: "Guatemala City", in: app)

        app.navigationBars["Review information"].buttons.firstMatch.tap()
        app.buttons["Forms and export"].tap()
        XCTAssertTrue(app.navigationBars["Forms"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.descendants(matching: .any)["package-generation-ready"]
                .waitForExistence(timeout: 3)
        )
        app.descendants(matching: .any)["package-generate"].tap()
        XCTAssertTrue(app.staticTexts["Fields checked"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Mismatches"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["package-generation-blocked"].exists)
    }

    /// T-54. The fail-closed generation gate (SME B-02 / AP-7) is enforced by a
    /// **client-side** control: `resolvesDiscrepancyID` is sent only when the applicant
    /// picks a side in `DiscrepancyPanel`. As T-37 established, the server cannot tell a
    /// deliberate adjudication from a reflexive one — both arrive as the current value
    /// plus a matching identifier — so no package test can cover this. A change to the
    /// sheet could reintroduce the original defect with every package test still green.
    /// This journey is the only thing that would catch it.
    func testConfirmingWithoutAdjudicatingLeavesTheDisagreementStanding() {
        let app = launchAuthenticatedApp()
        openCases(in: app)

        app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Petition for Alien Relative")
        ).firstMatch.tap()
        app.buttons["Review information"].tap()
        XCTAssertTrue(app.navigationBars["Review information"].waitForExistence(timeout: 3))

        // The seeded date-of-birth row is the one carrying a blocking disagreement.
        let dateOfBirth = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Date of Birth")
        ).firstMatch
        XCTAssertTrue(dateOfBirth.waitForExistence(timeout: 3))
        dateOfBirth.tap()
        XCTAssertTrue(app.navigationBars["Check this"].waitForExistence(timeout: 3))

        // Both choices are on screen and neither is touched. That is the whole point:
        // the applicant confirms without adjudicating.
        let currentChoice = app.descendants(matching: .any)["discrepancy-choice-current"]
        XCTAssertTrue(
            currentChoice.waitForExistence(timeout: 3),
            "Expected the seeded blocking disagreement on the date-of-birth field"
        )
        XCTAssertTrue(app.descendants(matching: .any)["discrepancy-choice-alternative"].exists)

        app.buttons["Confirm"].tap()
        XCTAssertTrue(app.navigationBars["Review information"].waitForExistence(timeout: 5))

        // Re-open the same field. If a plain Confirm had resolved the disagreement, the
        // panel would be gone. This is the assertion that actually detects the T-37
        // regression — the Forms screen alone cannot, because other blockers keep the
        // gate shut regardless and would mask a cleared discrepancy.
        let reopened = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Date of Birth")
        ).firstMatch
        XCTAssertTrue(reopened.waitForExistence(timeout: 3))
        reopened.tap()
        XCTAssertTrue(app.navigationBars["Check this"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.descendants(matching: .any)["discrepancy-choice-current"]
                .waitForExistence(timeout: 3),
            "Confirming without choosing a side must leave the disagreement standing"
        )
        // Dismiss by label rather than by position: the sheet's toolbar carries both
        // Cancel and Confirm, and `firstMatch` would depend on their ordering.
        app.buttons["Cancel"].tap()

        // And the gate the disagreement feeds is still shut.
        XCTAssertTrue(app.navigationBars["Review information"].waitForExistence(timeout: 3))
        app.navigationBars["Review information"].buttons.firstMatch.tap()
        app.buttons["Forms and export"].tap()
        XCTAssertTrue(app.navigationBars["Forms"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.descendants(matching: .any)["package-generation-blocked"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.staticTexts["Document disagreements"].exists)
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
        value.typeKey("a", modifierFlags: .command)
        value.typeText("Ramirez corrected")
        XCTAssertEqual(value.value as? String, "Ramirez corrected")
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

        XCTAssertTrue(app.navigationBars["Clientes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Clientes actuales"].exists)
        XCTAssertTrue(app.staticTexts["Acciones de clientes"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "personas", "documentos")
        ).firstMatch.exists)

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
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "preguntas breves", "minutos")
        ).firstMatch.exists)
        app.descendants(matching: .any)["missing-guided-finish"].tap()
        XCTAssertTrue(app.navigationBars["Finalización guiada"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Elija una sesión breve"].exists)
        app.navigationBars["Finalización guiada"].buttons.firstMatch.tap()

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

        XCTAssertTrue(app.navigationBars["Clients"].waitForExistence(timeout: 5))
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

        app.tabBars.buttons["Missing"].tap()
        let guidedFinish = app.descendants(matching: .any)["missing-guided-finish"]
        scrollToElement(guidedFinish, in: app)
        XCTAssertTrue(guidedFinish.isHittable)
    }

    func testAccessibilityProfileEnablesVoiceFirstTargetsAndWaivedBudget() {
        let app = launchAuthenticatedApp()

        app.tabBars.buttons["Me"].tap()
        XCTAssertTrue(app.navigationBars["Me"].waitForExistence(timeout: 3))
        let profile = app.switches["accessibility-profile-toggle"]
        XCTAssertTrue(profile.waitForExistence(timeout: 3))
        flipSwitch(in: app, identifier: "accessibility-profile-toggle", fallbackRowLabel: "Voice first")
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
        flipSwitch(
            in: app,
            identifier: "voice-consent-agree-toggle",
            fallbackRowLabel: "I understand and I'd like to continue."
        )
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
        XCTAssertTrue(app.navigationBars["Clients"].waitForExistence(timeout: 5))
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

        XCTAssertTrue(app.navigationBars["Clients"].waitForExistence(timeout: 5))
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

        let relayResolution = app.buttons["Ask someone to send it"].firstMatch
        scrollToElement(relayResolution, in: app)
        relayResolution.tap()
        let createRelay = app.buttons["private-relay-create"]
        XCTAssertTrue(createRelay.waitForExistence(timeout: 3))
        XCTAssertFalse(createRelay.isEnabled)
        XCTAssertTrue(
            app.staticTexts["A connection is required to create or manage a private request."]
                .exists
        )
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
        XCTAssertTrue(app.staticTexts["Large files wait for Wi-Fi."].exists)

        flipSwitch(in: app, identifier: "wifi-only-upload-toggle", fallbackRowLabel: "Use Wi-Fi for uploads over 10 MB")
        let disabled = NSPredicate(format: "value == '0'")
        expectation(for: disabled, evaluatedWith: wifiOnly)
        waitForExpectations(timeout: 2)
    }

    /// The product's flagship offline promise: a document captured with no
    /// connection survives a relaunch and uploads itself once the network returns.
    func testOfflineQueuedCaptureDrainsAfterRelaunchOnline() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset",
            "--ui-testing-authenticated",
            "--ui-testing-offline",
            "--ui-testing-enqueue-capture"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["offline-banner"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Capture"].tap()
        XCTAssertTrue(app.navigationBars["Add a document"].waitForExistence(timeout: 3))

        let enqueue = app.buttons["debug-enqueue-capture"]
        XCTAssertTrue(enqueue.waitForExistence(timeout: 3))
        enqueue.tap()

        // Offline, the capture is retained rather than uploaded.
        XCTAssertTrue(app.descendants(matching: .any)["capture-queued-status"].waitForExistence(timeout: 10))
        let queueSummary = app.descendants(matching: .any)["capture-queue-summary"]
        XCTAssertTrue(queueSummary.waitForExistence(timeout: 3))

        // Relaunch online without resetting: the durable queue must survive the
        // restart and drain on its own once a real network path arrives.
        app.terminate()
        app.launchArguments = ["--ui-testing-authenticated"]
        app.launch()

        app.tabBars.buttons["Capture"].tap()
        XCTAssertTrue(app.navigationBars["Add a document"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["capture-queue-summary"].waitForNonExistence(timeout: 15),
            "The queued capture should drain automatically once the app relaunches online."
        )
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
        let clients = app.navigationBars["Clients"]
        let applicantHome = app.navigationBars["Home"]
        XCTAssertTrue(
            clients.waitForExistence(timeout: 5) || applicantHome.waitForExistence(timeout: 1)
        )
        if clients.exists {
            XCTAssertTrue(app.staticTexts["Current clients"].exists)
            XCTAssertTrue(app.staticTexts["Client actions"].exists)
            // iPadOS 26 exposes the sidebar-style TabView as ordinary chrome rather
            // than an XCUI tab bar. The Clients navigation/content pair is the
            // stable readiness signal for the workforce shell.
        } else {
            XCTAssertTrue(app.staticTexts["Needs your attention"].exists)
            XCTAssertTrue(app.staticTexts["Your folders"].exists)
            XCTAssertTrue(app.tabBars.buttons["Capture"].exists)
            XCTAssertTrue(app.tabBars.buttons["Missing"].exists)
            XCTAssertTrue(app.tabBars.buttons["Me"].exists)
        }
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

    private func confirmReviewField(
        _ label: String,
        value: String? = nil,
        in app: XCUIApplication,
        chooseCurrentDiscrepancy: Bool = false
    ) {
        let field = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", label)
        ).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3), "Missing review field: \(label)")
        field.tap()
        XCTAssertTrue(app.navigationBars["Check this"].waitForExistence(timeout: 3))

        if chooseCurrentDiscrepancy {
            let choice = app.descendants(matching: .any)["discrepancy-choice-current"]
            XCTAssertTrue(choice.waitForExistence(timeout: 3))
            choice.tap()
        }
        if let value {
            let textField = app.textFields["Value"]
            XCTAssertTrue(textField.waitForExistence(timeout: 3))
            textField.tap()
            textField.typeText(value)
            app.keyboards.buttons["return"].tap()
        }
        app.buttons["Confirm"].tap()
        XCTAssertTrue(app.navigationBars["Review information"].waitForExistence(timeout: 5))
    }

    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 3), .completed)
    }

    /// Prefers the toggle's stable accessibility identifier; falls back to a
    /// trailing-edge coordinate tap on the labeled row for builds without one.
    private func launchMarketingRoute(_ route: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset",
            "--ui-testing-authenticated",
            "--ui-testing-marketing-safe",
            "--ui-testing-preview-route=\(route)"
        ]
        app.launch()
        return app
    }

    /// Store art must never show the realistic internal personas.
    private func assertNoInternalPersonas(in app: XCUIApplication) {
        // Query every element type, not just `staticTexts`. Folder names — the
        // surface most likely to carry a persona — render as buttons on Home, so a
        // staticTexts-only check would pass while "Familia Ramírez" was on screen.
        for persona in ["María", "Carlos", "Ramírez"] {
            let leak = app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", persona, persona)
            ).firstMatch
            XCTAssertFalse(
                leak.exists,
                "Marketing fixture leaked the internal persona \(persona)"
            )
        }
    }

    private func flipSwitch(in app: XCUIApplication, identifier: String, fallbackRowLabel: String) {
        // A SwiftUI Toggle's element spans the whole row, so a center tap lands
        // on the label and does not flip it — the tap must target the trailing
        // switch control. The identifier lookup keeps the tests stable when the
        // row copy changes; the label lookup is the fallback for older rows.
        let identified = app.switches[identifier].firstMatch
        let target = identified.exists ? identified : app.switches[fallbackRowLabel].firstMatch
        let before = target.value as? String

        // The coordinate is computed from the element's frame, and on a loaded
        // runner the presenting sheet can still be animating when the switch first
        // exists — the synthesized tap then lands off the control and the toggle
        // never flips. `tap()` returns only once the app is idle again, so the
        // value read after it is trustworthy: re-check and retry against the
        // settled frame rather than failing the journey on the machine's mood.
        // Bounded, and it never taps a switch that has already flipped, so a slow
        // runner cannot turn this into a double flip.
        for _ in 0..<3 {
            if (target.value as? String) != before { return }
            target.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
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
            // Without a tab bar (or before it has a frame) nothing is occluded,
            // so nothing may be ignored.
            let tabBar = app.tabBars.firstMatch
            guard tabBar.exists else { return false }
            let tabFrame = tabBar.frame
            guard tabFrame != .zero else { return false }
            return element.frame.maxY >= tabFrame.minY - 60
        }
    }
}
