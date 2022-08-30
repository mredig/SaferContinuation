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

		wait(for: [notificationExpectation], timeout: 1)
	}

	func testNoInvocations() async throws {
		let task = Task {
			let _: Void = try await withCheckedThrowingContinuation { continuation in
				let safer = SaferContinuation(continuation)
				DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
					// keep it around long enough to simulate waiting for a callback to do something, but ultimately not fire
					print(safer)
				}
			}
		}

		let result = await task.result

		XCTAssertThrowsError(try result.get())
	}

	func testCorrectInvocations() async throws {
		let task = Task {
			let _: Void = try await withCheckedThrowingContinuation { continuation in
				let safer = SaferContinuation(continuation)
				DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
					safer.resume(with: .success(Void()))
				}
			}
		}

		let result = await task.result

		XCTAssertNoThrow(try result.get())
	}
}
