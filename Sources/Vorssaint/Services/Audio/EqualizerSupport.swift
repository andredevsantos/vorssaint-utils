// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// How finely the equalizer divides the spectrum. Each layout follows the
/// convention listeners already know from the hardware and players that use
/// that number of bands, so a curve drawn here means what it means elsewhere.
///
/// - Three bands are a tone control: a low shelf, a broad mid bell and a high
///   shelf, the way hi-fi amplifiers and basic player EQs (eqMac's Basic EQ,
///   DJ mixers) split bass, mids and treble.
/// - Five bands put a bell on every second octave between two shelves, close
///   to the five-band layout phones ship.
/// - Ten bands are the octave graphic EQ on ISO 266 centres (31.5 Hz to 16 kHz)
///   that iTunes, Apple Music, Winamp and eqMac's Advanced EQ use.
/// - Fifteen bands are the two-thirds-octave graphic EQ, also on ISO centres.
///
/// Graphic layouts use constant-Q bells, the bandwidth a band of that width
/// spans: Q = √R / (R − 1) for a band ratio R, so 1.41 for an octave and 2.15
/// for two-thirds of one.
enum EqualizerLayout: Int, CaseIterable, Codable, Identifiable {
    case three = 3
    case five = 5
    case ten = 10
    case fifteen = 15

    static let `default`: EqualizerLayout = .three

    var id: Int { rawValue }
    var bandCount: Int { rawValue }

    var bands: [EqualizerBand] {
        switch self {
        case .three:
            return [
                EqualizerBand(kind: .lowShelf, frequency: 100, q: EqualizerBand.shelfQ),
                EqualizerBand(kind: .peak, frequency: 1000, q: 0.7),
                EqualizerBand(kind: .highShelf, frequency: 10000, q: EqualizerBand.shelfQ),
            ]
        case .five:
            let q = Self.constantQ(bandRatio: 4)
            return [
                EqualizerBand(kind: .lowShelf, frequency: 60, q: EqualizerBand.shelfQ),
                EqualizerBand(kind: .peak, frequency: 250, q: q),
                EqualizerBand(kind: .peak, frequency: 1000, q: q),
                EqualizerBand(kind: .peak, frequency: 4000, q: q),
                EqualizerBand(kind: .highShelf, frequency: 12000, q: EqualizerBand.shelfQ),
            ]
        case .ten:
            let q = Self.constantQ(bandRatio: 2)
            return [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000].map {
                EqualizerBand(kind: .peak, frequency: $0, q: q)
            }
        case .fifteen:
            let q = Self.constantQ(bandRatio: pow(2, 2.0 / 3.0))
            return [25, 40, 63, 100, 160, 250, 400, 630, 1000, 1600, 2500, 4000, 6300, 10000, 16000].map {
                EqualizerBand(kind: .peak, frequency: $0, q: q)
            }
        }
    }

    /// The Q of a bell whose -3 dB points sit a band ratio apart, which is
    /// what keeps neighbouring graphic bands from leaving gaps or piling up.
    static func constantQ(bandRatio: Double) -> Double {
        sqrt(bandRatio) / (bandRatio - 1)
    }
}

struct EqualizerBand: Equatable {
    enum Kind: Equatable {
        case lowShelf
        case peak
        case highShelf
    }

    /// A Butterworth shelf (slope 1): the steepest shelf that does not
    /// overshoot past its own gain.
    static let shelfQ = 1 / 2.0.squareRoot()

    let kind: Kind
    let frequency: Double
    let q: Double

    /// A short label for the band: "Low", "Mid" and "High" belong to the
    /// caller, since only it knows the language; this is the frequency, with
    /// the point every equalizer prints whatever the region.
    var frequencyLabel: String {
        let posix = Locale(identifier: "en_US_POSIX")
        if frequency >= 1000 {
            let k = frequency / 1000
            return k == k.rounded() ? "\(Int(k))k" : String(format: "%.1fk", locale: posix, k)
        }
        return frequency == frequency.rounded()
            ? "\(Int(frequency))"
            : String(format: "%.1f", locale: posix, frequency)
    }
}

