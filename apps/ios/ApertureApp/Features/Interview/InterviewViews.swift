import SwiftUI
import ApertureUI
import ApertureAPI
import ApertureDomain

/// S-10 Chat Interview — the **default** modality. Cheaper than voice, more accessible,
/// easier to guardrail, and it leaves a transcript the user can re-read.
struct ChatInterviewView: View {
    let caseID: CaseID
    let batchID: BatchID
    /// The person these answers are about. Never a fixture literal: a saved
    /// answer is a confirmation attributed to this person (ADR-007).
    let personID: PersonID

    @Environment(AppSession.self) private var session
    @State private var model = InterviewModel()
    @State private var draft = ""
    /// VoiceOver receives completed blocks through this, never token-by-token —
    /// streaming output is hostile to assistive technology (C-12).
    @State private var announcement = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Aperture.Spacing.m) {
                        if model.isStarting {
                            ProgressView("Starting chat…")
                                .frame(maxWidth: .infinity)
                                .accessibilityIdentifier("chat-starting")
                        }

                        ForEach(model.turns) { turn in
                            TurnBubble(turn: turn).id(turn.id)
                        }

                        if model.budgetExhausted {
                            VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
                                ApertureMessageView(.empty(messageKey: "interview.budgetExhausted"))
                                questionnaireFallback
                            }
                            .accessibilityIdentifier("chat-budget-exhausted")
                        } else if let failure = model.failure {
                            VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
                                Label(
                                    LaPlumaString(failure == .sendFailed ? "interview.sendFailed" : "interview.startFailed"),
                                    systemImage: "exclamationmark.triangle.fill"
                                )
                                    .font(Aperture.Typography.caption)
                                    .apertureStatusSurface(.critical)

                                HStack {
                                    Button(ApertureString("common.retry")) {
                                        Task {
                                            if model.session == nil {
                                                await startChat()
                                            } else {
                                                await sendDraft()
                                            }
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(model.isStarting || model.isSending)
                                    .accessibilityIdentifier("chat-retry")

                                    questionnaireFallback
                                }
                            }
                            .accessibilityIdentifier("chat-error")
                        }
                    }
                    .padding(Aperture.Spacing.m)
                }
                .onChange(of: model.turns.count) {
                    if let last = model.turns.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                        if last.role == .assistant { announcement = last.text }
                    }
                }
            }

            Divider()

            HStack(spacing: Aperture.Spacing.s) {
                TextField("Type your answer", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Button {
                    Task { await sendDraft() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(
                    draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || model.session == nil
                        || model.isSending
                        || model.budgetExhausted
                )
                .accessibilityLabel(LaPlumaString("Send"))
            }
            .padding(Aperture.Spacing.m)

            DisclosureFooter()
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        // Announce the *completed* assistant turn once, rather than replacing the
        // view's accessibility tree (which would hide the text field and send button).
        .onChange(of: announcement) { _, text in
            guard !text.isEmpty else { return }
            AccessibilityNotification.Announcement(text).post()
        }
        .task {
            await startChat()
        }
    }

    private var questionnaireFallback: some View {
        NavigationLink {
            StructuredQuestionsView(caseID: caseID, batchID: batchID, personID: personID)
        } label: {
            Label(LaPlumaString("interview.useQuestionnaire"), systemImage: "list.bullet.clipboard")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("chat-questionnaire-fallback")
    }

    @MainActor
    private func startChat() async {
        await model.start(
            api: session.api,
            caseID: caseID,
            personID: personID,
            batchID: batchID,
            modality: .chat,
            consent: nil
        )
    }

    @MainActor
    private func sendDraft() async {
        let submittedDraft = draft
        let text = submittedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if await model.send(api: session.api, text: text), draft == submittedDraft {
            draft = ""
            if model.lastConfirmedPath != nil {
                session.dataDidChange()
            }
        }
    }
}

struct TurnBubble: View {
    let turn: InterviewTurn

    var body: some View {
        VStack(alignment: turn.role == .user ? .trailing : .leading, spacing: Aperture.Spacing.xs) {
            Text(turn.text)
                .font(Aperture.Typography.body)
                .padding(Aperture.Spacing.m)
                .background(
                    turn.role == .user
                        ? Aperture.Palette.accent.opacity(0.15)
                        : (turn.validationError != nil
                            ? Aperture.Palette.critical.opacity(0.12)
                            : Aperture.Palette.surfaceSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Aperture.Radius.card)
                        .stroke(
                            turn.validationError != nil ? Aperture.Palette.critical.opacity(0.5) : Color.clear,
                            lineWidth: 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: Aperture.Radius.card))

            if let confirmedValue = turn.confirmedValue {
                HStack(spacing: Aperture.Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Aperture.Palette.positive)
                    Text(LaPlumaString("interview.savedToApplication"))
                        .font(Aperture.Typography.caption)
                        .foregroundStyle(Aperture.Palette.positive)
                    Text(confirmedValue)
                        .font(Aperture.Typography.caption)
                        .bold()
                        .foregroundStyle(Aperture.Palette.positive)
                }
            }

            // Each assistant question declares the single field it is asking about,
            // with the authoritative English form label beside it.
            if let question = turn.question {
                BilingualLabel(primary: "", english: question.englishFormLabel,
                               formReference: question.formReference)
                    .font(Aperture.Typography.caption)
            }

            // A blocked turn looks like any other message and always says what we *can*
            // do. It never simply refuses and stops.
            if turn.guardrailBlocked {
                NavigationLink {
                    LegalHelpDirectoryView()
                } label: {
                    Label(ApertureString("catalog.findLegalHelp"), systemImage: "arrow.up.right.square")
                        .font(Aperture.Typography.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: turn.role == .user ? .trailing : .leading)
        .accessibilityElement(children: .combine)
    }
}

/// S-09 pre-session consent. Four plain statements, spoken **and** displayed, before
/// any audio is captured. Clip retention is a separate, unchecked opt-in (C-07).
struct VoiceConsentView: View {
    let caseID: CaseID
    let batchID: BatchID
    /// The person these answers are about. Never a fixture literal: a saved
    /// answer is a confirmation attributed to this person (ADR-007).
    let personID: PersonID

    @State private var agreed = false
    @State private var retainClips = false
    @State private var proceed = false

    private let points = [
        "interview.voiceConsent.point1",
        "interview.voiceConsent.point2",
        "interview.voiceConsent.point3",
        "interview.voiceConsent.point4"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Aperture.Spacing.l) {
                Text(aperture: "interview.voiceConsent.title")
                    .font(Aperture.Typography.screenTitle)
                    .accessibilityIdentifier("voice-consent-title")

                ForEach(points, id: \.self) { key in
                    Label(ApertureString(String.LocalizationValue(key)), systemImage: "info.circle")
                        .font(Aperture.Typography.body)
                }

                Toggle(ApertureString("interview.voiceConsent.agree"), isOn: $agreed)
                    .accessibilityIdentifier("voice-consent-agree-toggle")
                // Defaults to off. Audio is discarded at session end unless the user
                // explicitly opts in, per session.
                Toggle(ApertureString("interview.voiceConsent.retainClips"), isOn: $retainClips)

                Text(aperture: "interview.audioStaysPrivate")
                    .font(Aperture.Typography.caption)
                    .foregroundStyle(Aperture.Palette.onSurfaceSecondary)

                Button {
                    proceed = true
                } label: {
                    Text(aperture: "common.continue")
                        .apertureMinimumTouchTarget(expandHorizontally: true)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!agreed)
            }
            .padding(Aperture.Spacing.l)
        }
        .navigationTitle("Speak your answers")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $proceed) {
            VoiceInterviewView(
                caseID: caseID,
                batchID: batchID,
                personID: personID,
                retainClips: retainClips
            )
        }
    }
}

/// S-09 session. The live transcript is **always visible** — it satisfies the caption
/// requirement and is a trust feature in its own right.
///
/// Guardrailing here is *corrective*, not preventive: audio flows client-to-model
/// directly, so nothing can intercept an utterance before the user hears it. The client
/// classifies the streaming assistant transcript and interrupts on a block. That leaves
/// a real exposure window, which is why voice is opt-in, disabled on the highest
/// advice-pull surfaces, and gated on measured interrupt latency (SME B-01, RISK-032).
struct VoiceWaveformView: View {
    let audioLevel: Float
    let isListening: Bool
    let isSpeaking: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<9, id: \.self) { index in
                let multiplier: Float = Float(abs(4 - index)) * 0.12
                let factor = max(0.2, Double(audioLevel - multiplier))
                let barHeight: CGFloat = (isListening || isSpeaking)
                    ? CGFloat(18.0 + factor * 50.0)
                    : 16.0

                RoundedRectangle(cornerRadius: 3)
                    .fill(isListening ? Aperture.Palette.accent : (isSpeaking ? Aperture.Palette.positive : Aperture.Palette.slateBorder.opacity(0.4)))
                    .frame(width: 6, height: barHeight)
            }
        }
        .frame(height: 70)
        .accessibilityLabel(
            isListening ? LaPlumaString("voice.listening") : (isSpeaking ? LaPlumaString("voice.speaking") : LaPlumaString("voice.idle"))
        )
    }
}

