//
//  NSObject+KVOWrapper.swift
//
//
//  Created by Wang Ya on 12/27/20.
//  Copyright © 2020 Yanni. All rights reserved.
//

import Foundation
import _ExceptionCatcher

extension NSObject {
    func wrapKVOIfNeeded(selector: Selector) throws {
        if kvoObserver == nil {
            kvoObserver = KVOObserver(target: self)
        }
        guard let KVOedClass = ObjectiveC.object_getClass(self) else {
            throw InterposeError.unknownError("wrapKVOIfNeeded: \(self), selector: \(NSStringFromSelector(selector))")
        }
        if getMethodWithoutSearchingSuperClasses(targetClass: KVOedClass, selector: selector) == nil,
           let propertyName = try getKVOName(setter: selector) {
            guard let observer = kvoObserver else {
                throw InterposeError.unknownError("wrapKVOIfNeeded: \(self), selector: \(NSStringFromSelector(selector))")
            }
            addObserver(observer, forKeyPath: propertyName, options: .new, context: &RealObserver.context)
            removeObserver(observer, forKeyPath: propertyName, context: &RealObserver.context)
        }
    }
    
    func isSupportedKVO() throws -> Bool {
        var isSupportedKVOAssociatedKey = 0
        if let isSupportedKVO = objc_getAssociatedObject(self, &isSupportedKVOAssociatedKey) as? Bool {
              return isSupportedKVO
          }
        guard let isaClass = ObjectiveC.object_getClass(self) else {
            throw InterposeError.unknownError("isSupportedKVO: \(self)")
        }
        let result: Bool
        
        if let actualClass = Interpose.checkObjectPosingAsDifferentClass(self), Interpose.isKVORuntimeGeneratedClass(actualClass) {
            result = true
        } else {
            do {
                try NSObject.catchException {
                    addObserver(RealObserver.shared, forKeyPath: RealObserver.keyPath, options: .new, context: &RealObserver.context)
                }
                defer {
                    removeObserver(RealObserver.shared, forKeyPath: RealObserver.keyPath, context: &RealObserver.context)
                }
                guard let isaClassNew = ObjectiveC.object_getClass(self) else {
                    throw InterposeError.unknownError("isSupportedKVO: \(self)")
                }
                result = isaClass != isaClassNew
            } catch {
                result = false
            }
        }
        objc_setAssociatedObject(self, &isSupportedKVOAssociatedKey, result, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        return result
    }
    
    fileprivate func getKVOName(setter: Selector) throws -> String? {
        let setterName = NSStringFromSelector(setter)
        guard setterName.hasPrefix("set") && setterName.hasSuffix(":") else {
            return nil
        }
        let propertyNameWithUppercase = String(setterName.dropFirst("set".count).dropLast(":".count))
        guard let firstCharacter = propertyNameWithUppercase.first else {
            return nil
        }
        let firstCharacterLowercase = firstCharacter.lowercased()
        let propertyName = firstCharacterLowercase + propertyNameWithUppercase.dropFirst()
        guard let baseClass = ObjectiveC.object_getClass(self) else {
            throw InterposeError.unknownError("getKVOName: \(self), setter: \(NSStringFromSelector(setter))")
        }
        if let property = class_getProperty(baseClass, propertyName) {
            return String.init(cString: property_getName(property))
        }
        if let property = class_getProperty(baseClass, propertyNameWithUppercase) {
            return String.init(cString: property_getName(property))
        }
        if responds(to: NSSelectorFromString(propertyName)) {
            return propertyName
        }
        if responds(to: NSSelectorFromString(propertyNameWithUppercase)) {
            return propertyNameWithUppercase
        }
        if responds(to: NSSelectorFromString("is" + propertyNameWithUppercase)) {
            return propertyName
        }
        return nil
    }
    
    fileprivate var kvoObserver: KVOObserver? {
        get {
            var swiftHookObserverAssociatedKey = 0
            return objc_getAssociatedObject(self, &swiftHookObserverAssociatedKey) as? KVOObserver
        }
        set {
            var swiftHookObserverAssociatedKey = 0
            objc_setAssociatedObject(self, &swiftHookObserverAssociatedKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    fileprivate class KVOObserver: NSObject {
        private unowned(unsafe) let target: NSObject
        
        init(target: NSObject) {
            self.target = target
            super.init()
            target.addObserver(RealObserver.shared, forKeyPath: RealObserver.keyPath, options: .new, context: &RealObserver.context)
        }
        
        deinit {
            self.target.removeObserver(RealObserver.shared, forKeyPath: RealObserver.keyPath, context: &RealObserver.context)
        }
    }
}

fileprivate class RealObserver: NSObject {
    nonisolated(unsafe) static let shared = RealObserver()
    static let keyPath = "kvoPrivateProperty"
    nonisolated(unsafe) static var context = 0
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath != Self.keyPath else { return }
        super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
    }
}

fileprivate func getMethodWithoutSearchingSuperClasses(targetClass: AnyClass, selector: Selector) -> Method? {
    var length: UInt32 = 0
    let firstMethod = withUnsafeMutablePointer(to: &length) { (pointer) -> UnsafeMutablePointer<Method>? in
        class_copyMethodList(targetClass, pointer)
    }
    defer {
        free(firstMethod)
    }
    let bufferPointer = UnsafeBufferPointer.init(start: firstMethod, count: Int(length))
    for method in bufferPointer where method_getName(method) == selector {
        return method
    }
    return nil
}
