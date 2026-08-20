import Foundation

/// Fuzzy subsequence scoring for the command palette. Pure and deterministic so it can be
/// unit-tested like the CLI parsers. Matching is a greedy left-to-right subsequence scan;
/// ranking follows the Sublime-style heuristics: an exact prefix beats a word-boundary
/// match beats a scattered subsequence, and tight matches beat spread-out ones.
enum FuzzyMatch {
    /// Characters that start a "word" inside identifiers and references
    /// (`kindest/node`, `my-app_v2`, `registry.io:tag`, `Stop: db`).
    private static let separators = Set(" -_./:@")

    /// Score `query` against `candidate`. Returns `nil` when the query is not a
    /// subsequence of the candidate; higher scores are better. An empty query matches
    /// everything with score 0 (the caller shows its curated default list).
    static func score(query: String, candidate: String) -> Int? {
        let q = Array(query.trimmingCharacters(in: .whitespaces).lowercased())
        guard !q.isEmpty else { return 0 }
        let c = Array(candidate.lowercased())
        guard c.count >= q.count else { return nil }

        // Greedy subsequence match, recording the matched indices.
        var matched: [Int] = []
        matched.reserveCapacity(q.count)
        var cursor = 0
        for ch in q {
            var found = false
            while cursor < c.count {
                if c[cursor] == ch {
                    matched.append(cursor)
                    cursor += 1
                    found = true
                    break
                }
                cursor += 1
            }
            if !found { return nil }
        }

        var score = 0

        // Whole query is a prefix of the candidate.
        if matched.first == 0, matched.last == q.count - 1 {
            score += 100
        }

        for (i, index) in matched.enumerated() {
            // Word-boundary start: first char, or preceded by a separator.
            if index == 0 || separators.contains(c[index - 1]) {
                score += 30
            }
            // Contiguity with the previously matched character.
            if i > 0, matched[i - 1] == index - 1 {
                score += 20
            }
        }

        // Penalise spread: characters skipped between the first and last match.
        if let first = matched.first, let last = matched.last {
            let gaps = (last - first + 1) - q.count
            score -= min(gaps, 30)
            // Penalise matches that start deep into the candidate.
            score -= min(first, 15)
        }

        return score
    }
}
