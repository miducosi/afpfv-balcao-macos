import Foundation

// Modelos da API mobile — espelho de `src/lib/openapi/mobile/contracts.ts` (afpfv-balcao).
// Dinheiro em cêntimos; instantes como Date; datas sem hora (AAAA-MM-DD) como String.
// Enums ficam como String: um valor novo no servidor não parte a app (mostra o código).

nonisolated struct MessageResult: Decodable, Sendable { let message: String }
nonisolated struct MessageWithId: Decodable, Sendable { let message: String; let id: String }

nonisolated struct FileRef: Decodable, Hashable, Sendable {
    let id: String
    let fileName: String
    let mimeType: String
    let size: Int
}

nonisolated struct Edition: Decodable, Sendable {
    let id: String
    let year: Int
    let name: String
    let startsOn: String
    let endsOn: String
    let status: String
}

nonisolated struct Pagination: Decodable, Sendable {
    let page: Int
    let limit: Int
    let total: Int
    let hasMore: Bool
}

// MARK: Sessão

nonisolated struct SessionUser: Decodable, Sendable {
    let id: String
    let email: String
    let name: String
    let phone: String?
    let role: String
    let areas: [String]
    let isActive: Bool
}

nonisolated struct Me: Decodable, Sendable {
    let user: SessionUser
    let capabilities: [String]
    let home: String
    let edition: Edition?
}

// MARK: Painel

nonisolated struct StaffDashboard: Decodable, Sendable {
    struct Tile: Decodable, Identifiable, Sendable {
        let key: String
        let area: String?
        let count: Int
        let label: String
        let hint: String
        var id: String { key }
    }
    let edition: Edition?
    let tiles: [Tile]
    let urgentCases: Int
}

// MARK: Pedidos

nonisolated struct CaseLink: Decodable, Hashable, Sendable {
    let kind: String
    let id: String
}

nonisolated struct CaseSummary: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let reference: String
    let type: String
    let status: String
    let priority: String
    let subject: String
    let area: String
    let requesterName: String
    let categoryName: String?
    let lastActivityAt: Date
    let createdAt: Date
    let unread: Bool
    let link: CaseLink?
}

nonisolated struct CaseMessage: Decodable, Identifiable, Sendable {
    let id: String
    let body: String
    let fromRequester: Bool
    let isInternal: Bool
    let authorName: String?
    let createdAt: Date
}

nonisolated struct CaseEvent: Decodable, Identifiable, Sendable {
    let id: String
    let type: String
    let label: String
    let actorName: String?
    let createdAt: Date
}

nonisolated struct CaseDetail: Decodable, Identifiable, Sendable {
    let id: String
    let reference: String
    let type: String
    let status: String
    let priority: String
    let subject: String
    let area: String
    let requesterName: String
    let categoryName: String?
    let lastActivityAt: Date
    let createdAt: Date
    let link: CaseLink?
    let requesterEmail: String
    let requesterPhone: String?
    let assignedToId: String?
    let assignedToName: String?
    let resolvedAt: Date?
    let closedAt: Date?
    let messages: [CaseMessage]
    let events: [CaseEvent]
    let canReply: Bool
}

nonisolated struct CasePage: Decodable, Sendable {
    let items: [CaseSummary]
    let pagination: Pagination
}

// MARK: Pagamentos

nonisolated struct PaymentSubmission: Decodable, Identifiable, Sendable {
    let id: String
    let method: String
    let amountCents: Int
    let paidAt: Date
    let reference: String?
    let notes: String?
    let proof: FileRef
    let status: String
    let rejectionReason: String?
    let createdAt: Date
}

nonisolated struct Invoice: Decodable, Identifiable, Sendable {
    let id: String
    let kind: String
    let number: String
    let issuedOn: Date
    let file: FileRef
}

nonisolated struct ChargeLine: Decodable, Sendable {
    let label: String
    let cents: Int
}

