# 听牌助手（iOS）

一个原生 SwiftUI 麻将牌效助手，目标安装方式为 LiveContainer。应用可以离线手动录牌并计算向听、进张、切牌建议；照片识别通过局域网连接参考项目的 FastAPI/YOLO 后端。

## 已实现

- iPhone 相机、相册识牌，以及识别后的逐张人工校正
- 标准四面子一将、七对、十三幺的向听与和牌判断
- 按“向听优先、进张数次优”排序切牌
- 对方出牌后的胡、碰、杠、吃判断
- 明杠、暗杠和副露记录
- 应用内规则开关与两个预设
- 默认规则：只碰不吃、报听后可胡、全程可杠
- 与参考项目的 `/api/start-session`、`/api/analyze-hand`、`/api/end-session` 接口兼容
- GitHub Actions 自动测试并生成未签名 IPA

## 照片识别

参考项目由 Android 客户端和 Python 后端组成。其仓库未声明开源许可证，因此本工程没有复制或分发其中的源码、模型或素材，只实现了兼容客户端。

1. 在电脑上单独运行[参考项目](https://github.com/LYiHub/AR-Mahjong-Assistant-preview)的 FastAPI 服务。
2. 保证 iPhone 和电脑连接同一局域网。
3. 在应用“设置”中填入电脑地址，例如 `http://192.168.1.100:8000`。
4. 横向拍照：上半部分放暗牌，下半部分放碰/杠后的副露。
5. 识别完成后点按错牌删除，再用“手动”补牌。

没有后端时，手动录牌和全部本地牌效功能仍可使用。

## 生成未签名 IPA

### GitHub Actions

将本目录推送到 GitHub，打开 `Actions → Build unsigned IPA → Run workflow`。构建成功后，在任务底部下载 `MahjongAssistant-unsigned-ipa`，解压即可得到：

```text
MahjongAssistant-unsigned.ipa
```

随后将 IPA 导入 LiveContainer。LiveContainer 的签名、JIT 和容器设置由你的设备环境负责。

### macOS 本地构建

需要 Xcode 16 和 XcodeGen：

```bash
brew install xcodegen
bash scripts/build-unsigned-ipa.sh
```

产物位于 `build/MahjongAssistant-unsigned.ipa`。

## 开发

生成 Xcode 工程：

```bash
xcodegen generate --spec project.yml
open MahjongAssistant.xcodeproj
```

运行不依赖 Xcode 的结构检查：

```bash
python tools/verify_project.py
```

最低系统为 iOS 16，无第三方 iOS 依赖。

