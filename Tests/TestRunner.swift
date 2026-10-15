import Foundation

// MARK: - Test Harness

var passedCount = 0
var failedCount = 0

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #file, line: Int = #line) {
    if actual == expected {
        passedCount += 1
    } else {
        failedCount += 1
        print("❌ FAIL [\(line)]: Expected '\(expected)', got '\(actual)'. \(message)")
    }
}

func assertTrue(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) {
    if condition {
        passedCount += 1
    } else {
        failedCount += 1
        print("❌ FAIL [\(line)]: Expected true, got false. \(message)")
    }
}

func assertFalse(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) {
    if !condition {
        passedCount += 1
    } else {
        failedCount += 1
        print("❌ FAIL [\(line)]: Expected false, got true. \(message)")
    }
}

func assertNotNil<T>(_ value: T?, _ message: String = "", file: String = #file, line: Int = #line) {
    if value != nil {
        passedCount += 1
    } else {
        failedCount += 1
        print("❌ FAIL [\(line)]: Expected non-nil value. \(message)")
    }
}

func assertNil<T>(_ value: T?, _ message: String = "", file: String = #file, line: Int = #line) {
    if value == nil {
        passedCount += 1
    } else {
        failedCount += 1
        print("❌ FAIL [\(line)]: Expected nil value, got '\(String(describing: value))'. \(message)")
    }
}

// MARK: - Main Test Suite

@main
struct TestRunnerApp {
    static func main() async {
        print("========================================")
        print(" IPTV Player Native MVP - Test Suite")
        print(" Architecture: Apple Silicon (arm64)")
        print("========================================\n")

        let startTime = CFAbsoluteTimeGetCurrent()

        await runM3UParserTests()
        runChannelModelTests()
        runSearchTests()
        runFavoriteTests()
        runXtreamResponseTests()
        runPersistenceTests()
        runMovieAndSeriesTests()
        runCatalogueFilterTests()
        runTitleCleanerTests()
        runAccountExpiryTests()
        runSourceDeletionTests()
        runErrorTests()

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        print("\n========================================")
        print(" Test Results:")
        print(" Passed: \(passedCount)")
        print(" Failed: \(failedCount)")
        print(String(format: " Duration: %.3f seconds", elapsed))
        print("========================================")

        if failedCount > 0 {
            print("🚨 SOME TESTS FAILED!")
            exit(1)
        } else {
            print("✅ ALL TESTS PASSED!")
            exit(0)
        }
    }

    // MARK: - M3U Parser Tests

