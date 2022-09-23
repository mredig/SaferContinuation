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

	let isFatal: SaferContinuation<UnsafeContinuation<Void, Error>>.FatalityOptions

	private var hasRun = false

	private typealias Statics = SaferContinuation<UnsafeContinuation<Void, Error>>

	private let file: StaticString
	private let line: Int
	private let function: StaticString
	public let context: Any?

	private let delayCheckInterval: TimeInterval?


	/**
	Basic usage:
	- Parameters:
	  - continuation: Provide the original continuation. This is the only required argument as everything else has default provided values.
	  - isFatal: Causes a `fatalError` upon mishandling of async/await calls if true.
	  - delayCheckInterval: The time delay in seconds to check to see if the continuation has been released from memory or not. If still present in
	  memory, will post a `SaferContinuation.potentialMemoryLeak` notification. Can be disabled by passing `nil`. Defaults to `3`
	  - file: Provides context of what file the continuation error occured in. Just don't touch, really.
	  - line: Provides context of what line the continuation error occured on. Just don't touch, really.
	  - function: Provides context of what function the continuation error occured in. Just don't touch, really.
	  - context: Allows you to provide any arbitrary data to differentiate between different continuations that you can inspect when errors are thrown or
	 notifications posted.. Could be a string, a UUID, a UIImage, or your mom's nickname. The last one is probably not useful though. You be the judge.
	 */
	public init(_ continuation: C, isFatal: SaferContinuation<UnsafeContinuation<Void, Error>>.FatalityOptions = false, delayCheckInterval: TimeInterval? = 3, file: StaticString = #file, line: Int = #line, function: StaticString = #function, context: Any? = nil) {
		self.continuation = continuation
		self.isFatal = isFatal
		self.file = file
		self.line = line
		self.function = function
		self.delayCheckInterval = delayCheckInterval
		self.context = context
	}

	deinit {
		Statics.safeContinuationLock.lock()
		defer { Statics.safeContinuationLock.unlock() }

		if hasRun == false {
			let error = SafeContinuationError.continuationNeverCompleted(file: file, line: line, function: function, context: context)
			self.continuation.resume(throwing: error)
			if isFatal.contains(.onDeinitWithoutCompletion) {
				fatalError("Continuation was never completed!: \(error)")
			}
		}
	}

	public func resume(returning value: C.T) {
		resume(with: .success(value))
	}

	public func resume(throwing error: C.E) {
		resume(with: .failure(error))
	}

	public func resume(with result: Result<C.T, C.E>) {
		do {
			try markCompleted()
		} catch {
			print("WARNING: Continuation already completed!: \(error)")
			NotificationCenter.default.post(name: Statics.multipleInvocations , object: self)
			if isFatal.contains(.onMultipleCompletions) {
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

		startDelayedCheck()
	}

	private func startDelayedCheck(iteration: Int = 0) {
		if let delayCheckInterval = delayCheckInterval {
			Task { [weak self, isFatal, file, line, function, context] in
				try await Task.sleep(nanoseconds: UInt64(delayCheckInterval * 1_000_000_000))
				guard self == nil else {
					let error = SafeContinuationError.alreadyRun(file: file, line: line, function: function, context: context)
					let message = "WARNING: Continuation completed \(delayCheckInterval * TimeInterval(iteration + 1)) seconds ago and hasn't been released from memory!: \(error)"
					print(message)
					NotificationCenter.default.post(name: Statics.potentialMemoryLeak, object: self)
					if isFatal.contains(.onPostRunDelayCheck) {
						fatalError(message)
					}
					self?.startDelayedCheck(iteration: iteration + 1)
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

	/**
	 This notification is posted to the `NotificationCenter` when a continuation is invoked multiple times. It includes the `SaferContinuation` object as
	 the `notification.object`
	 */
	public static let multipleInvocations = NSNotification.Name("com.redeggproductions.SaferContinuationMultipleInvocations")
	/**
	 This notification is posted to the `NotificationCenter` when a continuation is invoked but then not released from memory after `delayCheckInterval`
	 time has passed. You can disable this check by passing `nil` for `delayCheckInterval`. The `notification.object` is the `SaferContinuation`
	 object, allowing you to inspect context and call site information
	 */
	public static let potentialMemoryLeak = NSNotification.Name("com.redeggproductions.SaferContinuationPotentialMemoryLeak")

	private static let safeContinuationLock = NSLock()
}
