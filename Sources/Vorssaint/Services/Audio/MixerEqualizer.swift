// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

/// One output device's equalizer as the audio thread sees it. The mixer owns
/// one per device and every engine playing to that device reads it, so a
/// slider moves every app on the device at once without rebuilding a tap.
///
/// Each value is its own atomic float: a change that lands between two reads
/// can leave one block with a mix of old and new bands, which the processor's
/// smoothing turns into nothing audible.
final class EqualizerParameters {
    static let maximumBands = EqualizerLayout.allCases.map(\.bandCount).max() ?? 15

    private let enabledBox = AtomicFloatBox(0)
    private let layoutBox = AtomicFloatBox(Float(EqualizerLayout.default.rawValue))
    private let preampBox = AtomicFloatBox(0)
    private let gainBoxes = (0..<EqualizerParameters.maximumBands).map { _ in AtomicFloatBox(0) }

    init(_ settings: EqualizerSettings = .flat) {
        apply(settings)
    }

    /// Main thread.
    func apply(_ settings: EqualizerSettings) {
        let gains = settings.gains
        for index in gainBoxes.indices {
            gainBoxes[index].value = settings.enabled && index < gains.count ? Float(gains[index]) : 0
        }
        preampBox.value = settings.enabled ? Float(settings.preamp) : 0
        layoutBox.value = Float(settings.layout.rawValue)
        enabledBox.value = settings.enabled ? 1 : 0
    }

    var isEnabled: Bool { enabledBox.value != 0 }
    var layout: EqualizerLayout { EqualizerLayout(rawValue: Int(layoutBox.value)) ?? .default }
    var preampDB: Float { preampBox.value }
    func gainDB(band: Int) -> Float { gainBoxes[band].value }
}

/// Runs one engine's audio through its device's equalizer, in place, on the
/// realtime thread: a cascade of biquads per channel, with every band's gain
/// and the preamp gliding toward the user's setting over a few tens of
/// milliseconds so dragging a band does not click.
///
/// While the target and the glide are both flat the processor does not touch
/// the samples at all, so a switched-off equalizer is bit-identical to none.
///
/// Storage is allocated once in `init`; `process` allocates nothing and takes
/// no lock.
final class EqualizerProcessor {
    static let smoothingSeconds = 0.03

    private let parameters: EqualizerParameters
    private let channelCapacity: Int
    private let sampleRate: Double
    private let maximumBands = EqualizerParameters.maximumBands
    private var layout: EqualizerLayout
    /// Every layout's bands, built here because building them allocates.
    private let threeBands = EqualizerLayout.three.bands
    private let fiveBands = EqualizerLayout.five.bands
    private let tenBands = EqualizerLayout.ten.bands
    private let fifteenBands = EqualizerLayout.fifteen.bands
    /// Two state values per band per channel, transposed direct form II.
    private let state: UnsafeMutablePointer<Double>
    private let coefficients: UnsafeMutablePointer<BiquadCoefficients>
    private let currentDB: UnsafeMutablePointer<Double>
    private var currentPreampDB: Double = 0
    private var stateIsClear = true

    init(parameters: EqualizerParameters, channelCapacity: Int, sampleRate: Double) {
        self.parameters = parameters
        self.channelCapacity = max(channelCapacity, 1)
        self.sampleRate = sampleRate.isFinite && sampleRate >= 8000 ? sampleRate : 48000
        layout = parameters.layout
        state = .allocate(capacity: self.channelCapacity * maximumBands * 2)
        state.initialize(repeating: 0, count: self.channelCapacity * maximumBands * 2)
        coefficients = .allocate(capacity: maximumBands)
        coefficients.initialize(repeating: .identity, count: maximumBands)
        currentDB = .allocate(capacity: maximumBands)
        currentDB.initialize(repeating: 0, count: maximumBands)
    }

    deinit {
        state.deallocate()
        coefficients.deallocate()
        currentDB.deallocate()
    }

    /// Forgets the filters' memory, for a stream that broke continuity.
    func reset() {
        clearState()
    }

