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
final public class SaferContinuation<C: Continuation & Sendable>: @unchecked Sendable, Continuation where C.E == Error {
	private let continuation: C

	let isFatal: SaferContinuation<UnsafeContinuation<Void, Error>>.FatalityOptions

	public private(set) var hasRun = false

	private typealias Statics = SaferContinuation<UnsafeContinuation<Void, Error>>

	private let file: StaticString
	private let line: Int
	private let function: StaticString
	public let context: Any?

	private let delayCheckInterval: TimeInterval?

	private var timeoutTask: Task<Void, Error>?
	public let timeoutInterval: TimeInterval?

	/**
	 Be HYPER paranoid about retaining stuff in these blocks!
	 */
	private var onDeinitBlocks: [() -> Void] = []

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
	public init(
		_ continuation: C,
		isFatal: SaferContinuation<UnsafeContinuation<Void, Error>>.FatalityOptions? = nil,
		timeout: TimeInterval? = nil,
		delayCheckInterval: TimeInterval? = 3,
		file: StaticString = #file,
		line: Int = #line,
		function: StaticString = #function,
		context: Any? = nil
	) {
#if DEBUG
		let defaultFatalOptions: SaferContinuation<UnsafeContinuation<Void, Error>>.FatalityOptions = true
#else
		let defaultFatalOptions: SaferContinuation<UnsafeContinuation<Void, Error>>.FatalityOptions = false
#endif

		self.continuation = continuation
		self.isFatal = isFatal ?? defaultFatalOptions
		self.file = file
		self.line = line
		self.function = function
		self.delayCheckInterval = delayCheckInterval
		self.context = context
		self.timeoutInterval = timeout

		if let timeout = timeout {
			createTimeoutTask(timeout)
		}
	}

	deinit {
		Statics.safeContinuationLock.lock()
		defer { Statics.safeContinuationLock.unlock() }

		timeoutTask?.cancel()

		if hasRun == false {
			let error = SafeContinuationError.continuationNeverCompleted(file: file, line: line, function: function, context: context)
			log.error("ERROR: Continuation (\(memoryAddress)) was never completed!: \(error)")
			self.continuation.resume(throwing: error)
			if isFatal.contains(.onDeinitWithoutCompletion) {
				fatalError("Continuation (\(memoryAddress)) was never completed!: \(error)")
			}
		}

		onDeinitBlocks.forEach { $0() }
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
			log.error("ERROR: Continuation (\(memoryAddress)) already completed!: \(error)")
			NotificationCenter.default.post(name: Statics.multipleInvocations , object: self)
			if isFatal.contains(.onMultipleCompletions) {
				fatalError("Continuation (\(memoryAddress)) already completed!: \(error)")
			}
			return
		}
		continuation.resume(with: result)
	}

	public func onDeinit(_ block: @escaping () -> Void) {
		onDeinitBlocks.append(block)
	}

	private func markCompleted() throws {
		Statics.safeContinuationLock.lock()
		defer { Statics.safeContinuationLock.unlock() }

		try _markCompleted()
	}

	private func _markCompleted() throws {
		guard hasRun == false else { throw SafeContinuationError.alreadyRun(file: file, line: line, function: function, context: context) }
		hasRun = true

		startDelayedCheck()
	}

	private func startDelayedCheck(iteration: Int = 0) {
		if let delayCheckInterval = delayCheckInterval {
			Task(priority: .low) { [weak self, memoryAddress, isFatal, file, line, function, context] in
				let delay = UInt64(delayCheckInterval * 1_000_000_000)
				try await Task.sleep(nanoseconds: delay)
				if let self = self {
					let error = SafeContinuationError.previouslyRanButUnreleased(file: file, line: line, function: function, context: context)
					let message = "ERROR: Continuation (\(memoryAddress)) completed \(delayCheckInterval * TimeInterval(iteration + 1)) seconds ago and hasn't been released from memory!: \(error)"
					log.error(message)
					NotificationCenter.default.post(name: Statics.potentialMemoryLeak, object: self)
					if isFatal.contains(.onPostRunDelayCheck) {
						fatalError(message)
					}
					self.startDelayedCheck(iteration: iteration + 1)
				}
			}
		}
	}

	private func executeTimeout() {
		Statics.safeContinuationLock.lock()
		defer {
			Statics.safeContinuationLock.unlock()
		}

		guard
			Task.isCancelled == false
		else { return }
		do {
			try _markCompleted()
		} catch {
			return
		}

		let error = SafeContinuationError.timeoutMet(file: file, line: line, function: function, context: context)
		let message = "ERROR: Continuation (\(memoryAddress)) timed out!: \(error)"
		log.error(message)
		NotificationCenter.default.post(name: Statics.continuationTimedOut , object: self)
		if isFatal.contains(.onTimeout) {
			fatalError(message)
		}
		self.continuation.resume(throwing: error)
	}

	private func createTimeoutTask(_ timeout: TimeInterval) {
		self.timeoutTask = Task(priority: .low) { [weak self] in
			let timeoutDelay = UInt64(timeout * 1_000_000_000)
			try await Task.sleep(nanoseconds: timeoutDelay)

			try Task.checkCancellation()

			self?.executeTimeout()
		}
	}

	/**
	 Resets the timeout interval to keep long running tasks alive
	 */
	public func keepAlive() {
		guard
			let timeoutInterval,
			let oldTimeoutTask = timeoutTask
		else { return }

		oldTimeoutTask.cancel()

		createTimeoutTask(timeoutInterval)
	}
}

extension SaferContinuation: CustomStringConvertible, CustomDebugStringConvertible {
	public var description: String {
		descriptionBase(showAddress: true)
	}

	public var debugDescription: String {
		descriptionBase(showAddress: true)
	}

	private func descriptionBase(showAddress: Bool) -> String {
		"SaferContinuation\(showAddress ? " - \(memoryAddress)" : "") (\(C.self)): file: '\(file)' line: '\(line)' function: '\(function)' context: '\(context as Any)'"
	}

	public var memoryAddress: UnsafeRawPointer {
		UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
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
	public static let continuationTimedOut = NSNotification.Name("com.redeggproductions.ContinuationTimedOut")

	private static let safeContinuationLock = NSLock()

	/**
	 Only necessary to call if you want print statements/you aren't already using Swiftwood and have added logging destination(s) elsewhere.
	 */
	static public func initializeLogging() {
		setupLogging()
	}

	public func resume() {
		resume(returning: ())
	}
}

extension SaferContinuation where C == CheckedContinuation<Void, Error> {
	public func resume() {
		resume(returning: ())
	}
}
