import Foundation

/// `NSInvocation` is not directly accessible in Swift so we use a protocol.
@objc internal protocol ObjCInvocation {
    @objc(setSelector:)
    func setSelector(_ selector: Selector)

    @objc(selector)
    func selector() -> Selector

    @objc(target)
    var objcTarget: AnyObject { get }

    @objc(methodSignature)
    var objcMethodSignature: AnyObject { get }

    @objc(getArgument:atIndex:)
    func getArgument(_ argumentLocation: UnsafeMutableRawPointer, atIndex idx: Int)

    @objc(setArgument:atIndex:)
    func setArgument(_ argumentLocation: UnsafeMutableRawPointer, atIndex idx: Int)

    @objc(invoke)
    func invoke()

    @objc(invokeWithTarget:)
    func invoke(target: AnyObject)

    @objc(invocationWithMethodSignature:)
    static func invocation(methodSignature: AnyObject) -> AnyObject
}
