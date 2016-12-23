//===--- ManagedBufferTuple.swift - variable-sized buffer of aligned memory ----===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2016 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// TODO: replace with SwiftShims
import Swift
import SwiftShims

/// Abstract trait for instances ManagedBufferTuple class.
public protocol ManagedBufferTrait {}

/// A trait for instances with a single storage for an array of `Element`.
public protocol UnitManagedBufferTrait : ManagedBufferTrait {
  associatedtype Element
}

/// A trait for instances with a pair of storages of types (`Element1`, `Element2`)
public protocol PairManagedBufferTrait : ManagedBufferTrait {
  associatedtype Element1
  associatedtype Element2

  var count1: Int { get }
}

/// A trait for instances with a triple of storages of types (`Element1`, `Element2`, `Element3`)
public protocol TripleManagedBufferTrait : ManagedBufferTrait {
  associatedtype Element1
  associatedtype Element2
  associatedtype Element3

  var count1: Int { get }
  var count2: Int { get }
}

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
    _ body: (UnsafeMutablePointer<Header>) throws -> R
  ) rethrows -> R {
    defer { _fixLifetime(self) }
    return try body(headerAddress)
  }

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

  //===--- internal/private API -------------------------------------------===//

  /// Make ordinary initialization unavailable
  internal init(_doNotCallMe: ()) {
    _sanityCheckFailure("Only initialize these by calling create")
  }
}

/// TODO: put some explanations here
public extension ManagedBufferTuple where Trait : UnitManagedBufferTrait {
  typealias Element = Trait.Element
  /// The actual number of elements that can be stored in this object.
  ///
  /// This header may be nontrivial to compute; it is usually a good
  /// idea to store this information in the "header" area when
  /// an instance is created.
  public final var capacity: Int {
    let storageAddr = UnsafeMutableRawPointer(Builtin.bridgeToRawPointer(self))
    let endAddr = storageAddr + _swift_stdlib_malloc_size(storageAddr)
    let realCapacity = endAddr.assumingMemoryBound(to: Element.self) -
      firstElementAddress
    return realCapacity
  }

  internal final var firstElementAddress: UnsafeMutablePointer<Element> {
    return UnsafeMutablePointer(Builtin.projectTailElems(self,
                                                         Element.self))
  }

  /// Call `body` with an `UnsafeMutablePointer` to the `Element`
  /// storage.
  ///
  /// - Note: This pointer is valid only for the duration of the
  ///   call to `body`.
  public final func withUnsafeMutablePointerToElements<R>(
    _ body: (UnsafeMutablePointer<Element>) throws -> R
  ) rethrows -> R {
    defer { _fixLifetime(self) }
    return try body(firstElementAddress)
  }

  /// Call `body` with `UnsafeMutablePointer`s to the stored `Header`
  /// and raw `Element` storage.
  ///
  /// - Note: These pointers are valid only for the duration of the
  ///   call to `body`.
  public final func withUnsafeMutablePointers<R>(
    _ body: (UnsafeMutablePointer<Header>, UnsafeMutablePointer<Element>) throws -> R
  ) rethrows -> R {
    defer { _fixLifetime(self) }
    return try body(headerAddress, firstElementAddress)
  }
}

/// TODO: put some explanation here
public extension ManagedBufferTuple where Trait : PairManagedBufferTrait {
  typealias Element1 = Trait.Element1
  typealias Element2 = Trait.Element2
  /// The actual number of elements that can be stored in the first buffer.
  public final var capacity1: Int {
    return trait.count1
  }

  /// The actual number of elements that can be stored in the second buffer.
  public final var capacity2: Int {
    let storageAddr = UnsafeMutableRawPointer(Builtin.bridgeToRawPointer(self))
    let endAddr = storageAddr + _swift_stdlib_malloc_size(storageAddr)
    let realCapacity = endAddr.assumingMemoryBound(to: Element2.self) -
      secondBufferAddress
    return realCapacity
  }

  internal final var firstBufferAddress: UnsafeMutablePointer<Element1> {
    return UnsafeMutablePointer(Builtin.projectTailElems(self,
                                                         Element1.self))
  }
  internal final var secondBufferAddress: UnsafeMutablePointer<Element2> {
    return UnsafeMutablePointer(Builtin.getTailAddr_Word(
                                  Builtin.projectTailElems(self,
                                                           Element1.self),
                                  capacity1._builtinWordValue, 
                                  Element1.self,
                                  Element2.self)
           )
  }

