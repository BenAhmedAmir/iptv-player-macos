import XCTest
@testable import IPTVPlayer

final class M3UParserTests: XCTestCase {
    let parser = M3UParserService()
    let testSourceID = UUID()

    // MARK: - Basic Parsing

    func testParseValidM3U() async throws {
        let content = """
        #EXTM3U
        #EXTINF:-1 tvg-id="bbc1" tvg-name="BBC One" tvg-logo="https://example.com/bbc1.png" group-title="UK",BBC One HD
        http://stream.example.com/bbc1
        #EXTINF:-1 tvg-id="cnn" tvg-name="CNN" tvg-logo="https://example.com/cnn.png" group-title="News",CNN International
        http://stream.example.com/cnn
        """

        let channels = try await parser.parseContent(content, sourceID: testSourceID)
        XCTAssertEqual(channels.count, 2)

        let bbc = channels[0]
        XCTAssertEqual(bbc.name, "BBC One HD")
        XCTAssertEqual(bbc.tvgID, "bbc1")
        XCTAssertEqual(bbc.group, "UK")
        XCTAssertEqual(bbc.logoURL?.absoluteString, "https://example.com/bbc1.png")
        XCTAssertEqual(bbc.streamURL.absoluteString, "http://stream.example.com/bbc1")
        XCTAssertEqual(bbc.sourceID, testSourceID)

        let cnn = channels[1]
        XCTAssertEqual(cnn.name, "CNN International")
        XCTAssertEqual(cnn.group, "News")
    }

    func testParseM3UWithoutHeader() async throws {
        let content = """
        #EXTINF:-1,Channel 1
        http://stream.example.com/ch1
        """

        let channels = try await parser.parseContent(content, sourceID: testSourceID)
        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels[0].name, "Channel 1")
    }

    func testParseEmptyM3U() async {
        let content = "#EXTM3U\n"

        do {
            _ = try await parser.parseContent(content, sourceID: testSourceID)
            XCTFail("Should throw for empty M3U")
        } catch {
            // Expected
        }
    }

    func testParseLargePlaylist() async throws {
        var content = "#EXTM3U\n"
        for i in 0..<1000 {
            content += "#EXTINF:-1 group-title=\"Group \(i % 10)\",Channel \(i)\n"
            content += "http://stream.example.com/ch\(i)\n"
        }

        let channels = try await parser.parseContent(content, sourceID: testSourceID)
        XCTAssertEqual(channels.count, 1000)
    }

    // MARK: - Attribute Parsing

    func testParseAllAttributes() async throws {
        let content = """
        #EXTM3U
        #EXTINF:-1 tvg-id="test" tvg-name="Test Name" tvg-logo="https://logo.com/test.png" tvg-language="English" tvg-country="US" group-title="Test Group",Display Name
        http://stream.example.com/test
        """

        let channels = try await parser.parseContent(content, sourceID: testSourceID)
        XCTAssertEqual(channels.count, 1)

        let ch = channels[0]
        XCTAssertEqual(ch.name, "Display Name")
        XCTAssertEqual(ch.tvgID, "test")
        XCTAssertEqual(ch.group, "Test Group")
        XCTAssertEqual(ch.language, "English")
        XCTAssertEqual(ch.country, "US")
    }

    func testParseM3UWithInvalidURLs() async throws {
        let content = """
        #EXTM3U
        #EXTINF:-1,Valid Channel
        http://stream.example.com/valid
        #EXTINF:-1,Invalid Channel
        not-a-url
        """

        let channels = try await parser.parseContent(content, sourceID: testSourceID)
        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels[0].name, "Valid Channel")
    }
}

final class ChannelModelTests: XCTestCase {
    func testCompoundID() {
        let sourceID = UUID()
        let channel = Channel(
            id: "123",
            sourceID: sourceID,
            name: "Test",
            streamURL: URL(string: "http://example.com")!,
            logoURL: nil,
            group: nil,
            tvgID: nil,
            language: nil,
            country: nil
        )

        XCTAssertEqual(channel.compoundID, "\(sourceID.uuidString)_123")
    }

    func testChannelEquality() {
        let sourceID = UUID()
        let ch1 = Channel(id: "1", sourceID: sourceID, name: "A", streamURL: URL(string: "http://a.com")!,
                          logoURL: nil, group: nil, tvgID: nil, language: nil, country: nil)
        let ch2 = Channel(id: "1", sourceID: sourceID, name: "B", streamURL: URL(string: "http://b.com")!,
                          logoURL: nil, group: nil, tvgID: nil, language: nil, country: nil)

        XCTAssertEqual(ch1, ch2) // Same compound ID
    }

    func testDifferentSourceChannelsAreNotEqual() {
        let ch1 = Channel(id: "1", sourceID: UUID(), name: "A", streamURL: URL(string: "http://a.com")!,
                          logoURL: nil, group: nil, tvgID: nil, language: nil, country: nil)
        let ch2 = Channel(id: "1", sourceID: UUID(), name: "A", streamURL: URL(string: "http://a.com")!,
                          logoURL: nil, group: nil, tvgID: nil, language: nil, country: nil)

        XCTAssertNotEqual(ch1, ch2) // Different source IDs
    }
}

