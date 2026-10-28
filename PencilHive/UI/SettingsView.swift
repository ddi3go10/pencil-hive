import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 18) {
                    Text("Settings")
                        .roundedFont(28, .black)
                        .foregroundColor(Palette.ink)
                        .padding(.top, 24)

                    VStack(spacing: 0) {
                        Toggle("Sound", isOn: Binding(get: { app.settings.soundEnabled }, set: app.setSound))
                            .padding(16)
                        Divider()
                        Toggle("Haptics", isOn: Binding(get: { app.settings.hapticsEnabled }, set: app.setHaptics))
                            .padding(16)
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Tile symbols", isOn: Binding(get: { app.settings.tileSymbols }, set: app.setTileSymbols))
                            Text("Prints a shape on every tile so colours are easy to tell apart. Always on when iOS Differentiate Without Color is on.")
                                .font(.footnote)
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundColor(Palette.ink.opacity(0.6))
                        }
                        .padding(16)
                    }
                    .roundedFont(18, .bold)
                    .tint(Palette.green)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.panel))

                    Button("Reset Progress") { confirmReset = true }
                        .buttonStyle(ChunkyButtonStyle(color: Palette.coral, compact: true))
                        .confirmationDialog("Erase all stars and unlocked levels?", isPresented: $confirmReset, titleVisibility: .visible) {
                            Button("Erase Progress", role: .destructive) { app.resetProgress() }
                            Button("Cancel", role: .cancel) {}
                        }

                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(ChunkyButtonStyle(color: Palette.green))
                    Text("Pencil Hive works fully offline. No accounts, ads or purchases.")
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                        .foregroundColor(Palette.ink.opacity(0.6))
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
        }
        .background(Palette.cream.ignoresSafeArea())
    }
}
