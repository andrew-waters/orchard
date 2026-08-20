import Foundation
import Testing
@testable import Orchard

struct FuzzyMatchTests {

    @Test("Empty query matches everything at score zero")
    func emptyQuery() {
        #expect(FuzzyMatch.score(query: "", candidate: "anything") == 0)
        #expect(FuzzyMatch.score(query: "   ", candidate: "anything") != nil)
    }

    @Test("A query that is not a subsequence does not match")
    func nonSubsequence() {
        #expect(FuzzyMatch.score(query: "xyz", candidate: "db") == nil)
        #expect(FuzzyMatch.score(query: "dbb", candidate: "db") == nil)
        #expect(FuzzyMatch.score(query: "ba", candidate: "ab") == nil)
    }

    @Test("Matching is case-insensitive")
    func caseInsensitive() {
        #expect(FuzzyMatch.score(query: "STOP", candidate: "Stop: db") != nil)
        #expect(FuzzyMatch.score(query: "stop", candidate: "STOP: DB") != nil)
    }

    @Test("Exact match beats word-boundary match beats scattered subsequence")
    func rankingOrder() throws {
        let exact = try #require(FuzzyMatch.score(query: "db", candidate: "db"))
        let boundary = try #require(FuzzyMatch.score(query: "db", candidate: "my-db"))
        let scattered = try #require(FuzzyMatch.score(query: "db", candidate: "dashboard"))
        #expect(exact > boundary)
        #expect(boundary > scattered)
    }

    @Test("Prefix match outranks a later word-boundary match")
    func prefixBeatsBoundary() throws {
        let prefix = try #require(FuzzyMatch.score(query: "post", candidate: "postgres:16"))
        let boundary = try #require(FuzzyMatch.score(query: "post", candidate: "db-postgres"))
        #expect(prefix > boundary)
    }

    @Test("Separators start words: slash, dot, colon, dash, underscore")
    func separatorBoundaries() throws {
        // "node" starts after a slash in the reference - it should score at least as a
        // word-boundary match, well above a scattered match of the same letters.
        let boundary = try #require(FuzzyMatch.score(query: "node", candidate: "kindest/node:v1.29"))
        let scattered = try #require(FuzzyMatch.score(query: "node", candidate: "nginx-loadbalancer-demo"))
        #expect(boundary > scattered)
    }

    @Test("Tighter matches beat spread-out matches")
    func contiguityWins() throws {
        let tight = try #require(FuzzyMatch.score(query: "redis", candidate: "redis:alpine"))
        let spread = try #require(FuzzyMatch.score(query: "redis", candidate: "registry-edge-dist"))
        #expect(tight > spread)
    }
}
