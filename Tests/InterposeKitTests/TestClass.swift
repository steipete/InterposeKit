import Foundation
import QuartzCore

let testClassHi = "Hi from TestClass!"
let testString = " and Interpose"
let testString2 = " testString2"
let testSubclass = "Subclass is here!"

public func ==(lhs: CATransform3D, rhs: CATransform3D) -> Bool {
    return CATransform3DEqualToTransform(lhs, rhs)
}

extension CATransform3D: Equatable { }

public extension CATransform3D {

    // swiftlint:disable:next identifier_name
    func translated(x: CGFloat = 0, y: CGFloat = 0, z: CGFloat = 0) -> CATransform3D {
        return CATransform3DTranslate(self, x, y, z)
    }

    var inverted: CATransform3D {
        return CATransform3DInvert(self)
    }
}

class TestClass: NSObject {

    @objc dynamic var age: Int = 1
    @objc dynamic var name: String = "Tim Apple"

    @objc dynamic func sayHi() -> String {
        print(testClassHi)
        return testClassHi
    }

    @objc dynamic func doNothing() { }

    @objc dynamic func doubleString(string: String) -> String {
        string + string
    }

    @objc dynamic func returnInt() -> Int {
        7
    }

    @objc dynamic func calculate(var1: Int, var2: Int, var3: Int) -> Int {
        var1 + var2 + var3
    }

    @objc dynamic func calculate2(var1: Int, var2: Int, var3: Int, var4: Int, var5: Int, var6: Int) -> Int {
        var1 + var2 + var3 + var4 + var5 + var6
    }

    // This requires _objc_msgSendSuper_stret on x64, returns a large struct
    @objc dynamic func invert3DTransform(_ input: CATransform3D) -> CATransform3D {
        input.inverted
    }
}

class TestSubclass: TestClass {
    override func sayHi() -> String {
        return super.sayHi() + testSubclass
    }

    override func doNothing() {
        super.doNothing()
    }
}
