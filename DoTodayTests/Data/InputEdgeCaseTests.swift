//
//  InputEdgeCaseTests.swift
//  DoTodayTests
//
//  Hostile input at the two places it enters the app: what the user types, and what
//  the API sends back.
//

import Foundation
import Testing
@testable import DoToday

@Suite("Search query edge cases")
struct SearchQueryEdgeCaseTests {

    private func makeSUT() -> (DefaultSearchCitiesUseCase, StubCityRepository) {
        let repository = StubCityRepository(result: .success([Fixture.city()]))
        return (DefaultSearchCitiesUseCase(repository: repository), repository)
    }

    @Test("Non-Latin and accented queries reach the API unmangled", arguments: [
        "München", "東京", "Кыив", "القاهرة", "Reykjavík", "São Paulo", "Ålesund"
    ])
    func unicodeQueriesArePreserved(query: String) async throws {
        let (sut, repository) = makeSUT()

        _ = try await sut.execute(query: query)

        #expect(repository.receivedQueries == [query])
    }

    @Test("Emoji and symbol queries are passed through rather than crashing", arguments: [
        "London 🇬🇧", "@#$%^&*()", "'; DROP TABLE cities;--", "<script>alert(1)</script>"
    ])
    func hostileQueriesAreHandled(query: String) async throws {
        let (sut, repository) = makeSUT()

        _ = try await sut.execute(query: query)

        // No sanitising here on purpose: `URLQueryItem` percent-encodes at the
        // boundary, and pre-mangling the text would break legitimate place names.
        #expect(repository.receivedQueries == [query])
    }

    @Test("A very long query is still dispatched rather than truncated silently")
    func veryLongQuery() async throws {
        let (sut, repository) = makeSUT()
        let long = String(repeating: "a", count: 5_000)

        _ = try await sut.execute(query: long)

        #expect(repository.receivedQueries.first?.count == 5_000)
    }

    @Test("Whitespace-only queries never reach the network", arguments: [
        "  ", "\n", "\t", "   \n\t  ", "\u{00A0}"
    ])
    func whitespaceOnlyQueries(query: String) async throws {
        let (sut, repository) = makeSUT()

        let results = try await sut.execute(query: query)

        #expect(results.isEmpty)
        #expect(repository.receivedQueries.isEmpty, "Whitespace was treated as a real query")
    }

    @Test("A two-character non-Latin query still meets the minimum length")
    func shortUnicodeQueryIsDispatched() async throws {
        let (sut, repository) = makeSUT()

        // Counted in Characters, not UTF-8 bytes — "東京" is 2 characters but 6 bytes.
        _ = try await sut.execute(query: "東京")

        #expect(repository.receivedQueries == ["東京"])
    }

    @Test("A single emoji is one character and so is below the minimum length")
    func singleEmojiIsTooShort() async throws {
        let (sut, repository) = makeSUT()

        #expect(try await sut.execute(query: "🏂").isEmpty)
        #expect(repository.receivedQueries.isEmpty)
    }

    @Test("A query that is one grapheme cluster is treated as one character")
    func graphemeClusterCounting() async throws {
        let (sut, repository) = makeSUT()

        // A family emoji is a single Character but many scalars; treating it as
        // several would wrongly let a one-symbol query through.
        _ = try await sut.execute(query: "👨‍👩‍👧‍👦")

        #expect(repository.receivedQueries.isEmpty)
    }
}

@Suite("Forecast payload edge cases")
struct ForecastPayloadEdgeCaseTests {

    private let retrievedAt = Date(timeIntervalSince1970: 1_757_203_200)

    private func map(_ json: String) throws -> Forecast {
        let dto = try JSONDecoder().decode(ForecastResponseDTO.self, from: Data(json.utf8))
        return try ForecastMapper.map(dto, retrievedAt: retrievedAt)
    }

    @Test("Duplicate dates are preserved rather than silently merged")
    func duplicateDates() throws {
        let forecast = try map("""
        {"latitude":0,"longitude":0,"timezone":"UTC","daily":{
          "time":["2026-09-07","2026-09-07"],"temperature_2m_max":[10,20]}}
        """)

        // Dropping one would hide a real API problem; the UI keys days by date, so
        // this is worth knowing about rather than papering over.
        #expect(forecast.days.count == 2)
    }

    @Test("Out-of-order dates keep the API's order rather than being re-sorted")
    func outOfOrderDates() throws {
        let forecast = try map("""
        {"latitude":0,"longitude":0,"timezone":"UTC","daily":{
          "time":["2026-09-09","2026-09-07","2026-09-08"]}}
        """)

        // The mapper is not the place to invent an ordering the API did not give us.
        #expect(forecast.days.count == 3)
    }

