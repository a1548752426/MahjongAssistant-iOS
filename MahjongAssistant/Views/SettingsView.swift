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
                    Text("照片识别后端")
                } footer: {
                    Text("填写运行参考项目 FastAPI 服务的电脑局域网地址。iPhone 与电脑需在同一 Wi‑Fi；例如 http://192.168.1.100:8000。")
                }

                Section {
                    instructionRow(number: "1", title: "横向拍摄", detail: "让所有牌完整入镜，避免反光和遮挡。")
                    instructionRow(number: "2", title: "上下分区", detail: "照片上半部分放暗牌，下半部分放已碰/杠的副露。")
                    instructionRow(number: "3", title: "识别后校正", detail: "点按错误的牌删除，再用“手动”补入正确牌。")
                } header: {
                    Text("拍摄方式")
                } footer: {
                    Text("这是为兼容参考项目的双区域 YOLO 识别方式。")
                }

                Section {
                    LabeledContent("应用", value: "听牌助手")
                    LabeledContent("版本", value: "1.0.0")
                    LabeledContent("最低系统", value: "iOS 16")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("隐私说明")
                            .font(.subheadline.weight(.semibold))
                        Text("手动牌局数据只保存在本机。使用照片识别时，图片只发送到你在上方配置的服务器。")
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