    func process(_ output: UnsafeMutableAudioBufferListPointer, frames: Int) {
        guard frames > 0 else { return }
        let previousPreamp = currentPreampDB
        let active = advance(frames: frames)
        guard active else {
            clearState()
            return
        }
        stateIsClear = false
        let startScale = Self.linear(previousPreamp)
        let endScale = Self.linear(currentPreampDB)
        let bandCount = layout.bandCount

        var firstChannel = 0
        for buffer in output {
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0 else { continue }
            defer { firstChannel += channels }
            guard let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let available = MixerRender.frames(bytes: buffer.mDataByteSize, channels: buffer.mNumberChannels)
            let count = min(frames, available)
            guard count > 0 else { continue }
            for channel in 0..<channels {
                let globalChannel = firstChannel + channel
                guard globalChannel < channelCapacity else { break }
                if startScale != 1 || endScale != 1 {
                    applyScale(samples + channel, stride: channels, frames: count,
                               from: startScale, to: endScale)
                }
                for band in 0..<bandCount {
                    let c = coefficients[band]
                    guard !c.isIdentity else { continue }
                    let z = state + (globalChannel * maximumBands + band) * 2
                    filter(samples + channel, stride: channels, frames: count, coefficients: c, state: z)
                }
            }
        }
    }

    // MARK: Internals

    /// Moves the glide one block toward the parameters and refreshes the
    /// coefficients that moved. Answers whether anything is left to apply.
    private func advance(frames: Int) -> Bool {
        let targetLayout = parameters.layout
        if targetLayout != layout {
            // New centres and widths: start the new curve from flat rather
            // than reinterpreting the old one's memory.
            layout = targetLayout
            for band in 0..<maximumBands {
                currentDB[band] = 0
                coefficients[band] = .identity
            }
            clearState()
        }
        let step = 1 - exp(-Double(frames) / (sampleRate * Self.smoothingSeconds))
        var active = false
        for band in 0..<layout.bandCount {
            let target = Double(parameters.gainDB(band: band))
            let current = currentDB[band]
            let next = Self.glide(current, toward: target, step: step)
            if next != current {
                currentDB[band] = next
                coefficients[band] = BiquadCoefficients(band: self.band(band), gainDB: next,
                                                        sampleRate: sampleRate)
                if next == 0 { clearBand(band) }
            }
            if next != 0 { active = true }
        }
        currentPreampDB = Self.glide(currentPreampDB, toward: Double(parameters.preampDB), step: step)
        return active || currentPreampDB != 0
    }

    private func band(_ index: Int) -> EqualizerBand {
        switch layout {
        case .three: return threeBands[index]
        case .five: return fiveBands[index]
        case .ten: return tenBands[index]
        case .fifteen: return fifteenBands[index]
        }
    }

    private static func glide(_ current: Double, toward target: Double, step: Double) -> Double {
        guard target.isFinite else { return 0 }
        let next = current + (target - current) * step
        return abs(target - next) < 0.01 ? target : next
    }

    private static func linear(_ db: Double) -> Float {
        db == 0 ? 1 : Float(pow(10, db / 20))
    }

    private func applyScale(_ samples: UnsafeMutablePointer<Float>, stride: Int, frames: Int,
                            from start: Float, to end: Float) {
        let step = (end - start) / Float(frames)
        var scale = start
        var index = 0
        for _ in 0..<frames {
            scale += step
            samples[index] *= scale
            index += stride
        }
    }

    private func filter(_ samples: UnsafeMutablePointer<Float>, stride: Int, frames: Int,
                        coefficients c: BiquadCoefficients, state z: UnsafeMutablePointer<Double>) {
        var z1 = z[0]
        var z2 = z[1]
        var index = 0
        for _ in 0..<frames {
            let x = Double(samples[index])
            let y = c.b0 * x + z1
            z1 = c.b1 * x - c.a1 * y + z2
            z2 = c.b2 * x - c.a2 * y
            samples[index] = Float(y)
            index += stride
        }
        // Keep a decaying tail from wandering into denormals.
        z[0] = abs(z1) < 1e-20 ? 0 : z1
        z[1] = abs(z2) < 1e-20 ? 0 : z2
    }

    private func clearBand(_ band: Int) {
        for channel in 0..<channelCapacity {
            let z = state + (channel * maximumBands + band) * 2
            z[0] = 0
            z[1] = 0
        }
    }

    private func clearState() {
        guard !stateIsClear else { return }
        state.update(repeating: 0, count: channelCapacity * maximumBands * 2)
        stateIsClear = true
    }
}
