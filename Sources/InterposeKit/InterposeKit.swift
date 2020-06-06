//
//  Interpose.swift
//  InterposeKit
//
//  Copyright © 2020 Peter Steinberger. All rights reserved.
//

import Foundation

#if !os(Linux)
import MachO.dyld
#endif

/// Helper to swizzle methods the right way, via replacing the IMP.
final public class Interpose {
    /// Stores swizzle tasks and executes them at once.
    public let `class`: AnyClass
    /// Lists all tasks for the current interpose class object.
    public private(set) var tasks: [Task] = []

    /// If Interposing is object-based, this is set.
    public let object: AnyObject?

    /// Initializes an instance of Interpose for a specific class.
    /// If `builder` is present, `apply()` is automatically called.
    public init(_ `class`: AnyClass, builder: ((Interpose) throws -> Void)? = nil) throws {
        self.class = `class`
        self.object = nil

        // Only apply if a builder is present
        if let builder = builder {
            try apply(builder)
        }
    }

    /// Initialize with a single object to interpose.
    public init(_ object: AnyObject, builder: ((Interpose) throws -> Void)? = nil) throws {
        self.object = object
        self.class = type(of: object)

        // Only apply if a builder is present
        if let builder = builder {
            try apply(builder)
        }
    }

    deinit {
        guard let validatableTasks = tasks as? [ValidatableTask] else { return }
        validatableTasks.forEach({ $0.cleanup() })
    }

    /// Hook an `@objc dynamic` instance method via selector name on the current class.
    @discardableResult public func hook(_ selName: String,
                                        _ implementation: (Task) -> Any) throws -> Task {
        try hook(NSSelectorFromString(selName), implementation)
    }

    /// Hook an `@objc dynamic` instance method via selector  on the current class.
    @discardableResult public func hook(_ selector: Selector,
                                        _ implementation: (Task) -> Any) throws -> Task {

        var task: ValidatableTask
        if let object = self.object {
            task = try ObjectTask(object: object, selector: selector, implementation: implementation)
        } else {
            task = try ClassTask(class: `class`, selector: selector, implementation: implementation)
        }
        tasks.append(task)
        return task
    }

    /// Apply all stored hooks.
    @discardableResult public func apply(_ task: ((Interpose) throws -> Void)? = nil) throws -> Interpose {
        try execute(task) { try $0.apply() }
    }

    /// Revert all stored hooks.
    @discardableResult public func revert(_ task: ((Interpose) throws -> Void)? = nil) throws -> Interpose {
        try execute(task, expectedState: .interposed) { try $0.revert() }
    }

    private func execute(_ task: ((Interpose) throws -> Void)? = nil,
                         expectedState: Interpose.State = .prepared,
                         executor: ((Task) throws -> Void)) throws -> Interpose {
        // Run pre-apply code first
        if let task = task {
            try task(self)
        }
        // Validate all tasks, stop if anything is not valid
        guard let validatableTasks = tasks as? [ValidatableTask], validatableTasks.allSatisfy({
            (try? $0.validate(expectedState: expectedState)) != nil
        }) else {
            throw Error.invalidState
        }
        // Execute all tasks
        try tasks.forEach(executor)
        return self
    }

    /// The list of errors while hooking a method.
    public enum Error: Swift.Error {
        /// The method couldn't be found. Usually happens for when you use stringified selectors that do not exist.
        case methodNotFound

        /// The implementation could not be found. Class must be in a weird state for this to happen.
        case nonExistingImplementation

        /// Someone else changed the implementation; reverting removed this implementation.
        /// This is bad, likely someone else also hooked this method. If you are in such a codebase, do not use revert.
        case unexpectedImplementation

        case failedToAllocateClassPair

        /// Can't revert or apply if already done so.
        case invalidState
    }

    /// The possible task states.
    public enum State: Equatable {
        /// The task is prepared to be interposed.
        case prepared

        /// The method has been successfully interposed.
        case interposed

        /// An error happened while interposing a method.
        case error(Interpose.Error)
    }
}

// MARK: Interpose Task

public protocol Task {
    /// The class this tasks operates on.
    var `class`: AnyClass { get }

    /// If Interposing is object-based, this is set.
    //var object: AnyObject? { get }

    /// The selector this tasks operates on.
    var selector: Selector { get }

    /// The original implementation is set once the swizzling is complete.
    var origIMP: IMP? { get }

    /// The replacement implementation is created on initialization time.
    var replacementIMP: IMP! { get }

    /// The state of the interpose operation.
    var state: Interpose.State { get }

    /// Apply the interpose hook.
    func apply() throws

