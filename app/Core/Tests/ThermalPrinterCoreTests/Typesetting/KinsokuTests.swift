import Testing
@testable import ThermalPrinterCore

@Suite struct TypesettingKinsokuTests {

    @Test(arguments: Array("、。，．・：；？！ー～…‥」』）］｝〕〉》】〙〗’”ゝゞヽヾぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮヵヶ々"))
    func japaneseLineStartForbiddenCharactersAreListed(character: Character) {
        #expect(Kinsoku.lineStartForbidden.contains(character))
    }

    @Test(arguments: Array(",.:;?!)]}"))
    func asciiLineStartForbiddenCharactersAreListed(character: Character) {
        #expect(Kinsoku.lineStartForbidden.contains(character))
    }

    @Test(arguments: Array("「『（［｛〔〈《【〘〖‘“"))
    func japaneseLineEndForbiddenCharactersAreListed(character: Character) {
        #expect(Kinsoku.lineEndForbidden.contains(character))
    }

    @Test(arguments: Array("([{"))
    func asciiLineEndForbiddenCharactersAreListed(character: Character) {
        #expect(Kinsoku.lineEndForbidden.contains(character))
    }

    @Test func theTwoSetsDoNotOverlap() {
        #expect(Kinsoku.lineStartForbidden.isDisjoint(with: Kinsoku.lineEndForbidden))
    }

    @Test(arguments: Array("あいうえお漢字ABC123"))
    func ordinaryCharactersAreNotForbidden(character: Character) {
        #expect(!Kinsoku.lineStartForbidden.contains(character))
        #expect(!Kinsoku.lineEndForbidden.contains(character))
    }
}
