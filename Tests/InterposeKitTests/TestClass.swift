import Foundation

let testClassHi = "Hi from TestClass!"
let testSwizzleAddition = " and Interpose"
let testSubclass = "Subclass is here!"

class TestClass: NSObject {
    @objc dynamic func sayHi() -> String {
        print(testClassHi)
        return testClassHi
    }

    @objc dynamic func doNothing() { }

    @objc dynamic func returnInt() -> Int {
        7
    }
}

class TestSubclass: TestClass {
    override func sayHi() -> String {
        return super.sayHi() + testSubclass
    }
}