/// One output device's equalizer as the user left it. Gains are kept for
/// every layout the user has tried, so moving from three bands to ten and
/// back does not throw the three-band curve away.
struct EqualizerSettings: Codable, Equatable {
    static let gainRange: ClosedRange<Double> = -12...12
    static let preampRange: ClosedRange<Double> = -12...12

    var enabled: Bool
    var layout: EqualizerLayout
    var preamp: Double
    /// Decibels per band, keyed by the layout's band count.
    var gainsByLayout: [String: [Double]]

    static let flat = EqualizerSettings(enabled: false, layout: .default, preamp: 0, gainsByLayout: [:])

    init(enabled: Bool, layout: EqualizerLayout, preamp: Double, gainsByLayout: [String: [Double]]) {
        self.enabled = enabled
        self.layout = layout
        self.preamp = preamp
        self.gainsByLayout = gainsByLayout
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? container.decode(Bool.self, forKey: .enabled)) ?? false
        let rawLayout = (try? container.decode(Int.self, forKey: .layout)) ?? EqualizerLayout.default.rawValue
        layout = EqualizerLayout(rawValue: rawLayout) ?? .default
        preamp = Self.clamped((try? container.decode(Double.self, forKey: .preamp)) ?? 0, to: Self.preampRange)
        let raw = (try? container.decode([String: [Double]].self, forKey: .gainsByLayout)) ?? [:]
        var gains: [String: [Double]] = [:]
        for candidate in EqualizerLayout.allCases {
            guard let values = raw[String(candidate.rawValue)] else { continue }
            gains[String(candidate.rawValue)] = Self.sanitized(values, count: candidate.bandCount)
        }
        gainsByLayout = gains
    }

    /// The current layout's gains, always one finite, in-range value per band.
    var gains: [Double] {
        get { gains(for: layout) }
        set { gainsByLayout[String(layout.rawValue)] = Self.sanitized(newValue, count: layout.bandCount) }
    }

    func gains(for layout: EqualizerLayout) -> [Double] {
        Self.sanitized(gainsByLayout[String(layout.rawValue)] ?? [], count: layout.bandCount)
    }

    mutating func setGain(_ value: Double, band: Int) {
        var current = gains
        guard current.indices.contains(band) else { return }
        current[band] = value
        gains = current
    }

    mutating func reset() {
        preamp = 0
        gains = Array(repeating: 0, count: layout.bandCount)
    }

    /// Whether the equalizer changes the sound at all. Only then does it need
    /// the device's apps routed through the mixer; a flat or switched-off
    /// equalizer leaves them untouched, exactly as before it existed.
    var isAudible: Bool {
        enabled && (preamp != 0 || gains.contains { $0 != 0 })
    }

    static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    static func sanitized(_ values: [Double], count: Int) -> [Double] {
        (0..<count).map { index in
            index < values.count ? clamped(values[index], to: gainRange) : 0
        }
    }
}

/// Reading and writing the per-device settings. They live under one key as
/// device UID to JSON text, a shape settings backup carries as it is.
enum EqualizerStore {
    static func decode(_ stored: [String: String]) -> [String: EqualizerSettings] {
        var result: [String: EqualizerSettings] = [:]
        let decoder = JSONDecoder()
        for (uid, text) in stored where !uid.isEmpty {
            guard let data = text.data(using: .utf8),
                  let settings = try? decoder.decode(EqualizerSettings.self, from: data) else { continue }
            result[uid] = settings
        }
        return result
    }

    static func encode(_ settings: [String: EqualizerSettings]) -> [String: String] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var result: [String: String] = [:]
        for (uid, value) in settings where !uid.isEmpty && value != .flat {
            guard let data = try? encoder.encode(value),
                  let text = String(data: data, encoding: .utf8) else { continue }
            result[uid] = text
        }
        return result
    }
}

/// RBJ "Audio EQ Cookbook" biquads, normalised so a0 is 1.
struct BiquadCoefficients: Equatable {
    var b0: Double = 1
    var b1: Double = 0
    var b2: Double = 0
    var a1: Double = 0
    var a2: Double = 0

    static let identity = BiquadCoefficients()

    var isIdentity: Bool { self == .identity }

    init() {}

