enum GitHubNumber {
    static func reference(_ number: Int) -> String {
        "#" + String(number)
    }
}
