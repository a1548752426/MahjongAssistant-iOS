import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: GameStore
    @State private var draftURL = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://192.168.1.100:8000", text: $draftURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    HStack {
                        Button("保存地址") {
                            store.serverURL = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
                            store.connectionStatus = "未测试"
                        }
                        Spacer()
                        Button("测试连接") {
                            store.serverURL = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
                            Task { await store.testServer() }
                        }
                    }
                    LabeledContent("状态", value: store.connectionStatus)
                        .foregroundStyle(connectionColor)
                } header: {
                    Text("备用在线照片识别")
                } footer: {
                    Text("离线实时摄像头不使用这里的地址。只有选择“在线相册”时才会把照片发送到该 FastAPI 服务。")
                }

                Section {
                    instructionRow(number: "1", title: "横屏取景", detail: "让整排立牌完整入镜，避免手指遮挡和强烈反光。")
                    instructionRow(number: "2", title: "副露默认放右边", detail: "右侧橙色区域放碰/杠；可调整宽度或切换到左边。")
                    instructionRow(number: "3", title: "处理盖牌", detail: "露出两张同牌会自动推断暗杠；完全盖住时点“全盖暗杠＋”手动指定。")
                    instructionRow(number: "4", title: "记录摸牌", detail: "离开相机后，每轮在首页摸牌区点一下实际摸到的牌。")
                    instructionRow(number: "5", title: "按建议切牌", detail: "建议按预计胡牌率排序；点“切牌”后才会扣牌并记录自己的弃牌。")
                    instructionRow(number: "6", title: "自动报听", detail: "模型判断切牌后进入听牌时，会显示“切牌并报听”并自动记录报听状态。")
                } header: {
                    Text("离线实时识别")
                } footer: {
                    Text("模型随应用打包，视频帧在 iPhone 上处理，不需要网络。")
                }

                Section {
                    LabeledContent("应用", value: "听牌助手")
                    LabeledContent("版本", value: "1.2.0")
                    LabeledContent("最低系统", value: "iOS 16")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("隐私说明")
                            .font(.subheadline.weight(.semibold))
                        Text("离线实时模式不会上传摄像头画面。只有主动选择“在线相册”时，照片才会发送到上方配置的服务器。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("关于")
                }
            }
            .navigationTitle("设置")
            .onAppear {
                draftURL = store.serverURL
            }
        }
    }

    private var connectionColor: Color {
        if store.connectionStatus == "连接成功" { return .green }
        if store.connectionStatus == "未测试" || store.connectionStatus == "测试中…" { return .secondary }
        return .red
    }

    private func instructionRow(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
