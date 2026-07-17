# 听牌助手（iOS）

一个原生 SwiftUI 麻将牌效助手，目标安装方式为 LiveContainer。应用把 YOLO 模型打包在 IPA 内，能直接打开摄像头离线实时识牌、计算牌效，并把建议打出的牌标在画面上。

## 已实现

- iPhone 摄像头离线实时识牌，不上传视频画面
- 识别框、置信度和建议打牌绿色粗框实时叠加
- 等比例完整预览，检测框与摄像头画面使用同一坐标系
- 摄像头只识别自己的手牌和副露，不再要求拍下整桌弃牌
- 副露默认放在右侧橙色区域，也可切换到左边
- 两张相同明牌可推断为带两张盖牌的暗杠；全盖暗杠可手动指定
- Core ML 执行后端优先使用 Apple 神经引擎/GPU，CPU 自动兜底
- 在线相册识别保留为 FastAPI 备用方式
- 标准四面子一将、七对、十三幺的向听与和牌判断
- 首页摸牌区记录每轮实际摸牌，点击建议区“切牌”后记录自己的弃牌
- 切牌建议以预计胡牌率优先，向听数和进张数作为辅助信息
- 模型判断何时进入听牌；建议显示“切牌并报听”时会自动记录报听
- 明杠、暗杠和副露记录
- 应用内规则开关与两个预设
- 默认规则：只碰不吃、报听后可胡、全程可杠
- 与参考项目的 `/api/start-session`、`/api/analyze-hand`、`/api/end-session` 接口兼容
- GitHub Actions 自动测试并生成未签名 IPA

## 离线实时识别

1. 点击首页的“离线实时”，建议把 iPhone 横过来使用。
2. 让整排立牌进入画面，避免遮挡和强烈反光。
3. 把亮出的碰/杠牌放在右侧橙色区域，可调整橙色区域宽度或切换到左边。
4. 暗杠若有两张同牌朝上，会自动把另外两张盖牌补齐；如果四张全部盖住，点击“全盖暗杠＋”选择牌种。
5. 连续两帧识别稳定后，应用会同步手牌和副露；绿色粗框和顶部文字表示当时的建议。
6. 正式打牌时，每轮在首页“摸牌区”点选实际摸到的牌，再在“胜率优先建议”中点击“切牌”。

## 胜率与报听

应用只使用自己的手牌、副露和已经记录的自家弃牌，不假设知道其他玩家或未知牌墙。建议中的“预计胡牌率”以未来 8 次自己的摸牌为观察窗口：听牌状态按剩余等待牌进行不放回估算，未听牌状态会按仍需完成的改良阶段折减，因此它是用于比较切牌方案的本地估计值，不是整局精确胜率。

默认规则要求先听牌后才能胡。当某个切牌方案形成有效听牌时，模型会把它标为“切牌并报听”；点击后同时扣除该牌、记入自己的弃牌，并进入已报听状态。

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
