// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct MixerEqualizerStrings {
    let title: String
    let bands: String
    let preamp: String
    let reset: String
    let low: String
    let mid: String
    let high: String
    let caption: String
    let deviceTooltip: String

    static func localized(_ language: AppLanguage) -> MixerEqualizerStrings {
        switch language {
        case .enUS: return .init(
            title: "Equalizer", bands: "Bands", preamp: "Preamp", reset: "Reset",
            low: "Low", mid: "Mid", high: "High",
            caption: "Shapes the sound of apps playing on this output.",
            deviceTooltip: "Output to equalize")
        case .ptBR: return .init(
            title: "Equalizador", bands: "Bandas", preamp: "Pré-amplificador", reset: "Redefinir",
            low: "Graves", mid: "Médios", high: "Agudos",
            caption: "Ajusta o som dos apps que tocam nesta saída.",
            deviceTooltip: "Saída a equalizar")
        case .tr: return .init(
            title: "Ekolayzır", bands: "Bantlar", preamp: "Ön yükseltici", reset: "Sıfırla",
            low: "Bas", mid: "Orta", high: "Tiz",
            caption: "Bu çıkışta çalan uygulamaların sesini ayarlar.",
            deviceTooltip: "Ekolayzırın uygulanacağı çıkış")
        case .ru: return .init(
            title: "Эквалайзер", bands: "Полосы", preamp: "Предусилитель", reset: "Сбросить",
            low: "Низкие", mid: "Средние", high: "Высокие",
            caption: "Настраивает звук приложений, играющих через этот выход.",
            deviceTooltip: "Выход для эквалайзера")
        case .es: return .init(
            title: "Ecualizador", bands: "Bandas", preamp: "Preamplificador", reset: "Restablecer",
            low: "Graves", mid: "Medios", high: "Agudos",
            caption: "Ajusta el sonido de las apps que se reproducen en esta salida.",
            deviceTooltip: "Salida que ecualizar")
        case .sk: return .init(
            title: "Ekvalizér", bands: "Pásma", preamp: "Predzosilňovač", reset: "Obnoviť",
            low: "Basy", mid: "Stredy", high: "Výšky",
            caption: "Upravuje zvuk aplikácií prehrávaných na tomto výstupe.",
            deviceTooltip: "Výstup na ekvalizáciu")
        case .de: return .init(
            title: "Equalizer", bands: "Bänder", preamp: "Vorverstärkung", reset: "Zurücksetzen",
            low: "Tiefen", mid: "Mitten", high: "Höhen",
            caption: "Formt den Klang der Apps, die über diese Ausgabe spielen.",
            deviceTooltip: "Ausgabe für den Equalizer")
        case .fr: return .init(
            title: "Égaliseur", bands: "Bandes", preamp: "Préampli", reset: "Réinitialiser",
            low: "Graves", mid: "Médiums", high: "Aigus",
            caption: "Ajuste le son des apps qui jouent sur cette sortie.",
            deviceTooltip: "Sortie à égaliser")
        case .it: return .init(
            title: "Equalizzatore", bands: "Bande", preamp: "Preamplificatore", reset: "Ripristina",
            low: "Bassi", mid: "Medi", high: "Alti",
            caption: "Regola il suono delle app che riproducono su questa uscita.",
            deviceTooltip: "Uscita da equalizzare")
        case .ja: return .init(
            title: "イコライザ", bands: "バンド", preamp: "プリアンプ", reset: "リセット",
            low: "低音", mid: "中音", high: "高音",
            caption: "この出力で再生されるアプリの音質を調整します。",
            deviceTooltip: "イコライザを適用する出力")
        case .ko: return .init(
            title: "이퀄라이저", bands: "밴드", preamp: "프리앰프", reset: "재설정",
            low: "저음", mid: "중음", high: "고음",
            caption: "이 출력으로 재생되는 앱의 소리를 조정합니다.",
            deviceTooltip: "이퀄라이저를 적용할 출력")
        case .uk: return .init(
            title: "Еквалайзер", bands: "Смуги", preamp: "Попередній підсилювач", reset: "Скинути",
            low: "Низькі", mid: "Середні", high: "Високі",
            caption: "Налаштовує звук програм, що відтворюються через цей вихід.",
            deviceTooltip: "Вихід для еквалайзера")
        case .zhHans: return .init(
            title: "均衡器", bands: "频段", preamp: "前级放大", reset: "重置",
            low: "低音", mid: "中音", high: "高音",
            caption: "调整通过此输出播放的 App 的声音。",
            deviceTooltip: "要均衡的输出")
        case .zhTW: return .init(
            title: "等化器", bands: "頻段", preamp: "前級放大", reset: "重置",
            low: "低音", mid: "中音", high: "高音",
            caption: "調整透過此輸出播放的 App 聲音。",
            deviceTooltip: "要等化的輸出")
        case .zhHK: return .init(
            title: "等化器", bands: "頻段", preamp: "前級放大", reset: "重設",
            low: "低音", mid: "中音", high: "高音",
            caption: "調整透過此輸出播放的 App 聲音。",
            deviceTooltip: "要等化的輸出")
        }
    }

    /// The label under one band: the three-band layout names its bands the
    /// way a tone control does, every other layout shows the frequency.
    func label(for band: Int, in layout: EqualizerLayout) -> String {
        if layout == .three {
            switch band {
            case 0: return low
            case 1: return mid
            default: return high
            }
        }
        let bands = layout.bands
        return bands.indices.contains(band) ? bands[band].frequencyLabel : ""
    }
}
