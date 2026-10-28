import SwiftUI

struct HowToPlayView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [(icon: String, title: String, text: String)] = [
        ("hand.draw.fill", "Drag a stack", "Pick up a stack from the tray and drop it on any empty cell of the board."),
        ("arrow.triangle.merge", "Match colours", "When you drop a stack, it pulls the top run of its colour from every touching stack that shows the same colour. Revealed colours can match again, so chains keep going!"),
        ("pencil", "Make pencils", "Collect enough tiles of one colour on top of a stack and they turn into a pencil."),
        ("paintbrush.pointed.fill", "Collect your picture", "Each needed pencil fills the meter at the top. Finish every colour goal to reveal the completed picture, then find it in your Gallery."),
        ("star.fill", "Earn three stars", "One for finishing the picture, one for the level's bonus goal (see the pause menu), and one for finishing without using a booster."),
        ("wand.and.stars", "Use boosters", "Undo a move, smash a stack with the hammer, or swap the tray for fresh stacks."),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("How to Play")
                .roundedFont(28, .black)
                .foregroundColor(Palette.ink)
                .padding(.top, 24)
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                        HStack(spacing: 14) {
                            Image(systemName: step.icon)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 48, height: 48)
                                .background(Circle().fill(Palette.blue))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title).roundedFont(17, .heavy)
                                Text(step.text).roundedFont(14, .medium).foregroundColor(Palette.ink.opacity(0.75))
                            }
                            .foregroundColor(Palette.ink)
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.panel))
                    }
                }
            }
            Button("Got it") { dismiss() }
                .buttonStyle(ChunkyButtonStyle(color: Palette.green))
        }
        .padding(24)
        .background(Palette.cream.ignoresSafeArea())
    }
}
