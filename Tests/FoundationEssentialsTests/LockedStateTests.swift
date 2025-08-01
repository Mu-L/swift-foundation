//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Testing

#if canImport(FoundationEssentials)
@testable import FoundationEssentials
#else
@testable import Foundation
#endif

@Suite("LockedState")
private struct LockedStateTests {
    final class TestObject {
        var deinitBlock: () -> Void = {}

        deinit {
            deinitBlock()
        }
    }

    struct TestError: Error {}

    @Test func withLockDoesNotExtendLifetimeOfState() {
        weak var state: TestObject?
        let lockedState: LockedState<TestObject>

        (state, lockedState) = {
            let state = TestObject()
            return (state, LockedState(initialState: state))
        }()

        lockedState.withLock { state in
            weak var oldState = state
            state = TestObject()
            #expect(oldState == nil, "State object lifetime was extended after reassignment within body")
        }

        #expect(state == nil, "State object lifetime was extended beyond end of call")
    }

    @Test func withLockExtendingLifetimeExtendsLifetimeOfStatePastReassignment() {
        let lockedState = LockedState(initialState: TestObject())

        lockedState.withLockExtendingLifetimeOfState { state in
            weak var oldState = state
            state = TestObject()
            #expect(oldState != nil, "State object lifetime was not extended after reassignment within body")
        }
    }

    @Test func withLockExtendingLifetimeExtendsLifetimeOfStatePastEndOfLockedScope() {
        let lockedState: LockedState<TestObject> = {
            let state = TestObject()
            let lockedState = LockedState(initialState: state)

            // `withLockExtendingLifetimeOfState()` should extend the lifetime of the state until after the lock is
            // released. By asserting that the lock is not held when the state object is deinit-ed, we can confirm
            // that the lifetime was extended past the end of the locked scope.
            state.deinitBlock = {
                assertLockNotHeld(lockedState, "State object lifetime was not extended to end of locked scope")
            }

            return lockedState
        }()

        lockedState.withLockExtendingLifetimeOfState { state in
            state = TestObject()
        }
    }

    @Test func withLockExtendingLifetimeDoesNotExtendLifetimeOfStatePastEndOfCall() {
        weak var state: TestObject?
        let lockedState: LockedState<TestObject>

        (state, lockedState) = {
            let state = TestObject()
            return (state, LockedState(initialState: state))
        }()

        lockedState.withLockExtendingLifetimeOfState { state in
            state = TestObject()
        }

        #expect(state == nil, "State object lifetime was extended beyond end of call")
    }

    @Test func withLockExtendingLifetimeReleasesLockWhenBodyThrows() {
        let lockedState = LockedState(initialState: TestObject())

        #expect(throws: TestError.self, "The body was expected to throw an error, but it did not.") {
            try lockedState.withLockExtendingLifetimeOfState { _ in
                throw TestError()
            }
        }

        assertLockNotHeld(lockedState, "Lock was not properly released by withLockExtendingLifetimeOfState()")
    }
    
    @Test func withLockExtendingLifespanDoesExtendLifetimeOfState() {
        weak var state: TestObject?
        let lockedState: LockedState<TestObject>
        
        (state, lockedState) = {
            let state = TestObject()
            return (state, LockedState(initialState: state))
        }()
        
        lockedState.withLockExtendingLifetimeOfState { state in
            weak var oldState = state
            state = TestObject()
            #expect(oldState != nil, "State object lifetime was not extended after reassignment within body")
        }
        
        #expect(state == nil, "State object lifetime was extended beyond end of call")
    }
}

/// Assert that the locked state is not currently locked.
///
/// ⚠️ This assertion fails by crashing. If the lock is currently held, the `withLock()` call will abort the program.
private func assertLockNotHeld<Value>(_ lockedState: LockedState<Value>, _ message: @autoclosure () -> String) {
    // Note: Since the assertion fails by crashing, `message` is never logged.
    lockedState.withLock { _ in
        // PASS
    }
}
