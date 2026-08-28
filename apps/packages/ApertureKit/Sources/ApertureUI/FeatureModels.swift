import Foundation
import Observation
import ApertureDomain
import ApertureAPI

// Screen models for the applicant app's feature views. They hold no SwiftUI and no
// localized copy, only load/act state transitions over `ApertureAPIClient`, so they
// live here rather than in the app target: `swift test` exercises them on every pull
// request without a simulator, where an app-target class is reachable only through a
// scheduled XCUITest journey. Copy for any failure they report is chosen by the view,
// which is the layer that owns localization tables.

/// Home dashboard state: folders plus the cases that need the applicant's attention.
@Observable
@MainActor
public final class HomeModel {
    public enum Phase { case loading, loaded, failed }

    public var phase: Phase = .loading
    public var folders: [Folder] = []
    public var attentionItems: [AttentionItem] = []

    public struct AttentionItem: Identifiable, Sendable {
        public let id: String
        public let caseID: CaseID
        public let title: String
        public let blockingCount: Int

        public init(id: String, caseID: CaseID, title: String, blockingCount: Int) {
            self.id = id
            self.caseID = caseID
            self.title = title
            self.blockingCount = blockingCount
        }
    }

    public init() {}

    public func load(api: any ApertureAPIClient) async {
        do {
            let folders = try await api.folders()
            self.folders = folders
            self.attentionItems = folders.flatMap { folder in
                folder.cases.compactMap { summary -> AttentionItem? in
                    guard summary.counters.blockingItems > 0 else { return nil }
                    return AttentionItem(
                        id: summary.id.rawValue,
                        caseID: summary.id,
                        title: summary.packageTitle,
                        blockingCount: summary.counters.blockingItems
                    )
                }
            }
            phase = .loaded
        } catch {
            phase = .failed
        }
    }
}

/// Catalog browsing state over the locale-scoped, case-independent package list.
@Observable
@MainActor
public final class CatalogModel {
    public var state: ApertureLoadState<[FormPackage]> = .idle
    /// Set when the newest request failed while an earlier result is still on screen.
    public var isStale = false

    private var packages: [FormPackage] { state.value ?? [] }

    public var categoryGroups: [CatalogCategoryGroup] {
        Dictionary(grouping: packages, by: \.category)
            .map { CatalogCategoryGroup(category: $0.key, packages: $0.value) }
            .sorted {
                ($0.category.sortOrder, $0.category.title, $0.category.code)
                    < ($1.category.sortOrder, $1.category.title, $1.category.code)
            }
    }

    public init() {}

    /// Note the parameters: a locale-scoped query and nothing else. No folder, no case,
    /// no person. The absence is the control.
    public func load(api: any ApertureAPIClient, query: String) async {
        // `.task(id: query)` re-runs on every keystroke, so a spinner only appears
        // before there is anything to show.
        if state.value == nil { state = .loading }
        do {
            let result = try await api.catalogPackages(query: query.isEmpty ? nil : query)
            isStale = false
            state = result.isEmpty ? .empty : .loaded(result)
        } catch is CancellationError {
            return
        } catch {
            if state.value == nil {
                state = .failed
            } else {
                isStale = true
            }
        }
    }
}

public struct CatalogCategoryGroup: Identifiable, Sendable {
    public var id: String { category.id }
    public let category: CatalogCategory
    public let packages: [FormPackage]

    public init(category: CatalogCategory, packages: [FormPackage]) {
        self.category = category
        self.packages = packages
    }

    public var formCount: Int { packages.reduce(0) { $0 + $1.forms.count } }
    public var subcategoryCount: Int { Set(packages.map(\.subcategory.id)).count }

    public var subcategoryGroups: [(subcategory: CatalogSubcategory, packages: [FormPackage])] {
        Dictionary(grouping: packages, by: \.subcategory)
            .map { (subcategory: $0.key, packages: $0.value.sorted(by: Self.packageOrder)) }
            .sorted {
                ($0.subcategory.sortOrder, $0.subcategory.title, $0.subcategory.code)
                    < ($1.subcategory.sortOrder, $1.subcategory.title, $1.subcategory.code)
            }
    }

    private static func packageOrder(_ left: FormPackage, _ right: FormPackage) -> Bool {
        let leftForm = left.forms.first?.formNumber ?? left.packageCode
        let rightForm = right.forms.first?.formNumber ?? right.packageCode
        return (leftForm, left.packageCode) < (rightForm, right.packageCode)
    }
}

