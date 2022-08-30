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


/// Can only work with throwing continuations because it needs to be able to throw on failed scenarios
final public class SaferContinuation<C: Continuation>: Sendable, Continuation where C.E == Error {
	private let continuation: C

	let isFatal: Bool

	private var hasRun = false

	private typealias Statics = SaferContinuation<UnsafeContinuation<Void, Error>>

	private let file: StaticString
	private let line: Int
	private let function: StaticString
	public let context: Any?

	private let delayCheckInterval: TimeInterval?


	public init(_ continuation: C, isFatal: Bool = false, delayCheckInterval: TimeInterval? = 3, file: StaticString = #file, line: Int = #line, function: StaticString = #function, context: Any? = nil) {
		self.continuation = continuation
		self.isFatal = isFatal
		self.file = file
		self.line = line
		self.function = function
		self.delayCheckInterval = delayCheckInterval
		self.context = context
	}

	deinit {
		SaferContinuation<UnsafeContinuation<Void, Error>>.safeContinuationLock.lock()
		defer { SaferContinuation<UnsafeContinuation<Void, Error>>.safeContinuationLock.unlock() }

		if hasRun == false {
			let error = SafeContinuationError.continuationNeverCompleted(file: file, line: line, function: function, context: context)
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
			NotificationCenter.default.post(name: Statics.multipleInvocations , object: self)
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
			NotificationCenter.default.post(name: Statics.multipleInvocations , object: self)
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
			NotificationCenter.default.post(name: Statics.multipleInvocations , object: self)
			if isFatal {
				fatalError("Continuation already completed!: \(error)")
			}
			return
		}
		continuation.resume(with: result)
	}

	private func markCompleted() throws {
		Statics.safeContinuationLock.lock()
		defer { Statics.safeContinuationLock.unlock() }

		guard hasRun == false else { throw SafeContinuationError.alreadyRun(file: file, line: line, function: function, context: context) }
		hasRun = true

		if let delayCheckInterval = delayCheckInterval {
			Task { [weak self, isFatal, file, line, function, context] in
				try await Task.sleep(nanoseconds: UInt64(delayCheckInterval * 1_000_000_000))
				guard self == nil else {
					let error = SafeContinuationError.alreadyRun(file: file, line: line, function: function, context: context)
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
		case alreadyRun(file: StaticString, line: Int, function: StaticString, context: Any?)
		case continuationNeverCompleted(file: StaticString, line: Int, function: StaticString, context: Any?)
	}
}

extension SaferContinuation where C == UnsafeContinuation<Void, Error> {
//	static let test = "fart"
	public static let multipleInvocations = NSNotification.Name("com.redeggproductions.SaferContinuationMultipleInvocations")
	private static let safeContinuationLock = NSLock()

}
