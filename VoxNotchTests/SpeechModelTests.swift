//
//  SpeechModelTests.swift
//  VoxNotchTests
//

import XCTest
@testable import VoxNotch

final class SpeechModelTests: XCTestCase {

  // MARK: - Model Identity

  func testBuiltinModelResolves() {
    let (builtin, custom) = SpeechModel.resolve("fluidaudio-v2")
    XCTAssertEqual(builtin, .parakeetV2)
    XCTAssertNil(custom)
  }

  func testAllBuiltinModelsResolve() {
    for model in SpeechModel.allCases {
      let (builtin, custom) = SpeechModel.resolve(model.rawValue)
      XCTAssertEqual(builtin, model, "SpeechModel.resolve(\(model.rawValue)) should return \(model)")
      XCTAssertNil(custom)
    }
  }

  func testUnknownModelResolvesToCustom() {
    let (builtin, _) = SpeechModel.resolve("unknown-model-id-that-does-not-exist")
    XCTAssertNil(builtin)
  }

  // MARK: - Engine Mapping

  func testFluidAudioModelsMapToFluidAudioEngine() {
    XCTAssertEqual(SpeechModel.parakeetV2.engine, .fluidAudio)
    XCTAssertEqual(SpeechModel.parakeetV3.engine, .fluidAudio)
  }

  func testMLXModelsMapToMLXEngine() {
    XCTAssertEqual(SpeechModel.glmAsrNano.engine, .mlxAudio)
    XCTAssertEqual(SpeechModel.qwen3Asr.engine, .mlxAudio)
  }

  // MARK: - Version Conversion

  func testFluidAudioVersionConversion() {
    XCTAssertEqual(SpeechModel.parakeetV2.fluidAudioVersion, .v2English)
    XCTAssertEqual(SpeechModel.parakeetV3.fluidAudioVersion, .v3Multilingual)
    XCTAssertNil(SpeechModel.glmAsrNano.fluidAudioVersion)
    XCTAssertNil(SpeechModel.qwen3Asr.fluidAudioVersion)
  }

  func testMLXAudioVersionConversion() {
    XCTAssertNil(SpeechModel.parakeetV2.mlxAudioVersion)
    XCTAssertNil(SpeechModel.parakeetV3.mlxAudioVersion)
    XCTAssertEqual(SpeechModel.glmAsrNano.mlxAudioVersion, .glmAsrNano)
    XCTAssertEqual(SpeechModel.qwen3Asr.mlxAudioVersion, .qwen3Asr)
  }
}
