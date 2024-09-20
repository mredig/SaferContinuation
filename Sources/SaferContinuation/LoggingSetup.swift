import Foundation
@preconcurrency import Swiftwood

private final class LockBlock: @unchecked Sendable {
	private var hasRun = false

	private static let lock = NSLock()

	func performOnce(_ block: () -> Void) {
		Self.lock.lock()
		defer { Self.lock.unlock() }
		guard hasRun == false else { return }
		hasRun = true

		block()
	}
}

fileprivate let setupLockBlock = LockBlock()

typealias log = Swiftwood

func setupLogging() {
	setupLockBlock.performOnce {
		let consoleDestination = ConsoleLogDestination(maxBytesDisplayed: -1)
		consoleDestination.minimumLogLevel = .veryVerbose
		log.appendDestination(consoleDestination, replicationOption: .forfeitToAlike)
	}
}

