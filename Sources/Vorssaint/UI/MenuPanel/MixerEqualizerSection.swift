// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The per-output equalizer, folded under the mixer's output picker. It edits
/// the current output unless another one is chosen, and every change reaches
/// the apps on that output as it is made.
struct MixerEqualizerDisclosure: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var mixer = AppVolumeMixer.shared
    @State private var expanded = false
    @State private var chosenDeviceUID: String?

    private var strings: MixerEqualizerStrings { .localized(l10n.language) }

    private var devices: [MixerOutputDevice] {
        mixer.outputDevices.filter {
            $0.canBeDefaultOutput && !MixerRoutingSupport.isAirPlaySentinel($0.uid)
        }
    }

    private var deviceUID: String? {
        if let chosenDeviceUID, devices.contains(where: { $0.uid == chosenDeviceUID }) {
            return chosenDeviceUID
        }
        if let current = mixer.currentOutputDeviceUID, devices.contains(where: { $0.uid == current }) {
            return current
        }
        return devices.first?.uid
    }

    private var settings: EqualizerSettings {
        deviceUID.map { mixer.equalizerSettings(for: $0) } ?? .flat
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if expanded, let deviceUID {
                MixerEqualizerEditor(settings: settings, strings: strings) { updated in
                    mixer.setEqualizerSettings(updated, for: deviceUID)
                }
                .padding(.leading, 24)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.vertical.3")
                        .font(.system(size: 10.5, weight: .semibold))
                        .frame(width: 16)
                    Text(strings.title)
                        .font(.system(size: 11.5, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(strings.title)

            Spacer(minLength: 6)

            if expanded, devices.count > 1 {
                Picker(strings.deviceTooltip, selection: deviceBinding) {
                    ForEach(devices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(maxWidth: 130)
                .help(strings.deviceTooltip)
            }

            Toggle(strings.title, isOn: enabledBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(deviceUID == nil)
        }
    }

    private var deviceBinding: Binding<String> {
        Binding(get: { deviceUID ?? "" }, set: { chosenDeviceUID = $0 })
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { settings.enabled }, set: { enabled in
            guard let deviceUID else { return }
            var updated = settings
            updated.enabled = enabled
            mixer.setEqualizerSettings(updated, for: deviceUID)
            if enabled { expanded = true }
        })
    }
}

/// Band count, response curve, preamp and one vertical slider per band.
private struct MixerEqualizerEditor: View {
    let settings: EqualizerSettings
    let strings: MixerEqualizerStrings
    let onChange: (EqualizerSettings) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(strings.bands)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Picker(strings.bands, selection: layoutBinding) {
                    ForEach(EqualizerLayout.allCases) { layout in
                        Text("\(layout.bandCount)").tag(layout)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                Spacer(minLength: 4)
                Button(strings.reset) {
                    var updated = settings
                    updated.reset()
                    onChange(updated)
                }
                .controlSize(.small)
                .disabled(settings.preamp == 0 && settings.gains.allSatisfy { $0 == 0 })
            }

            EqualizerResponseCurve(layout: settings.layout, gains: settings.gains,
                                   preamp: settings.preamp, enabled: settings.enabled)
                .frame(height: 40)

            HStack(alignment: .top, spacing: 2) {
                EqualizerBandColumn(value: preampBinding, range: EqualizerSettings.preampRange,
                                    label: strings.preamp, accessibilityLabel: strings.preamp,
                                    enabled: settings.enabled, compact: false)
                    .frame(width: 44)
                Divider().frame(height: 96)
                ForEach(0..<settings.layout.bandCount, id: \.self) { band in
                    EqualizerBandColumn(value: gainBinding(band), range: EqualizerSettings.gainRange,
                                        label: strings.label(for: band, in: settings.layout),
                                        accessibilityLabel: accessibilityLabel(band),
                                        enabled: settings.enabled,
                                        compact: settings.layout.bandCount > 5)
                        .frame(maxWidth: .infinity)
                }
            }
            .opacity(settings.enabled ? 1 : 0.55)

            Text(strings.caption)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(.easeOut(duration: 0.15), value: settings.layout)
    }

    private func accessibilityLabel(_ band: Int) -> String {
        let bands = settings.layout.bands
        guard bands.indices.contains(band) else { return "" }
        let name = strings.label(for: band, in: settings.layout)
        let hz = bands[band].frequencyLabel + " Hz"
        return settings.layout == .three ? "\(name), \(hz)" : hz
    }

    private var layoutBinding: Binding<EqualizerLayout> {
        Binding(get: { settings.layout }, set: { layout in
            var updated = settings
            updated.layout = layout
            onChange(updated)
        })
    }

    private var preampBinding: Binding<Double> {
        Binding(get: { settings.preamp }, set: { value in
            var updated = settings
            updated.preamp = EqualizerSettings.clamped(value, to: EqualizerSettings.preampRange)
            onChange(updated)
        })
    }

    private func gainBinding(_ band: Int) -> Binding<Double> {
        Binding(get: {
            let gains = settings.gains
            return gains.indices.contains(band) ? gains[band] : 0
        }, set: { value in
            var updated = settings
            updated.setGain(value, band: band)
            onChange(updated)
        })
    }
}

/// One vertical fader with its value above and its name below. Dragging
/// snaps to half decibels; a double click returns it to 0 dB.
private struct EqualizerBandColumn: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String
    let accessibilityLabel: String
    let enabled: Bool
    let compact: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text(valueText)
                .font(.system(size: compact ? 8 : 9, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            EqualizerVerticalSlider(value: $value, range: range, enabled: enabled)
                .frame(height: 72)
                .accessibilityElement()
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(String(format: "%+.1f dB", locale: .current, value))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: value = min(value + 1, range.upperBound)
                    case .decrement: value = max(value - 1, range.lowerBound)
                    @unknown default: break
                    }
                }
            Text(label)
                .font(.system(size: compact ? 8 : 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private var valueText: String {
        if value == 0 { return "0" }
        return value == value.rounded()
            ? String(format: "%+.0f", locale: .current, value)
            : String(format: "%+.1f", locale: .current, value)
    }
}

private struct EqualizerVerticalSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let enabled: Bool

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let knob: CGFloat = 10
            let travel = max(height - knob, 1)
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? (value - range.lowerBound) / span : 0.5
            let zeroFraction = span > 0 ? (0 - range.lowerBound) / span : 0.5
            let knobY = knob / 2 + travel * CGFloat(1 - fraction)
            let zeroY = knob / 2 + travel * CGFloat(1 - zeroFraction)
            let midX = geometry.size.width / 2
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 3, height: height)
                    .position(x: midX, y: height / 2)
                Rectangle()
                    .fill(Color.primary.opacity(0.25))
                    .frame(width: 9, height: 1)
                    .position(x: midX, y: zeroY)
                Capsule()
                    .fill(enabled ? Color.accentColor : Color.secondary)
                    .frame(width: 3, height: abs(knobY - zeroY))
                    .position(x: midX, y: (knobY + zeroY) / 2)
                Circle()
                    .fill(Color(nsColor: .controlColor))
                    .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                    .frame(width: knob, height: knob)
                    .position(x: midX, y: knobY)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let y = min(max(drag.location.y - knob / 2, 0), travel)
                        let raw = range.upperBound - Double(y / travel) * span
                        let snapped = (raw * 2).rounded() / 2
                        let clamped = min(max(snapped, range.lowerBound), range.upperBound)
                        if clamped != value { value = clamped }
                    }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { value = 0 })
        }
    }
}