    static func runM3UParserTests() async {
        print("▶ Running M3UParserTests...")
        let parser = M3UParserService()
        let testSourceID = UUID()

        // 1. Valid M3U
        do {
            let content = """
            #EXTM3U
            #EXTINF:-1 tvg-id="bbc1" tvg-name="BBC One" tvg-logo="https://example.com/bbc1.png" group-title="UK",BBC One HD
            http://stream.example.com/bbc1
            #EXTINF:-1 tvg-id="cnn" tvg-name="CNN" tvg-logo="https://example.com/cnn.png" group-title="News",CNN International
            http://stream.example.com/cnn
            """
            let channels = try await parser.parseContent(content, sourceID: testSourceID)
            assertEqual(channels.count, 2, "Channel count should be 2")
            let bbc = channels[0]
            assertEqual(bbc.name, "BBC One HD")
            assertEqual(bbc.tvgID, "bbc1")
            assertEqual(bbc.group, "UK")
            assertEqual(bbc.logoURL?.absoluteString, "https://example.com/bbc1.png")
            assertEqual(bbc.streamURL.absoluteString, "http://stream.example.com/bbc1")
            assertEqual(bbc.sourceID, testSourceID)

            let cnn = channels[1]
            assertEqual(cnn.name, "CNN International")
            assertEqual(cnn.group, "News")
        } catch {
            failedCount += 1
            print("❌ testParseValidM3U failed with error: \(error)")
        }

        // 2. M3U without header
        do {
            let content = """
            #EXTINF:-1,Channel 1
            http://stream.example.com/ch1
            """
            let channels = try await parser.parseContent(content, sourceID: testSourceID)
            assertEqual(channels.count, 1)
            assertEqual(channels[0].name, "Channel 1")
        } catch {
            failedCount += 1
            print("❌ testParseM3UWithoutHeader failed: \(error)")
        }

        // 3. Empty M3U throws
        do {
            _ = try await parser.parseContent("#EXTM3U\n", sourceID: testSourceID)
            failedCount += 1
            print("❌ Empty M3U should throw")
        } catch {
            passedCount += 1
        }

        // 4. Large playlist (1000 items)
        do {
            var content = "#EXTM3U\n"
            for i in 0..<1000 {
                content += "#EXTINF:-1 group-title=\"Group \(i % 10)\",Channel \(i)\n"
                content += "http://stream.example.com/ch\(i)\n"
            }
            let channels = try await parser.parseContent(content, sourceID: testSourceID)
            assertEqual(channels.count, 1000, "Should parse 1000 channels")
        } catch {
            failedCount += 1
            print("❌ Large playlist failed: \(error)")
        }

        // 5. Parse attributes
        do {
            let content = """
            #EXTM3U
            #EXTINF:-1 tvg-id="test" tvg-name="Test Name" tvg-logo="https://logo.com/test.png" tvg-language="English" tvg-country="US" group-title="Test Group",Display Name
            http://stream.example.com/test
            """
            let channels = try await parser.parseContent(content, sourceID: testSourceID)
            assertEqual(channels.count, 1)
            let ch = channels[0]
            assertEqual(ch.name, "Display Name")
            assertEqual(ch.tvgID, "test")
            assertEqual(ch.group, "Test Group")
            assertEqual(ch.language, "English")
            assertEqual(ch.country, "US")
        } catch {
            failedCount += 1
            print("❌ All attributes failed: \(error)")
        }

        // 6. Invalid URLs
        do {
            let content = """
            #EXTM3U
            #EXTINF:-1,Valid Channel
            http://stream.example.com/valid
            #EXTINF:-1,Invalid Channel
            not-a-url
            """
            let channels = try await parser.parseContent(content, sourceID: testSourceID)
            assertEqual(channels.count, 1)
            assertEqual(channels[0].name, "Valid Channel")
        } catch {
            failedCount += 1
            print("❌ Invalid URLs test failed: \(error)")
        }

        // 7. Directives (#EXTVLCOPT, #KODIPROP) and commas inside attribute quotes
        do {
            let content = """
            #EXTM3U
            #EXTVLCOPT:http-user-agent=Mozilla/5.0
            #KODIPROP:inputstream.adaptive.manifest_type=hls
            #EXTINF:-1 tvg-id="cnn-hd" tvg-name="CNN, 24/7 Live" group-title="News, World",CNN International, HD
            #EXTVLCOPT:network-caching=1000
            http://stream.example.com/live/cnn.m3u8?token=xyz,123
            """
            let channels1 = try await parser.parseContent(content, sourceID: testSourceID)
            assertEqual(channels1.count, 1)
            let ch = channels1[0]
            assertEqual(ch.name, "CNN International, HD")
            assertEqual(ch.tvgID, "cnn-hd")
            assertEqual(ch.group, "News, World")
            assertEqual(ch.id, "cnn-hd")

            // Re-parsing should yield the identical channel ID
            let channels2 = try await parser.parseContent(content, sourceID: testSourceID)
            assertEqual(channels2[0].id, channels1[0].id)
            assertEqual(channels2[0].compoundID, channels1[0].compoundID)
        } catch {
            failedCount += 1
            print("❌ Directives & commas in quotes test failed: \(error)")
        }
    }

    // MARK: - Channel Model Tests

    static func runChannelModelTests() {
        print("▶ Running ChannelModelTests...")
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
        assertEqual(channel.compoundID, "\(sourceID.uuidString)_123")

        let ch1 = Channel(id: "1", sourceID: sourceID, name: "A", streamURL: URL(string: "http://a.com")!,
                          logoURL: nil, group: nil, tvgID: nil, language: nil, country: nil)
        let ch2 = Channel(id: "1", sourceID: sourceID, name: "B", streamURL: URL(string: "http://b.com")!,
                          logoURL: nil, group: nil, tvgID: nil, language: nil, country: nil)
        assertEqual(ch1, ch2) // Equality based on compound ID

        let ch3 = Channel(id: "1", sourceID: UUID(), name: "A", streamURL: URL(string: "http://a.com")!,
                          logoURL: nil, group: nil, tvgID: nil, language: nil, country: nil)
        assertTrue(ch1 != ch3) // Different source ID
    }

    // MARK: - Search Tests

