import Foundation

extension SaferContinuation where C == UnsafeContinuation<Void, Error> {
	public struct FatalityOptions: OptionSet, Sendable, ExpressibleByBooleanLiteral {
		public var rawValue: UInt8

		public static let onDeinitWithoutCompletion = FatalityOptions(rawValue: 1 << 0)
		public static let onMultipleCompletions = FatalityOptions(rawValue: 1 << 1)
		public static let onPostRunDelayCheck = FatalityOptions(rawValue: 1 << 2)
		public static let onTimeout = FatalityOptions(rawValue: 1 << 3)

		public init(rawValue: UInt8 = 0) {
			self.rawValue = rawValue
		}

		public init(booleanLiteral value: BooleanLiteralType) {
			rawValue = value ? .max : .zero
		}
	}
}
