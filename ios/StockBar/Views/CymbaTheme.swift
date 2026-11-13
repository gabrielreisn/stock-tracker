import SwiftUI
import UIKit

/// Keep these tokens in sync with mobile/src/constants/theme.ts.
enum CymbaTheme {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color { Color(uiColor: adaptiveUIColor(light, dark)) }
    static func adaptiveUIColor(_ light: UInt32, _ dark: UInt32) -> UIColor {
        UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        }
    }
    static let background = adaptive(0xffffff, 0x0a0a0a)
    static let surface = adaptive(0xf2f2f4, 0x1a1a1c)
    static let selected = adaptive(0xe4e4e7, 0x2a2a2e)
    static let text = adaptive(0x171717, 0xededed)
    static let secondary = adaptive(0x63636b, 0xa1a1aa)
    static let accent = Color(hex: 0x2563eb)
    static let link = adaptive(0x2563eb, 0x60a5fa)
    static let success = adaptive(0x16a34a, 0x22c55e)
    static let warning = adaptive(0xb45309, 0xfb923c)
    static let danger = Color(hex: 0xdc2626)
}

struct CymbaPage<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16).padding(.bottom, 16)
        }
        .background(CymbaTheme.background)
        .foregroundStyle(CymbaTheme.text)
        .scrollDismissesKeyboard(.interactively)
    }
}

struct CymbaCard<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(CymbaTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct CymbaHeading: View {
    let title: LocalizedStringKey
    var size: CGFloat = 20
    var body: some View { Text(title).font(.system(size: size, weight: .semibold)).accessibilityAddTraits(.isHeader) }
}

struct CymbaCaption: View {
    let text: LocalizedStringKey
    var body: some View { Text(text).font(.system(size: 13)).foregroundStyle(CymbaTheme.secondary).fixedSize(horizontal: false, vertical: true) }
}

struct CymbaRootTitle: View {
    let title: LocalizedStringKey
    let identifier: String
    var body: some View {
        Text(title).font(.system(size: 34, weight: .bold)).accessibilityAddTraits(.isHeader).accessibilityIdentifier(identifier)
    }
}

struct CymbaActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 16, weight: .semibold))
            .foregroundStyle(primary ? .white : CymbaTheme.text)
            .frame(minHeight: 44).padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(primary ? CymbaTheme.accent : CymbaTheme.selected, in: RoundedRectangle(cornerRadius: 10))
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.7 : 1)
    }
}

struct CymbaInputStyle: TextFieldStyle {
    var inset = false
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.font(.system(size: 17)).padding(.horizontal, 12).frame(minHeight: 48)
            .foregroundStyle(CymbaTheme.text)
            .background(inset ? CymbaTheme.background : CymbaTheme.surface, in: RoundedRectangle(cornerRadius: 10))
            .tint(CymbaTheme.accent)
    }
}

struct CymbaMetric: View {
    let label: LocalizedStringKey
    let value: String
    var color: Color = CymbaTheme.text
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 13)).foregroundStyle(CymbaTheme.secondary)
            Text(value).font(.system(size: 20, weight: .semibold)).monospacedDigit().foregroundStyle(color).minimumScaleFactor(0.65).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func cymbaNavigationTitle(_ title: LocalizedStringKey) -> some View {
        navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(CymbaTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
    func cymbaList() -> some View {
        listStyle(.insetGrouped).scrollContentBackground(.hidden)
            .background(CymbaTheme.background)
            .listSectionSpacing(16)
    }
}

struct CymbaChoices: View {
    let values: [String]
    @Binding var selected: String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Button { selected = value } label: {
                        Text(LocalizedStringKey(value)).font(.system(size: 14))
                            .foregroundStyle(selected == value ? .white : CymbaTheme.text)
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(selected == value ? CymbaTheme.accent : CymbaTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).accessibilityAddTraits(selected == value ? .isSelected : [])
                }
            }
        }
    }
}

struct CymbaField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var prompt: LocalizedStringKey = ""
    var numeric = false
    var identifier = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 16, weight: .medium))
            TextField(title, text: $text, prompt: Text(prompt)).textFieldStyle(CymbaInputStyle())
                .keyboardType(numeric ? .decimalPad : .default).accessibilityLabel(Text(title)).accessibilityIdentifier(identifier)
        }
    }
}