    static func runSearchTests() {
        print("▶ Running SearchTests...")
        let channels = [
            makeChannel(name: "BBC News"),
            makeChannel(name: "CNN"),
            makeChannel(name: "Sky News"),
            makeChannel(name: "France 24"),
        ]

        let query = "news"
        let results = channels.filter { $0.name.lowercased().contains(query) }
        assertEqual(results.count, 2)
        assertTrue(results.contains(where: { $0.name == "BBC News" }))
        assertTrue(results.contains(where: { $0.name == "Sky News" }))

        let caseResults = [makeChannel(name: "BBC NEWS")].filter { $0.name.lowercased().contains("bbc") }
        assertEqual(caseResults.count, 1)
    }

    private static func makeChannel(name: String) -> Channel {
        Channel(id: UUID().uuidString, sourceID: UUID(), name: name,
                streamURL: URL(string: "http://example.com")!,
                logoURL: nil, group: nil, tvgID: nil, language: nil, country: nil)
    }

    // MARK: - Favorite Tests

    static func runFavoriteTests() {
        print("▶ Running FavoriteTests...")
        let sourceID = UUID()
        let fav = Favorite(profileID: UUID(), sourceID: sourceID, channelID: "42", channelName: "Test")
        assertEqual(fav.compoundChannelID, "\(sourceID.uuidString)_42")

        let profileA = UUID()
        let profileB = UUID()
        let favA = Favorite(profileID: profileA, sourceID: sourceID, channelID: "1", channelName: "Ch1")
        let favB = Favorite(profileID: profileB, sourceID: sourceID, channelID: "1", channelName: "Ch1")
        assertTrue(favA.profileID != favB.profileID)
        assertEqual(favA.compoundChannelID, favB.compoundChannelID)
    }

    // MARK: - Xtream Response Tests