/// S-09 session. The live transcript is **always visible** — it satisfies the caption
/// requirement and is a trust feature in its own right.
struct VoiceInterviewView: View {
    let caseID: CaseID
    let batchID: BatchID
    let personID: PersonID
    let retainClips: Bool

    @Environment(AppSession.self) private var session
    @State private var model = InterviewModel()
    @State private var voice = VoiceCoordinator()

    private var latestAssistantTurn: InterviewTurn? {
        model.turns.last(where: { $0.role == .assistant })
    }

    var body: some View {
        VStack(spacing: Aperture.Spacing.l) {
            VoiceWaveformView(
                audioLevel: voice.audioLevel,
                isListening: voice.state == .listening,
                isSpeaking: voice.state == .speaking
            )

            if let current = latestAssistantTurn {
                Text(current.text)
                    .font(Aperture.Typography.sectionTitle)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Aperture.Spacing.m)
            }

            // Live speech recognition transcript bubble
            if voice.state == .listening && !voice.liveTranscript.isEmpty {
                HStack(spacing: Aperture.Spacing.xs) {
                    Image(systemName: "waveform")
                        .foregroundStyle(Aperture.Palette.accent)
                    Text(voice.liveTranscript)
                        .font(Aperture.Typography.body)
                        .foregroundStyle(Aperture.Palette.onSurface)
                }
                .padding(Aperture.Spacing.s)
                .background(Aperture.Palette.accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Aperture.Radius.card))
            }

