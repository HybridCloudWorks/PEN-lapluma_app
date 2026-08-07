import SwiftUI

/// A shared, explicit lifecycle for remote or persisted content. Views must distinguish
/// a legitimate empty result from a failed request instead of translating both to `nil`.
public enum ApertureLoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case empty
    case failed

    public var value: Value? {
        guard case .loaded(let value) = self else { return nil }
        return value
    }

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

extension ApertureLoadState: Equatable where Value: Equatable {}

/// Error and empty states that say what happened, whose fault it is when it is ours,
/// and what to do next. Never a bare "something went wrong".
public struct ApertureMessageView: View {
    public enum Kind {
        case offline
        case aiUnavailable
        case extractionFailed
        case generationFailed
        case formDrift
        case failed(messageKey: String)
        case attention(messageKey: String)
        case empty(messageKey: String)

        var systemImage: String {
            switch self {
            case .offline: "wifi.slash"
            case .aiUnavailable: "bubble.left.and.exclamationmark.bubble.right"
            case .extractionFailed: "doc.viewfinder"
            case .generationFailed: "exclamationmark.triangle"
            case .formDrift: "arrow.triangle.2.circlepath"
            case .failed: "exclamationmark.triangle.fill"
            case .attention: "exclamationmark.circle.fill"
            case .empty: "tray"
            }
        }

        var messageKey: String {
            switch self {
            case .offline: "error.offline.body"
            case .aiUnavailable: "error.aiUnavailable"
            case .extractionFailed: "error.extractionFailed"
            case .generationFailed: "error.generationFailed"
            case .formDrift: "error.formDrift"
            case .failed(let key): key
            case .attention(let key): key
            case .empty(let key): key
            }
        }

        var tone: Aperture.StatusTone {
            switch self {
            case .offline, .aiUnavailable, .extractionFailed, .formDrift, .attention: .attention
            case .generationFailed, .failed: .critical
            case .empty: .information
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
                .foregroundStyle(kind.tone.foreground)
                .frame(width: 64, height: 64)
                .background(kind.tone.background, in: Circle())
            Text(ApertureString(String.LocalizationValue(kind.messageKey)))
                .font(Aperture.Typography.body)
                .multilineTextAlignment(.center)
            if let action {
                Button(action.title, action: action.handler)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(Aperture.Spacing.l)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: action == nil ? .combine : .contain)
    }
}

/// A loading state that announces itself to assistive technology rather than leaving a
/// VoiceOver user on a silent screen.
public struct ApertureLoadingView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: Aperture.Spacing.s) {
            ProgressView()
            Text(ApertureString("common.loading"))
                .font(Aperture.Typography.caption)
                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
