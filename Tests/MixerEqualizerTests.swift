// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

/// The per-device equalizer: its band layouts, the filters they build, the
/// settings it saves and the realtime processor the engines run.
enum MixerEqualizerContract {
    static func run(_ suite: TestSuite) {
        layoutsFollowTheirConventions(suite)
        filtersReachTheirGain(suite)
        settingsStaySane(suite)
        settingsTravelThroughBackup(suite)
        processorLeavesFlatAudioAlone(suite)
        processorAppliesAndReleasesABand(suite)
        processorCoversEveryChannel(suite)
        audibleEqualizerTapsTheDevice(suite)
        everyLanguageNamesTheControls(suite)
    }

    // MARK: Layouts and filters

    private static func layoutsFollowTheirConventions(_ suite: TestSuite) {
        for layout in EqualizerLayout.allCases {
            let bands = layout.bands
            suite.expect(bands.count == layout.bandCount, "\(layout) has one band per count")
            suite.expect(zip(bands, bands.dropFirst()).allSatisfy { $0.frequency < $1.frequency },
                         "\(layout) bands rise in frequency")
            suite.expect(bands.allSatisfy { $0.frequency >= 20 && $0.frequency <= 20000 && $0.q > 0 },
                         "\(layout) bands stay in the audible range with a positive Q")
            suite.expect(bands.count <= EqualizerParameters.maximumBands,
                         "\(layout) fits the processor's band storage")
        }
        let three = EqualizerLayout.three.bands
        suite.expect(EqualizerLayout.default == .three, "three bands are the default")
        suite.expect(three.map(\.kind) == [.lowShelf, .peak, .highShelf]
                     && three.map(\.frequency) == [100, 1000, 10000],
                     "three bands are a low shelf, a mid bell and a high shelf")
        suite.expect(EqualizerLayout.ten.bands.map(\.frequency)
                     == [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000],
                     "ten bands sit on the ISO octave centres")
        suite.expect(EqualizerLayout.ten.bands.allSatisfy { $0.kind == .peak },
                     "a graphic EQ is all bells")
        suite.expectClose(EqualizerLayout.constantQ(bandRatio: 2), 1.4142, "octave Q", tol: 0.001)
        suite.expectClose(EqualizerLayout.constantQ(bandRatio: pow(2, 2.0 / 3.0)), 2.145,
                          "two-thirds-octave Q", tol: 0.002)
        suite.expect(EqualizerLayout.ten.bands[0].frequencyLabel == "31.5"
                     && EqualizerLayout.ten.bands[5].frequencyLabel == "1k"
                     && EqualizerLayout.fifteen.bands[12].frequencyLabel == "6.3k",
                     "band labels read like the frequencies they name")
    }

    private static func filtersReachTheirGain(_ suite: TestSuite) {
        let rate = 48000.0
        let bell = EqualizerBand(kind: .peak, frequency: 1000, q: 1.41)
        let boosted = BiquadCoefficients(band: bell, gainDB: 6, sampleRate: rate)
        suite.expectClose(boosted.magnitudeDB(at: 1000, sampleRate: rate), 6, "bell centre", tol: 0.01)
        suite.expect(abs(boosted.magnitudeDB(at: 50, sampleRate: rate)) < 0.1
                     && abs(boosted.magnitudeDB(at: 15000, sampleRate: rate)) < 0.2,
                     "a bell leaves frequencies far from it alone")
        let cut = BiquadCoefficients(band: bell, gainDB: -9, sampleRate: rate)
        suite.expectClose(cut.magnitudeDB(at: 1000, sampleRate: rate), -9, "bell cut", tol: 0.01)

        let low = BiquadCoefficients(band: EqualizerLayout.three.bands[0], gainDB: 8, sampleRate: rate)
        suite.expectClose(low.magnitudeDB(at: 20, sampleRate: rate), 8, "low shelf floor", tol: 0.3)
        suite.expectClose(low.magnitudeDB(at: 100, sampleRate: rate), 4, "low shelf midpoint", tol: 0.2)
        suite.expect(abs(low.magnitudeDB(at: 5000, sampleRate: rate)) < 0.1, "low shelf leaves highs alone")

        let high = BiquadCoefficients(band: EqualizerLayout.three.bands[2], gainDB: -6, sampleRate: rate)
        suite.expectClose(high.magnitudeDB(at: 20000, sampleRate: rate), -6, "high shelf top", tol: 0.4)
        suite.expect(abs(high.magnitudeDB(at: 200, sampleRate: rate)) < 0.1, "high shelf leaves lows alone")

        suite.expect(BiquadCoefficients(band: bell, gainDB: 0, sampleRate: rate).isIdentity,
                     "a band at 0 dB is no filter")
        let nearNyquist = BiquadCoefficients(band: EqualizerBand(kind: .peak, frequency: 16000, q: 1.41),
                                             gainDB: 12, sampleRate: 32000)
        suite.expect([nearNyquist.b0, nearNyquist.b1, nearNyquist.b2, nearNyquist.a1, nearNyquist.a2]
                        .allSatisfy(\.isFinite) && abs(nearNyquist.a2) < 1,
                     "a band above the device's range stays a stable filter")

        let flat = EqualizerResponse.curve(layout: .ten, gains: Array(repeating: 0, count: 10), preamp: -3,
                                           frequencies: EqualizerResponse.logFrequencies(count: 20))
        suite.expect(flat.allSatisfy { abs($0 + 3) < 1e-9 }, "a flat curve is the preamp alone")
    }

