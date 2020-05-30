//
//  Interpose.swift
//  InterposeKit
//
//  Created by Peter Steinberger on 07.05.20.
//  Copyright © 2020 PSPDFKit GmbH. All rights reserved.
//

import Foundation

#if !os(Linux)
import MachO.dyld
#else
// Linux is used to create Jazzy docs
final public class Selector {}
final public class IMP {}
final public class Method {}
#endif

/// Helper to swizzle methods the right way, via replacing the IMP.
final public class Interpose {
    /// Stores swizzle tasks and executes them at once.
    public let `class`: AnyClass
    /// Lists all tasks for the current interpose class object.
    public private(set) var tasks: [Task] = []

    /// Initializes an instance of Interpose for a specific class.
    /// If `builder` is present, `apply()` is automatically called.
    public init(_ `class`: AnyClass, builder: ((Interpose) throws -> Void)? = nil) throws {
        self.class = `class`

        // Only apply if a builder is present
        if let builder = builder {
            try apply(builder)
        }
    }

    @discardableResult public func hook(_ selName: String,
                                        _ implementation: (Task) -> Any) throws -> Task {
        try hook(NSSelectorFromString(selName), implementation)
    }

    /// Interpose a method instance on the class.
    @discardableResult public func hook(_ selector: Selector,
                                        _ implementation: (Task) -> Any) throws -> Task {
        let task = try Task(class: `class`, selector: selector, implementation: implementation)
        tasks.append(task)
        return task
    }

    /// Apply all stored tasks
    @discardableResult public func apply(_ task: ((Interpose) throws -> Void)? = nil) throws -> Interpose {
        try execute(task) { try $0.apply() }
    }

    @discardableResult public func revert(_ task: ((Interpose) throws -> Void)? = nil) throws -> Interpose {
        try execute(task, expectedState: .interposed) { try $0.revert() }
    }

    private func execute(_ task: ((Interpose) throws -> Void)? = nil,
                         expectedState: Task.State = .prepared,
                         executor: ((Task) throws -> Void)) throws -> Interpose {
        // Run pre-apply code first
        if let task = task {
            try task(self)
        }
        // Validate all tasks, stop if anything is not valid
        guard tasks.allSatisfy({
            (try? $0.validate(expectedState: expectedState)) != nil
        }) else {
            throw InterposeError.invalidState
        }
        // Execute all tasks
        try tasks.forEach(executor)
        return self
    }

    public enum InterposeError: Error {
        /// The method couldn't be found. Usually happens for when you use stringified selectors that do not exist.
        case methodNotFound

        /// The implementation could not be found. Class must be in a weird state for this to happen.
        case nonExistingImplementation

        /// Someone else changed the implementation; reverting removed this implementation.
        /// This is bad, likely someone else also hooked this method. If you are in such a codebase, do not use revert.
        case unexpectedImplementation

        /// Can't revert or apply if already done so.
        case invalidState
    }
}

// MARK: Interpose Task Logic

extension Interpose {
    /// Instance methods only for now
    final public class Task {
        /// The class this tasks operates on
        public let `class`: AnyClass

        /// The selector this tasks operates on
        public let selector: Selector

        /// The original implementation is set once the swizzling is complete
        public private(set) var origIMP: IMP? // fetched at apply time, changes late, thus class requirement

        /// The replacement implementation is created on initialization time.
        public private(set) var replacementIMP: IMP! // else we validate init order

        /// The state of the interpose operation.
        public private(set) var state = State.prepared

        public enum State: Equatable {
            case prepared
            case interposed
            case error(InterposeError)
        }

        /// Initialize a new task to interpose an instance method.
        public init(`class`: AnyClass, selector: Selector, implementation: (Task) -> Any) throws {
            self.selector = selector
            self.class = `class`
            // Check if method exists
            try validate()
            #if !os(Linux)
            replacementIMP = imp_implementationWithBlock(implementation(self))
            #endif
        }

