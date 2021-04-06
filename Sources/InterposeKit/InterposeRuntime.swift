import Foundation

extension Method {
    var implementation: IMP {
        method_getImplementation(self)
    }

    var typeEncoding: UnsafePointer<Int8>? {
        method_getTypeEncoding(self)
    }

    var name: Selector {
        method_getName(self)
    }
}

/// Looks for an instance method in `klass`, without looking up the hierarchy.
func implementsExactClass(klass: AnyClass, selector: Selector) -> Bool {
    var methodCount: CUnsignedInt = 0
    guard let methodsInAClass = class_copyMethodList(klass, &methodCount) else { return false }
    defer { free(methodsInAClass) }
    for index in 0 ..< Int(methodCount) {
        let method = methodsInAClass[index]
        if method_getName(method) == selector {
            return true
        }
    }
    return false
}

struct InterposeClass: ModifyableClass {
    let `class`: AnyClass

    init(_ class: AnyClass) {
        self.`class` = `class`
    }
}

protocol ModifyableClass {
    var `class`: AnyClass { get }
    func add(selector: Selector, imp: IMP, encoding: UnsafePointer<Int8>?) throws
    @discardableResult func replace(method: Method, imp: IMP) throws  -> IMP
    @discardableResult func replace(selector: Selector, imp: IMP, encoding: UnsafePointer<Int8>?) throws -> IMP
    func implementsExact(selector: Selector) -> Bool
    func instanceMethod(_ selector: Selector) -> Method?
    func methodImplementation(_ selector: Selector) throws -> IMP
}

extension ModifyableClass {
    var superclass: AnyClass? {
        class_getSuperclass(`class`)
    }

    func add(selector: Selector, imp: IMP, encoding: UnsafePointer<Int8>?) throws {
        if !class_addMethod(`class`, selector, imp, encoding) {
            Interpose.log("Unable to add: -[\(`class`).\(selector)] IMP: \(imp)")
            throw InterposeError.unableToAddMethod(`class`, selector)
        }
    }

    @discardableResult func replace(method: Method, imp: IMP) throws -> IMP {
        try replace(selector: method.name, imp: imp, encoding: method.typeEncoding)
    }

    @discardableResult func replace(selector: Selector, imp: IMP, encoding: UnsafePointer<Int8>?) throws -> IMP {
        guard let imp = class_replaceMethod(`class`, selector, imp, encoding) else {
            throw InterposeError.unableToAddMethod(`class`, selector)
        }
        return imp
    }

    /// Looks for an instance method in this subclass, without looking up the hierarchy.
    func implementsExact(selector: Selector) -> Bool {
        implementsExactClass(klass: `class`, selector: selector)
    }

    func instanceMethod(_ selector: Selector) -> Method? {
        class_getInstanceMethod(`class`, selector)
    }

    func methodImplementation(_ selector: Selector) throws -> IMP {
        guard let imp = class_getMethodImplementation(`class`, selector) else {
            throw InterposeError.unknownError("Unable to get method implementation")
        }
        return imp
    }
}
