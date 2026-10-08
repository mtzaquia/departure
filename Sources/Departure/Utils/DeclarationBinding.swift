/// A conflicting key remains present so lookup cannot fall back to another scope.
enum DeclarationBinding<Value> {
    case declared(Value)
    case conflict

    var declaration: Value? {
        if case let .declared(value) = self { return value }
        return nil
    }

    func map<Output>(_ transform: (Value) -> Output) -> DeclarationBinding<Output> {
        switch self {
        case .declared(let value): .declared(transform(value))
        case .conflict: .conflict
        }
    }
}

extension DeclarationBinding: Sendable where Value: Sendable {}
