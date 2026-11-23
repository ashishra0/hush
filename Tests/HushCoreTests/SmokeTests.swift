import Testing
@testable import HushCore
@Test func version() { #expect(!HushCore.version.isEmpty) }