/// What the bands add up to, drawn on a log frequency axis from 20 Hz to
/// 20 kHz between ±12 dB.
private struct EqualizerResponseCurve: View {
    let layout: EqualizerLayout
    let gains: [Double]
    let preamp: Double
    let enabled: Bool

    private static let frequencies = EqualizerResponse.logFrequencies(count: 96)
    private static let range = 12.0

    var body: some View {
        let curve = EqualizerResponse.curve(layout: layout, gains: gains, preamp: preamp,
                                            frequencies: Self.frequencies)
        Canvas { context, size in
            let midY = size.height / 2
            var grid = Path()
            grid.move(to: CGPoint(x: 0, y: midY))
            grid.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(grid, with: .color(.primary.opacity(0.15)), lineWidth: 0.5)

            guard curve.count > 1 else { return }
            var line = Path()
            for (index, db) in curve.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(curve.count - 1)
                let clamped = min(max(db, -Self.range), Self.range)
                let y = midY - CGFloat(clamped / Self.range) * (size.height / 2 - 1)
                index == 0 ? line.move(to: CGPoint(x: x, y: y)) : line.addLine(to: CGPoint(x: x, y: y))
            }
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: midY))
            fill.addLine(to: CGPoint(x: 0, y: midY))
            fill.closeSubpath()
            let tint: Color = enabled ? .accentColor : .secondary
            context.fill(fill, with: .color(tint.opacity(0.15)))
            context.stroke(line, with: .color(tint), lineWidth: 1.25)
        }
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.04)))
        .accessibilityHidden(true)
    }
}
