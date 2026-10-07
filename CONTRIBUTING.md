# 参与 JustNow

欢迎提交问题、交互建议和 Pull Request。请围绕「定时回顾、逐项记录、本地保存」这条主线改进体验。用户介绍见 [English README](README.md) 与[中文 README](README.zh-CN.md)。

## 开发

需要 macOS 14+、Swift 6.2 工具链、Xcode Command Line Tools 和 Python 3。

```sh
git clone https://github.com/AbyssSkb/JustNow.git
cd JustNow
swift test --no-parallel
python3 scripts/check-editor-wrapping.py
./scripts/build-app.sh
python3 scripts/check-single-instance.py dist/JustNow.app/Contents/MacOS/JustNow
open dist/JustNow.app
```

单实例验证使用 Python 3 标准库，在隔离的临时用户目录中占用日志锁，确认第二个实例会在读取或写入日志前退出，不会访问真实日志。

- 一个 PR 解决一个清楚的问题；附上复现步骤和验证结果。
- 修改计时、恢复或存储行为时，增加能够复现问题的核心测试。
- UI 改动请附上浅色、深色截图，检查键盘操作与 VoiceOver 标签。
- 界面文字只保留名称、状态、时间、统计、操作标签和必要说明，不添加宣传语或重复标题的副标题。
- 记录内容属于私人数据。不要将真实日志、导出文件、证书或密钥提交到仓库。
- 新依赖请先说明现有 Swift / AppKit / SwiftUI 为什么不能解决问题。

## 图标与发布

macOS Dock 和 Finder 图标使用白色圆角底板上的紫色文档与时钟轮廓，源图是 `Resources/AppIcon-macOS-source.png`，编辑提示词是 `Resources/AppIcon-macOS-prompt.txt`。

应用内透明标识使用 `Resources/AppIcon-source.png`，对应 `Resources/AppIcon-outline-prompt.txt`；旧提示词 `Resources/AppIcon-prompt.txt` 保留为设计历史。脚本使用原生 AppKit 从两张 PNG 缩放生成 ICNS、macOS 图标预览和透明界面品牌资源：

```sh
swift scripts/generate-icon.swift Resources
```

发布脚本、更新源签名及 Developer ID / Apple 公证步骤见 [docs/RELEASING.md](docs/RELEASING.md)。未配置 Apple Developer 签名身份的构建使用 ad-hoc 签名，没有经过公证；请以对应 Release 的签名说明为准。

## English

Use macOS 14+, a Swift 6.2 toolchain and Python 3. Run `swift test --no-parallel`, `python3 scripts/check-editor-wrapping.py`, `./scripts/build-app.sh`, and `python3 scripts/check-single-instance.py dist/JustNow.app/Contents/MacOS/JustNow` before submitting. The single-instance check uses only the Python standard library and an isolated temporary journal. Keep changes focused, add a regression check for timing or persistence changes, and include light/dark screenshots for UI changes. UI copy should contain names, states, times, counts, actions and necessary explanations; omit slogans and redundant subtitles. Never commit private journal data, certificates, or keys. See the [release guide](docs/RELEASING.md) for signing, notarization and update feeds. Contributions are licensed under MIT.
