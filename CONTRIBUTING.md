# 参与 JustNow

欢迎提交问题、交互建议和 Pull Request。请围绕「定时回顾、自由文字、本地保存」这条主线改进体验。

## 开发

需要 macOS 14+ 和 Xcode Command Line Tools（Swift 5.9+）。

```sh
git clone https://github.com/AbyssSkb/justnow.git
cd justnow
swift test
./scripts/build-app.sh
python3 scripts/check-single-instance.py dist/JustNow.app/Contents/MacOS/JustNow
open dist/JustNow.app
```

单实例验证使用 Python 3 标准库，在隔离的临时用户目录中占用日志锁，确认第二个实例会在读取或写入日志前退出，不会访问真实日志。

- 一个 PR 解决一个清楚的问题；附上复现步骤和验证结果。
- 修改计时、恢复或存储行为时，增加能够复现问题的核心测试。
- UI 改动请附上浅色、深色截图，检查键盘操作与 VoiceOver 标签。
- 记录内容属于私人数据。不要将真实日志、导出文件、证书或密钥提交到仓库。
- 新依赖请先说明现有 Swift / AppKit / SwiftUI 为什么不能解决问题。

## 图标与发布

现用图标是透明紫色轮廓的文档与时钟。源图是 `Resources/AppIcon-source.png`，编辑提示词保存在 `Resources/AppIcon-outline-prompt.txt`，旧提示词 `Resources/AppIcon-prompt.txt` 保留为设计历史。脚本使用原生 AppKit 缩放，生成 ICNS、预览图和界面品牌资源：

```sh
swift scripts/generate-icon.swift Resources
```

发布脚本及 Developer ID / Apple 公证步骤见 [README](README.md#发布签名与公证)。CI 会测试和构建通用安装包；`v*` 标签创建**草稿** Release，其默认附件没有经过 Apple 公证。

## English

Use macOS 14+ and Swift 5.9+. Run `swift test`, `./scripts/build-app.sh`, and `python3 scripts/check-single-instance.py dist/JustNow.app/Contents/MacOS/JustNow` before submitting. The Python check uses only the standard library and an isolated temporary journal. Keep changes focused, add a regression check for timing or persistence changes, and include light/dark screenshots for UI changes. Never commit private journal data, certificates, or keys. Contributions are licensed under MIT.