final class SearchTests: XCTestCase {
    func testPartialSearch() {
        let channels = [
            makeChannel(name: "BBC News"),
            makeChannel(name: "CNN"),
            makeChannel(name: "Sky News"),
            makeChannel(name: "France 24"),
        ]

        let query = "news"
        let results = channels.filter { $0.name.lowercased().contains(query) }

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.contains(where: { $0.name == "BBC News" }))
        XCTAssertTrue(results.contains(where: { $0.name == "Sky News" }))
    }

    func testCaseInsensitiveSearch() {
        let channels = [makeChannel(name: "BBC NEWS")]
        let query = "bbc"
        let results = channels.filter { $0.name.lowercased().contains(query) }
        XCTAssertEqual(results.count, 1)
    }

    private func makeChannel(name: String) -> Channel {
        Channel(id: UUID().uuidString, sourceID: UUID(), name: name,
                streamURL: URL(string: "http://example.com")!,
                logoURL: nil, group: nil, tvgID: nil, language: nil, country: nil)
    }
}

final class FavoriteTests: XCTestCase {
    func testFavoriteCompoundID() {
        let sourceID = UUID()
        let fav = Favorite(profileID: UUID(), sourceID: sourceID, channelID: "42", channelName: "Test")
        XCTAssertEqual(fav.compoundChannelID, "\(sourceID.uuidString)_42")
    }

    func testProfileIsolation() {
        let profileA = UUID()
        let profileB = UUID()
        let sourceID = UUID()

        let favA = Favorite(profileID: profileA, sourceID: sourceID, channelID: "1", channelName: "Ch1")
        let favB = Favorite(profileID: profileB, sourceID: sourceID, channelID: "1", channelName: "Ch1")

        XCTAssertNotEqual(favA.profileID, favB.profileID)
        XCTAssertEqual(favA.compoundChannelID, favB.compoundChannelID)
        // Same channel compound ID but different profile scopes
    }
}

final class XtreamResponseTests: XCTestCase {
    func testDecodeAuthResponse() throws {
        let json = """
        {
            "user_info": {
                "username": "demo",
                "password": "test",
                "status": "Active",
                "exp_date": "9999999999",
                "is_trial": false,
                "active_cons": "1",
                "max_connections": "2",
                "created_at": "1609459200"
            },
            "server_info": {
                "url": "example.com",
                "port": "8080",
                "https_port": "8443",
                "server_protocol": "http",
                "rtmp_port": "1935",
                "timezone": "UTC",
                "timestamp_now": 1700000000,
                "time_now": "2023-01-01"
            }
        }
        """

        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(XtreamAuthResponse.self, from: data)

        XCTAssertNotNil(response.userInfo)
        XCTAssertEqual(response.userInfo?.username, "demo")
        XCTAssertEqual(response.userInfo?.status, "Active")
        XCTAssertTrue(response.userInfo?.isActive ?? false)
        XCTAssertFalse(response.userInfo?.isExpired ?? true)
        XCTAssertNotNil(response.serverInfo)
    }

    func testDecodeCategories() throws {
        let json = """
        [
            {"category_id": "1", "category_name": "News", "parent_id": 0},
            {"category_id": "2", "category_name": "Sports", "parent_id": 0}
        ]
        """

        let data = json.data(using: .utf8)!
        let categories = try JSONDecoder().decode([XtreamCategory].self, from: data)

        XCTAssertEqual(categories.count, 2)
        XCTAssertEqual(categories[0].categoryName, "News")
        XCTAssertEqual(categories[1].categoryID, "2")
    }

    func testExpiredAccount() throws {
        let json = """
        {
            "user_info": {
                "username": "demo",
                "password": "test",
                "status": "Active",
                "exp_date": "1000000000",
                "is_trial": false
            }
        }
        """

        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(XtreamAuthResponse.self, from: data)
        XCTAssertTrue(response.userInfo?.isExpired ?? false)
    }
}

final class PersistenceTests: XCTestCase {
    func testCachedChannelRoundTrip() {
        let sourceID = UUID()
        let channel = Channel(
            id: "42",
            sourceID: sourceID,
            name: "Test Channel",
            streamURL: URL(string: "http://example.com/stream")!,
            logoURL: URL(string: "http://example.com/logo.png"),
            group: "News",
            tvgID: "test-id",
            language: "English",
            country: "US"
        )

        let cached = CachedChannel(from: channel)
        let restored = cached.toChannel()

        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.id, channel.id)
        XCTAssertEqual(restored?.sourceID, channel.sourceID)
        XCTAssertEqual(restored?.name, channel.name)
        XCTAssertEqual(restored?.streamURL, channel.streamURL)
        XCTAssertEqual(restored?.logoURL, channel.logoURL)
        XCTAssertEqual(restored?.group, channel.group)
        XCTAssertEqual(restored?.tvgID, channel.tvgID)
    }

    func testProfileCodable() throws {
        let profile = Profile(name: "Test User")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(profile)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Profile.self, from: data)

        XCTAssertEqual(decoded.id, profile.id)
        XCTAssertEqual(decoded.name, profile.name)
    }
}

final class ErrorTests: XCTestCase {
    func testErrorDescriptions() {
        let errors: [IPTVError] = [
            .invalidCredentials,
            .expiredAccount,
            .serverUnavailable,
            .networkUnavailable,
            .timeout,
            .invalidResponse,
            .emptyChannelList,
            .invalidM3U("bad format"),
            .emptyM3U,
            .invalidStreamURL,
            .playbackFailed("codec error"),
            .keychainError("access denied"),
            .fileNotFound("/path/to/file"),
            .unknown("something broke"),
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }
}
