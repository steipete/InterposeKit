import Foundation

// Linux is used to create Jazzy docs
#if os(Linux)
/// :nodoc: Selector
public struct Selector: Equatable {
    var name: String?
    init(_ name: String) { self.name = name }
}
/// :nodoc: IMP
public struct IMP: Equatable {}
/// :nodoc: Method
public struct Method {}
func NSSelectorFromString(_ aSelectorName: String) -> Selector { Selector("") }
func class_getInstanceMethod(_ cls: AnyClass?, _ name: Selector) -> Method? { return nil }
func class_getMethodImplementation(_ cls: AnyClass?, _ name: Selector) -> IMP? { return nil }
func class_replaceMethod(_ cls: AnyClass?, _ name: Selector,
                         _ imp: IMP, _ types: UnsafePointer<Int8>?) -> IMP? { IMP() }
func class_addMethod(_ cls: AnyClass?, _ name: Selector,
                     _ imp: IMP, _ types: UnsafePointer<Int8>?) -> Bool { return false }
func class_copyMethodList(_ cls: AnyClass?,
                          _ outCount: UnsafeMutablePointer<UInt32>?) -> UnsafeMutablePointer<Method>? { return nil }
func object_getClass(_ obj: Any?) -> AnyClass? { return nil }
@discardableResult func object_setClass(_ obj: Any?, _ cls: AnyClass) -> AnyClass? { return nil }
func method_getName(_ method: Method) -> Selector { Selector("") }
func class_getSuperclass(_ cls: AnyClass?) -> AnyClass? { return nil }
func method_getTypeEncoding(_ method: Method) -> UnsafePointer<Int8>? { return nil }
func method_getImplementation(_ method: Method) -> IMP { IMP() }
// swiftlint:disable:next identifier_name
func _dyld_register_func_for_add_image(_ func:
    (@convention(c) (UnsafePointer<Int8>?, Int) -> Void)!) {}
func objc_allocateClassPair(_ superclass: AnyClass?,
                            _ name: UnsafePointer<Int8>,
                            _ extraBytes: Int) -> AnyClass? { return nil }
func objc_registerClassPair(_ cls: AnyClass) {}
func objc_getClass(_: UnsafePointer<Int8>!) -> Any! { return nil }
func imp_implementationWithBlock(_ block: Any) -> IMP { IMP() }
func imp_getBlock(_ anImp: IMP) -> Any? { return nil }
@discardableResult func imp_removeBlock(_ anImp: IMP) -> Bool { false }
@objc class NSError: NSObject {}
// AutoreleasingUnsafeMutablePointer is not available on Linux.
typealias NSErrorPointer = UnsafeMutablePointer<NSError?>?
extension NSObject {
    /// :nodoc: value
    open func value(forKey key: String) -> Any? { return nil }
}
/// :nodoc: objc_AssociationPolicy
// swiftlint:disable:next type_name
enum objc_AssociationPolicy: UInt {
    // swiftlint:disable:next identifier_name
    case OBJC_ASSOCIATION_ASSIGN = 0
    // swiftlint:disable:next identifier_name
    case OBJC_ASSOCIATION_RETAIN_NONATOMIC = 1
    // swiftlint:disable:next identifier_name
    case OBJC_ASSOCIATION_COPY_NONATOMIC = 3
    // swiftlint:disable:next identifier_name
    case OBJC_ASSOCIATION_RETAIN = 769
    // swiftlint:disable:next identifier_name
    case OBJC_ASSOCIATION_COPY = 771
}
func objc_setAssociatedObject(_ object: Any, _ key: UnsafeRawPointer,
                              _ value: Any?, _ policy: objc_AssociationPolicy) {}
func objc_getAssociatedObject(_ object: Any,
                              _ key: UnsafeRawPointer) -> Any? { return nil }
#endif
