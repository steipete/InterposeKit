import Foundation

#if !os(Linux)
import MachO.dyld
#endif

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

    /// Helper that stores hooks to a specific class and executes them once the class becomes available.
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
