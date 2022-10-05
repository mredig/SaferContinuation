import Foundation

public enum SafeContinuationError: Error {
	/// internally used by safercontinuation. cannot be thrown by the continuation as that would cause bugs to have the continuation resume multiple times (which is exactly what we are avoiding here)
	case alreadyRun(file: StaticString, line: Int, function: StaticString, context: Any?)

	/// internally used by safercontinuation. cannot be thrown by the continuation as that would cause bugs to have the continuation resume multiple times (which is exactly what we are avoiding here)
	case previouslyRanButUnreleased(file: StaticString, line: Int, function: StaticString, context: Any?)

	/// thrown by safer continuation when the continuation is deinited and has never been called
	case continuationNeverCompleted(file: StaticString, line: Int, function: StaticString, context: Any?)

	/// thrown by safer continuation when the continuation doesn't fire within the timeout period
	case timeoutMet(file: StaticString, line: Int, function: StaticString, context: Any?)
}