  /// Call `body` with an `UnsafeMutablePointer` to the `Element1`
  /// storage.
  ///
  /// - Note: This pointer is valid only for the duration of the
  ///   call to `body`.
  public final func withUnsafeMutablePointerToFirstBuffer<R>(
    _ body: (UnsafeMutablePointer<Element1>) throws -> R
  ) rethrows -> R {
    defer { _fixLifetime(self) }
    return try body(firstBufferAddress)
  }
  /// Call `body` with an `UnsafeMutablePointer` to the `Element2`
  /// storage.
  ///
  /// - Note: This pointer is valid only for the duration of the
  ///   call to `body`.
  public final func withUnsafeMutablePointerToSecondBuffer<R>(
    _ body: (UnsafeMutablePointer<Element2>) throws -> R
  ) rethrows -> R {
    defer { _fixLifetime(self) }
    return try body(secondBufferAddress)
  }

  /// Call `body` with `UnsafeMutablePointer`s to the stored `Header`
  /// and raw `Element1` and `Element2` storages.
  ///
  /// - Note: These pointers are valid only for the duration of the
  ///   call to `body`.
  public final func withUnsafeMutablePointers<R>(
    _ body: (UnsafeMutablePointer<Header>, UnsafeMutablePointer<Element1>, UnsafeMutablePointer<Element2>) throws -> R
  ) rethrows -> R {
    defer { _fixLifetime(self) }
    return try body(headerAddress, firstBufferAddress, secondBufferAddress)
  }
}

/// TODO: put some explanation here
public extension ManagedBufferTuple where Trait : TripleManagedBufferTrait {
  typealias Element3 = Trait.Element3
  /// The actual number of elements that can be stored in the first buffer.
  public final var capacity1: Int {
    return trait.count1
  }

  /// The actual number of elements that can be stored in the second buffer.
  public final var capacity2: Int {
    return trait.count2
  }

  /// The actual number of elements that can be stored in the third buffer.
  public final var capacity3: Int {
    let storageAddr = UnsafeMutableRawPointer(Builtin.bridgeToRawPointer(self))
    let endAddr = storageAddr + _swift_stdlib_malloc_size(storageAddr)
    let realCapacity = endAddr.assumingMemoryBound(to: Element3.self) -
      thirdBufferAddress
    return realCapacity
  }

  internal final var firstBufferAddress: UnsafeMutablePointer<Element1> {
    return UnsafeMutablePointer(Builtin.projectTailElems(self,
                                                         Element1.self))
  }
  internal final var secondBufferAddress: UnsafeMutablePointer<Element2> {
    let firstBufferAddr = Builtin.projectTailElems(self, Element1.self)
    return UnsafeMutablePointer(Builtin.getTailAddr_Word(firstBufferAddr,
                                  capacity1._builtinWordValue, 
                                  Element1.self,
                                  Element2.self)
           )
  }
  internal final var thirdBufferAddress: UnsafeMutablePointer<Element3> {
    let firstBufferAddr = Builtin.projectTailElems(self, Element1.self)
    let secondBufferAddr = Builtin.getTailAddr_Word(firstBufferAddr,
                                  capacity1._builtinWordValue, 
                                  Element1.self,
                                  Element2.self)
    return UnsafeMutablePointer(Builtin.getTailAddr_Word(secondBufferAddr,
                                  capacity2._builtinWordValue, 
                                  Element2.self,
                                  Element3.self)
           )
  }

  /// Call `body` with an `UnsafeMutablePointer` to the `Element1`
  /// storage.
  ///
  /// - Note: This pointer is valid only for the duration of the
  ///   call to `body`.
  public final func withUnsafeMutablePointerToFirstBuffer<R>(
    _ body: (UnsafeMutablePointer<Element1>) throws -> R
  ) rethrows -> R {
    defer { _fixLifetime(self) }
    return try body(firstBufferAddress)
  }
  /// Call `body` with an `UnsafeMutablePointer` to the `Element2`
  /// storage.
  ///
  /// - Note: This pointer is valid only for the duration of the
  ///   call to `body`.
  public final func withUnsafeMutablePointerToSecondBuffer<R>(
    _ body: (UnsafeMutablePointer<Element2>) throws -> R
  ) rethrows -> R {
    defer { _fixLifetime(self) }
    return try body(secondBufferAddress)
  }
  /// Call `body` with an `UnsafeMutablePointer` to the `Element3`
  /// storage.
  ///
  /// - Note: This pointer is valid only for the duration of the
  ///   call to `body`.
  public final func withUnsafeMutablePointerToSecondBuffer<R>(
    _ body: (UnsafeMutablePointer<Element3>) throws -> R
  ) rethrows -> R {
    defer { _fixLifetime(self) }
    return try body(thirdBufferAddress)
  }

