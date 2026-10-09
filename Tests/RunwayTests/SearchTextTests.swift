import Testing
@testable import Runway

struct SearchTextTests {
    @Test func plainQueryMatchesAccentedText() {
        #expect(SearchText.contains("Cust: KSÍ smoke", "ksi"))
        #expect(SearchText.contains("sjöppa", "sjoppa"))
        #expect(SearchText.contains("Ｒｕｎｗａｙ", "runway"))
    }

    @Test func icelandicLettersAreSpelledOut() {
        #expect(SearchText.contains("Arnar Þór Sveinsson", "thor"))
        #expect(SearchText.contains("Guðrún Ægisdóttir", "gudrun aegis"))
        #expect(SearchText.contains("Straße", "strasse"))
    }

    @Test func accentedQueryStillMatchesAccentedText() {
        #expect(SearchText.contains("Arnar Þór Sveinsson", "Þór"))
        #expect(SearchText.contains("Cust: KSÍ smoke", "KSÍ"))
        #expect(SearchText.contains("Cust: KSI smoke", "ksí"))
    }

    @Test func unrelatedTextDoesNotMatch() {
        #expect(!SearchText.contains("Cust: KSÍ smoke", "ksa"))
    }

    @Test func tokensMatchInAnyOrderAndEmptyQueryMatchesNothing() {
        #expect(SearchText.containsAllTokens(of: "smoke ksi", in: "Cust: KSÍ smoke"))
        #expect(!SearchText.containsAllTokens(of: "smoke ksa", in: "Cust: KSÍ smoke"))
        #expect(!SearchText.containsAllTokens(of: "   ", in: "Cust: KSÍ smoke"))
    }
}
