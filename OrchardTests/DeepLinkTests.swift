import Foundation
import Testing
@testable import Orchard

private func link(_ string: String) -> DeepLink? {
    URL(string: string).flatMap(DeepLink.parse)
}

@Test("DeepLink: bare tab links resolve case-insensitively")
func deepLinkTabs() {
    #expect(link("orchard://containers") == .tab(.containers))
    #expect(link("orchard://Dashboard") == .tab(.dashboard))
    #expect(link("orchard://systemlogs") == .tab(.systemLogs))
    #expect(link("orchard://nonsense") == nil)
}

@Test("DeepLink: resource links carry their identifier")
func deepLinkResources() {
    #expect(link("orchard://container/web-1") == .container("web-1"))
    #expect(link("orchard://machine/dev-box") == .machine("dev-box"))
    #expect(link("orchard://dns/test.local") == .dnsDomain("test.local"))
    #expect(link("orchard://network/mynet") == .network("mynet"))
    #expect(link("orchard://mount/abc123") == .mount("abc123"))
}

@Test("DeepLink: image references keep interior slashes and tags")
func deepLinkImageReference() {
    #expect(link("orchard://image/docker.io/library/nginx:latest")
        == .image("docker.io/library/nginx:latest"))
}

@Test("DeepLink: a resource noun without an identifier falls back to its tab")
func deepLinkNounFallsBackToTab() {
    #expect(link("orchard://container") == .tab(.containers))
    #expect(link("orchard://container/") == .tab(.containers))
    #expect(link("orchard://image") == .tab(.images))
    #expect(link("orchard://dns") == .tab(.dns))
}

@Test("DeepLink: percent-encoded identifiers decode")
func deepLinkPercentDecoding() {
    #expect(link("orchard://container/web%2D1") == .container("web-1"))
}

@Test("DeepLink: foreign schemes are rejected")
func deepLinkForeignScheme() {
    #expect(link("https://container/web") == nil)
    #expect(link("docker://container/web") == nil)
}