  /// Call `body` with `UnsafeMutablePointer`s to the stored `Header`
  /// and raw `Element1`, `Element2` and `Element3` storages.
  ///
  /// - Note: These pointers are valid only for the duration of the
  ///   call to `body`.
  public final func withUnsafeMutablePointers<R>(
    _ body: (UnsafeMutablePointer<Header>, 
             UnsafeMutablePointer<Element1>, 
             UnsafeMutablePointer<Element2>,
             UnsafeMutablePointer<Element3>) throws -> R
  ) rethrows -> R {
    defer { _fixLifetime(self) }
    return try body(headerAddress, firstBufferAddress, secondBufferAddress, thirdBufferAddress)
  }
}

public struct _UnitManagedBufferTrait<T> : UnitManagedBufferTrait {
  public typealias Element = T
}
public struct _PairManagedBufferTrait<A, B> : PairManagedBufferTrait {
  public typealias Element1 = A
  public typealias Element2 = B

  public let count1: Int
}
public struct _TripleManagedBufferTrait<A, B, C> : TripleManagedBufferTrait {
  public typealias Element1 = A
  public typealias Element2 = B
  public typealias Element3 = C

  public let count1: Int
  public let count2: Int
}

public struct ManagedBufferTupleFactory {
  
  /// Create a new instance of ManagedBufferTuple with Unit trait, calling
  /// `factory` on the partially-constructed object to generate an initial
  /// `Header`.
  public static func create<Header, Element>(
    elementsOf type: Element.Type,
    minimumCapacity: Int,
    makingHeaderWith factory: (
      ManagedBufferTuple<Header, _UnitManagedBufferTrait<Element>>) throws -> Header
  ) rethrows -> ManagedBufferTuple<Header, _UnitManagedBufferTrait<Element>> {

    let p = Builtin.allocWithTailElems_1(
         ManagedBufferTuple<Header, _UnitManagedBufferTrait<Element>>.self,
         minimumCapacity._builtinWordValue, Element.self)

    let initHeaderVal = try factory(p)
    p.headerAddress.initialize(to: initHeaderVal)
    // The _fixLifetime is not really needed, because p is used afterwards.
    // But let's be conservative and fix the lifetime after we use the
    // headerAddress.
    _fixLifetime(p) 
    return p
  }

  /// Create a new instance of ManagedBufferTuple with Pair trait, calling
  /// `factory` on the partially-constructed object to generate an initial
  /// `Header`
  public static func create<Header, Element1, Element2>(
    elementsOf type1: Element1.Type,
    minimumCapacity capacity1: Int,
    elementsOf type2: Element2.Type,
    minimumCapacity capacity2: Int,
    makingHeaderWith factory: (
      ManagedBufferTuple<Header, _PairManagedBufferTrait<Element1, Element2>>) throws -> Header
  ) rethrows -> ManagedBufferTuple<Header, _PairManagedBufferTrait<Element1, Element2>> {

    let p = Builtin.allocWithTailElems_2(
         ManagedBufferTuple<Header, _PairManagedBufferTrait<Element1, Element2>>.self,
         capacity1._builtinWordValue, type1,
         capacity2._builtinWordValue, type2)

    let trait = _PairManagedBufferTrait<Element1, Element2>(count1: capacity1)
    p.traitAddress.initialize(to: trait)
    let initHeaderVal = try factory(p)
    p.headerAddress.initialize(to: initHeaderVal)
    // The _fixLifetime is not really needed, because p is used afterwards.
    // But let's be conservative and fix the lifetime after we use the
    // headerAddress.
    _fixLifetime(p) 
    return p
  }