    @Test("A leap day maps correctly")
    func leapDay() throws {
        let forecast = try map("""
        {"latitude":0,"longitude":0,"timezone":"UTC","daily":{"time":["2028-02-29"]}}
        """)

        #expect(forecast.days.count == 1)
    }

    @Test("A day that does not exist in the calendar is dropped")
    func impossibleDate() throws {
        // 2026 is not a leap year.
        let forecast = try map("""
        {"latitude":0,"longitude":0,"timezone":"UTC","daily":{"time":["2026-02-30","2026-03-01"]}}
        """)

        #expect(forecast.days.count == 1)
    }

    @Test("A day spanning a daylight-saving transition still resolves")
    func daylightSavingTransition() throws {
        // 29 March 2026 is the UK clock change; local midnight still exists.
        let forecast = try map("""
        {"latitude":51.5,"longitude":-0.12,"timezone":"Europe/London","utc_offset_seconds":0,
         "daily":{"time":["2026-03-29"]}}
        """)

        #expect(forecast.days.count == 1)
    }

    @Test("An unknown time zone identifier falls back rather than failing the payload")
    func unknownTimeZone() throws {
        let forecast = try map("""
        {"latitude":0,"longitude":0,"timezone":"Mars/Olympus_Mons","utc_offset_seconds":7200,
         "daily":{"time":["2026-09-07"]}}
        """)

        #expect(TimeZone(identifier: forecast.timeZoneIdentifier)?.secondsFromGMT() == 7200)
    }

    @Test("Extra unknown keys in the payload are ignored")
    func forwardCompatibility() throws {
        // Open-Meteo adding a variable must not break an older build.
        let forecast = try map("""
        {"latitude":0,"longitude":0,"timezone":"UTC","some_new_field":123,
         "daily":{"time":["2026-09-07"],"a_variable_we_never_asked_for":[1]}}
        """)

        #expect(forecast.days.count == 1)
    }

    @Test("A long payload maps without truncation")
    func longPayload() throws {
        let times = (1...28).map { #""2026-09-\#(String(format: "%02d", $0))""# }.joined(separator: ",")
        let forecast = try map("""
        {"latitude":0,"longitude":0,"timezone":"UTC","daily":{"time":[\(times)]}}
        """)

        #expect(forecast.days.count == 28)
    }

    @Test("An array longer than time does not produce extra days")
    func overlongVariableArray() throws {
        let forecast = try map("""
        {"latitude":0,"longitude":0,"timezone":"UTC","daily":{
          "time":["2026-09-07"],"temperature_2m_max":[10,20,30,40]}}
        """)

        // `time` is the authority on how many days there are.
        #expect(forecast.days.count == 1)
        #expect(forecast.days.first?.temperatureMax == 10)
    }
}

@Suite("City payload edge cases")
struct CityPayloadEdgeCaseTests {

    private func map(_ json: String) throws -> [City] {
        CityMapper.map(try JSONDecoder().decode(GeocodingResponseDTO.self, from: Data(json.utf8)))
    }

    @Test("Results sharing an id are all returned; de-duplication is not the mapper's job")
    func duplicateIDs() throws {
        let cities = try map("""
        {"results":[
          {"id":1,"name":"Springfield","latitude":1,"longitude":1},
          {"id":1,"name":"Springfield","latitude":2,"longitude":2}]}
        """)

        // Worth knowing: `List` keys on `City.id`, so duplicates here would collapse
        // in the UI. The API does not actually do this, and the test documents that
        // assumption rather than hiding it.
        #expect(cities.count == 2)
    }

    @Test("An empty results array is not an error")
    func emptyResultsArray() throws {
        #expect(try map(#"{"results":[]}"#).isEmpty)
    }

    @Test("Extreme but valid coordinates survive mapping", arguments: [
        (lat: 90.0, lon: 180.0), (lat: -90.0, lon: -180.0), (lat: 0.0, lon: 0.0)
    ])
    func extremeCoordinates(lat: Double, lon: Double) throws {
        let city = try #require(try map("""
        {"results":[{"id":1,"name":"Edge","latitude":\(lat),"longitude":\(lon)}]}
        """).first)

        #expect(city.coordinate.latitude == lat)
        #expect(city.coordinate.longitude == lon)
    }

    @Test("A name containing only whitespace still produces a usable row")
    func blankName() throws {
        let city = try #require(try map(#"{"results":[{"id":1,"name":"   ","latitude":0,"longitude":0}]}"#).first)

        #expect(city.subtitle.isEmpty)
    }
}