nonisolated struct RecordedPayment: Decodable, Identifiable, Sendable {
    let id: String
    let method: String
    let amountCents: Int
    let paidAt: Date
    let reference: String?
}

nonisolated struct TreasuryCharge: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let caseId: String
    let caseReference: String
    let kind: String
    let description: String
    let amountCents: Int
    let lines: [ChargeLine]
    let dueAt: Date
    let status: String
    let displayStatus: String
    let paidAt: Date?
    let cancelReason: String?
    let submissions: [PaymentSubmission]
    let invoices: [Invoice]
    let awaitingReview: Bool
    let payments: [RecordedPayment]
    let payerName: String
    let payerEmail: String

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

nonisolated struct TreasurySubmission: Decodable, Identifiable, Sendable {
    let id: String
    let method: String
    let amountCents: Int
    let paidAt: Date
    let reference: String?
    let notes: String?
    let proof: FileRef
    let status: String
    let rejectionReason: String?
    let createdAt: Date
    let chargeId: String
    let chargeDescription: String
    let chargeAmountCents: Int
    let caseReference: String
    let payerName: String
}

nonisolated struct TreasuryOverview: Decodable, Sendable {
    struct Totals: Decodable, Sendable {
        let pendingCents: Int
        let overdueCents: Int
        let paidCents: Int
    }
    let pendingSubmissions: [TreasurySubmission]
    let totals: Totals
}

// MARK: Terrados

nonisolated struct StallRequirement: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String?
    let isRequired: Bool
    let requiresExpiry: Bool
}

nonisolated struct StallDocument: Decodable, Identifiable, Sendable {
    let id: String
    let requirementId: String?
    let requirementName: String?
    let file: FileRef
    let expiresOn: String?
    let reviewStatus: String
    let reviewNote: String?
    let createdAt: Date
}

nonisolated struct RequirementProblem: Decodable, Sendable {
    let requirementId: String
    let name: String
    let problem: String
}

nonisolated struct FreePlot: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let code: String
    let zoneName: String
    let widthM: Double
    let depthM: Double
}

nonisolated struct StaffStallApplication: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let caseId: String?
    let reference: String?
    let status: String
    let stallTypeName: String
    let holderName: String
    let submittedAt: Date?
    let updatedAt: Date
    let plotCode: String?
    let holderType: String
    let nif: String
    let address: String
    let postalCode: String
    let locality: String
    let phone: String
    let activityDescription: String
    let productsDescription: String
    let requestedWidthM: Double
    let requestedDepthM: Double
    let powerNeedsKw: Double?
    let needsWater: Bool
    let preferredZoneName: String?
    let decisionReason: String?
    let quotedAmountCents: Int?
    let requirements: [StallRequirement]
    let documents: [StallDocument]
    let problems: [RequirementProblem]
    let applicantName: String
    let applicantEmail: String
    let staffActions: [String]
    let freePlots: [FreePlot]

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: Provas

nonisolated struct WindowInfo: Decodable, Sendable {
    let open: Bool
    let reason: String?
    let opensAt: Date?
    let closesAt: Date?
}

