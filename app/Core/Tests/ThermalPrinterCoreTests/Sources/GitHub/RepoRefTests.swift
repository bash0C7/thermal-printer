import Testing
@testable import ThermalPrinterCore

@Test(arguments: [
    "octo-org/sample",
    "  octo-org/sample  ",
    "https://github.com/octo-org/sample",
    "https://github.com/octo-org/sample/",
    "https://github.com/octo-org/sample.git",
    "https://github.com/octo-org/sample/issues/12",
    "https://www.github.com/octo-org/sample/pull/3",
    "github.com/octo-org/sample",
    "https://github.com/octo-org/sample?tab=readme-ov-file",
    "https://github.com/octo-org/sample#readme",
])
func everyFormOfTheSameRepoParsesToOwnerAndName(text: String) {
    #expect(RepoRef.parse(text) == RepoRef(owner: "octo-org", name: "sample"))
}

@Test(arguments: ["", "octo-org", "octo-org/sample/extra words", "https://example.com/a/b",
                  "-bad/repo", "owner/..", "owner/re po", "a/b; rm -rf ~"])
func textThatIsNotARepoParsesToNil(text: String) {
    #expect(RepoRef.parse(text) == nil)
}

@Test func theNameWithOwnerJoinsTheTwoWithASlash() {
    #expect(RepoRef(owner: "octo-org", name: "sample").nameWithOwner == "octo-org/sample")
}
