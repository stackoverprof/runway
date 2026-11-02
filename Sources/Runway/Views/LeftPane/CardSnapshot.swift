import AppKit
import SwiftUI

/// Draw the flight cards to a PNG and quit.
///
/// A design is checked by looking at it, and the window cannot always be
/// photographed: it may be on another Space, or behind something. Running
/// `RUNWAY_SNAPSHOT=/path/out.png` renders the real view with made-up issues
/// at a known width, so the card can be read pixel for pixel against the
/// sheet it was drawn from.
@MainActor
enum CardSnapshot {
    static var wanted: String? { ProcessInfo.processInfo.environment["RUNWAY_SNAPSHOT"] }

    static func writeAndExit(to path: String) {
        let board = FlightBoard.shared
        let samples: [(AssignedIssue, Int?)] = [
            (issue(17361, "Price Mismatch", legs: 34, landed: 33), 1),
            (issue(17357, "OneSignal Exit", legs: 4, landed: 0), 1),
            (issue(17354, "Zocalo", legs: 11, landed: 9), 1),
            (issue(17355, "Saffran", legs: 4, landed: 0), 2),
            (issue(17349, "Kiosk Receipts", legs: 7, landed: 7, closed: true), 2),
            (issue(17356, "Teya Ecom", legs: 12, landed: 9), 3),
        ]
        for (sample, level) in samples {
            if let level { board.setPriority(level, for: sample.number, in: "snapshot") }
        }
        let view = VStack(alignment: .leading, spacing: 16) {
            ForEach(samples.map(\.0)) { sample in
                AssignedIssueCard(
                    issue: sample,
                    repository: "monorepo",
                    boardKey: "snapshot",
                    isFlying: sample.number == 17354
                )
            }
        }
        .padding(16)
        .frame(width: 500)
        .background(Color.black)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("snapshot failed\n".utf8))
            exit(1)
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
        exit(0)
    }

    private static func issue(
        _ number: Int,
        _ title: String,
        legs: Int,
        landed: Int,
        closed: Bool = false
    ) -> AssignedIssue {
        var sample = AssignedIssue(
            number: number,
            title: title,
            state: closed ? "CLOSED" : "OPEN",
            closedAt: nil,
            createdAt: nil,
            updatedAt: nil,
            url: URL(string: "https://github.com/VISKA-IO/monorepo/issues/\(number)")!
        )
        sample.legs = (0..<legs).map { index in
            IssueLeg(
                number: number + index + 1,
                title: "leg \(index + 1)",
                state: index < landed ? "CLOSED" : "OPEN",
                url: URL(string: "https://github.com/VISKA-IO/monorepo/issues/\(number)")!
            )
        }
        return sample
    }
}
