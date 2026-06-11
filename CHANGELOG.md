## Master

##### Breaking

* None.

##### Enhancements

* None.

##### Bug Fixes

* Preserve trampoline argument registers in code-coverage builds.
* Preserve object-hook super trampolines in optimized Release builds, fixing https://github.com/steipete/InterposeKit/issues/29. Thanks to [@Thomvis](https://github.com/Thomvis).
* Preserve floating-point arguments when object hooks invoke original methods on arm64. Thanks to [@ishutinvv](https://github.com/ishutinvv).
* Run class-availability hooks after Objective-C loads a new image, fixing https://github.com/steipete/InterposeKit/issues/26.

## 0.01

##### Breaking

* Swift 5.2 or later is required to build InterposeKit.  
  [Peter Steinberger](https://github.com/steipete)

##### Enhancements

* Initial Release.

##### Bug Fixes

* None.
