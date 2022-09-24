import Foundation

/// Container for AnyObject
public class AnyObjectContainer {
    public var object: AnyObject {
        fatalError("Always override")
    }
}

/// The container that hold a strong reference to the object
internal class StrongObjectContainer: AnyObjectContainer {
    override var object: AnyObject {
        _object
    }

    private let _object: AnyObject

    init(_ object: AnyObject) {
        self._object = object
    }
}

/// The container that hold a weak reference to the object
internal class WeakObjectContainer: AnyObjectContainer {
    override var object: AnyObject {
        guard let object = _object else { fatalError("Bad Access") }
        return object
    }

    private weak var _object: AnyObject?

    init(_ object: AnyObject) {
        self._object = object
    }
}

/// The container that hold an unowned reference to the object
internal class UnownedObjectContainer: AnyObjectContainer {
    override var object: AnyObject { _object }

    private unowned let _object: AnyObject

    init(_ object: AnyObject) {
        self._object = object
    }
}

extension AnyObjectContainer {
    /// Create a strong reference container
    public static func strong(_ object: AnyObject) -> AnyObjectContainer {
        StrongObjectContainer(object)
    }

    /// Create a weak reference container
    public static func weak(_ object: AnyObject) -> AnyObjectContainer {
        WeakObjectContainer(object)
    }

    /// Create an unowned reference container
    public static func unowned(_ object: AnyObject) -> AnyObjectContainer {
        UnownedObjectContainer(object)
    }
}
