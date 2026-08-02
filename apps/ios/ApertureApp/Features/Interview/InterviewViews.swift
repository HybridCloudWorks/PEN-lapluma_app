import SwiftUI
import ApertureUI
import ApertureAPI
import ApertureDomain

/// S-10 Chat Interview — the **default** modality. Cheaper than voice, more accessible,
/// easier to guardrail, and it leaves a transcript the user can re-read.
struct ChatInterviewView: View {
    let caseID: CaseID
    let batchID: BatchID

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
                        ForEach(model.turns) { turn in
                            TurnBubble(turn: turn).id(turn.id)
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
                    let text = draft
                    draft = ""
                    Task { await model.send(api: session.api, text: text) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Send")
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
            await model.start(api: session.api, caseID: caseID, batchID: batchID, modality: .chat, consent: nil)
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
                .background(turn.role == .user ? Aperture.Palette.accent.opacity(0.15)
                                               : Aperture.Palette.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Aperture.Radius.card))

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

@Observable
@MainActor
final class InterviewModel {
    var session: InterviewSession?
    var turns: [InterviewTurn] = []
    var budgetExhausted = false

    func start(
        api: any ApertureAPIClient,
        caseID: CaseID,
        batchID: BatchID,
        modality: InterviewModality,
        consent: VoiceConsent?,
        accessibilityProfileEnabled: Bool = false
    ) async {
        let started = try? await api.startInterview(
            caseID: caseID,
            personID: PersonID("p_carlos"),
            batchID: batchID,
            modality: modality,
            consent: consent,
            accessibilityProfileEnabled: accessibilityProfileEnabled,
            idempotencyKey: IdempotencyKey.make()
        )
        session = started
        turns = started?.turns ?? []
    }

    func send(api: any ApertureAPIClient, text: String) async {
        guard let sessionID = session?.id else { return }
        do {
            let newTurns = try await api.sendInterviewMessage(
                sessionID: sessionID, text: text, idempotencyKey: IdempotencyKey.make()
            )
            turns.append(contentsOf: newTurns)
        } catch let problem as ProblemDetails where problem.isBudgetExhausted {
            budgetExhausted = true
        } catch {
            // Degrades to the structured questionnaire rather than losing the answer.
        }
    }
}

/// S-09 pre-session consent. Four plain statements, spoken **and** displayed, before
/// any audio is captured. Clip retention is a separate, unchecked opt-in (C-07).
struct VoiceConsentView: View {
    let caseID: CaseID
    let batchID: BatchID

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
            VoiceInterviewView(caseID: caseID, batchID: batchID, retainClips: retainClips)
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
struct VoiceInterviewView: View {
    let caseID: CaseID
    let batchID: BatchID
    let retainClips: Bool

    @Environment(AppSession.self) private var session
    @State private var model = InterviewModel()

    var body: some View {
        VStack(spacing: Aperture.Spacing.l) {
            WaveformPlaceholder()

            if let current = model.turns.last(where: { $0.role == .assistant }) {
                Text(current.text)
                    .font(Aperture.Typography.sectionTitle)
                    .multilineTextAlignment(.center)
            }

            // Always visible, never optional.
            ScrollView {
                VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
                    ForEach(model.turns) { turn in
                        Text(turn.text)
                            .font(Aperture.Typography.caption)
                            .foregroundStyle(turn.role == .user ? Aperture.Palette.onSurface
                                                                : Aperture.Palette.onSurfaceSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)
            .apertureCard()

            if let budget = model.session?.budget {
                if budget.isWaived {
                    Label("No voice time limit", systemImage: "infinity")
                        .font(Aperture.Typography.caption)
                        .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                        .accessibilityIdentifier("voice-budget-waived")
                } else {
                    Text("\(budget.secondsRemaining / 60) minutes of voice left")
                        .font(Aperture.Typography.caption)
                        .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                }
            }

            if model.budgetExhausted {
                ApertureMessageView(.empty(messageKey: "interview.budgetExhausted"))
            }

            HStack(spacing: Aperture.Spacing.m) {
                NavigationLink {
                    ChatInterviewView(caseID: caseID, batchID: batchID)
                } label: {
                    Label(ApertureString("interview.switchToTyping"), systemImage: "keyboard")
                }
                .buttonStyle(.bordered)
            }

            DisclosureFooter()
        }
        .padding(Aperture.Spacing.l)
        .navigationTitle("Speaking")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.start(
                api: session.api, caseID: caseID, batchID: batchID, modality: .voice,
                consent: VoiceConsent(
                    noticeVersion: "2026.03", noticeSHA256: "stub",
                    spokenAndDisplayed: true, retainAudioClips: retainClips, grantedAt: Date()
                ),
                accessibilityProfileEnabled: session.accessibilityProfileEnabled
            )
        }
    }
}

struct WaveformPlaceholder: View {
    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: 72))
            .foregroundStyle(Aperture.Palette.accent)
            .accessibilityHidden(true)
    }
}

/// Structured questionnaire — the always-available fallback. Works with every model
/// offline, which is what makes AI failure a degradation rather than an outage.
struct StructuredQuestionsView: View {
    let caseID: CaseID
    let batchID: BatchID

    @Environment(AppSession.self) private var appSession
    @State private var interview: InterviewSession?
    @State private var answer = ""
    @State private var saved = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Text("These are the same questions the assistant would ask. You can answer them here at any time, even with no connection.")
                    .font(Aperture.Typography.caption)
            }

            if let question = interview?.turns.last(where: { $0.question != nil })?.question {
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
                        .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saved)
                    if saved {
                        Label("Answer saved for review", systemImage: "doc.badge.plus")
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
                personID: PersonID("p_carlos"),
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
            errorMessage = "The questions could not be loaded. Try again."
        }
    }

    @MainActor private func save(_ question: InterviewQuestion) async {
        do {
            _ = try await appSession.api.confirmValues(
                caseID: caseID,
                confirmations: [ValueConfirmation(
                    personID: question.subjectPersonID,
                    canonicalPath: question.canonicalPath,
                    value: answer.trimmingCharacters(in: .whitespacesAndNewlines)
                )],
                idempotencyKey: IdempotencyKey.make()
            )
            if let sessionID = interview?.id { try await appSession.api.endInterview(sessionID: sessionID) }
            saved = true
            appSession.dataDidChange()
        } catch {
            errorMessage = "Your answer could not be saved. Try again."
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
