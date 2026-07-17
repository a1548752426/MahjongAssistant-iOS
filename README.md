# 听牌助手（iOS）

一个原生 SwiftUI 麻将牌效助手，目标安装方式为 LiveContainer。应用把 YOLO 模型打包在 IPA 内，能直接打开摄像头离线实时识牌、计算牌效，并把建议打出的牌标在画面上。

## 已实现

- iPhone 摄像头离线实时识牌，不上传视频画面
- 识别框、置信度和建议打牌绿色粗框实时叠加
- 可调手牌/副露分界线，支持碰、杠牌放在立牌上方或前方
- Core ML 执行后端优先使用 Apple 神经引擎/GPU，CPU 自动兜底
- 在线相册识别保留为 FastAPI 备用方式
- 标准四面子一将、七对、十三幺的向听与和牌判断
- 按“向听优先、进张数次优”排序切牌
- 对方出牌后的胡、碰、杠、吃判断
- 明杠、暗杠和副露记录
- 应用内规则开关与两个预设
- 默认规则：只碰不吃、报听后可胡、全程可杠
- 与参考项目的 `/api/start-session`、`/api/analyze-hand`、`/api/end-session` 接口兼容
- GitHub Actions 自动测试并生成未签名 IPA

## 离线实时识别

1. 点击首页的“离线实时”，建议把 iPhone 横过来使用。
2. 让整排立牌进入画面，避免遮挡和强烈反光。
3. 把亮出的碰/杠牌放在立牌上方或前方。
4. 拖动黄色分界线，让立牌和副露分别位于线的两侧；如果摆放方向相反，可点击“副露在上/下”切换。
5. 连续两帧识别稳定后，应用会同步本地牌局；绿色粗框和顶部文字表示建议打出的牌。

实时推理会自动丢弃来不及处理的旧视频帧，并限制推理频率，以控制延迟和发热。在线相册仍与参考项目的 `/api/start-session`、`/api/analyze-hand`、`/api/end-session` 接口兼容。

离线模型来源和再分发注意事项见 [`THIRD_PARTY_MODEL_NOTICE.md`](THIRD_PARTY_MODEL_NOTICE.md)。参考仓库没有声明许可证，公开分发 IPA 前应先向上游作者确认授权。

## 生成未签名 IPA

### GitHub Actions

将本目录推送到 GitHub，打开 `Actions → Build unsigned IPA → Run workflow`。构建成功后，在任务底部下载 `MahjongAssistant-unsigned-ipa`，解压即可得到：

```text
MahjongAssistant-unsigned.ipa
```

随后将 IPA 导入 LiveContainer。LiveContainer 的签名、JIT 和容器设置由你的设备环境负责。

### macOS 本地构建

需要 Xcode 16、XcodeGen 和 CocoaPods：

```bash
brew install xcodegen
sudo gem install cocoapods
bash scripts/build-unsigned-ipa.sh
```

产物位于 `build/MahjongAssistant-unsigned.ipa`。

## 开发

生成 Xcode 工程：

```bash
xcodegen generate --spec project.yml
pod install
open MahjongAssistant.xcworkspace
```

运行不依赖 Xcode 的结构检查：

```bash
python tools/verify_project.py
```

最低系统为 iOS 16。离线推理使用微软 `onnxruntime-objc` 1.22.0。