    init(b0: Double, b1: Double, b2: Double, a0: Double, a1: Double, a2: Double) {
        self.b0 = b0 / a0
        self.b1 = b1 / a0
        self.b2 = b2 / a0
        self.a1 = a1 / a0
        self.a2 = a2 / a0
    }

    /// Highest centre a band may use, as a fraction of the sample rate. The
    /// bilinear transform squeezes everything toward Nyquist, so a 16 kHz
    /// band at 32 kHz would otherwise land on it and blow up.
    static let maximumFrequencyRatio = 0.45

    init(band: EqualizerBand, gainDB: Double, sampleRate: Double) {
        guard gainDB != 0, gainDB.isFinite, sampleRate.isFinite, sampleRate > 0 else {
            self.init()
            return
        }
        let frequency = min(band.frequency, sampleRate * Self.maximumFrequencyRatio)
        let a = pow(10, gainDB / 40)
        let w0 = 2 * Double.pi * frequency / sampleRate
        let cosW = cos(w0)
        let alpha = sin(w0) / (2 * band.q)
        switch band.kind {
        case .peak:
            self.init(b0: 1 + alpha * a, b1: -2 * cosW, b2: 1 - alpha * a,
                      a0: 1 + alpha / a, a1: -2 * cosW, a2: 1 - alpha / a)
        case .lowShelf:
            let s = 2 * a.squareRoot() * alpha
            self.init(b0: a * ((a + 1) - (a - 1) * cosW + s),
                      b1: 2 * a * ((a - 1) - (a + 1) * cosW),
                      b2: a * ((a + 1) - (a - 1) * cosW - s),
                      a0: (a + 1) + (a - 1) * cosW + s,
                      a1: -2 * ((a - 1) + (a + 1) * cosW),
                      a2: (a + 1) + (a - 1) * cosW - s)
        case .highShelf:
            let s = 2 * a.squareRoot() * alpha
            self.init(b0: a * ((a + 1) + (a - 1) * cosW + s),
                      b1: -2 * a * ((a - 1) + (a + 1) * cosW),
                      b2: a * ((a + 1) + (a - 1) * cosW - s),
                      a0: (a + 1) - (a - 1) * cosW + s,
                      a1: 2 * ((a - 1) - (a + 1) * cosW),
                      a2: (a + 1) - (a - 1) * cosW - s)
        }
    }

    /// The filter's gain in decibels at one frequency.
    func magnitudeDB(at frequency: Double, sampleRate: Double) -> Double {
        let w = 2 * Double.pi * frequency / sampleRate
        let cos1 = cos(w), sin1 = sin(w)
        let cos2 = cos(2 * w), sin2 = sin(2 * w)
        let numRe = b0 + b1 * cos1 + b2 * cos2
        let numIm = -(b1 * sin1 + b2 * sin2)
        let denRe = 1 + a1 * cos1 + a2 * cos2
        let denIm = -(a1 * sin1 + a2 * sin2)
        let numerator = numRe * numRe + numIm * numIm
        let denominator = denRe * denRe + denIm * denIm
        guard numerator > 0, denominator > 0 else { return -120 }
        return 10 * log10(numerator / denominator)
    }
}

enum EqualizerResponse {
    /// The whole curve's gain in decibels at each frequency, preamp included,
    /// for drawing what the bands add up to.
    static func curve(layout: EqualizerLayout, gains: [Double], preamp: Double,
                      frequencies: [Double], sampleRate: Double = 48000) -> [Double] {
        let filters = zip(layout.bands, EqualizerSettings.sanitized(gains, count: layout.bandCount)).map {
            BiquadCoefficients(band: $0, gainDB: $1, sampleRate: sampleRate)
        }
        return frequencies.map { frequency in
            filters.reduce(preamp) { $0 + $1.magnitudeDB(at: frequency, sampleRate: sampleRate) }
        }
    }

    /// Frequencies spaced evenly on a log axis from 20 Hz to 20 kHz.
    static func logFrequencies(count: Int, from low: Double = 20, to high: Double = 20000) -> [Double] {
        guard count > 1 else { return [low] }
        let ratio = log(high / low)
        return (0..<count).map { low * exp(ratio * Double($0) / Double(count - 1)) }
    }
}
