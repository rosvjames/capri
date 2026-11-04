import Foundation

/// Lo que Capri tiene entre manos. Cuando coinciden varias cosas, la de más prioridad ocupa el notch; con la
/// misma prioridad, la más reciente. Es la base de los avisos que vendrán (temporizadores en la Fase 6, agentes
/// en la Fase 7): cada uno será una actividad con su prioridad, sin cambiar a las demás.
enum ActivityKind: Int, CaseIterable {
    /// Música sonando o en pausa: queda de fondo.
    case music = 10
    /// James habla con Capri (escucha, interpreta, ejecuta o responde): una interacción nunca se interrumpe.
    case conversation = 100

    var priority: Int { rawValue }
}

struct ActivityBoard {
    /// Actividades en curso y desde cuándo.
    private(set) var active: [ActivityKind: Date] = [:]

    mutating func set(_ kind: ActivityKind, _ isActive: Bool) {
        if !isActive {
            active[kind] = nil
        } else if active[kind] == nil {
            active[kind] = Date()
        }
    }

    func contains(_ kind: ActivityKind) -> Bool { active[kind] != nil }

    /// La que ocupa el notch, o nil si no hay ninguna.
    var foreground: ActivityKind? {
        active.max { a, b in (a.key.priority, a.value) < (b.key.priority, b.value) }?.key
    }
}
