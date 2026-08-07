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
        ApertureCanvas {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: Aperture.Spacing.l) {
                        VStack(spacing: Aperture.Spacing.m) {
                            Image("BrandMark")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 148, height: 148)
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: Aperture.Radius.card,
                                        style: .continuous
                                    )
                                )
                                .shadow(
                                    color: Aperture.Palette.accent.opacity(0.25),
                                    radius: 24,
                                    y: 12
                                )
                                .accessibilityHidden(true)

                            VStack(spacing: Aperture.Spacing.xs) {
                                Text("LaPluma")
                                    .font(Aperture.Typography.screenTitle)
                                Text("Paperwork, made clearer.")
                                    .font(Aperture.Typography.body)
                                    .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)

                        VStack(spacing: Aperture.Spacing.s) {
                            Button {
                                showsWhatWeStore = true
                            } label: {
                                Text("Create account")
                                    .fontWeight(.semibold)
                                    .apertureMinimumTouchTarget(expandHorizontally: true)
                            }
                            .apertureGlassButton(prominent: true)
                            .buttonBorderShape(.roundedRectangle(radius: Aperture.Radius.control))

                            Button("Sign in") { showsSignIn = true }
                                .apertureGlassButton()
                                .buttonBorderShape(.roundedRectangle(radius: Aperture.Radius.control))
                                .apertureMinimumTouchTarget(expandHorizontally: true)
                        }
                        .apertureGlassCard()

                        // Present before authentication, and never suppressible.
                        DisclosureFooter()
                    }
                    .padding(Aperture.Spacing.l)
                    .frame(minHeight: proxy.size.height, alignment: .center)
                    .apertureReadableContentWidth(maximum: 680)
                }
            }
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

    private let points: [(icon: String, title: String, text: String)] = [
        ("lock.shield", "Private by design", "Your documents and answers are encrypted. Only you and people you choose can see them."),
        ("hand.raised", "Never sold", "No ads or trackers. We require valid legal process for government requests and challenge requests that are too broad."),
        ("trash", "You stay in control", "Delete everything in Settings. We also delete documents 90 days after your case closes.")
    ]

    var body: some View {
        NavigationStack {
            ApertureCanvas {
                ScrollView {
                    VStack(alignment: .leading, spacing: Aperture.Spacing.l) {
                        VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
                            Text("What we store")
                                .font(Aperture.Typography.screenTitle)
                                .accessibilityAddTraits(.isHeader)
                            Text("A clear promise before you start.")
                                .font(Aperture.Typography.body)
                                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                        }

                        VStack(spacing: 0) {
                            ForEach(points, id: \.title) { point in
                                HStack(alignment: .top, spacing: Aperture.Spacing.m) {
                                    Image(systemName: point.icon)
                                        .font(.title3)
                                        .foregroundStyle(Aperture.Palette.accent)
                                        .frame(width: 32, height: 32)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
                                        Text(LaPlumaString(String.LocalizationValue(point.title)))
                                            .font(Aperture.Typography.value)
                                        Text(LaPlumaString(String.LocalizationValue(point.text)))
                                            .font(Aperture.Typography.caption)
                                            .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, Aperture.Spacing.m)
                                .accessibilityElement(children: .combine)

                                if point.title != points.last?.title {
                                    Divider()
                                }
                            }
                        }
                        .apertureGlassCard()

                        Button {
                            showsRegistration = true
                        } label: {
                            Text(ApertureString("common.continue"))
                                .fontWeight(.semibold)
                                .apertureMinimumTouchTarget(expandHorizontally: true)
                        }
                        .apertureGlassButton(prominent: true)
                        .buttonBorderShape(.roundedRectangle(radius: Aperture.Radius.control))
                    }
                    .padding(Aperture.Spacing.l)
                }
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
