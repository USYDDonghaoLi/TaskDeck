import SwiftUI

struct FocusConsoleView: View {
    @EnvironmentObject private var focus: FocusStore
    @EnvironmentObject private var language: LanguageStore

    var body: some View {
        if let active = focus.active {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = focus.elapsed(at: context.date)
                VStack(spacing: 0) {
                    HStack(spacing: 13) {
                        Button {
                            active.isPaused ? focus.resume() : focus.pause()
                        } label: {
                            Image(systemName: active.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(DeckTheme.void)
                                .frame(width: 30, height: 30)
                                .background(active.isPaused ? DeckTheme.lime : DeckTheme.cyan)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(active.isPaused
                            ? language.text("继续专注", "Resume focus")
                            : language.text("暂停专注", "Pause focus"))

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 7) {
                                Text(active.isPaused
                                    ? language.text("专注已暂停", "FOCUS PAUSED")
                                    : language.text("专注频道运行中", "FOCUS CHANNEL ACTIVE"))
                                    .font(.system(size: 7, weight: .black))
                                    .foregroundStyle(active.isPaused ? DeckTheme.lime : DeckTheme.cyan)
                                    .tracking(1.1)
                                Text("// \((active.direction == "未分类" ? language.text("未分类", "Uncategorized") : active.direction).uppercased())")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(DeckTheme.muted)
                            }
                            Text(active.taskTitle)
                                .font(.system(size: 10, weight: .bold))
                                .lineLimit(1)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(formatDuration(Int(elapsed)))
                                .font(.system(size: 18, weight: .black))
                                .foregroundStyle(DeckTheme.text)
                                .monospacedDigit()
                            Text(language.format("目标 %d 分钟", "TARGET %d MIN", active.estimatedMinutes))
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(DeckTheme.muted)
                        }

                        Button(language.text("结束专注", "Finish Focus")) { _ = focus.finish() }
                            .buttonStyle(.plain)
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(DeckTheme.text)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(DeckTheme.panelRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .accessibilityLabel(language.text("结束专注", "Finish focus") + " " + active.taskTitle)

                        Menu {
                            Button(language.text("放弃本次记录", "Discard This Session"), role: .destructive) { focus.discardActive() }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(DeckTheme.muted)
                                .frame(width: 24, height: 28)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .accessibilityLabel(language.text("更多专注操作", "More focus actions"))
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 56)

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(DeckTheme.panelRaised)
                            Rectangle()
                                .fill(elapsed >= Double(active.estimatedMinutes * 60) ? DeckTheme.lime : DeckTheme.cyan)
                                .frame(width: geometry.size.width * min(1, elapsed / Double(max(60, active.estimatedMinutes * 60))))
                        }
                    }
                    .frame(height: 2)
                }
                .background(DeckTheme.panel.opacity(0.88))
            }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remaining = seconds % 60
        return hours > 0
            ? String(format: "%02d:%02d:%02d", hours, minutes, remaining)
            : String(format: "%02d:%02d", minutes, remaining)
    }
}
