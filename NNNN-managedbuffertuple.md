# Extend API for managing tail allocated buffers

* Proposal: [SE-NNNN](NNNN-managedbuffertuple.md)
* Authors: [Alexey Komnin](https://github.com/Interfere)
* Review Manager: TBD
* Status: **Awaiting review**

## Introduction

Some Swift intrinsics (`allocWithTailElems_{n}`) are widely used by Swift standard 
library to implement tail-allocated buffers, used by containers. Some of those are 
wrapped by publicly available operators and functions. `ManagedBuffer.create(minimumCapacity:)` 
class method is just a wrapper around call to allocWithTailElems_1 builtin function. 
It is possible to implement some containers, like Deque or linked-list using ManagedBuffer, 
but it is not enough if developer is going to implement advanced data structures 
like OrderedSet, LRU-cache or something more complex.

This proposal outlines a new API for managing tail allocated buffers.

Swift-evolution thread: [TBD](https://lists.swift.org/pipermail/swift-evolution/)

## Motivation

Collections in Swift are implemnted using tail-allocated buffers. A handful of 
intrinsics are available for developers of swift standard library to allocate and 
manage data stored in them. For example, the buffer, used by Array, is implemented 
with `allocWithTailElems_1<U>` routine, which is able to allocate contiguous buffer 
for `N` elements of type `U`. `Set` is implemented with `allocWithTailElems_3<T, U, V>` 
routine, which is able to allocate contiguous buffer, consisted of three areas for 
elements of types `T`, `U` and `V`.

Ordinary developer can't use these instrinsics. He is proposed to use `ManagedBuffer` 
instead, which is a simple wrapper over the single-area tail-allocated buffer. It uses 
`allocWithTailElems_1<U>` to allocate storage for elements of type U the same way the 
Array container does. Since, ManagedBuffer is a perfect choice for implementing containers 
based on single-area contiguous buffer, such as Array or Deque, there is no convenient way 
for implementing complex containers such as OrderedSet or LRU-cache. Instead, developer 
is forced to do lots of pointer arithmetic and reinvent multiple-area managed buffers.

## Proposed solution

This proposal introduces a new class ManagedBufferTuple and a list of traits for single and 
multiple areas cases. The traits are to keep all internal information about structure of the 
areas.

These changes make it simple to implement multi-area buffers as simple as single-area. Example:

```swift
class TwoAreasManagedBuffer<T, U>: ManagedBufferTuple<CustomHeader, TwoAreasManagedBufferTrait<T, U>> {
    static func create(minimumCapacity: Int) -> TwoAreasManagedBuffer<T, U> {
        let p = create(minimumCapacity1: minimumCapacity, minimumCapacity2: minimumCapacity) { buffer in
            return CustomHeader(capacity1: buffer.capacity1, capacity2: buffer.capacity2)
        }
        return unsafeDowncast(p, to: self)
    }
    
    private init(_doNotCall: ()) {
        fatalError()
    }
}

```

## Detailed Design

### ManagedBufferTuple

The standard library introduces new class `ManagedBufferTuple`. The base interface of the class 
is simple and minimalistic:

```swift
open class ManagedBufferTuple<Header, Trait : ManagedBufferTrait> {
     
  fileprivate final var traitAddress: UnsafeMutablePointer<Trait> {
    return UnsafeMutablePointer<Trait>(Builtin.addressof(&trait))
  }
  internal final var headerAddress: UnsafeMutablePointer<Header> {
    return UnsafeMutablePointer<Header>(Builtin.addressof(&header))
  }

  /// Call `body` with an `UnsafeMutablePointer` to the stored
  /// `Header`.
  ///
  /// - Note: This pointer is valid only for the duration of the
  ///   call to `body`.
  public final func withUnsafeMutablePointerToHeader<R>(
    _ body: (UnsafeMutablePointer<Header>) throws -> R) rethrows -> R

  /// The stored `Trait` instance.
  fileprivate final var trait: Trait

  /// The stored `Header` instance.
  ///
  /// During instance creation, in particular during
  /// `ManagedBufferTupleFactory.create`'s call to initialize, 
  /// `ManagedBufferTuple`'s `header` property is as-yet uninitialized, 
  /// and therefore reading the `header` property during `ManagedBufferTupleFactory.create` 
  /// is undefined.
  public final var header: Header
}

```

The class is parametrized with a `Header` and `Trait` types. `Trait` has to conform to 
abstract `ManagedBufferTrait` type constraint.

```swift
/// Abstract trait for instances ManagedBufferTuple class.
public protocol ManagedBufferTrait {}
```

### Traits

The standard library introduces a handful of traits. Each trait consists of type constraint 
and corresponding implementation. Type constraint is used for extensions of `ManagedBufferTuple`.

#### Single area trait

```swift
/// A trait for instances with a single storage for an array of `Element`.
public protocol _SingleAreaManagedBufferTrait : ManagedBufferTrait {
  associatedtype Element
}

public struct SingleAreaManagedBufferTrait<T> : _SingleAreaManagedBufferTrait {
  public typealias Element = T
}
```

Extension of ManagedBufferTuple defines interface for single area buffer.

```swift
public extension ManagedBufferTuple where Trait : _SingleAreaManagedBufferTrait {
  /// The actual number of elements that can be stored in this object.
  ///
  /// This header may be nontrivial to compute; it is usually a good
  /// idea to store this information in the "header" area when
  /// an instance is created.
  public final var capacity: Int

  /// Call `body` with an `UnsafeMutablePointer` to the `Element`
  /// storage.
  ///
  /// - Note: This pointer is valid only for the duration of the
  ///   call to `body`.
  public final func withUnsafeMutablePointerToElements<R>(
    _ body: (UnsafeMutablePointer<Trait.Element>) throws -> R) rethrows -> R

  /// Call `body` with `UnsafeMutablePointer`s to the stored `Header`
  /// and raw `Element` storage.
  ///
  /// - Note: These pointers are valid only for the duration of the
  ///   call to `body`.
  public final func withUnsafeMutablePointers<R>(
    _ body: (UnsafeMutablePointer<Header>, UnsafeMutablePointer<Trait.Element>) throws -> R) rethrows -> R
}
```

Method `create` is the only way to instantiate buffer and is a wrapper around `allocWithTailElems_1` routine.
```swift
public extension ManagedBufferTuple where Trait : _SingleAreaManagedBufferTrait {
  /// Create a new instance of ManagedBufferTuple with single area trait, 
  /// calling `factory` on the partially-constructed object to generate an 
  /// initial `Header`.
  public static func create(
    minimumCapacity: Int,
    makingHeaderWith factory: (
      ManagedBufferTuple<Header, Trait>) throws -> Header
  ) rethrows -> ManagedBufferTuple<Header, Trait> {

    let p = Builtin.allocWithTailElems_1(
         self,
         minimumCapacity._builtinWordValue, 
         Element.self)

    let initHeaderVal = try factory(p)
    p.headerAddress.initialize(to: initHeaderVal)
    // The _fixLifetime is not really needed, because p is used afterwards.
    // But let's be conservative and fix the lifetime after we use the
    // headerAddress.
    _fixLifetime(p) 
    return p
  }
}
```

The implementation for single area case follows the current implementation of `ManagedBuffer`. 
Hence, it would be possible to define it as
```swift
typealias ManagedBuffer<Header, Element> = ManagedBufferTuple<Header, SingleAreaManagedBufferTrait<Element>>
```

#### Two areas trait

```swift
/// A trait for instances with a single storage for an array of `Element`.
public protocol _TwoAreasManagedBufferTrait : ManagedBufferTrait {
  associatedtype Element1
  associatedtype Element2

  var count1: Int { get }
  init(count1: Int)
}

public struct TwoAreasManagedBufferTrait<T, U> : _TwoAreasManagedBufferTrait {
  public typealias Element1 = T
  public typealias Element2 = U

  public let count1: Int

  public init(count1: Int) {
    self.count1 = count1
  }
}
```

Corresponding extension:

```swift
public extension ManagedBufferTuple where Trait : _TwoAreasManagedBufferTrait {

  /// The actual number of elements that can be stored in the first buffer.
  public final var capacity1: Int

  /// The actual number of elements that can be stored in the second buffer.
  public final var capacity2: Int

  /// Call `body` with an `UnsafeMutablePointer` to the `Element1`
  /// storage.
  ///
  /// - Note: This pointer is valid only for the duration of the
  ///   call to `body`.
  public final func withUnsafeMutablePointerToFirstBuffer<R>(
    _ body: (UnsafeMutablePointer<Trait.Element1>) throws -> R) rethrows -> R

  /// Call `body` with an `UnsafeMutablePointer` to the `Element2`
  /// storage.
  ///
  /// - Note: This pointer is valid only for the duration of the
  ///   call to `body`.
  public final func withUnsafeMutablePointerToSecondBuffer<R>(
    _ body: (UnsafeMutablePointer<Trait.Element2>) throws -> R) rethrows -> R

  /// Call `body` with `UnsafeMutablePointer`s to the stored `Header`
  /// and raw `Element1` and `Element2` storages.
  ///
  /// - Note: These pointers are valid only for the duration of the
  ///   call to `body`.
  public final func withUnsafeMutablePointers<R>(
    _ body: (UnsafeMutablePointer<Header>, 
             UnsafeMutablePointer<Trait.Element1>, 
             UnsafeMutablePointer<Trait.Element2>) throws -> R
  ) rethrows -> R
}
```

And corresponding create method with ability to define minimalCapacity for each area:

```swift
public extension ManagedBufferTuple where Trait : _TwoAreasManagedBufferTrait {
  /// Create a new instance of ManagedBufferTuple with Pair trait, calling
  /// `factory` on the partially-constructed object to generate an initial
  /// `Header`
  public static func create(
    minimumCapacity1 capacity1: Int,
    minimumCapacity2 capacity2: Int,
    makingHeaderWith factory: (
      ManagedBufferTuple<Header, Trait>) throws -> Header
  ) rethrows -> ManagedBufferTuple<Header, Trait> {

    let p = Builtin.allocWithTailElems_2(
         self,
         capacity1._builtinWordValue, Element1.self,
         capacity2._builtinWordValue, Element2.self)

    let trait = Trait(count1: capacity1)
    p.traitAddress.initialize(to: trait)
    let initHeaderVal = try factory(p)
    p.headerAddress.initialize(to: initHeaderVal)
    // The _fixLifetime is not really needed, because p is used afterwards.
    // But let's be conservative and fix the lifetime after we use the
    // headerAddress.
    _fixLifetime(p) 
    return p
  }
}
```

#### Three areas trait

All multiple areas traits and extensions are similar. In three areas case create method is 
a wrapper around `allocWithTailElems_3` routine. Source code is omitted.

Traits is a flexible approach. It provides a convenient way of extending tail-allocated 
buffers with a minimal impact on existing code. In future, if there is a need, it would be 
easy to add more traits to support 4-, 5-areas.

Moreover, user is free to implement its own traits and extensions for any specific case.

Proof of concept is available at [ManagedBufferTuple.swift](https://github.com/Interfere/ManagedBufferTuple/blob/master/ManagedBufferTuple.swift)


## Source compatibility

It's an additive feature. There is no impact on existing code. No changes in syntax or behavior.


## Effect on API resilience

The feature can be added without breaking ABI. 


## Alternatives considered

1. Add `ManagedBuffer2` and `ManagedBuffer3` classes
2. Make `allocWithTailElems_{n}` routines available for all developers
