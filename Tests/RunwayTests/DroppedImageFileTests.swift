import Foundation
import Testing
@testable import Runway

@Suite("Dropped image naming")
struct DroppedImageFileTests {
    @Test("A drag that names its file keeps that name")
    func keepsSuggestedName() {
        #expect(
            DroppedImageFile.name(
                suggested: "Screenshot 2026-08-24 at 20.59.47 (1).png",
                typeIdentifier: "public.png",
                timestamp: 1_787_580_185
            ) == "Screenshot 2026-08-24 at 20.59.47 (1).png"
        )
    }

    @Test("A name without an extension gets the one its type implies")
    func addsExtension() {
        #expect(
            DroppedImageFile.name(
                suggested: "pasted",
                typeIdentifier: "public.png",
                timestamp: 7
            ) == "pasted.png"
        )
    }

    @Test("Path separators in a suggested name cannot escape the drops folder")
    func sanitizesSeparators() {
        let name = DroppedImageFile.name(
            suggested: "../../etc/passwd.png",
            typeIdentifier: "public.png",
            timestamp: 7
        )
        #expect(!name.contains("/"))
    }

    @Test("A nameless drag falls back to a timestamped name")
    func fallsBackToTimestamp() {
        #expect(
            DroppedImageFile.name(
                suggested: nil,
                typeIdentifier: "public.jpeg",
                timestamp: 42
            ) == "dropped-image-42.jpeg"
        )
        #expect(
            DroppedImageFile.name(
                suggested: "   ",
                typeIdentifier: nil,
                timestamp: 42
            ) == "dropped-image-42.png"
        )
    }
}