  /// Create a new instance of ManagedBufferTuple with Triple trait, calling
  /// `factory` on the partially-constructed object to generate an initial
  /// `Header`
  public static func create<Header, Element1, Element2, Element3>(
    elementsOf type1: Element1.Type,
    minimumCapacity capacity1: Int,
    elementsOf type2: Element2.Type,
    minimumCapacity capacity2: Int,
    elementsOf type3: Element3.Type,
    minimumCapacity capacity3: Int,
    makingHeaderWith factory: (
      ManagedBufferTuple<Header, _TripleManagedBufferTrait<Element1, Element2, Element3>>) throws -> Header
  ) rethrows -> ManagedBufferTuple<Header, _TripleManagedBufferTrait<Element1, Element2, Element3>> {

    let p = Builtin.allocWithTailElems_3(
         ManagedBufferTuple<Header, _TripleManagedBufferTrait<Element1, Element2, Element3>>.self,
         capacity1._builtinWordValue, type1,
         capacity2._builtinWordValue, type2,
         capacity3._builtinWordValue, type3)

    let trait = _TripleManagedBufferTrait<Element1, Element2, Element3>(count1: capacity1, count2: capacity2)
    p.traitAddress.initialize(to: trait)
    let initHeaderVal = try factory(p)
    p.headerAddress.initialize(to: initHeaderVal)
    // The _fixLifetime is not really needed, because p is used afterwards.
    // But let's be conservative and fix the lifetime after we use the
    // headerAddress.
    _fixLifetime(p) 
    return p
  }

  //===--- internal/private API -------------------------------------------===//

  /// Make ordinary initialization unavailable
  internal init(_doNotCallMe: ()) {
    _sanityCheckFailure("Only initialize these by calling create")
  }
}

/// Examples

struct MyCustomHeader {
    let capacity: Int
}
let buffer = ManagedBufferTupleFactory.create(elementsOf: String.self, minimumCapacity: 32, makingHeaderWith: { b in MyCustomHeader(capacity: b.capacity) })
let buffer2 = ManagedBuffer<MyCustomHeader, String>.create(minimumCapacity: 32, makingHeaderWith: { b in MyCustomHeader(capacity: b.capacity) })

print("cap1: \(buffer.capacity), cap2: \(buffer.header.capacity)")
print("size: \(MemoryLayout.size(ofValue: buffer)), alignment: \(MemoryLayout.alignment(ofValue: buffer))")
print("trait: \(buffer.trait), isPod: \(_isPOD(type(of: buffer.trait)))")
print("headerAddress: \(buffer.headerAddress), traitAddress: \(buffer.traitAddress)")
print("")
print("cap1: \(buffer2.capacity), cap2: \(buffer2.header.capacity)")
print("size: \(MemoryLayout.size(ofValue: buffer2)), alignment: \(MemoryLayout.alignment(ofValue: buffer2))")
print("")

var buffer3 = ManagedBufferTupleFactory.create(elementsOf: UInt.self, minimumCapacity: 32, elementsOf: String.self, minimumCapacity: 64, makingHeaderWith: { b in MyCustomHeader(capacity: b.capacity2) })

print("cap1: \(buffer3.capacity1), cap2: \(buffer3.capacity2), cap3: \(buffer3.header.capacity)")
print("size: \(MemoryLayout.size(ofValue: buffer3)), alignment: \(MemoryLayout.alignment(ofValue: buffer3))")
print("trait: \(buffer3.trait), isPod: \(_isPOD(type(of: buffer3.trait)))")
print("headerAddress: \(buffer3.headerAddress), traitAddress: \(buffer3.traitAddress), buffer: \(UnsafeRawPointer(Builtin.addressof(&buffer3)))")

var buffer4 = ManagedBufferTupleFactory.create(elementsOf: UInt.self, minimumCapacity: 32, 
                                               elementsOf: String.self, minimumCapacity: 64,
                                               elementsOf: String.self, minimumCapacity: 32,
                                               makingHeaderWith: { b in MyCustomHeader(capacity: b.capacity3) })
print("cap1: \(buffer4.capacity1), cap2: \(buffer4.capacity2), cap3: \(buffer4.header.capacity)")
print("size: \(MemoryLayout.size(ofValue: buffer4)), alignment: \(MemoryLayout.alignment(ofValue: buffer4))")
print("trait: \(buffer4.trait), isPod: \(_isPOD(type(of: buffer4.trait)))")
print("headerAddress: \(buffer4.headerAddress), traitAddress: \(buffer4.traitAddress), buffer: \(UnsafeRawPointer(Builtin.addressof(&buffer4)))")