        /// Validate that the selector exists on the active class
        @discardableResult func validate(expectedState: State = .prepared) throws -> Method {
            guard let method = class_getInstanceMethod(`class`, selector) else { throw InterposeError.methodNotFound }
            guard state == expectedState else { throw InterposeError.invalidState }
            return method
        }

        /// Apply the implementation change
        public func apply() throws {
            try execute(newState: .interposed) { try replaceImplementation() }
        }

        public func revert() throws {
            try execute(newState: .prepared) { try resetImplementation() }
        }

        private func execute(newState: State, task: () throws -> Void) throws {
            do {
                try task()
                state = newState
            } catch let error as InterposeError {
                state = .error(error)
                throw error
            }
        }

        private func replaceImplementation() throws {
            let method = try validate()
            origIMP = class_replaceMethod(`class`, selector, replacementIMP, method_getTypeEncoding(method))
            guard origIMP != nil else { throw InterposeError.nonExistingImplementation }
            Interpose.log("Swizzled -[\(`class`).\(selector)] IMP: \(origIMP!) -> \(replacementIMP!)")
        }

        private func resetImplementation() throws {
            let method = try validate(expectedState: .interposed)
            precondition(origIMP != nil)
            let previousIMP = class_replaceMethod(`class`, selector, origIMP!, method_getTypeEncoding(method))
            guard previousIMP == replacementIMP else { throw InterposeError.unexpectedImplementation }
            Interpose.log("Restored -[\(`class`).\(selector)] IMP: \(origIMP!)")
        }

        /// Convenience to call the original implementation
        public func callAsFunction<U>(_ type: U.Type) -> U {
            unsafeBitCast(origIMP, to: type)
        }
    }
}

// MARK: Logging

extension Interpose {
    /// Logging uses print and is minimal.
    public static var isLoggingEnabled = true

    /// Simply log wrapper for print
    fileprivate class func log(_ object: Any) {
        if isLoggingEnabled {
            print("[Interposer] \(object)")
        }
    }
}

// MARK: Interpose Class Loadeer Watcher

extension Interpose {
    // Separate definitions to have more eleveant calling syntax when completion is not needed.
    @discardableResult public class func whenAvailable(_ classParts: [String],
                                                       builder: @escaping (Interpose) throws -> Void) throws -> Waiter {
        try whenAvailable(classParts, builder: builder, completion: nil)
    }

    @discardableResult public class func whenAvailable(_ classParts: [String],
                                                       builder: @escaping (Interpose) throws -> Void,
                                                       completion: (() -> Void)? = nil) throws -> Waiter {
        try whenAvailable(classParts.joined(), builder: builder, completion: completion)
    }

    @discardableResult public class func whenAvailable(_ className: String,
                                                       builder: @escaping (Interpose) throws -> Void) throws -> Waiter {
        try Waiter(className: className, builder: builder, completion: nil)
    }

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

        @discardableResult public init(className: String,
                                       builder: @escaping (Interpose) throws -> Void,
                                       completion: (() -> Void)? = nil) throws {
            self.className = className
            self.builder = builder
            self.completion = completion

            // Immediately try to execute task. If not there, install waiter.
            if try tryExecute() == false {
                InterposeWatcher.globalWatchers.append(self)
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
    fileprivate static var globalWatchers: [Interpose.Waiter] = {
        // Register after Swift global registers to not deadlock
        DispatchQueue.main.async { InterposeWatcher.installGlobalImageLoadWatcher() }
        return []
    }()

    // Register hook when dyld loads an image
    private static let globalWatcherQueue = DispatchQueue(label: "com.steipete.global-image-watcher")
    private static func installGlobalImageLoadWatcher() {
        _dyld_register_func_for_add_image { _, _ in
            InterposeWatcher.globalWatcherQueue.sync {
                // this is called on the thread the image is loaded.
                InterposeWatcher.globalWatchers = InterposeWatcher.globalWatchers.filter { (waiter) -> Bool in
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

#if DEBUG
extension Interpose.Task: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "\(selector) -> \(String(describing: origIMP))"
    }
}
#endif
