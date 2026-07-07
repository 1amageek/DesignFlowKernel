import Foundation

struct DesignFlowCLIArgumentParser {
    private let arguments: [String]
    private var index: Int

    init(arguments: [String]) {
        self.arguments = arguments
        self.index = 0
    }

    mutating func next() -> String? {
        guard index < arguments.count else {
            return nil
        }
        let value = arguments[index]
        index += 1
        return value
    }

    mutating func requiredValue(after option: String) throws -> String {
        guard let value = next(), !value.hasPrefix("--") else {
            throw DesignFlowCLIError.missingValue(option)
        }
        return value
    }
}
