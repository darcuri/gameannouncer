import SwiftUI

/// Stand-in for `@State`.
///
/// In this SDK `@State` is a compiler macro whose plugin (SwiftUIMacros) ships only with
/// Xcode, so builds with the Command Line Tools fail. `State` itself is still a regular
/// `DynamicProperty`; wrapping it in another `DynamicProperty` keeps SwiftUI's storage and
/// invalidation working the same way.
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    private let storage: State<Value>

    init(wrappedValue: Value) {
        storage = State(initialValue: wrappedValue)
    }

    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> { storage.projectedValue }
}