    // MARK: Settings

    private static func settingsStaySane(_ suite: TestSuite) {
        var settings = EqualizerSettings.flat
        suite.expect(!settings.isAudible && settings.gains == [0, 0, 0], "a new equalizer is off and flat")
        settings.enabled = true
        suite.expect(!settings.isAudible, "turned on but flat changes nothing")
        settings.setGain(40, band: 0)
        settings.setGain(.nan, band: 1)
        suite.expect(settings.gains == [12, 0, 0], "gains are clamped and a non-number is dropped")
        suite.expect(settings.isAudible, "a boosted band is audible")

        settings.layout = .ten
        suite.expect(settings.gains == Array(repeating: 0, count: 10), "a new layout starts flat")
        settings.setGain(-4, band: 9)
        settings.layout = .three
        suite.expect(settings.gains == [12, 0, 0], "switching back keeps the three-band curve")
        suite.expect(settings.gains(for: .ten).last == -4, "and the ten-band curve is kept too")

        settings.enabled = false
        suite.expect(!settings.isAudible, "switched off is never audible")
        settings.reset()
        suite.expect(settings.gains == [0, 0, 0] && settings.preamp == 0, "reset flattens the current layout")

        let json = #"{"enabled":true,"layout":7,"preamp":99,"gainsByLayout":{"3":[1,2,3,4],"5":[1]}}"#
        let decoded = EqualizerStore.decode(["Speakers": json, "Broken": "{", "": json])
        suite.expect(decoded.keys.sorted() == ["Speakers"], "unreadable or nameless entries are dropped")
        let restored = decoded["Speakers"]
        suite.expect(restored?.layout == .three && restored?.preamp == 12
                     && restored?.gains(for: .three) == [1, 2, 3]
                     && restored?.gains(for: .five) == [1, 0, 0, 0, 0],
                     "a hand-edited entry is brought back into range")

        var saved = EqualizerSettings.flat
        saved.enabled = true
        saved.layout = .five
        saved.gains = [3, -2, 0, 1.5, 6]
        let encoded = EqualizerStore.encode(["Headphones": saved, "Untouched": .flat])
        suite.expect(encoded.keys.sorted() == ["Headphones"], "a flat device is not stored")
        suite.expect(EqualizerStore.decode(encoded)["Headphones"] == saved, "settings round-trip")
    }

