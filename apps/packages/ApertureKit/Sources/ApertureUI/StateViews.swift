import SwiftUI

/// Error and empty states that say what happened, whose fault it is when it is ours,
/// and what to do next. Never a bare "something went wrong".
public struct ApertureMessageView: View {
    public enum Kind {
        case offline
        case aiUnavailable
        case extractionFailed
        case generationFailed
        case formDrift
        case empty(messageKey: String)

        var systemImage: String {
            switch self {
            case .offline: "wifi.slash"
            case .aiUnavailable: "bubble.left.and.exclamationmark.bubble.right"
            case .extractionFailed: "doc.viewfinder"
            case .generationFailed: "exclamationmark.triangle"
            case .formDrift: "arrow.triangle.2.circlepath"
            case .empty: "checkmark.circle"
            }
        }

        var messageKey: String {
            switch self {
            case .offline: "error.offline.body"
            case .aiUnavailable: "error.aiUnavailable"
            case .extractionFailed: "error.extractionFailed"
            case .generationFailed: "error.generationFailed"
            case .formDrift: "error.formDrift"
            case .empty(let key): key
            }
        }
    }

    private let kind: Kind
    private let action: (title: String, handler: () -> Void)?

    public init(_ kind: Kind, action: (title: String, handler: () -> Void)? = nil) {
        self.kind = kind
        self.action = action
    }

    public var body: some View {
        VStack(spacing: Aperture.Spacing.m) {
            Image(systemName: kind.systemImage)
                .font(.largeTitle)
                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
            Text(String(localized: String.LocalizationValue(kind.messageKey), bundle: .module))
                .font(Aperture.Typography.body)
                .multilineTextAlignment(.center)
            if let action {
                Button(action.title, action: action.handler)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(Aperture.Spacing.l)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A loading state that announces itself to assistive technology rather than leaving a
/// VoiceOver user on a silent screen.
public struct ApertureLoadingView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: Aperture.Spacing.s) {
            ProgressView()
            Text(String(localized: "common.loading", bundle: .module))
                .font(Aperture.Typography.caption)
                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
