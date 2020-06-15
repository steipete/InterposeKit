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
#endif
