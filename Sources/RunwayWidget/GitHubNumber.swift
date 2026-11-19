/// How a number is printed in Runway.
///
/// Always `String(number)`, never an interpolated `Int` inside a `Text`
/// literal. A `Text("#\(n)")` is a LocalizedStringKey, so the formatter puts
/// the locale's thousands separator in and the pane printed `#17.416` for
/// pull 17416. An issue number, a pull number and a count are all identifiers
/// or tallies, never quantities to format: use `Text(verbatim:)` or hand it a
/// String.
enum GitHubNumber {
    static func reference(_ number: Int) -> String {
        "#" + String(number)
    }
}