    private static func settingsTravelThroughBackup(_ suite: TestSuite) {
        var saved = EqualizerSettings.flat
        saved.enabled = true
        saved.gains = [2, 0, -2]
        let stored = EqualizerStore.encode(["BuiltInSpeakerDevice": saved])
        let values: [String: Any] = [DefaultsKey.mixerEqualizers: stored]
        let backup = SettingsBackupSupport.payload(appVersion: "test") { values[$0] }
        let restored = SettingsBackupSupport.sanitizedSettings(from: backup)
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.mixerEqualizers)
                     && restored?[DefaultsKey.mixerEqualizers] as? [String: String] == stored,
                     "per-device equalizers round-trip through settings backup")
    }

    // MARK: Processor

    private static func sine(frequency: Double, frames: Int, channels: Int,
                             amplitude: Float = 0.25, rate: Double = 48000) -> [Float] {
        var samples = [Float](repeating: 0, count: frames * channels)
        for frame in 0..<frames {
            let value = amplitude * Float(sin(2 * Double.pi * frequency * Double(frame) / rate))
            for channel in 0..<channels { samples[frame * channels + channel] = value }
        }
        return samples
    }

    /// Runs `blocks` blocks of interleaved audio through the processor, in
    /// buffers shaped by `layout` (channels per buffer), and answers the
    /// output in the same interleaved order as the input.
    private static func process(_ processor: EqualizerProcessor, _ input: [Float], channels: Int,
                                layout: [Int], blockFrames: Int = 512) -> [Float] {
        let frames = input.count / channels
        var output = [Float](repeating: 0, count: input.count)
        var start = 0
        while start < frames {
            let count = min(blockFrames, frames - start)
            let list = AudioBufferList.allocate(maximumBuffers: layout.count)
            defer {
                for buffer in list { buffer.mData?.deallocate() }
                free(list.unsafeMutablePointer)
            }
            var firstChannel = 0
            for (index, width) in layout.enumerated() {
                let data = UnsafeMutablePointer<Float>.allocate(capacity: count * width)
                for frame in 0..<count {
                    for channel in 0..<width {
                        data[frame * width + channel] = input[(start + frame) * channels + firstChannel + channel]
                    }
                }
                list[index] = AudioBuffer(mNumberChannels: UInt32(width),
                                          mDataByteSize: UInt32(count * width * MemoryLayout<Float>.size),
                                          mData: UnsafeMutableRawPointer(data))
                firstChannel += width
            }
            processor.process(list, frames: count)
            firstChannel = 0
            for (index, width) in layout.enumerated() {
                let data = list[index].mData!.assumingMemoryBound(to: Float.self)
                for frame in 0..<count {
                    for channel in 0..<width {
                        output[(start + frame) * channels + firstChannel + channel] = data[frame * width + channel]
                    }
                }
                firstChannel += width
            }
            start += count
        }
        return output
    }

    private static func rms(_ samples: ArraySlice<Float>, channel: Int, channels: Int) -> Double {
        var sum = 0.0
        var count = 0
        var index = samples.startIndex + channel
        while index < samples.endIndex {
            sum += Double(samples[index]) * Double(samples[index])
            count += 1
            index += channels
        }
        return count > 0 ? (sum / Double(count)).squareRoot() : 0
    }

    private static func processorLeavesFlatAudioAlone(_ suite: TestSuite) {
        let input = sine(frequency: 440, frames: 4096, channels: 2)
        var settings = EqualizerSettings.flat
        let off = EqualizerProcessor(parameters: EqualizerParameters(settings), channelCapacity: 2,
                                     sampleRate: 48000)
        suite.expect(process(off, input, channels: 2, layout: [2]) == input,
                     "an equalizer that is off is bit-identical to none")
        settings.enabled = true
        let flat = EqualizerProcessor(parameters: EqualizerParameters(settings), channelCapacity: 2,
                                      sampleRate: 48000)
        suite.expect(process(flat, input, channels: 2, layout: [2]) == input,
                     "an equalizer that is on but flat is bit-identical to none")
    }

    private static func processorAppliesAndReleasesABand(_ suite: TestSuite) {
        var settings = EqualizerSettings.flat
        settings.enabled = true
        settings.layout = .ten
        settings.setGain(6, band: 5) // 1 kHz
        let parameters = EqualizerParameters(settings)
        let processor = EqualizerProcessor(parameters: parameters, channelCapacity: 2, sampleRate: 48000)

        let frames = 48000
        let input = sine(frequency: 1000, frames: frames, channels: 2)
        let output = process(processor, input, channels: 2, layout: [2])
        let tail = (frames / 2 * 2)..<(frames * 2)
        let gainDB = 20 * log10(rms(output[tail], channel: 0, channels: 2) / rms(input[tail], channel: 0, channels: 2))
        suite.expectClose(gainDB, 6, "a 6 dB band boosts its own frequency by 6 dB", tol: 0.1)
        suite.expect(output.allSatisfy(\.isFinite), "the boosted audio stays finite")

        let other = sine(frequency: 60, frames: frames, channels: 2)
        let otherOut = process(processor, other, channels: 2, layout: [2])
        let otherDB = 20 * log10(rms(otherOut[tail], channel: 0, channels: 2) / rms(other[tail], channel: 0, channels: 2))
        suite.expect(abs(otherDB) < 0.3, "the 1 kHz band leaves 60 Hz alone (\(otherDB) dB)")

        // The first block after a change glides instead of stepping.
        settings.setGain(0, band: 5)
        parameters.apply(settings)
        let release = process(processor, input, channels: 2, layout: [2], blockFrames: 256)
        let firstBlock = rms(release[0..<512], channel: 0, channels: 2) / rms(input[0..<512], channel: 0, channels: 2)
        suite.expect(firstBlock > 1.3, "a band released mid-play fades instead of stepping (\(firstBlock))")
        let settled = process(processor, input, channels: 2, layout: [2])
        suite.expect(settled == input, "once the glide ends the audio is untouched again")

        settings.layout = .fifteen
        settings.gains = Array(repeating: 12, count: 15)
        settings.preamp = -12
        parameters.apply(settings)
        let extreme = process(processor, input, channels: 2, layout: [2])
        suite.expect(extreme.allSatisfy(\.isFinite), "every band at full boost after a layout change stays finite")
    }

    private static func processorCoversEveryChannel(_ suite: TestSuite) {
        var settings = EqualizerSettings.flat
        settings.enabled = true
        settings.gains = [0, -6, 0]
        let input = sine(frequency: 1000, frames: 24000, channels: 4)
        let processor = EqualizerProcessor(parameters: EqualizerParameters(settings), channelCapacity: 4,
                                           sampleRate: 48000)
        let output = process(processor, input, channels: 4, layout: [1, 1, 2])
        let tail = (12000 * 4)..<(24000 * 4)
        let levels = (0..<4).map {
            20 * log10(rms(output[tail], channel: $0, channels: 4) / rms(input[tail], channel: $0, channels: 4))
        }
        suite.expect(levels.allSatisfy { $0 < -4 }, "split and interleaved buffers are all equalized (\(levels))")
        suite.expect(zip(levels, levels.dropFirst()).allSatisfy { abs($0 - $1) < 0.01 },
                     "every channel gets the same curve")
    }

    // MARK: Routing and strings

    private static func audibleEqualizerTapsTheDevice(_ suite: TestSuite) {
        suite.expect(!MixerRoutingSupport.requiresEngine(volume: 1, selectedOutputDeviceUID: nil,
                                                         targetOutputDeviceUID: "Speakers",
                                                         defaultOutputDeviceUID: "Speakers"),
                     "an untouched app on a device without an equalizer is not tapped")
        suite.expect(MixerRoutingSupport.requiresEngine(volume: 1, selectedOutputDeviceUID: nil,
                                                        targetOutputDeviceUID: "Speakers",
                                                        defaultOutputDeviceUID: "Speakers",
                                                        equalizerActive: true),
                     "an audible equalizer routes the device's apps through the mixer")
        suite.expect(!MixerRoutingSupport.requiresEngine(hasAudioObjects: false, volume: 1,
                                                         selectedOutputDeviceUID: nil,
                                                         targetOutputDeviceUID: "Speakers",
                                                         defaultOutputDeviceUID: "Speakers",
                                                         equalizerActive: true),
                     "an app with no audio is still not tapped")
        suite.expect(!MixerRoutingSupport.requiresEngine(volume: 1, selectedOutputDeviceUID: nil,
                                                         targetOutputDeviceUID: AirPlayRouteManager.airPlaySentinelUID,
                                                         defaultOutputDeviceUID: nil,
                                                         equalizerActive: true),
                     "the AirPlay stream is not equalized")
        suite.expect(MixerRoutingSupport.rowMayBeTapped(savedVolume: nil, savedRouteUID: nil,
                                                        defaultOutputDeviceUID: "Speakers",
                                                        equalizerActive: true)
                     && !MixerRoutingSupport.rowMayBeTapped(savedVolume: nil, savedRouteUID: nil,
                                                            defaultOutputDeviceUID: "Speakers"),
                     "only an audible equalizer lets an untouched row be tapped")
    }

    private static func everyLanguageNamesTheControls(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let strings = MixerEqualizerStrings.localized(language)
            let all = [strings.title, strings.bands, strings.preamp, strings.reset, strings.low, strings.mid,
                       strings.high, strings.caption, strings.deviceTooltip]
            suite.expect(all.allSatisfy { !$0.isEmpty }, "\(language) names every equalizer control")
            suite.expect(strings.label(for: 0, in: .three) == strings.low
                         && strings.label(for: 2, in: .three) == strings.high
                         && strings.label(for: 0, in: .ten) == "31.5",
                         "\(language) labels three bands by name and the rest by frequency")
        }
    }
}