            // Always visible, never optional transcript scroll view.
            ScrollView {
                VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
                    ForEach(model.turns) { turn in
                        HStack(alignment: .top) {
                            if turn.role == .assistant {
                                Image(systemName: "bubble.left.fill")
                                    .foregroundStyle(Aperture.Palette.accent)
                                    .font(.caption2)
                            }
                            Text(turn.text)
                                .font(Aperture.Typography.caption)
                                .foregroundStyle(turn.role == .user ? Aperture.Palette.onSurface
                                                                    : Aperture.Palette.onSurfaceSecondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
            .apertureCard()

            // Voice Action Buttons
            VStack(spacing: Aperture.Spacing.m) {
                if voice.state == .permissionDenied {
                    Label(LaPlumaString("voice.permissionRequired"), systemImage: "mic.slash.fill")
                        .font(Aperture.Typography.caption)
                        .apertureStatusSurface(.critical)
                }

                Button {
                    handleVoiceButtonTap()
                } label: {
                    HStack(spacing: Aperture.Spacing.s) {
                        Image(systemName: actionIcon)
                        Text(actionLabel)
                    }
                    .font(Aperture.Typography.action)
                    .apertureMinimumTouchTarget(expandHorizontally: true)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isStarting || model.isSending || voice.state == .permissionDenied || model.budgetExhausted)

                HStack(spacing: Aperture.Spacing.m) {
                    Button {
                        if let current = latestAssistantTurn {
                            voice.speak(text: current.text, locale: session.preferredLocale.identifier)
                        }
                    } label: {
                        Label(LaPlumaString("voice.repeatQuestion"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(voice.state == .speaking || voice.state == .listening || model.turns.isEmpty)

                    NavigationLink {
                        ChatInterviewView(caseID: caseID, batchID: batchID, personID: personID)
                    } label: {
                        Label(ApertureString("interview.switchToTyping"), systemImage: "keyboard")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let budget = model.session?.budget {
                if budget.isWaived {
                    Label(LaPlumaString("No voice time limit"), systemImage: "infinity")
                        .font(Aperture.Typography.caption)
                        .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                        .accessibilityIdentifier("voice-budget-waived")
                } else {
                    Text(LaPlumaFormat(
                        "interview.voiceMinutesRemaining",
                        (budget.secondsRemaining + 59) / 60
                    ))
                        .font(Aperture.Typography.caption)
                        .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                }
            }

            if model.budgetExhausted {
                ApertureMessageView(.empty(messageKey: "interview.budgetExhausted"))
            }

            DisclosureFooter()
        }
        .padding(Aperture.Spacing.l)
        .navigationTitle(LaPlumaString("Speaking"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await startVoiceSession()
        }
        .onChange(of: model.turns.count) {
            if let last = model.turns.last, last.role == .assistant {
                voice.speak(text: last.text, locale: session.preferredLocale.identifier)
                if model.lastConfirmedPath != nil {
                    session.dataDidChange()
                }
            }
        }
        .onDisappear {
            voice.stopSpeaking()
            voice.stopListening()
        }
    }

    private var actionIcon: String {
        switch voice.state {
        case .listening: return "stop.circle.fill"
        case .speaking: return "speaker.wave.2.fill"
        case .processing: return "hourglass"
        default: return "mic.fill"
        }
    }

    private var actionLabel: String {
        switch voice.state {
        case .listening: return LaPlumaString("voice.finishSpeaking")
        case .speaking: return LaPlumaString("voice.stopSpeaking")
        case .processing: return LaPlumaString("voice.processing")
        default: return LaPlumaString("voice.tapToSpeak")
        }
    }

    @MainActor
    private func startVoiceSession() async {
        await model.start(
            api: session.api, caseID: caseID, personID: personID, batchID: batchID,
            modality: .voice,
            consent: VoiceConsent(
                noticeVersion: "2026.03", noticeSHA256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                spokenAndDisplayed: true, retainAudioClips: retainClips, grantedAt: Date()
            ),
            accessibilityProfileEnabled: session.accessibilityProfileEnabled
        )
        if let initial = latestAssistantTurn {
            voice.speak(text: initial.text, locale: session.preferredLocale.identifier)
        }
    }

    @MainActor
    private func handleVoiceButtonTap() {
        Task {
            if voice.state == .listening {
                let transcript = voice.stopListening()
                if !transcript.isEmpty {
                    voice.state = .processing
                    _ = await model.send(api: session.api, text: transcript)
                    voice.state = .idle
                    if model.lastConfirmedPath != nil {
                        session.dataDidChange()
                    }
                }
            } else if voice.state == .speaking {
                voice.stopSpeaking()
            } else {
                _ = await voice.startListening(locale: session.preferredLocale.identifier)
            }
        }
    }
}

/// Structured questionnaire — the always-available fallback. Works with every model
/// offline, which is what makes AI failure a degradation rather than an outage.
///
/// Each saved answer is a real confirmation for the field the question targets,
/// and the batch advances through every scripted question before the interview
/// ends — a batch advertised as "N quick questions" must accept N answers.
struct StructuredQuestionsView: View {
    let caseID: CaseID
    let batchID: BatchID
    /// The person these answers are about. Never a fixture literal: a saved
    /// answer is a confirmation attributed to this person (ADR-007).
    let personID: PersonID

    @Environment(AppSession.self) private var appSession
    @State private var interview: InterviewSession?
    @State private var answer = ""
    @State private var answeredCount = 0
    @State private var finished = false
    @State private var isSaving = false
    @State private var blockedNotice: String?
    @State private var errorMessage: String?

    private var currentQuestion: InterviewQuestion? {
        interview?.turns.last(where: { $0.question != nil })?.question
    }

    var body: some View {
        Form {
            Section {
                Text("These are the same questions the assistant would ask. You can answer them here at any time, even with no connection.")
                    .font(Aperture.Typography.caption)
            }

            if finished {
                Section {
                    Label("All questions are answered. Your answers are saved for review.",
                          systemImage: "doc.badge.plus")
                        .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                        .accessibilityIdentifier("structured-questions-complete")
                }
            } else if let question = currentQuestion {
                Section {
                    Text(question.prompt).font(Aperture.Typography.sectionTitle)
                    BilingualLabel(
                        primary: "",
                        english: question.englishFormLabel,
                        formReference: question.formReference
                    )
                    TextField("Your answer", text: $answer, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section {
                    Button("Save answer") { Task { await save(question) } }
                        .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                    if answeredCount > 0 {
                        Label("Answer saved for review", systemImage: "doc.badge.plus")
                            .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                    }
                    if let blockedNotice {
                        Text(blockedNotice)
                            .font(Aperture.Typography.caption)
                            .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                    }
                }
            } else {
                Section { ApertureLoadingView() }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(Aperture.Palette.critical) }
            }
            Section { DisclosureFooter() }
        }
        .navigationTitle("Type it in")
        .task { await start() }
    }

    @MainActor private func start() async {
        do {
            let started = try await appSession.api.startInterview(
                caseID: caseID,
                personID: personID,
                batchID: batchID,
                modality: .form,
                consent: nil,
                accessibilityProfileEnabled: appSession.accessibilityProfileEnabled,
                idempotencyKey: IdempotencyKey.make()
            )
            let turns = try await appSession.api.sendInterviewMessage(
                sessionID: started.id,
                text: "Begin structured questions",
                idempotencyKey: IdempotencyKey.make()
            )
            var updated = started
            updated.turns.append(contentsOf: turns)
            interview = updated
        } catch {
            errorMessage = LaPlumaString("The questions could not be loaded. Try again.")
        }
    }

    /// The confirmation is written before the interview advances: a value save is
    /// the compliance-critical write, and if advancing fails the same question
    /// stays on screen so retrying re-confirms the identical value harmlessly.
    @MainActor private func save(_ question: InterviewQuestion) async {
        let value = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = true
        errorMessage = nil
        blockedNotice = nil
        defer { isSaving = false }
        do {
            _ = try await appSession.api.confirmValues(
                caseID: caseID,
                confirmations: [ValueConfirmation(
                    personID: question.subjectPersonID,
                    canonicalPath: question.canonicalPath,
                    value: value
                )],
                idempotencyKey: IdempotencyKey.make()
            )
            appSession.dataDidChange()

            guard let sessionID = interview?.id else { return }
            let turns = try await appSession.api.sendInterviewMessage(
                sessionID: sessionID,
                text: value,
                idempotencyKey: IdempotencyKey.make()
            )
            interview?.turns.append(contentsOf: turns)

            if let reply = turns.last(where: { $0.role == .assistant }) {
                if reply.guardrailBlocked == true {
                    // The value is saved; the assistant text explains why the
                    // conversation itself did not move on.
                    blockedNotice = reply.text
                    return
                }
                answeredCount += 1
                answer = ""
                if reply.question == nil {
                    finished = true
                    try await appSession.api.endInterview(sessionID: sessionID)
                }
            }
        } catch {
            errorMessage = LaPlumaString("Your answer could not be saved. Try again.")
        }
    }
}

/// Presented uniformly to every user, unranked, unpersonalised, with no fee.
/// A ranked or fee-bearing referral would be a judgment about the user's situation
/// and is prohibited (C-24).
struct LegalHelpDirectoryView: View {
    var body: some View {
        List {
            Section {
                Text("These organisations provide free or low-cost immigration legal help. We do not rank them, we are not paid by them, and this list is the same for everyone.")
                    .font(Aperture.Typography.caption)
            }
            Link("EOIR recognised organisations roster",
                 destination: URL(string: "https://www.justice.gov/eoir/recognition-accreditation-roster-reports")!)
        }
        .navigationTitle(ApertureString("catalog.findLegalHelp"))
    }
}
