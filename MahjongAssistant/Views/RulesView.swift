import SwiftUI

struct RulesView: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        store.setRulesPreset(.localDefault)
                    } label: {
                        presetRow(
                            title: "本地玩法（默认）",
                            detail: "只碰不吃 · 报听后可胡 · 全程可杠",
                            selected: store.rules == .localDefault
                        )
                    }
                    Button {
                        store.setRulesPreset(.common)
                    } label: {
                        presetRow(
                            title: "大众麻将",
                            detail: "可吃碰杠 · 成牌即可胡",
                            selected: store.rules == .common
                        )
                    }
                } header: {
                    Text("快速预设")
                }

                Section {
                    Toggle("允许吃牌", isOn: binding(\.allowChi))
                    Toggle("允许碰牌", isOn: binding(\.allowPon))
                    Toggle("允许杠牌", isOn: binding(\.allowKan))
                    Toggle("必须先报听才能胡", isOn: binding(\.winRequiresReady))
                } header: {
                    Text("鸣牌与获胜")
                } footer: {
                    Text("“必须先报听”打开时，即使牌型已经完成，助手也只会在已报听状态下建议胡牌。")
                }

                Section {
                    Toggle("七对", isOn: binding(\.allowSevenPairs))
                    Toggle("十三幺", isOn: binding(\.allowThirteenOrphans))
                    Toggle("只推荐不降牌效的碰", isOn: binding(\.onlyRecommendUsefulPon))
                } header: {
                    Text("特殊牌型与建议偏好")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("当前规则")
                            .font(.headline)
                        Text(store.rules.summary)
                            .foregroundStyle(Color.accentColor)
                        Text(ruleExplanation)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("麻将规则")
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<RuleSettings, T>) -> Binding<T> {
        Binding(
            get: { store.rules[keyPath: keyPath] },
            set: { store.rules[keyPath: keyPath] = $0 }
        )
    }

    private func presetRow(title: String, detail: String, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private var ruleExplanation: String {
        var lines: [String] = []
        lines.append(store.rules.allowChi ? "顺子可通过吃牌组成。" : "不会显示吃牌建议。")
        lines.append(store.rules.allowPon ? "手中两张同牌时可判断碰牌。" : "不会显示碰牌建议。")
        lines.append(store.rules.allowKan ? "明杠、暗杠在整局中均可记录。" : "不会显示杠牌建议。")
        lines.append(store.rules.winRequiresReady ? "只有点击“报听”后才会建议胡牌。" : "牌型完成即可建议胡牌。")
        return lines.joined(separator: "\n")
    }
}

