// StrengthWorkoutTests.swift
//
// add-workout-tracker: the exercises of a gym session read from the vault's
// example fixture (the `gym-a` workout: a hold, two exercises, a rest).

import XCTest
@testable import TrainingCore

final class StrengthWorkoutTests: XCTestCase {
    private func builder() throws -> PlanBuilder {
        let bytes = try Fixtures.example()
        guard case .success(let decoded) = ProjectionDecoder.decode(bytes) else {
            XCTFail("fixture did not decode")
            throw ProjectionRejection.invalid(reason: "test")
        }
        return PlanBuilder(source: .loaded(TrainingSnapshot(projection: decoded.projection)), language: .english, today: D.asOf)
    }

    func testGymSessionListsItsExercisesAsPlanned() throws {
        let model = try XCTUnwrap(builder().strengthWorkout(sessionId: "2030-w43-mon-pm"))
        XCTAssertEqual(model.sessionID, "2030-w43-mon-pm")
        XCTAssertEqual(model.exercises.map(\.name), ["Seated calf raise", "Split squat"], "only `exercise` steps, in plan order")

        let calf = model.exercises[0]
        XCTAssertEqual(calf.setCount, 3)
        XCTAssertEqual(calf.repsText, "8-12")
        XCTAssertEqual(calf.loadText, "40 kg")
        XCTAssertEqual(calf.tempo, "3-0-3")
        XCTAssertFalse(calf.eachSide)

        let split = model.exercises[1]
        XCTAssertEqual(split.repsText, "8", "a numeric reps value reads as text")
        XCTAssertNil(split.loadText)
        XCTAssertTrue(split.eachSide)
        XCTAssertNotEqual(calf.id, split.id)
    }

    func testARunSessionHasNoStrengthWorkout() throws {
        XCTAssertNil(try builder().strengthWorkout(sessionId: "2030-w43-wed-am"))
    }

    func testAnUnknownSessionHasNoStrengthWorkout() throws {
        XCTAssertNil(try builder().strengthWorkout(sessionId: "nope"))
    }
}
