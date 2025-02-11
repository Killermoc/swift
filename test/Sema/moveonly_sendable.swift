// RUN: %target-typecheck-verify-swift -enable-experimental-move-only -strict-concurrency=complete -disable-availability-checking

// REQUIRES: concurrency


struct CopyableStruct {}
class Ref { var x = 0 } // expected-note 3{{class 'Ref' does not conform to the 'Sendable' protocol}}

@_moveOnly
struct FileDescriptor: Sendable {
  var id = 0
}

@_moveOnly
enum MaybeFile { // should implicitly conform
  case available(FileDescriptor)
  case closed
}

@_moveOnly
struct NotSendableMO { // expected-note 2{{consider making struct 'NotSendableMO' conform to the 'Sendable' protocol}}
  var ref: Ref
}

// expect no warnings about sendable conformance when crossing actor boundaries:
func invalidFile() async -> FileDescriptor {
  return FileDescriptor(id: -1)
}

func takeNotSendable(_ nsmo: NotSendableMO) async {}

actor A {
  init(_ t: FileDescriptor) {}
  init (_ t: MaybeFile) {}
  func takeFileDescriptor(_ fd: __owned FileDescriptor) {}
  func takeMaybeFile(_ mfd: __owned MaybeFile) {}
  func giveFileDescriptor() -> MaybeFile {
    return .closed
  }

  func getRef() -> NotSendableMO { return NotSendableMO(ref: Ref()) }
}

@MainActor
func processFiles(_ a: A, _ anotherFile: FileDescriptor) async {
  let file = await invalidFile()
  await a.takeFileDescriptor(file)

  await a.takeMaybeFile(.available(anotherFile))
  _ = A(.available(anotherFile))

  let ns = await a.getRef() // expected-warning {{non-sendable type 'NotSendableMO' returned by implicitly asynchronous call to actor-isolated instance method 'getRef()' cannot cross actor boundary}}
  await takeNotSendable(ns) // expected-warning {{non-sendable type 'NotSendableMO' exiting main actor-isolated context in call to non-isolated global function 'takeNotSendable' cannot cross actor boundary}}

  switch (await a.giveFileDescriptor()) {
  case let .available(fd):
    await a.takeFileDescriptor(fd)
  default:
    break
  }
}

func caller() async {
  await processFiles(A(invalidFile()), invalidFile())
}

// now make sure you can't form a Sendable existential from a move-only type.

@_moveOnly
struct RefPair: Sendable {
  var left: Ref // expected-warning {{stored property 'left' of 'Sendable'-conforming struct 'RefPair' has non-sendable type 'Ref'}}
  var right: Ref  // expected-warning {{stored property 'right' of 'Sendable'-conforming struct 'RefPair' has non-sendable type 'Ref'}}
}

@_moveOnly
enum MaybeRef: Sendable {
  case ref(Ref) // expected-warning {{associated value 'ref' of 'Sendable'-conforming enum 'MaybeRef' has non-sendable type 'Ref'}}
  case null
}

@_moveOnly
enum OK_NoncopyableOption<T: Sendable> : Sendable {
  case some(T)
  case none
}

@_moveOnly
enum Wrong_NoncopyableOption<T> : Sendable { // expected-note {{consider making generic parameter 'T' conform to the 'Sendable' protocol}}
  case some(T) // expected-warning {{associated value 'some' of 'Sendable'-conforming generic enum 'Wrong_NoncopyableOption' has non-sendable type 'T'}}
  case none
}

func takeAnySendable(_ s: any Sendable) {}
func takeSomeSendable(_ s: some Sendable) {}

// expected-error@+1 {{move-only type 'FileDescriptor' cannot be used with generics yet}}
func mkSendable() -> Sendable { return FileDescriptor(id: 0) }

func tryToCastIt(_ fd: FileDescriptor) {
  let _: any Sendable = fd // expected-error {{move-only type 'FileDescriptor' cannot be used with generics yet}}
  let _: Sendable = fd // expected-error {{move-only type 'FileDescriptor' cannot be used with generics yet}}

  takeAnySendable(fd) // expected-error {{move-only type 'FileDescriptor' cannot be used with generics yet}}
  takeSomeSendable(fd) // expected-error {{move-only type 'FileDescriptor' cannot be used with generics yet}}

  let _ = fd as Sendable // expected-error {{move-only type 'FileDescriptor' cannot be used with generics yet}}

  let _ = fd as? Sendable // expected-warning {{cast from 'FileDescriptor' to unrelated type 'any Sendable' always fails}}
                          // expected-error@-1 {{marker protocol 'Sendable' cannot be used in a conditional cast}}

  let _ = fd as! Sendable // expected-warning {{cast from 'FileDescriptor' to unrelated type 'any Sendable' always fails}}

  let _ = fd is Sendable // expected-warning {{cast from 'FileDescriptor' to unrelated type 'any Sendable' always fails}}
                         // expected-error@-1 {{marker protocol 'Sendable' cannot be used in a conditional cast}}
}

protocol GiveSendable<T> {
  associatedtype T: Sendable // expected-note {{protocol requires nested type 'T'; do you want to add it?}}
  func give() -> T
}

// make sure witnessing associatedtypes is still prevented, even though we meet the explicit constraint.
class Bad: GiveSendable { // expected-error {{type 'Bad' does not conform to protocol 'GiveSendable'}}
  typealias T = FileDescriptor // expected-note {{possibly intended match 'Bad.T' (aka 'FileDescriptor') does not conform to '_Copyable'}}
  func give() -> FileDescriptor { return FileDescriptor(id: -1) }
}

class Ok: GiveSendable {
  typealias T = CopyableStruct
  func give() -> CopyableStruct { return CopyableStruct() }
}

class Container<T> where T:Sendable {
  var elm: T
  init(_ t: T) { self.elm = t }
}

func createContainer(_ fd: FileDescriptor) {
  let _: Container<Sendable> = Container(fd) // expected-error {{move-only type 'FileDescriptor' cannot be used with generics yet}}
  let _: Container<Sendable> = Container(CopyableStruct())
}

func takeTwo<T: Sendable>(_ s1: T, _ s2: T) {}

extension Sendable {
  func doIllegalThings() {
    return takeTwo(self, self)
  }
}

func tryToDupe(_ fd: FileDescriptor) {
  fd.doIllegalThings() // expected-error {{move-only type 'FileDescriptor' cannot be used with generics yet}}
}