    static func runXtreamResponseTests() {
        print("▶ Running XtreamResponseTests...")
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

        do {
            let data = json.data(using: .utf8)!
            let response = try JSONDecoder().decode(XtreamAuthResponse.self, from: data)
            assertNotNil(response.userInfo)
            assertEqual(response.userInfo?.username, "demo")
            assertEqual(response.userInfo?.status, "Active")
            assertTrue(response.userInfo?.isActive ?? false)
            assertFalse(response.userInfo?.isExpired ?? true)
            assertNotNil(response.serverInfo)
        } catch {
            failedCount += 1
            print("❌ Xtream decode failed: \(error)")
        }

        // Test is_trial as String "0" and "1"
        let stringTrialJSON = """
        {
            "user_info": {
                "username": "trial_user",
                "status": "Active",
                "is_trial": "1"
            }
        }
        """
        do {
            let resp = try JSONDecoder().decode(XtreamAuthResponse.self, from: stringTrialJSON.data(using: .utf8)!)
            assertTrue(resp.userInfo?.isTrial ?? false, "String is_trial '1' should decode as true")
        } catch {
            failedCount += 1
            print("❌ String trial '1' decode failed: \(error)")
        }

        // Test is_trial as numeric 0
        let intTrialJSON = """
        {
            "user_info": {
                "username": "regular_user",
                "status": "Active",
                "is_trial": 0
            }
        }
        """
        do {
            let resp = try JSONDecoder().decode(XtreamAuthResponse.self, from: intTrialJSON.data(using: .utf8)!)
            assertFalse(resp.userInfo?.isTrial ?? true, "Integer is_trial 0 should decode as false")
        } catch {
            failedCount += 1
            print("❌ Integer trial 0 decode failed: \(error)")
        }

        // Test XtreamLiveStream with string stream_id, numeric num, etc.
        let liveStreamJSON = """
        [
            {
                "num": "10",
                "name": "Live Channel 1",
                "stream_type": "live",
                "stream_id": "45678",
                "stream_icon": "http://img.example.com/logo.png",
                "category_id": "5",
                "container_extension": "ts"
            },
            {
                "num": 20,
                "name": "Live Channel 2",
                "stream_type": "live",
                "stream_id": 99999,
                "stream_icon": "",
                "category_id": 5,
                "container_extension": null
            }
        ]
        """
        do {
            let streams = try JSONDecoder().decode([XtreamLiveStream].self, from: liveStreamJSON.data(using: .utf8)!)
            assertEqual(streams.count, 2)
            assertEqual(streams[0].streamID, 45678)
            assertEqual(streams[0].num, 10)
            assertEqual(streams[0].categoryID, "5")
            assertEqual(streams[0].containerExtension, "ts")
            assertEqual(streams[1].streamID, 99999)
            assertEqual(streams[1].num, 20)
            assertEqual(streams[1].categoryID, "5")
            assertNil(streams[1].containerExtension)

            // Test convertToChannels with duplicate categories
            let categories = [
                try JSONDecoder().decode(XtreamCategory.self, from: "{\"category_id\":\"5\",\"category_name\":\"News\"}".data(using: .utf8)!),
                try JSONDecoder().decode(XtreamCategory.self, from: "{\"category_id\":\"5\",\"category_name\":\"News Duplicate\"}".data(using: .utf8)!)
            ]
            let service = XtreamAPIService()
            let sourceID = UUID()
            let channels = service.convertToChannels(
                streams: streams,
                categories: categories,
                serverURL: "http://example.com:8080/player_api.php",
                username: "user1",
                password: "pass1",
                sourceID: sourceID
            )
            assertEqual(channels.count, 2)
            assertEqual(channels[0].streamURL.absoluteString, "http://example.com:8080/live/user1/pass1/45678.ts")
            assertEqual(channels[1].streamURL.absoluteString, "http://example.com:8080/live/user1/pass1/99999.m3u8")
            assertEqual(channels[0].group, "News")
        } catch {
            failedCount += 1
            print("❌ Live stream decode or conversion failed: \(error)")
        }

        let catJSON = """
        [
            {"category_id": "1", "category_name": "News", "parent_id": 0},
            {"category_id": "2", "category_name": "Sports", "parent_id": 0}
        ]
        """
        do {
            let categories = try JSONDecoder().decode([XtreamCategory].self, from: catJSON.data(using: .utf8)!)
            assertEqual(categories.count, 2)
            assertEqual(categories[0].categoryName, "News")
            assertEqual(categories[1].categoryID, "2")
        } catch {
            failedCount += 1
            print("❌ Xtream category decode failed: \(error)")
        }

        let expiredJSON = """
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
        do {
            let resp = try JSONDecoder().decode(XtreamAuthResponse.self, from: expiredJSON.data(using: .utf8)!)
            assertTrue(resp.userInfo?.isExpired ?? false)
        } catch {
            failedCount += 1
            print("❌ Expired account test failed: \(error)")
        }
    }

    // MARK: - Persistence Tests

    static func runPersistenceTests() {
        print("▶ Running PersistenceTests...")
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

        assertNotNil(restored)
        assertEqual(restored?.id, channel.id)
        assertEqual(restored?.sourceID, channel.sourceID)
        assertEqual(restored?.name, channel.name)
        assertEqual(restored?.streamURL, channel.streamURL)
        assertEqual(restored?.logoURL, channel.logoURL)
        assertEqual(restored?.group, channel.group)
        assertEqual(restored?.tvgID, channel.tvgID)

        do {
            let profile = Profile(name: "Test User")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(profile)

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(Profile.self, from: data)
            assertEqual(decoded.id, profile.id)
            assertEqual(decoded.name, profile.name)
        } catch {
            failedCount += 1
            print("❌ Profile codable test failed: \(error)")
        }
    }

    // MARK: - Movies & TV Shows (VOD) Tests

    static func runMovieAndSeriesTests() {
        print("▶ Running MovieAndSeriesTests...")
        let xtreamService = XtreamAPIService()
        let testSourceID = UUID()

        // 1. Decode Xtream VOD Stream JSON
        let vodJSON = """
        [
            {
                "num": 1,
                "name": "Inception (2010)",
                "stream_type": "movie",
                "stream_id": 55123,
                "stream_icon": "https://image.tmdb.org/t/p/w600/inception.jpg",
                "rating": "8.8",
                "category_id": "10",
                "container_extension": "mkv"
            },
            {
                "num": 2,
                "name": "Interstellar (2014)",
                "stream_type": "movie",
                "stream_id": "99412",
                "stream_icon": "https://image.tmdb.org/t/p/w600/interstellar.jpg",
                "rating": 8.6,
                "category_id": 10,
                "container_extension": "mp4"
            }
        ]
        """.data(using: .utf8)!

        do {
            let streams = try JSONDecoder().decode([XtreamVODStream].self, from: vodJSON)
            assertEqual(streams.count, 2, "Should decode 2 VOD streams")
            assertEqual(streams[0].streamID, 55123)
            assertEqual(streams[1].streamID, 99412)
            assertEqual(streams[0].rating, 8.8)
            assertEqual(streams[1].rating, 8.6)

            let cat = try JSONDecoder().decode([XtreamCategory].self, from: """
            [{"category_id": "10", "category_name": "Sci-Fi"}]
            """.data(using: .utf8)!)

            let movies = xtreamService.convertToMovies(
                streams: streams,
                categories: cat,
                serverURL: "http://example.com:8080",
                username: "testuser",
                password: "testpass",
                sourceID: testSourceID
            )

            assertEqual(movies.count, 2, "Should convert to 2 movies")
            assertEqual(movies[0].name, "Inception (2010)")
            assertEqual(movies[0].categoryName, "Sci-Fi")
            assertEqual(movies[0].streamURL.absoluteString, "http://example.com:8080/movie/testuser/testpass/55123.mkv")
            assertEqual(movies[1].streamURL.absoluteString, "http://example.com:8080/movie/testuser/testpass/99412.mp4")
            assertEqual(movies[0].compoundID, "\(testSourceID.uuidString)_55123")
        } catch {
            failedCount += 1
            print("❌ VOD decoding failed: \(error)")
        }

        // 2. Decode Series JSON
        let seriesJSON = """
        [
            {
                "series_id": 4410,
                "name": "Breaking Bad",
                "cover": "https://image.tmdb.org/t/p/w600/bb.jpg",
                "plot": "A chemistry teacher diagnosed with cancer...",
                "genre": "Crime, Drama",
                "rating": "9.5",
                "episode_run_time": "47",
                "category_id": "20",
                "backdrop_path": ["https://image.tmdb.org/t/p/w1280/bb_back.jpg"]
            }
        ]
        """.data(using: .utf8)!

        do {
            let seriesItems = try JSONDecoder().decode([XtreamSeriesItem].self, from: seriesJSON)
            assertEqual(seriesItems.count, 1, "Should decode 1 series item")
            assertEqual(seriesItems[0].seriesID, 4410)
            assertEqual(seriesItems[0].rating, 9.5)
            assertEqual(seriesItems[0].backdropPath?.count, 1)

            let cat = try JSONDecoder().decode([XtreamCategory].self, from: """
            [{"category_id": "20", "category_name": "Top Drama"}]
            """.data(using: .utf8)!)

            let seriesList = xtreamService.convertToSeries(
                items: seriesItems,
                categories: cat,
                serverURL: "http://example.com:8080",
                username: "testuser",
                password: "testpass",
                sourceID: testSourceID
            )

            assertEqual(seriesList.count, 1)
            let bb = seriesList[0]
            assertEqual(bb.name, "Breaking Bad")
            assertEqual(bb.categoryName, "Top Drama")
            assertEqual(bb.genre, "Crime, Drama")
            assertEqual(bb.compoundID, "\(testSourceID.uuidString)_4410")
        } catch {
            failedCount += 1
            print("❌ Series decoding failed: \(error)")
        }

        // 3. Decode Series Info & Episodes
        let seriesInfoJSON = """
        {
            "episodes": {
                "1": [
                    {
                        "id": "8001",
                        "episode_num": 1,
                        "title": "Pilot",
                        "container_extension": "mp4",
                        "season": 1,
                        "info": {
                            "duration_secs": 3480,
                            "duration": "00:58:00",
                            "plot": "Walter White begins his journey"
                        }
                    },
                    {
                        "id": "8002",
                        "episode_num": 2,
                        "title": "Cat's in the Bag...",
                        "container_extension": "mkv",
                        "season": 1,
                        "info": {
                            "duration_secs": 2880,
                            "duration": "00:48:00"
                        }
                    }
                ]
            }
        }
        """.data(using: .utf8)!

        do {
            let infoResponse = try JSONDecoder().decode(XtreamSeriesInfoResponse.self, from: seriesInfoJSON)
            assertNotNil(infoResponse.episodes)
            assertEqual(infoResponse.episodes?["1"]?.count, 2)

            let episodes = xtreamService.convertToEpisodes(
                response: infoResponse,
                seriesID: "4410",
                serverURL: "http://example.com:8080",
                username: "testuser",
                password: "testpass",
                sourceID: testSourceID
            )

            assertEqual(episodes.count, 2, "Should convert to 2 episodes")
            assertEqual(episodes[0].seasonNumber, 1)
            assertEqual(episodes[0].episodeNumber, 1)
            assertEqual(episodes[0].title, "Pilot")
            assertEqual(episodes[0].durationSecs, 3480)
            assertEqual(episodes[0].formattedDuration, "00:58:00")
            assertEqual(episodes[0].streamURL.absoluteString, "http://example.com:8080/series/testuser/testpass/8001.mp4")
            assertEqual(episodes[1].streamURL.absoluteString, "http://example.com:8080/series/testuser/testpass/8002.mkv")
        } catch {
            failedCount += 1
            print("❌ Series info decoding failed: \(error)")
        }

        // 4. Persistence of VOD and Series
        let persistence = PersistenceController.shared
        let dummyMovie = Movie(
            id: "test1",
            sourceID: testSourceID,
            name: "Test Movie",
            streamURL: URL(string: "http://example.com/test.mp4")!,
            posterURL: nil,
            rating: 7.5,
            categoryID: "1",
            categoryName: "Action",
            containerExtension: "mp4",
            added: nil
        )
        persistence.saveCachedMovies([dummyMovie], sourceID: testSourceID)
        let loadedMovies = persistence.loadCachedMovies(sourceID: testSourceID)
        assertNotNil(loadedMovies)
        assertEqual(loadedMovies?.count, 1)
        assertEqual(loadedMovies?.first?.name, "Test Movie")

        let dummySeries = Series(
            id: "series1",
            sourceID: testSourceID,
            name: "Test Show",
            coverURL: nil,
            backdropURL: nil,
            plot: "Test plot",
            cast: nil,
            director: nil,
            genre: "Sci-Fi",
            releaseDate: "2024",
            rating: 8.0,
            episodeRunTime: "50",
            categoryID: "2",
            categoryName: "Sci-Fi"
        )
        persistence.saveCachedSeries([dummySeries], sourceID: testSourceID)
        let loadedSeries = persistence.loadCachedSeries(sourceID: testSourceID)
        assertNotNil(loadedSeries)
        assertEqual(loadedSeries?.count, 1)
        assertEqual(loadedSeries?.first?.name, "Test Show")
    }

    // MARK: - Error Tests


    // MARK: - Catalogue Filter Metadata

    static func runCatalogueFilterTests() {
        print("▶ Running CatalogueFilterTests...")

        // Year is read from free text, so the exact shapes the provider sends matter.
        assertEqual(VODMetadata.year(in: "Back in Action 2025 (Multi)"), 2025, "year inside a movie title")
        assertEqual(VODMetadata.year(in: "2026-03-27"), 2026, "ISO release date")
        assertEqual(VODMetadata.year(in: "2021"), 2021, "bare year")
        // Ranges take the later year: a show running 1989-2011 is filtered on its end.
        assertEqual(VODMetadata.year(in: "1989-2011"), 2011, "year range takes the later year")
        assertEqual(VODMetadata.year(in: "2024-2026"), 2026, "ongoing range takes the later year")
        assertNil(VODMetadata.year(in: "The Movie"), "no year present")
        assertNil(VODMetadata.year(in: nil), "nil input")
        assertNil(VODMetadata.year(in: "1899"), "out-of-range year is not matched")

        // Ratings are nominally out of 10 but this catalogue contains 57, and 0
        // means "unrated" rather than "terrible".
        assertEqual(VODMetadata.normalizedRating(7.0), 7.0, "ordinary rating")
        assertEqual(VODMetadata.normalizedRating(10.0), 10.0, "upper bound kept")
        assertNil(VODMetadata.normalizedRating(0), "zero means unrated")
        assertNil(VODMetadata.normalizedRating(57), "out-of-scale rating discarded")
        assertNil(VODMetadata.normalizedRating(-3), "negative discarded")
        assertNil(VODMetadata.normalizedRating(nil), "missing rating")

        let sourceID = UUID()
        let movie = Movie(
            id: "1",
            sourceID: sourceID,
            name: "Whiplash 2014",
            streamURL: URL(string: "http://example.com/movie/1.mkv")!,
            posterURL: nil,
            rating: 8.5,
            categoryID: "10",
            categoryName: "Drama",
            containerExtension: "mkv",
            added: "1790842349"
        )
        assertEqual(movie.year, 2014, "movie year parsed from title")
        assertEqual(movie.normalizedRating, 8.5, "movie rating normalized")
        assertNotNil(movie.addedDate, "added timestamp parsed")

        let unrated = Movie(
            id: "2", sourceID: sourceID, name: "Untitled",
            streamURL: URL(string: "http://example.com/movie/2.mp4")!,
            posterURL: nil, rating: 0, categoryID: nil, categoryName: nil,
            containerExtension: "mp4", added: "not-a-number"
        )
        assertNil(unrated.normalizedRating, "zero rating treated as unrated")
        assertNil(unrated.year, "no year in title")
        assertNil(unrated.addedDate, "unparseable timestamp")

        let show = Series(
            id: "5", sourceID: sourceID, name: "Example Show",
            coverURL: nil, backdropURL: nil, plot: nil, cast: nil, director: nil,
            genre: "Action & Adventure, Drama , ,Crime",
            releaseDate: "1989-2011", rating: 9.0,
            episodeRunTime: "45", categoryID: nil, categoryName: nil
        )
        assertEqual(show.genreList, ["Action & Adventure", "Drama", "Crime"], "genres split and trimmed, blanks dropped")
        assertEqual(show.year, 2011, "series year from release range")
        assertEqual(show.normalizedRating, 9.0, "series rating normalized")
    }


    // MARK: - Title Cleaning

    static func runTitleCleanerTests() {
        print("▶ Running TitleCleanerTests...")

        // Series: language prefix becomes a badge, year ranges disappear.
        let dark = TitleCleaner.series("DE | Dark (2017-2020)")
        assertEqual(dark.badge, "DE", "language prefix lifted to badge")
        assertEqual(dark.title, "Dark", "year range stripped")

        let lupin = TitleCleaner.series("FR - Lupin (2021)")
        assertEqual(lupin.badge, "FR", "dash-separated prefix")
        assertEqual(lupin.title, "Lupin", "single year stripped")

        let trailing = TitleCleaner.series("Breaking Bad (EN)")
        assertEqual(trailing.badge, "EN", "trailing tag lifted to badge")
        assertEqual(trailing.title, "Breaking Bad", "trailing tag removed")

        let plain = TitleCleaner.series("The Undertow")
        assertNil(plain.badge, "no badge when there is no tag")
        assertEqual(plain.title, "The Undertow", "plain title untouched")

        // A genuine word must not be mistaken for a language tag.
        let documentary = TitleCleaner.series("Documentary - The Deep")
        assertNil(documentary.badge, "long prefix is not a namespace")

        // Episodes: SxxExx markers in every shape the regex covers.
        assertEqual(
            TitleCleaner.episode("Dark S01E03 The Crossing", seriesName: "Dark", number: 3),
            "The Crossing", "S01E03 marker and series name removed"
        )
        assertEqual(
            TitleCleaner.episode("Dark S01.E02", seriesName: "Dark", number: 2),
            "Episode 2", "nothing left but the marker falls back"
        )
        assertEqual(
            TitleCleaner.episode("s1 - e12 Fault Lines", seriesName: "Dark", number: 12),
            "Fault Lines", "spaced and dashed marker"
        )
        assertEqual(
            TitleCleaner.episode(nil, seriesName: "Dark", number: 7),
            "Episode 7", "missing title falls back"
        )
        assertEqual(
            TitleCleaner.episode("  ", seriesName: "Dark", number: 4),
            "Episode 4", "blank title falls back"
        )
        assertEqual(
            TitleCleaner.episode("5", seriesName: "Dark", number: 5),
            "Episode 5", "bare number is not a title"
        )
        assertEqual(
            TitleCleaner.episode("Open Water", seriesName: "Dark", number: 4),
            "Open Water", "real titles survive untouched"
        )

        // Duration formatting.
        assertEqual(TitleCleaner.duration(seconds: 4860, fallback: nil), "1h 21m", "over an hour")
        assertEqual(TitleCleaner.duration(seconds: 2820, fallback: nil), "47m", "under an hour")
        assertEqual(TitleCleaner.duration(seconds: nil, fallback: "45"), "45", "falls back to provider string")
        assertEqual(TitleCleaner.duration(seconds: 0, fallback: nil), "", "zero yields nothing")
    }


    // MARK: - Account Expiry

    static func runAccountExpiryTests() {
        print("▶ Running AccountExpiryTests...")

        func info(expDate: String?) throws -> XtreamAccountInfo {
            let exp = expDate.map { "\"\($0)\"" } ?? "null"
            let json = "{\"status\":\"Active\",\"exp_date\":\(exp),\"max_connections\":\"2\"}"
            return try JSONDecoder().decode(XtreamAccountInfo.self, from: Data(json.utf8))
        }

        // exp_date arrives as a Unix timestamp string.
        let future = Date().addingTimeInterval(60 * 60 * 24 * 30)
        let decoded = try? info(expDate: String(Int(future.timeIntervalSince1970)))
        assertNotNil(decoded?.expiryDate, "timestamp parsed into a date")
        assertFalse(decoded?.isExpired ?? true, "future expiry is not expired")

        let past = Date().addingTimeInterval(-60 * 60 * 24)
        let lapsed = try? info(expDate: String(Int(past.timeIntervalSince1970)))
        assertTrue(lapsed?.isExpired ?? false, "past expiry is expired")

        // Lifetime accounts send nothing, or a zero — neither is a real date.
        let lifetime = try? info(expDate: nil)
        assertNil(lifetime?.expiryDate, "absent exp_date yields no date")
        assertFalse(lifetime?.isExpired ?? true, "no expiry is not 'expired'")

        let zero = try? info(expDate: "0")
        assertNil(zero?.expiryDate, "zero timestamp is not a date")
        assertFalse(zero?.isExpired ?? true, "zero timestamp is not expired")

        let garbage = try? info(expDate: "not-a-number")
        assertNil(garbage?.expiryDate, "unparseable exp_date yields no date")

        assertEqual(decoded?.maxConnectionCount, 2, "max_connections parsed")
    }


    // MARK: - Source Deletion

    static func runSourceDeletionTests() {
        print("▶ Running SourceDeletionTests...")

        let persistence = PersistenceController.shared
        let profileID = UUID()
        let doomed = UUID()
        let keeper = UUID()

        func channel(_ sourceID: UUID, _ name: String) -> CachedChannel {
            CachedChannel(from: Channel(
                id: "ch1",
                sourceID: sourceID,
                name: name,
                streamURL: URL(string: "http://example.com/live/1.ts")!,
                logoURL: nil,
                group: nil,
                tvgID: nil,
                language: nil,
                country: nil
            ))
        }

        // Caches for two sources, so deletion must be surgical rather than broad.
        persistence.saveCachedChannels([channel(doomed, "Doomed")], sourceID: doomed)
        persistence.saveCachedChannels([channel(keeper, "Keeper")], sourceID: keeper)
        persistence.saveVODCategories(
            [XtreamCategory(categoryID: "1", categoryName: "Action", parentID: 0)],
            sourceID: doomed
        )
        persistence.saveSeriesCategories(
            [XtreamCategory(categoryID: "2", categoryName: "Drama", parentID: 0)],
            sourceID: doomed
        )

        let favorites = [
            Favorite(profileID: profileID, sourceID: doomed, channelID: "a", channelName: "Doomed"),
            Favorite(profileID: profileID, sourceID: keeper, channelID: "b", channelName: "Keeper")
        ]
        persistence.saveFavorites(favorites, profileID: profileID)

        assertNotNil(persistence.loadCachedChannels(sourceID: doomed), "doomed cache written")
        assertEqual(persistence.loadFavorites(profileID: profileID).count, 2, "both favorites written")

        persistence.deleteAllData(sourceID: doomed, profileID: profileID)

        // Everything belonging to the deleted source is gone...
        assertNil(persistence.loadCachedChannels(sourceID: doomed), "channel cache removed")
        assertNil(persistence.loadVODCategories(sourceID: doomed), "VOD categories removed")
        assertNil(persistence.loadSeriesCategories(sourceID: doomed), "series categories removed")

        let remainingFavorites = persistence.loadFavorites(profileID: profileID)
        assertEqual(remainingFavorites.count, 1, "only the doomed favorite is dropped")
        assertEqual(remainingFavorites.first?.sourceID, keeper, "the other source's favorite survives")

        // ...and the untouched source is intact.
        assertNotNil(persistence.loadCachedChannels(sourceID: keeper), "other source's cache survives")

        // Clean up so the test leaves nothing behind.
        persistence.deleteAllData(sourceID: keeper, profileID: profileID)
        persistence.deleteProfileData(profileID: profileID)
    }

    static func runErrorTests() {
        print("▶ Running ErrorTests...")
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
            assertNotNil(error.errorDescription)
            assertFalse(error.errorDescription!.isEmpty)
        }
    }
}