nonisolated struct StaffRace: Decodable, Identifiable, Hashable, Sendable {
    struct Counts: Decodable, Sendable {
        let confirmed: Int
        let pending: Int
        let waitlisted: Int
        let checkedIn: Int
    }
    let id: String
    let slug: String
    let name: String
    let startsAt: Date
    let location: String?
    let distanceKm: Double?
    let window: WindowInfo
    let seatsLeft: Int
    let currentPriceCents: Int?
    let maxParticipants: Int
    let counts: Counts

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

nonisolated struct RaceParticipant: Decodable, Identifiable, Sendable {
    let id: String
    let fullName: String
    let birthDate: String
    let gender: String
    let categoryName: String?
    let tshirtSize: String?
    let priceCents: Int
    let bib: Int?
    let checkedInAt: Date?
}

nonisolated struct StaffRaceRegistration: Decodable, Identifiable, Sendable {
    let id: String
    let reference: String?
    let status: String
    let totalCents: Int
    let paymentDueAt: Date?
    let participants: [RaceParticipant]
    let userName: String
    let userEmail: String
    let createdAt: Date
}

// MARK: Livres-trânsito

nonisolated struct StaffPass: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let caseId: String?
    let reference: String?
    let typeName: String
    let typeColor: String
    let zones: [String]
    let origin: String
    let status: String
    let code: String
    let token: String?
    let holderName: String
    let organization: String?
    let plate: String
    let vehicleDescription: String?
    let purpose: String?
    let validFrom: Date?
    let validTo: Date?
    let issuedAt: Date?
    let rejectionReason: String?
    let revokedReason: String?
    let createdAt: Date
    let email: String?
    let phone: String?
    let internalNotes: String?
    let requesterName: String?

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

nonisolated struct PassScanOutcome: Decodable, Sendable {
    struct PassInfo: Decodable, Sendable {
        let code: String
        let holderName: String
        let organization: String?
        let plate: String
        let typeName: String
        let typeColor: String
        let zones: [String]
        let validFrom: Date?
        let validTo: Date?
    }
    let result: String
    let previousScans: Int
    let pass: PassInfo?
    let scannedAt: Date
}

nonisolated struct PassScanLog: Decodable, Identifiable, Sendable {
    let id: String
    let result: String
    let input: String
    let holderName: String?
    let plate: String?
    let checkpoint: String?
    let scannedByName: String?
    let createdAt: Date
}

// MARK: Refeições

nonisolated struct MealService: Decodable, Sendable {
    struct Period: Decodable, Sendable {
        let id: String
        let name: String
        let startsAt: String
        let endsAt: String
        let priceCents: Int
    }
    let id: String
    let date: String
    let period: Period
    let menu: String?
}

nonisolated struct MealItem: Decodable, Identifiable, Sendable {
    let id: String
    let service: MealService
    let quantity: Int
    let usedCount: Int
    let priceCents: Int
    let cancelledAt: Date?
}

nonisolated struct NextMeal: Decodable, Sendable {
    let date: String
    let periodName: String
    let startsAt: String
}

nonisolated struct StaffMealTicket: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let reference: String?
    let kind: String
    let status: String
    let origin: String
    let code: String
    let token: String?
    let holderName: String?
    let entityName: String?
    let dietaryNotes: String?
    let charged: Bool
    let paid: Bool
    let totalCents: Int
    let rejectionReason: String?
    let items: [MealItem]
    let next: NextMeal?
    let createdAt: Date
    let requesterName: String?
    let requesterEmail: String?
    let internalNotes: String?

    var displayName: String { holderName ?? entityName ?? requesterName ?? code }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

nonisolated struct MealScanOutcome: Decodable, Sendable {
    let result: String
    let holderName: String?
    let entityName: String?
    let kind: String?
    let periodName: String?
    let remaining: Int
    let consumed: Int
    let nextMeal: NextMeal?
    let scannedAt: Date
}

nonisolated struct MealDayMap: Decodable, Identifiable, Sendable {
    struct Period: Decodable, Sendable {
        let periodName: String
        let ordered: Int
        let served: Int
    }
    let date: String
    let periods: [Period]
    var id: String { date }
}

// MARK: Equipa

nonisolated struct StaffUser: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let email: String
    let phone: String?
    let role: String
    let areas: [String]
    let isActive: Bool
    let lastLoginAt: Date?
    let createdAt: Date
}

nonisolated struct AuditLogList: Decodable, Sendable {
    struct Item: Decodable, Identifiable, Sendable {
        let id: String
        let action: String
        let entityType: String
        let entityId: String?
        let actorName: String?
        let summary: String
        let createdAt: Date
    }
    let items: [Item]
    let pagination: Pagination
}
