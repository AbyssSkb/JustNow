<p align="center">
  <img src="Resources/AppIcon-preview.png" width="128" alt="JustNow 图标：紫色对话气泡中的时钟">
</p>

# JustNow · 刚才

**刚才这半小时，你做了什么？**

JustNow 是一个原生 macOS 时间日志。手动开始后，每隔一段时间弹出一个小窗口，写一句话，继续手头的事。没有需要提前维护的 Project / Task，也没有后台活动监控。

免费开源 · 本地存储 · 无账号 · macOS 14+ · Apple Silicon 与 Intel

![JustNow 主界面](Resources/screenshots/overview.png)

<details>
<summary>查看提醒窗口、深色外观与首次使用引导</summary>

![JustNow 提醒窗口](Resources/screenshots/reminder.png)

![JustNow 深色外观](Resources/screenshots/dark.png)

![JustNow 首次使用引导](Resources/screenshots/onboarding.png)

</details>

## 为什么做这个

我们想保留定时回顾的习惯，同时让记录足够轻：不用事先定义任务，不用全天开着计时器，也不用把私人活动上传到服务端。JustNow 只在你主动开始后工作。

## 核心体验

- **手动开始，手动停止。** 默认 30 分钟一次；可在设置中更改间隔。
- **直接写刚才做了什么。** 每段记录包含起止时间与自由文字，支持多行。
- **时间线与回顾。** 按日期查看、搜索、修改历史记录，也可以手动补记。
- **漏填也能补。** 点「稍后」保留待填写时间段，不丢失它的位置。
- **本地保存与导出。** JSON 日志自动保存，保留上一次成功保存的备份，支持 CSV / JSON 导出。
- **随时从菜单栏操作。** 查看状态、打开日志、开始或结束记录。

## 安装

正式版本发布后，可在 [Releases](https://github.com/AbyssSkb/justnow/releases) 选择通用版 DMG，打开后将 JustNow 拖入 Applications。ZIP 包也包含同一个应用。最低系统版本是 **macOS 14 Sonoma**。

**签名状态：** 本仓库默认构建和 CI 附件使用 ad-hoc 签名，尚未经过 Apple 公证。从网络下载后 Gatekeeper 可能阻止打开；这与本机编译运行不同。正常的公开分发需要发布者使用 Developer ID Application 证书签名并经过 Apple 公证，请以对应 Release 的签名说明为准。当前没有可承诺无警告安装的已公证版本。

你也可以直接从源码构建：

```sh
git clone https://github.com/AbyssSkb/justnow.git
cd justnow
swift test
./scripts/build-app.sh
open dist/JustNow.app
```

需要 Xcode Command Line Tools（Swift 5.9+）；`xcode-select --install` 可安装。应用使用系统框架，不需要第三方包。构建脚本会生成 `dist/JustNow.app`、通用 ZIP、DMG 与 SHA-256 校验文件。

## 怎么记录

1. 打开 JustNow，点击「开始记录」。
2. 到时间后，弹窗显示刚结束的时间段。输入文字，点击保存。
3. 忙的时候可以点「稍后」，之后从时间线补写。
4. 工作告一段落，点击「停止记录」；不足一个间隔的最后一段也可以填写。

计时从点击开始的时刻计算，而不是对齐钟表刻度。例如 09:07 开始、间隔 30 分钟，第一段是 09:07–09:37，第二段是 09:37–10:07。**填写和保存不会推迟下一次提醒**。更改间隔对下一次开始记录生效。

Mac 进入睡眠时暂停，唤醒后仅恢复此前正在进行的记录；睡眠时间不会算作活动时间。退出或重启后不会自动开始计时；异常退出留下的记录可按上次保存的活动状态恢复为待填写时段，再由你手动开始新一轮。

## 你的数据

日志保存在：

```text
~/Library/Application Support/JustNow/
```

数据采用本地 JSON 文件，保留上一次成功保存的备份。可通过应用导出 CSV 或 JSON，方便迁移、长期备份和自己的分析。上一次保存备份不能替代跨设备备份；请按需要将导出文件保存在自己的备份位置。

JustNow **不读取屏幕、应用使用记录或浏览器历史，不包含遥测，不需要网络或账号**。它记录的内容只有你自己填写的文字与时间。应用不提供云同步；你拥有原始数据。

## 发布签名与公证

本地使用可以直接构建。准备公开发布时，需要提供 `notarytool` / `stapler` 的 Xcode 工具、Apple Developer Program 的 Developer ID Application 证书，以及保存在 macOS Keychain 中的 `notarytool` 凭据配置；**不要把证书、密码或私钥提交到 GitHub**。

```sh
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
VERSION=0.1.0 ./scripts/build-app.sh

SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='justnow-notary' ./scripts/notarize.sh
```

先按照 [Apple 的公证流程](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) 创建 Keychain profile。脚本会检查 Developer ID 签名、hardened runtime 与时间戳；提交 ZIP、等待通过后将票据附加到 app，再重新生成 ZIP / DMG，提交并附加 DMG 票据，最后验证与更新校验文件。ZIP 本身不能附加票据，分发的 ZIP 内包含已附加票据的 app。

GitHub Actions 在 push / PR 时测试与构建；推送 `v0.1.0` 这类标签会创建一个带安装包的**草稿 Release**。CI 未配置签名凭据，附件会明确标为 ad-hoc / 未公证。正式发布前，用公证后的安装包替换草稿附件。没有证书时，仍可分享源码和清楚标注签名状态的构建。

## 参与开发

详见 [CONTRIBUTING.md](CONTRIBUTING.md)。图标由原生 AppKit 绘制，源文件保存在 `scripts/generate-icon.swift`。许可采用 [MIT](LICENSE)。

---

## English

**What did you do just now?**

JustNow is a native, local-first activity journal for macOS 14+. Start a session manually, receive a prompt every 30 minutes by default, and describe the previous interval in your own words. No projects or tasks to set up. Apple Silicon and Intel are supported by the same universal build.

- Adjustable intervals; saving an entry does not reset the timer.
- Daily timeline, search, editing, manual backfill, and pending entries when you choose Later.
- Stop captures the final partial interval. Sleep pauses tracking; waking resumes only an active session. Relaunch always requires a manual start.
- Local JSON journal with previous-save backup, plus CSV / JSON export.
- No account, telemetry, network requests, screen monitoring, or browsing history access.

Build with `swift test` and `./scripts/build-app.sh`, then open `dist/JustNow.app`. Requires Xcode Command Line Tools and Swift 5.9+. Data lives in `~/Library/Application Support/JustNow/`.

**Distribution:** Default builds are ad-hoc signed and **not notarized**; Gatekeeper may block downloaded copies. A verified public release requires a Developer ID Application certificate and Apple notarization. Set `SIGNING_IDENTITY` when building, then run `scripts/notarize.sh` with the same identity and a `NOTARY_PROFILE` stored in Keychain. Tag builds create draft releases, so maintainers can replace CI assets with notarized packages before publishing.

Free and open source under the MIT license. Contributions welcome.
