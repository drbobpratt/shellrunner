import Foundation
import SwiftData

@Model
final class CommandRun {
    var startedAt: Date
    var finishedAt: Date?
    var exitCode: Int32?
    var output: String
    var resolvedCommandText: String

    var command: SavedCommand?

    init(resolvedCommandText: String, command: SavedCommand? = nil) {
        self.startedAt = Date()
        self.output = ""
        self.resolvedCommandText = resolvedCommandText
        self.command = command
    }

    var duration: TimeInterval? {
        guard let finishedAt else { return nil }
        return finishedAt.timeIntervalSince(startedAt)
    }

    var isFinished: Bool { finishedAt != nil }

    var didSucceed: Bool { exitCode == 0 }
}