    /// Revert the interpose hoook.
    func revert() throws

    /// Convenience to call the original implementation.
    func callAsFunction<U>(_ type: U.Type) -> U
}

public protocol ValidatableTask: Task {
    func validate(expectedState: Interpose.State) throws -> Method
    func cleanup()
}

// MARK: Logging

extension Interpose {
    /// Logging uses print and is minimal.
    public static var isLoggingEnabled = false

    /// Simple log wrapper for print.
    class func log(_ object: Any) {
        if isLoggingEnabled {
            print("[Interposer] \(object)")
        }
    }
}

// MARK: Interpose Class Load Watcher

extension Interpose {
    // Separate definitions to have more eleveant calling syntax when completion is not needed.

    /// Interpose a class once available. Class is passed via `classParts` string array.
    @discardableResult public class func whenAvailable(_ classParts: [String],
                                                       builder: @escaping (Interpose) throws -> Void) throws -> Waiter {
        try whenAvailable(classParts, builder: builder, completion: nil)
    }

    /// Interpose a class once available. Class is passed via `classParts` string array, with completion handler.
    @discardableResult public class func whenAvailable(_ classParts: [String],
                                                       builder: @escaping (Interpose) throws -> Void,
                                                       completion: (() -> Void)? = nil) throws -> Waiter {
        try whenAvailable(classParts.joined(), builder: builder, completion: completion)
    }

    /// Interpose a class once available. Class is passed via `className` string.
    @discardableResult public class func whenAvailable(_ className: String,
                                                       builder: @escaping (Interpose) throws -> Void) throws -> Waiter {
        try whenAvailable(className, builder: builder, completion: nil)
    }

    /// Interpose a class once available. Class is passed via `className` string, with completion handler.
    @discardableResult public class func whenAvailable(_ className: String,
                                                       builder: @escaping (Interpose) throws -> Void,
                                                       completion: (() -> Void)? = nil) throws -> Waiter {
        try Waiter(className: className, builder: builder, completion: completion)
    }

    /// Helper that stores tasks to a specific class and executes them once the class becomes available.
    public struct Waiter {
        fileprivate let className: String
        private var builder: ((Interpose) throws -> Void)?
        private var completion: (() -> Void)?

        /// Initialize waiter object.
        @discardableResult init(className: String,
                                builder: @escaping (Interpose) throws -> Void,
                                completion: (() -> Void)? = nil) throws {
            self.className = className
            self.builder = builder
            self.completion = completion

            // Immediately try to execute task. If not there, install waiter.
            if try tryExecute() == false {
                InterposeWatcher.append(waiter: self)
            }
        }

        func tryExecute() throws -> Bool {
            guard let `class` = NSClassFromString(className), let builder = self.builder else { return false }
            try Interpose(`class`).apply(builder)
            if let completion = self.completion {
                completion()
            }
            return true
        }
    }
}

// dyld C function cannot capture class context so we pack it in a static struct.
private struct InterposeWatcher {
    // Global list of waiters; can be multiple per class
    private static var globalWatchers: [Interpose.Waiter] = {
        // Register after Swift global registers to not deadlock
        DispatchQueue.main.async { InterposeWatcher.installGlobalImageLoadWatcher() }
        return []
    }()

    fileprivate static func append(waiter: Interpose.Waiter) {
        InterposeWatcher.globalWatcherQueue.sync {
            globalWatchers.append(waiter)
        }
    }

    // Register hook when dyld loads an image
    private static let globalWatcherQueue = DispatchQueue(label: "com.steipete.global-image-watcher")
    private static func installGlobalImageLoadWatcher() {
        _dyld_register_func_for_add_image { _, _ in
            InterposeWatcher.globalWatcherQueue.sync {
                // this is called on the thread the image is loaded.
                InterposeWatcher.globalWatchers = InterposeWatcher.globalWatchers.filter { waiter -> Bool in
                    do {
                        if try waiter.tryExecute() == false {
                            return true // only collect if this fails because class is not there yet
                        } else {
                            Interpose.log("\(waiter.className) was successful.")
                        }
                    } catch {
                        Interpose.log("Error while executing task: \(error).")
                        // We can't bubble up the throw into the C context.
                        #if DEBUG
                        // Instead of silently eating, it's better to crash in DEBUG.
                        fatalError("Error while executing task: \(error).")
                        #endif
                    }
                    return false
                }
            }
        }
    }
}

// MARK: Debug Helper

#if os(Linux)
// Linux is used to create Jazzy docs
/// :nodoc: Selector
public struct Selector {}
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
func imp_removeBlock(_ anImp: IMP) -> Bool { false }
#endif
