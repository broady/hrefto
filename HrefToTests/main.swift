import Foundation

private func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ msg: String,
                                        file: StaticString = #file, line: UInt = #line) {
    if actual != expected {
        print("FAIL [\(file):\(line)] \(msg)\n  got:      \(actual)\n  expected: \(expected)")
        exit(1)
    }
}

private func assertNil<T>(_ value: T?, _ msg: String,
                          file: StaticString = #file, line: UInt = #line) {
    if value != nil {
        print("FAIL [\(file):\(line)] \(msg)\n  got: \(value!)")
        exit(1)
    }
}

private func extract(_ s: String) -> (host: String, prefix: String)? {
    PathPrefixHost.extract(from: URL(string: s)!)
}

// Basic github.com repo URL.
do {
    let r = extract("https://github.com/anthropics/claude-code")
    assertEqual(r?.host, "github.com", "basic repo host")
    assertEqual(r?.prefix, "/anthropics/claude-code", "basic repo prefix")
}

// Deeper path under a repo still resolves to the org/repo prefix.
do {
    let r = extract("https://github.com/anthropics/claude-code/blob/main/README.md")
    assertEqual(r?.host, "github.com", "deep path host")
    assertEqual(r?.prefix, "/anthropics/claude-code", "deep path prefix")
}

// www.github.com is canonicalised to github.com.
do {
    let r = extract("https://www.github.com/anthropics/claude-code")
    assertEqual(r?.host, "github.com", "www. canonicalised")
    assertEqual(r?.prefix, "/anthropics/claude-code", "www. prefix")
}

// Uppercase host is canonicalised.
do {
    let r = extract("https://GitHub.com/Anthropics/Claude-Code")
    assertEqual(r?.host, "github.com", "uppercase host lowercased")
    // Path segments preserve their original case (URLs are path-case-sensitive).
    assertEqual(r?.prefix, "/Anthropics/Claude-Code", "path case preserved")
}

// User profile (only one path segment) → no prefix match.
assertNil(extract("https://github.com/anthropics"), "single segment rejected")

// Bare host with no path → no prefix match.
assertNil(extract("https://github.com/"), "bare host rejected")
assertNil(extract("https://github.com"), "no path rejected")

// Subdomains are not in the supported list.
assertNil(extract("https://gist.github.com/abc/def"), "gist subdomain rejected")
assertNil(extract("https://api.github.com/repos/x/y"), "api subdomain rejected")

// Other hosts are unaffected.
assertNil(extract("https://example.com/foo/bar"), "non-supported host rejected")
assertNil(extract("https://gitlab.com/foo/bar"), "gitlab not yet supported")

// Trailing slash after repo still works.
do {
    let r = extract("https://github.com/anthropics/claude-code/")
    assertEqual(r?.prefix, "/anthropics/claude-code", "trailing slash ignored")
}

print("PathPrefixHost: all tests passed")
