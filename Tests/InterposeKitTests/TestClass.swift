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
}

class TestSubclass: TestClass {
    override func sayHi() -> String {
        return super.sayHi() + testSubclass
    }

    override func doNothing() {
        super.doNothing()
    }
}
