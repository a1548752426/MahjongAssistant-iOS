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
                    instructionRow(number: "2", title: "调整黄线", detail: "立牌放在手牌区；亮出的碰/杠放到黄线另一侧。")
                    instructionRow(number: "3", title: "看绿色牌框", detail: "稳定识别两帧后，绿色粗框和顶部文字就是建议打出的牌。")
                } header: {
                    Text("离线实时识别")
                } footer: {
                    Text("模型随应用打包，视频帧在 iPhone 上处理，不需要网络。")
                }

                Section {
                    LabeledContent("应用", value: "听牌助手")
                    LabeledContent("版本", value: "1.1.0")
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
