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

  func testLegacyFluidAudioV3ResolvesToDefault() {
    let (builtin, custom) = SpeechModel.resolve("fluidaudio-v3")
    XCTAssertEqual(builtin, SpeechModel.defaultModel)
    XCTAssertNil(custom)
  }

  // MARK: - Engine Mapping

  func testFluidAudioModelsMapToFluidAudioEngine() {
    XCTAssertEqual(SpeechModel.parakeetV2.engine, .fluidAudio)
  }

  func testMLXModelsMapToMLXEngine() {
    XCTAssertEqual(SpeechModel.glmAsrNano.engine, .mlxAudio)
    XCTAssertEqual(SpeechModel.qwen3Asr.engine, .mlxAudio)
    XCTAssertEqual(SpeechModel.voxtralMini.engine, .mlxAudio)
  }

  // MARK: - Version Conversion

  func testFluidAudioVersionConversion() {
    XCTAssertEqual(SpeechModel.parakeetV2.fluidAudioVersion, .v2English)
    XCTAssertNil(SpeechModel.glmAsrNano.fluidAudioVersion)
    XCTAssertNil(SpeechModel.qwen3Asr.fluidAudioVersion)
    XCTAssertNil(SpeechModel.voxtralMini.fluidAudioVersion)
  }

  func testMLXAudioVersionConversion() {
    XCTAssertNil(SpeechModel.parakeetV2.mlxAudioVersion)
    XCTAssertEqual(SpeechModel.glmAsrNano.mlxAudioVersion, .glmAsrNano)
    XCTAssertEqual(SpeechModel.qwen3Asr.mlxAudioVersion, .qwen3Asr)
    XCTAssertEqual(SpeechModel.voxtralMini.mlxAudioVersion, .voxtralMini)
  }
}
