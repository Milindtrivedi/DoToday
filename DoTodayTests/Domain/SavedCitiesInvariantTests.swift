//
//  SavedCitiesInvariantTests.swift
//  DoTodayTests
//
//  Property-based ("monkey") testing for the saved-cities state machine.
//
//  The example-based tests in `SavedCitiesUseCaseTests` check sequences I thought of.
//  These throw thousands of *random* operation sequences at the same type and assert
//  that a set of invariants holds after every single step — which catches the orderings
//  I did not think of. A failure prints the exact seed and step, so any counterexample
//  is reproducible rather than a mystery.
//

import Foundation
import Testing
@testable import DoToday

@Suite("SavedCities invariants under random operation sequences")
struct SavedCitiesInvariantTests {

    /// The operations a user can perform on the saved lists.
    private enum Operation: CaseIterable, CustomStringConvertible {
        case visit, toggleFavourite, removeRecent, clearRecents, reload

        var description: String {
            switch self {
            case .visit: return "visit"
            case .toggleFavourite: return "toggleFavourite"
            case .removeRecent: return "removeRecent"
            case .clearRecents: return "clearRecents"
            case .reload: return "reload"
            }
        }
    }

    /// Deterministic PRNG so a failing run can be replayed exactly from its seed.
    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
        mutating func next() -> UInt64 {
            // xorshift64*
            state ^= state >> 12
            state ^= state << 25
            state ^= state >> 27
            return state &* 2_685_821_657_736_338_717
        }
    }

    /// Everything that must be true of the two lists after *any* operation.
    private func assertInvariants(_ lists: SavedCityLists, context: String) {

        // 1. Recents are capped. An uncapped list would grow without bound.
        #expect(lists.recent.count <= DefaultSavedCitiesUseCase.recentLimit,
                "recents exceeded the cap — \(context)")

        // 2. Neither list may contain the same city twice. Duplicates would render as
        //    repeated rows and break ForEach identity.
        #expect(Set(lists.recent.map(\.id)).count == lists.recent.count,
                "duplicate in recents — \(context)")
        #expect(Set(lists.favourites.map(\.id)).count == lists.favourites.count,
                "duplicate in favourites — \(context)")

        // 3. isFavourite must agree with the favourites list it is derived from.
        for city in lists.favourites {
            #expect(lists.isFavourite(city), "isFavourite disagreed with the list — \(context)")
        }
        for city in lists.recent where !lists.favourites.contains(where: { $0.id == city.id }) {
            #expect(!lists.isFavourite(city), "isFavourite reported a non-favourite — \(context)")
        }
    }

    @Test("Invariants hold across random operation sequences")
    func randomSequencesPreserveInvariants() async {
        // A spread of seeds; each drives a different 60-step sequence.
        for seed in UInt64(1)...40 {
            var rng = SeededGenerator(seed: seed)
            let store = InMemorySavedCitiesStore()
            let clock = FixedDateProvider()
            let sut = DefaultSavedCitiesUseCase(store: store, dateProvider: clock)

            // A small city pool, so collisions and re-selections happen often — that
            // is where the interesting behaviour lives.
            let cities = (1...8).map { Fixture.city(id: $0, name: "City \($0)") }

            for step in 1...60 {
                let operation = Operation.allCases.randomElement(using: &rng)!
                let city = cities.randomElement(using: &rng)!

                let lists: SavedCityLists
                switch operation {
                case .visit: lists = await sut.recordVisit(to: city)
                case .toggleFavourite: lists = await sut.toggleFavourite(city)
                case .removeRecent: lists = await sut.removeRecent(city)
                case .clearRecents: lists = await sut.clearRecents()
                case .reload: lists = await sut.reload()
                }

                assertInvariants(lists, context: "seed \(seed), step \(step), \(operation)(city \(city.id))")
                clock.advance(by: 30)
            }
        }
    }

    @Test("Storage never retains a record that neither list references")
    func noOrphanedRecordsAccumulate() async {
        for seed in UInt64(1)...20 {
            var rng = SeededGenerator(seed: seed)
            let store = InMemorySavedCitiesStore()
            let clock = FixedDateProvider()
            let sut = DefaultSavedCitiesUseCase(store: store, dateProvider: clock)
            let cities = (1...6).map { Fixture.city(id: $0, name: "City \($0)") }

            for _ in 1...50 {
                let city = cities.randomElement(using: &rng)!
                switch Operation.allCases.randomElement(using: &rng)! {
                case .visit: _ = await sut.recordVisit(to: city)
                case .toggleFavourite: _ = await sut.toggleFavourite(city)
                case .removeRecent: _ = await sut.removeRecent(city)
                case .clearRecents: _ = await sut.clearRecents()
                case .reload: _ = await sut.reload()
                }
                clock.advance(by: 30)
            }

            // A record with neither timestamp is dead weight that would grow the
            // database forever, and would resurface as a phantom on the next reload.
            let orphans = await store.load().filter(\.isOrphaned)
            #expect(orphans.isEmpty, "seed \(seed) left \(orphans.count) orphaned record(s)")
        }
    }

    @Test("The in-memory view always agrees with what a reload would produce")
    func cacheNeverDivergesFromStorage() async {
        for seed in UInt64(1)...20 {
            var rng = SeededGenerator(seed: seed)
            let store = InMemorySavedCitiesStore()
            let clock = FixedDateProvider()
            let sut = DefaultSavedCitiesUseCase(store: store, dateProvider: clock)
            let cities = (1...6).map { Fixture.city(id: $0, name: "City \($0)") }

            for step in 1...40 {
                let city = cities.randomElement(using: &rng)!
                switch Operation.allCases.randomElement(using: &rng)! {
                case .visit: _ = await sut.recordVisit(to: city)
                case .toggleFavourite: _ = await sut.toggleFavourite(city)
                case .removeRecent: _ = await sut.removeRecent(city)
                case .clearRecents: _ = await sut.clearRecents()
                case .reload: _ = await sut.reload()
                }
                clock.advance(by: 30)

                // What the UI is showing must survive a relaunch unchanged. A cache
                // that has drifted from storage shows one thing now and another later.
                let inMemory = await sut.lists()
                let fromStorage = await sut.reload()
                #expect(inMemory == fromStorage,
                        "cache diverged from storage at seed \(seed), step \(step)")
            }
        }
    }

    @Test("Concurrent random mutations never corrupt the lists")
    func concurrentRandomMutationsStayConsistent() async {
        for seed in UInt64(1)...10 {
            var rng = SeededGenerator(seed: seed)
            let sut = DefaultSavedCitiesUseCase(
                store: InMemorySavedCitiesStore(),
                dateProvider: FixedDateProvider()
            )
            let cities = (1...6).map { Fixture.city(id: $0, name: "City \($0)") }

            // Build the plan up front: the generator is not Sendable and must not be
            // touched from inside the task group.
            let plan: [(Operation, City)] = (1...20).map { _ in
                (Operation.allCases.randomElement(using: &rng)!, cities.randomElement(using: &rng)!)
            }

            await withTaskGroup(of: Void.self) { group in
                for (operation, city) in plan {
                    group.addTask {
                        switch operation {
                        case .visit: _ = await sut.recordVisit(to: city)
                        case .toggleFavourite: _ = await sut.toggleFavourite(city)
                        case .removeRecent: _ = await sut.removeRecent(city)
                        case .clearRecents: _ = await sut.clearRecents()
                        case .reload: _ = await sut.reload()
                        }
                    }
                }
            }

            let lists = await sut.lists()
            assertInvariants(lists, context: "seed \(seed), after concurrent storm")

            let inMemory = await sut.lists()
            let fromStorage = await sut.reload()
            if inMemory != fromStorage {
                let planText = plan.map { "\($0.0)(\($0.1.id))" }.joined(separator: ", ")
                Issue.record("seed \(seed) DIVERGED | memory recent=\(inMemory.recent.map(\.id)) fav=\(inMemory.favourites.map(\.id)) | storage recent=\(fromStorage.recent.map(\.id)) fav=\(fromStorage.favourites.map(\.id)) | plan: \(planText)")
            }
        }
    }
}
