# JustNow

[English](README.md) | 简体中文

**一款记录具体做了什么的原生 macOS 时间日志。**

JustNow 定时提醒你回顾上一时段，逐项写下做过的事。每项事件包含主题与具体内容，主题可以边写边输入，无需提前创建项目或任务。使用 SwiftUI 与 AppKit 构建。

[下载 macOS 版本](https://github.com/AbyssSkb/JustNow/releases/latest) · [反馈问题](https://github.com/AbyssSkb/JustNow/issues) · [发布指南](docs/RELEASING.md)

![JustNow 今日页面，显示最近的片段](docs/images/justnow-today.png)

## 记录一个时段

默认随应用启动开始记录，首次使用会在完成引导后开始。每隔 30 分钟，提醒窗口显示刚结束的时段。分别填写每件事的主题与具体内容，主题留空归入「其他」，按 `Enter` 新增一项，按 `Command-Return` 保存。窗口随列表增高，达到高度上限后滚动。

上一时段的记录可以作为只读参照。可选的应用线索显示你使用过的前台应用及其时间占比，帮助回忆细节，具体内容由你自己填写。

![JustNow 提醒窗口，包含独立的主题与内容输入框、上一段记录和应用线索](docs/images/justnow-reminder.png)

选择「稍后」可以留下待补记时段，空白时段也可以跳过。草稿自动保存。你可以从日志继续填写待补记记录、补记遗漏的时段，或修改已有记录。

计时从开始记录的时刻计算：09:07 开始、间隔 30 分钟，时段依次为 09:07–09:37、09:37–10:07。保存记录不会改变提醒节奏。设置支持 1–240 分钟的间隔，修改对下一次开始记录生效。

## 按日期与主题回顾

今日的片段按时间倒序排列。时间档案支持切换日期、搜索当天记录，以及修改记录的日期、起止时间和事件。

主题页将已保存的事件归类，统计事件数量和涉及时段数。一个时段可以包含多个主题，同一主题的不同大小写写法会合并。这些统计不会推测每个主题花了多长时间。

![JustNow 主题页面，显示主题统计与已保存的事件](docs/images/justnow-topics.png)

旧版本的纯文字记录保留原文，使用事件输入框编辑并保存后才加入主题统计。待补记记录不计入统计。

*截图来自原生应用，使用示例数据。*

## 开始、停止与回来

主窗口和菜单栏都可以开始或结束记录。结束时会保留最后一个不足整段的时段，没有需要记的内容时可以跳过。你也可以在设置中关闭随启动开始记录。

Mac 睡眠、屏幕睡眠或切换到其他用户会话时暂停记录。默认还会在连续 30 分钟没有键鼠操作时暂停，这项规则可以关闭。回来后，你可以选择跳过间隙、从现在继续，或保留这段时间供补记。暂停状态会在重启和更新后保留，等待你决定。

设置还包括中文与英文、浅色与深色外观、提醒声音、应用线索和登录时启动。

## 你的数据

记录与草稿以本地 JSON 保存于：

```text
~/Library/Application Support/JustNow/
```

JustNow 保留上一次成功保存的备份，并支持导出 CSV 或 JSON。JSON 包含事件、主题与应用线索；CSV 包含记录文字、时间和状态。长期备份请使用导出文件或自己的备份系统。

应用线索可以关闭，仅在正在记录时采集，将应用名称、标识和前台停留时长随时段保存。占比以整个时段为基准，未观测的时间单独显示。之后编辑记录时仍能查看；修改起止时间后，线索保留原始采集范围。

无需账号，没有遥测和云同步。JustNow 不采集截图、窗口标题、网页地址、浏览器历史、文件内容或按键内容。无操作检测只读取系统汇总的空闲时长。网络用于检查更新与下载安装包，日志留在你的 Mac 上。

## 安装与更新

需要 **macOS 14 或更新版本**。通用发布包支持 **Apple silicon 与 Intel Mac**。

1. 从 [Releases](https://github.com/AbyssSkb/JustNow/releases/latest) 下载最新 DMG。
2. 打开后将 JustNow 拖入 Applications。ZIP 包包含同一个应用。
3. 打开 JustNow，完成首次引导后开始记录，默认间隔为 30 分钟。

发布版本使用 Sparkle 与 [GitHub 更新源](https://github.com/AbyssSkb/JustNow/releases/latest/download/appcast.xml)，可以从应用菜单或设置检查更新。应用内更新重启前，JustNow 保存当前会话与草稿；新版继续原来的提醒节奏，并保留暂停状态。源码构建默认使用同一个更新源；明确关闭更新配置的构建不启用更新检查。

**签名状态：** 请查看对应版本的发布说明。未配置 Apple Developer 签名身份的构建使用 ad-hoc 签名，没有经过公证，macOS 可能阻止打开下载的应用。签名与公证步骤见[发布指南](docs/RELEASING.md)。

## 从源码构建

需要 macOS 14 或更新版本、**Swift 6.2 工具链**、Xcode Command Line Tools，以及用于原生编辑器检查的 Python 3。Swift Package Manager 会下载 Sparkle 框架。

```sh
git clone https://github.com/AbyssSkb/JustNow.git
cd JustNow
swift test --no-parallel
python3 scripts/check-editor-wrapping.py
./scripts/build-app.sh
open dist/JustNow.app
```

构建脚本在 `dist/` 生成通用应用、ZIP、DMG 与 SHA-256 校验文件。开发检查见 [CONTRIBUTING.md](CONTRIBUTING.md)，更新签名与打包流程见 [docs/RELEASING.md](docs/RELEASING.md)。

## 反馈与许可

欢迎通过 [GitHub Issues](https://github.com/AbyssSkb/JustNow/issues) 报告问题与提出建议。请提供 macOS 和 JustNow 版本、复现步骤，并在截图中移除私人内容。

JustNow 使用 [MIT 许可证](LICENSE)。