/// Review screen state: the case's reviewable fields grouped by the person they are about.
@Observable
@MainActor
public final class ReviewModel {
    public var state: ApertureLoadState<[ReviewableField]> = .idle
    public var personLabels: [PersonID: String] = [:]

    private var fields: [ReviewableField] { state.value ?? [] }

    public struct PersonGroup: Sendable {
        public let person: String
        public let fields: [ReviewableField]

        public init(person: String, fields: [ReviewableField]) {
            self.person = person
            self.fields = fields
        }
    }

    public var groupedByPerson: [PersonGroup] {
        Dictionary(grouping: fields, by: \.subjectPersonID)
            .map {
                PersonGroup(
                    person: personLabels[$0.key] ?? "Person",
                    fields: $0.value
                )
            }
            .sorted { $0.person < $1.person }
    }

    public init() {}

    public func load(api: any ApertureAPIClient, caseID: CaseID) async {
        state = .loading
        do {
            async let fieldsRequest = api.reviewableFields(caseID: caseID)
            async let foldersRequest = api.folders()
            let (fields, folders) = try await (fieldsRequest, foldersRequest)
            let people = folders.flatMap(\.persons)
            personLabels = people.reduce(into: [:]) { labels, person in
                labels[person.id] = person.displayLabel
            }
            state = fields.isEmpty ? .empty : .loaded(fields)
        } catch is CancellationError {
            return
        } catch {
            personLabels = [:]
            state = .failed
        }
    }
}

/// Package screen state: readiness and, once every gate is clear, the generated output.
@Observable
@MainActor
public final class PackageModel {
    /// Readiness always exists; a generated package exists only once every gate is
    /// clear. Keeping them in one loaded value means the screen can never present
    /// the compliance verdict from a request that did not arrive.
    public struct Content {
        public let generated: GeneratedPackage?
        public let readiness: PackageGenerationReadiness

        public init(generated: GeneratedPackage?, readiness: PackageGenerationReadiness) {
            self.generated = generated
            self.readiness = readiness
        }
    }

    public var state: ApertureLoadState<Content> = .idle
    public var isGenerating = false
    public var generationFailed = false
    private var generationIdempotencyKey = IdempotencyKey.make()

    public init() {}

    public func load(api: any ApertureAPIClient, caseID: CaseID) async {
        state = .loading
        do {
            async let packageRequest = api.generatedPackage(caseID: caseID)
            async let readinessRequest = api.packageGenerationReadiness(caseID: caseID)
            let (generated, readiness) = try await (packageRequest, readinessRequest)
            state = .loaded(Content(generated: generated, readiness: readiness))
        } catch is CancellationError {
            return
        } catch {
            state = .failed
        }
    }

    @discardableResult
    public func generate(api: any ApertureAPIClient, caseID: CaseID) async -> Bool {
        guard !isGenerating,
              case .loaded(let content) = state,
              content.generated == nil,
              content.readiness.canGenerate else { return false }
        isGenerating = true
        generationFailed = false
        defer { isGenerating = false }
        do {
            let generated = try await api.requestPackageGeneration(
                caseID: caseID,
                idempotencyKey: generationIdempotencyKey
            )
            state = .loaded(Content(generated: generated, readiness: content.readiness))
            generationIdempotencyKey = IdempotencyKey.make()
            return true
        } catch is CancellationError {
            return false
        } catch {
            // Keep the last successful readiness result visible. A generation
            // transport failure is not evidence that review became incomplete.
            generationFailed = true
            return false
        }
    }
}

/// Missing-items screen state: blocking and advisory items plus their question batches.
@Observable
@MainActor
public final class MissingItemsModel {
    public var required: [MissingItem] = []
    public var advisory: [MissingItem] = []
    public var batches: [MissingItemBatch] = []
    public var hasLoaded = false
    public var isLoading = false
    /// The view chooses the copy; the model only records that the load failed.
    public var loadFailed = false

    public init() {}

    /// The person a batch's questions are about. Derived from the items rather
    /// than assumed, because an answer is a compliance-critical write attributed
    /// to a specific person inside a shared folder (ADR-007).
    public func personID(forBatch batchID: BatchID) -> PersonID? {
        (required + advisory).first { $0.batchID == batchID }?.assignedPersonID
    }

    public func load(api: any ApertureAPIClient, caseID: CaseID) async {
        guard !isLoading else { return }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }

        do {
            let result = try await api.missingItems(caseID: caseID)
            required = result.items.filter { $0.severity == .blocking }
            advisory = result.items.filter { $0.severity == .advisory }
            batches = result.batches
            hasLoaded = true
        } catch {
            loadFailed = true
        }
    }
}
