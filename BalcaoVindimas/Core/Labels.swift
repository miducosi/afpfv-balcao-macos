import SwiftUI

/// Labels dos enums — cópia de `src/types/domain.ts` do afpfv-balcao. Valores desconhecidos mostram o código.
nonisolated enum Labels {
    static let role = ["ADMIN": "Administrador", "OPERATOR": "Operador", "USER": "Utilizador"]

    static let areas: [(code: String, label: String, hint: String)] = [
        ("GENERAL_SUPPORT", "Atendimento geral", "Pedidos de informação e base de conhecimento"),
        ("STALLS", "Terrados", "Candidaturas, lotes e lista de espera"),
        ("TREASURY", "Tesouraria", "Cobranças, comprovativos e faturas"),
        ("PASSES", "Livres-trânsito", "Pedidos e emissão de livres-trânsito"),
        ("ACCESS_CONTROL", "Controlo de acessos", "Só leitura de QR nos pontos de controlo"),
        ("RACES", "Provas desportivas", "Provas, inscrições e dorsais"),
        ("CANTEEN", "Refeitório", "Senhas de refeição, entidades, ementas e mapa de refeições"),
        ("MEAL_VALIDATION", "Validação de refeições", "Só leitura de senhas à entrada do refeitório"),
    ]
    static let area = Dictionary(uniqueKeysWithValues: areas.map { ($0.code, $0.label) })

    static let editionStatus = ["DRAFT": "Em preparação", "OPEN": "Aberta", "RUNNING": "A decorrer", "CLOSED": "Encerrada"]

    static let caseType = [
        "INFO": "Pedido de informação", "STALL": "Terrado", "PASS": "Livre-trânsito",
        "RACE": "Prova desportiva", "MEAL": "Senhas de refeição",
    ]
    static let caseStatusOrder = ["NEW", "IN_REVIEW", "WAITING_USER", "RESOLVED", "CLOSED"]
    static let caseStatus = [
        "NEW": "Novo", "IN_REVIEW": "Em análise", "WAITING_USER": "A aguardar resposta",
        "RESOLVED": "Resolvido", "CLOSED": "Fechado",
    ]
    static let casePriority = ["LOW": "Baixa", "NORMAL": "Normal", "HIGH": "Alta", "URGENT": "Urgente"]

    static let priceRule = ["PER_PLOT": "Valor fixo por lote", "PER_SQUARE_METER": "Por m²", "PER_FRONT_METER": "Por metro de frente"]
    static let stallStatus = [
        "DRAFT": "Rascunho", "SUBMITTED": "Submetida", "IN_REVIEW": "Em análise",
        "AWAITING_DOCUMENTS": "Elementos pedidos", "APPROVED": "Aprovada", "WAITLISTED": "Lista de espera",
        "REJECTED": "Não aprovada", "WITHDRAWN": "Desistência", "CANCELLED": "Anulada",
    ]
    static let holderType = ["INDIVIDUAL": "Pessoa singular", "COMPANY": "Pessoa coletiva"]
    static let documentReview = ["PENDING": "Por validar", "ACCEPTED": "Aceite", "REJECTED": "Recusado"]
    static let stallAction = [
        "start_review": "Iniciar análise", "request_documents": "Pedir elementos",
        "approve": "Aprovar e atribuir lote", "waitlist": "Lista de espera",
        "reject": "Não aprovar", "cancel": "Anular aprovação",
    ]
    static let requirementProblem = [
        "missing": "Em falta", "rejected": "Recusado",
        "expires_before_edition": "Expira antes da edição", "missing_expiry": "Sem data de validade",
    ]

    static let chargeKind = [
        "STALL_FEE": "Terrado", "STALL_DEPOSIT": "Caução", "RACE_FEE": "Inscrição em prova",
        "MEAL_FEE": "Senhas de refeição", "OTHER": "Outro",
    ]
    static let chargeStatus = [
        "PENDING": "Por pagar", "OVERDUE": "Em atraso", "PAID": "Paga", "CANCELLED": "Anulada", "REFUNDED": "Reembolsada",
    ]
    static let paymentMethods = ["TRANSFER", "MBWAY", "CASH", "CARD", "OTHER"]
    static let paymentMethod = [
        "CARD": "Cartão", "MBWAY": "MB WAY", "TRANSFER": "Transferência bancária", "CASH": "Numerário", "OTHER": "Outro",
    ]
    static let submissionStatus = ["PENDING": "Por validar", "APPROVED": "Validado", "REJECTED": "Recusado"]
    static let invoiceKind = ["INVOICE": "Fatura", "CREDIT_NOTE": "Nota de crédito"]

    static let registrationStatus = [
        "PENDING_PAYMENT": "A aguardar pagamento", "CONFIRMED": "Confirmada", "WAITLISTED": "Lista de espera",
        "CANCELLED": "Cancelada", "EXPIRED": "Expirada (sem pagamento)",
    ]
    static let gender = ["MALE": "Masculino", "FEMALE": "Feminino"]

    static let passStatus = [
        "PENDING": "Pedido", "ISSUED": "Emitido", "REJECTED": "Recusado", "REVOKED": "Revogado", "CANCELLED": "Cancelado",
    ]
    static let passOrigin = ["PUBLIC_REQUEST": "Pedido externo", "STAFF": "Emitido pela organização"]
    static let passScanResult = [
        "VALID": "Válido", "NOT_YET_VALID": "Ainda não é válido", "EXPIRED": "Expirado",
        "REVOKED": "Revogado", "NOT_ISSUED": "Não emitido", "UNKNOWN": "Desconhecido",
    ]

    static let mealKind = ["UNIT": "Unitária", "GROUP": "Grupo"]
    static let mealStatus = ["PENDING": "Pedido", "APPROVED": "Aprovada", "REJECTED": "Recusada", "CANCELLED": "Cancelada"]
    static let mealOrigin = ["REQUEST": "Pedida na área pessoal", "STAFF": "Emitida pelo Refeitório"]
    static let mealScanResult = [
        "VALID": "Válida", "NOT_APPROVED": "Não aprovada", "UNPAID": "Por pagar", "NO_MEAL_NOW": "Sem refeição agora",
        "ALREADY_USED": "Já utilizada", "EXHAUSTED": "Esgotada", "UNKNOWN": "Desconhecida",
    ]

    static func label(_ map: [String: String], _ code: String) -> String { map[code] ?? code }
}

/// Tom dos estados (cor do selo): o mesmo critério da web.
enum Tone {
    case neutral, info, success, warning, danger

    var color: Color {
        switch self {
        case .neutral: .secondary
        case .info: .blue
        case .success: .green
        case .warning: .orange
        case .danger: .red
        }
    }

    static func of(_ status: String) -> Tone {
        switch status {
        case "NEW", "SUBMITTED", "PENDING", "PENDING_PAYMENT": .info
        case "IN_REVIEW", "WAITING_USER", "AWAITING_DOCUMENTS", "WAITLISTED", "OVERDUE", "NOT_YET_VALID", "NO_MEAL_NOW":
            .warning
        case "RESOLVED", "APPROVED", "CONFIRMED", "ISSUED", "PAID", "ACCEPTED", "VALID", "FINISHED": .success
        case "REJECTED", "REVOKED", "EXPIRED", "UNKNOWN", "NOT_ISSUED", "NOT_APPROVED", "UNPAID", "ALREADY_USED",
             "EXHAUSTED", "URGENT":
            .danger
        default: .neutral
        }
    }
}
