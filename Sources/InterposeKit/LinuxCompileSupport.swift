import Foundation

// Linux is used to create Jazzy docs
#if os(Linux)

/// :nodoc: Selector
public struct Selector {
    init(_ name: String) {}
}
/// :nodoc: IMP
public struct IMP: Equatable {}
/// :nodoc: Method
public struct Method {}
func NSSelectorFromString(_ aSelectorName: String) -> Selector { Selector() }
func class_getInstanceMethod(_ cls: AnyClass?, _ name: Selector) -> Method? { return nil }
// swiftlint:disable:next line_length
func class_replaceMethod(_ cls: AnyClass?, _ name: Selector, _ imp: IMP, _ types: UnsafePointer<Int8>?) -> IMP? { IMP() }
// swiftlint:disable:next identifier_name
func method_getTypeEncoding(_ m: Method) -> UnsafePointer<Int8>? { return nil }
// swiftlint:disable:next identifier_name
func _dyld_register_func_for_add_image(_ func: (@convention(c) (UnsafePointer<Int8>?, Int) -> Void)!) {}
func imp_implementationWithBlock(_ block: Any) -> IMP { IMP() }
func imp_getBlock(_ anImp: IMP) -> Any? { return nil }
func imp_removeBlock(_ anImp: IMP) -> Bool { false }
class NSError : NSObject {}
public typealias NSErrorPointer = AutoreleasingUnsafeMutablePointer<NSError?>?
extension NSObject {
open func value(forKey key: String) -> Any?
}
/// :nodoc: objc_AssociationPolicy
public enum objc_AssociationPolicy : UInt {
    case OBJC_ASSOCIATION_ASSIGN = 0
    case OBJC_ASSOCIATION_RETAIN_NONATOMIC = 1
    case OBJC_ASSOCIATION_COPY_NONATOMIC = 3
    case OBJC_ASSOCIATION_RETAIN = 769
    case OBJC_ASSOCIATION_COPY = 771
}
public func objc_setAssociatedObject(_ object: Any, _ key: UnsafeRawPointer, _ value: Any?, _ policy: objc_AssociationPolicy) {}
public func objc_getAssociatedObject(_ object: Any, _ key: UnsafeRawPointer) -> Any? { return nil }
#endif
