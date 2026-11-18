import Foundation
import Testing
@testable import AtolyeCore

/// Dil seçimi ve çeviri; global tabloya dokunmaz (diğer testler Türkçe metin bekliyor).
@Suite struct L10nTests {
    @Test func resolvesSystemLanguage() {
        #expect(L10n.resolve(.system, preferred: ["tr-TR", "en"]) == "tr")
        #expect(L10n.resolve(.system, preferred: ["de-DE", "tr"]) == "en") // Türkçe dışı her dil İngilizce
        #expect(L10n.resolve(.system, preferred: []) == "en")
        #expect(L10n.resolve(.tr, preferred: ["en"]) == "tr")
        #expect(L10n.resolve(.en, preferred: ["tr"]) == "en")
    }

    @Test func englishLooksUpTableAndFillsPlaceholders() {
        let table = ["Bugün ≈ {0} · {1} token": "Today ≈ {0} · {1} tokens"]
        #expect(L10n.translate("Bugün ≈ {0} · {1} token", ["$3", "12K"], language: "en", table: table) == "Today ≈ $3 · 12K tokens")
        #expect(L10n.translate("Çevirisi olmayan", [], language: "en", table: table) == "Çevirisi olmayan")
    }

    @Test func turkishUsesKeyWithPlaceholders() {
        #expect(L10n.translate("{0} gün", ["5"], language: "tr", table: ["{0} gün": "{0} days"]) == "5 gün")
    }

    @Test func loadsTableFromJSON() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("l10n-\(UUID().uuidString).json")
        try Data(#"{"Robotlar":"Robots"}"#.utf8).write(to: url)
        #expect(L10n.loadTable(url) == ["Robotlar": "Robots"])
        #expect(L10n.loadTable(url.appendingPathExtension("yok")) == [:])
    }
}

@Suite struct ProfileDisplayNameTests {
    let en = ["Profil {0}": "Profile {0}", "Varsayılan": "Default"]
    @Test func numberedAndDefaultNamesAreTranslated() {
        #expect(AccountProfile.displayName("Profil 3", language: "en", table: en) == "Profile 3")
        #expect(AccountProfile.displayName("Varsayılan", language: "en", table: en) == "Default")
        #expect(AccountProfile.displayName("Profil 3", language: "tr", table: en) == "Profil 3")
    }
    @Test func customNamesStay() {
        #expect(AccountProfile.displayName("İş hesabı", language: "en", table: en) == "İş hesabı")
        #expect(AccountProfile.displayName("Profil x", language: "en", table: en) == "Profil x")
    }
}
