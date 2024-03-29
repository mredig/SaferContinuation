import XCTest
@testable import SaferContinuation

extension Task where Success == Never, Failure == Never {
	public static func sleep(duration: TimeInterval) async throws {
		let nanosecondsTI = duration * 1_000_000_000
		let nanoseconds: UInt64

		switch nanosecondsTI {
		case TimeInterval(UInt64.max)...:
			nanoseconds = .max
		case ...0:
			nanoseconds = 0
		default:
			nanoseconds = UInt64(nanosecondsTI)
		}
		try await Task.sleep(nanoseconds: nanoseconds)
	}
}

final class SaferContinuationTests: XCTestCase {

	override func setUp() {
		SaferContinuation.initializeLogging()
	}

	func testMultipleInvocations() async throws {
		let notificationExpectation = expectation(forNotification: SaferContinuation.multipleInvocations, object: nil)

		let _: Void = try await withCheckedThrowingContinuation { continuation in
			let safer = SaferContinuation(continuation)
			DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
				safer.resume(with: .success(Void()))
			}
			DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
				safer.resume(with: .success(Void()))
			}
		}

		await fulfillment(of: [notificationExpectation], timeout: 1)
	}

	func testNoInvocations() async throws {
		let task = Task {
			let _: Void = try await withCheckedThrowingContinuation { continuation in
				let safer = SaferContinuation(continuation)
				DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
					// keep it around long enough to simulate waiting for a callback to do something, but ultimately not fire
					log.veryVerbose(safer)
				}
			}
		}

		let result = await task.result

		XCTAssertThrowsError(try result.get())
		guard
			case .failure(let error) = result,
			case .continuationNeverCompleted = (error as! SafeContinuationError)
		else {
			XCTFail()
			return
		}
		// for some reason, coverage says the lines that throw the error for the result never run, but both a test
		// breakpoint and this print statement beg to differ.
		log.veryVerbose(result)
	}

	func testCorrectInvocationsResult() async throws {
		let task = Task {
			let _: Void = try await withCheckedThrowingContinuation { continuation in
				let safer = SaferContinuation(
					continuation,
					delayCheckInterval: 1)
				DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
					safer.resume(with: .success(Void()))
				}
			}
		}

		let result = await task.result

		XCTAssertNoThrow(try result.get())

		try await Task.sleep(duration: 2)
	}

	func testCorrectInvocationsReturn() async throws {
		let task = Task {
			let _: Void = try await withCheckedThrowingContinuation { continuation in
				let safer = SaferContinuation(continuation)
				DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
					safer.resume(returning: ())
				}
			}
		}

		let result = await task.result

		XCTAssertNoThrow(try result.get())
	}

	func testCorrectInvocationsThrowing() async throws {
		let expectedError = NSError(domain: "sample.error", code: -1)

		let task = Task {
			let _: Void = try await withCheckedThrowingContinuation { continuation in
				let safer = SaferContinuation(continuation)
				DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
					safer.resume(throwing: expectedError)
				}
			}
		}

		let result = await task.result

		XCTAssertThrowsError(try result.get())

		guard case .failure(let error as NSError) = result else {
			XCTFail()
			return
		}

		XCTAssertEqual(error, expectedError)
	}

	func testInvokeThenMemoryLeak() async throws {
		let notificationExpectation = expectation(forNotification: SaferContinuation.potentialMemoryLeak, object: nil)

		let printed = expectation(description: "wait for print statement")

		let _: Void = try await withCheckedThrowingContinuation { continuation in
			let safer = SaferContinuation(continuation, delayCheckInterval: 0.25)
			DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
				safer.resume(with: .success(Void()))
			}
			DispatchQueue.global().asyncAfter(deadline: .now() + 0.75) {
				log.veryVerbose(safer)
				printed.fulfill()
			}
		}

		await fulfillment(of: [notificationExpectation, printed], timeout: 1)
	}

	func testTimeoutWithShortlyCallingAfter() async throws {
		let notificationExpectation = expectation(forNotification: SaferContinuation.continuationTimedOut, object: nil)

		let task = Task {
			let _: Void = try await withCheckedThrowingContinuation { continuation in
				let safer = SaferContinuation(continuation, timeout: 0.25)
				DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
					// keep it around long enough to allow a timeout
					log.veryVerbose(safer)
					safer.resume(with: .success(()))
				}
			}
		}

		let result = await task.result

		XCTAssertThrowsError(try result.get())
		guard
			case .failure(let error) = result,
			case .timeoutMet = (error as! SafeContinuationError)
		else {
			XCTFail()
			return
		}

		await fulfillment(of: [notificationExpectation], timeout: 1)
	}

	func testTimeoutWithNeverCalling() async throws {
		let notificationExpectation = expectation(forNotification: SaferContinuation.continuationTimedOut, object: nil)

		let task = Task {
			let _: Void = try await withCheckedThrowingContinuation { continuation in
				let safer = SaferContinuation(continuation, timeout: 0.25)
				DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
					// keep it around long enough to allow a timeout
					log.veryVerbose(safer)
				}
			}
		}

		let result = await task.result

		XCTAssertThrowsError(try result.get())
		guard
			case .failure(let error) = result,
			case .timeoutMet = (error as! SafeContinuationError)
		else {
			XCTFail()
			return
		}

		await fulfillment(of: [notificationExpectation], timeout: 1)
	}

	func testTimeoutWithKeepaliveSuccess() async throws {
//		let notificationExpectation = expectation(forNotification: SaferContinuation.continuationTimedOut, object: nil)

		let task = Task {
			let _: Void = try await withCheckedThrowingContinuation { continuation in
				let safer = SaferContinuation(continuation, timeout: 0.25)
				DispatchQueue.global().asyncAfter(deadline: .now() + 0.24) {
					safer.keepAlive()
				}
				DispatchQueue.global().asyncAfter(deadline: .now() + 0.34) {
					safer.keepAlive()
				}

				DispatchQueue.global().asyncAfter(deadline: .now() + 0.487) {
					// keep it around long enough to allow a timeout
					safer.resume(with: .success(()))
				}
			}
		}

		let result = await task.result

		XCTAssertNoThrow(try result.get())
	}

	func testTimeoutWithKeepaliveTimeout() async throws {
		let notificationExpectation = expectation(forNotification: SaferContinuation.continuationTimedOut, object: nil)

		let task = Task {
			let _: Void = try await withCheckedThrowingContinuation { continuation in
				let safer = SaferContinuation(continuation, timeout: 0.25)
				DispatchQueue.global().asyncAfter(deadline: .now() + 0.24) {
					safer.keepAlive()
				}
				DispatchQueue.global().asyncAfter(deadline: .now() + 0.34) {
					safer.keepAlive()
				}

				DispatchQueue.global().asyncAfter(deadline: .now() + 0.34 + 0.3) {
					// keep it around long enough to allow a timeout
					log.veryVerbose(safer)
				}
			}
		}

		let result = await task.result

		XCTAssertThrowsError(try result.get())

		guard
			case .failure(let error) = result,
			case .timeoutMet = (error as! SafeContinuationError)
		else {
			XCTFail()
			return
		}

		await fulfillment(of: [notificationExpectation], timeout: 1)
	}

	func testOnDeinit() async throws {
		let deinitExpectation = expectation(description: "on deinit")

		let task = Task {
			let _: Void = try await withCheckedThrowingContinuation { continuation in
				let safer = SaferContinuation(continuation)
				safer.onDeinit {
					deinitExpectation.fulfill()
				}
				DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
					safer.resume(returning: ())
				}
			}
		}

		let _ = await task.result

		await fulfillment(of: [deinitExpectation], timeout: 10)
	}
}
