import SwiftUI
import ApertureUI
import ApertureDomain

/// S-01/S-02 entry. The **"what we store" screen is shown before any field is
/// collected** — one of the highest-leverage trust interventions in the product
/// (US-01.06). A user decides whether to trust us before we ask for anything.
struct WelcomeView: View {
    @Environment(AppSession.self) private var session
    @State private var showsWhatWeStore = false
    @State private var showsSignIn = false

    var body: some View {
        VStack(spacing: Aperture.Spacing.l) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 56))
                .foregroundStyle(Aperture.Palette.accent)
                .accessibilityHidden(true)

            Text("Aperture")
                .font(Aperture.Typography.screenTitle)

            Text("Get your paperwork right, in your language, on your phone.")
                .font(Aperture.Typography.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                .padding(.horizontal, Aperture.Spacing.l)

            Spacer()

            VStack(spacing: Aperture.Spacing.s) {
                Button {
                    showsWhatWeStore = true
                } label: {
                    Text("Create account")
                        .apertureMinimumTouchTarget(expandHorizontally: true)
                }
                .buttonStyle(.borderedProminent)

                Button("Sign in") { showsSignIn = true }
                    .apertureMinimumTouchTarget()
            }
            .padding(.horizontal, Aperture.Spacing.l)

            // Present before authentication, and never suppressible.
            DisclosureFooter()
        }
        .sheet(isPresented: $showsWhatWeStore) { WhatWeStoreView() }
        .sheet(isPresented: $showsSignIn) { SignInView() }
    }
}

/// Six plain sentences, shown *before* any account exists. Target: 6th-grade reading
/// level, measured in CI.
struct WhatWeStoreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @State private var showsRegistration = false

    private let points: [(icon: String, text: String)] = [
        ("doc.on.doc", "We keep the documents you send us and the answers you give."),
        ("lock.shield", "Everything is encrypted. Only you and the people you choose can see it."),
        ("calendar", "We delete your documents 90 days after your case closes, or sooner if you ask."),
        ("person.2.slash", "We never sell or share your information. There are no ads and no trackers."),
        ("building.columns", "If a government agency asks us for your information, we require valid legal process, we push back on requests that are too broad, and we tell you unless the law forbids it."),
        ("trash", "You can delete everything at any time, from Settings.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Aperture.Spacing.l) {
                    Text("What we store")
                        .font(Aperture.Typography.screenTitle)

                    ForEach(points, id: \.text) { point in
                        HStack(alignment: .top, spacing: Aperture.Spacing.m) {
                            Image(systemName: point.icon)
                                .foregroundStyle(Aperture.Palette.accent)
                                .frame(width: 28)
                                .accessibilityHidden(true)
                            Text(point.text)
                                .font(Aperture.Typography.body)
                        }
                        .accessibilityElement(children: .combine)
                    }

                    Button {
                        showsRegistration = true
                    } label: {
                        Text(ApertureString("common.continue"))
                            .apertureMinimumTouchTarget(expandHorizontally: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, Aperture.Spacing.m)
                }
                .padding(Aperture.Spacing.l)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ApertureString("common.cancel")) { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showsRegistration) { RegistrationView() }
        }
    }
}
