import Foundation

public protocol Continuation {
	associatedtype T
	func resume(returning value: T)

	associatedtype E: Error
	func resume(throwing error: E)

	func resume(with result: Result<T, E>)
}

extension UnsafeContinuation: Continuation {}
extension CheckedContinuation: Continuation {}


fileprivate let safeContinuationLock = NSLock()

/// Can only work with throwing continuations because it needs to be able to throw on failed scenarios
final public class SaferContinuation<C: Continuation>: Sendable, Continuation where C.E == Error {
	private let continuation: C

	let isFatal: Bool

	private var hasRun = false

	private let file: StaticString
	private let line: Int
	private let function: StaticString

	private let delayCheckInterval: TimeInterval?


	public init(_ continuation: C, isFatal: Bool = false, delayCheckInterval: TimeInterval? = 3, file: StaticString = #file, line: Int = #line, function: StaticString = #function) {
		self.continuation = continuation
		self.isFatal = isFatal
		self.file = file
		self.line = line
		self.function = function
		self.delayCheckInterval = delayCheckInterval
	}

	deinit {
		safeContinuationLock.lock()
		defer { safeContinuationLock.unlock() }
		if hasRun == false {
			let error = SafeContinuationError.continuationNeverCompleted(file: file, line: line, function: function)
			self.continuation.resume(throwing: error)
			if isFatal {
				fatalError("Continuation was never completed!: \(error)")
			}
		}
	}

	public func resume(returning value: C.T) {
		do {
			try markCompleted()
		} catch {
			print("WARNING: Continuation already completed!: \(error)")
			if isFatal {
				fatalError("Continuation already completed!: \(error)")
			}
			return
		}
		continuation.resume(returning: value)
	}

	public func resume(throwing error: C.E) {
		do {
			try markCompleted()
		} catch {
			print("WARNING: Continuation already completed!: \(error)")
			if isFatal {
				fatalError("Continuation already completed!: \(error)")
			}
			return
		}
		continuation.resume(throwing: error)
	}

	public func resume(with result: Result<C.T, C.E>) {
		do {
			try markCompleted()
		} catch {
			print("WARNING: Continuation already completed!: \(error)")
			if isFatal {
				fatalError("Continuation already completed!: \(error)")
			}
			return
		}
		continuation.resume(with: result)
	}

	private func markCompleted() throws {
		safeContinuationLock.lock()
		defer { safeContinuationLock.unlock() }
		guard hasRun == false else { throw SafeContinuationError.alreadyRun(file: file, line: line, function: function) }
		hasRun = true

		if let delayCheckInterval = delayCheckInterval {
			Task { [weak self, isFatal, file, line, function] in
				try await Task.sleep(nanoseconds: UInt64(delayCheckInterval * 1_000_000_000))
				guard self == nil else {
					let error = SafeContinuationError.alreadyRun(file: file, line: line, function: function)
					let message = "WARNING: Continuation completed \(delayCheckInterval) seconds ago and hasn't been released from memory!: \(error)"
					print(message)
					if isFatal {
						fatalError(message)
					}
					return
				}
			}
		}
	}

	public enum SafeContinuationError: Error {
		case alreadyRun(file: StaticString, line: Int, function: StaticString)
		case continuationNeverCompleted(file: StaticString, line: Int, function: StaticString)
	}
}
