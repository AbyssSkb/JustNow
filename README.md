<p align="center">
  <img src="Resources/AppIcon-preview.png" width="128" alt="JustNow macOS 图标：白色圆角底板上的紫色文档与时钟轮廓">
</p>

# JustNow · 刚才

**刚才这半小时，你做了什么？**

JustNow 是一个原生 macOS 时间日志。默认随应用启动记录，每隔一段时间弹出一个小窗口，写一句话，继续手头的事。无需提前维护 Project / Task；记录时的应用摘要可以帮你回忆，内容由你自己填写。

免费开源 · 本地存储 · 无账号 · macOS 14+ · Apple Silicon 与 Intel

![JustNow 主界面](Resources/screenshots/overview.png)

<details>
<summary>查看提醒与编辑窗口、设置、深色外观与首次使用引导</summary>

![JustNow 提醒窗口](Resources/screenshots/reminder.png)

![JustNow 记录编辑窗口](Resources/screenshots/editor.png)

![JustNow 设置：外观和语言选项并排展示](Resources/screenshots/settings.png)

![JustNow 深色外观](Resources/screenshots/dark.png)

![JustNow 首次使用引导](Resources/screenshots/onboarding.png)

</details>

## 为什么做这个

我们想保留定时回顾的习惯，同时让记录足够轻：不用事先定义任务，不用反复惦记开始和停止，也不用把私人活动上传到服务端。长时间离开时，JustNow 会暂停并在你回来后确认这段时间如何处理。

## 核心体验

- **启动即记录，随时能停止。** 默认每次启动自动开始，首次使用完成引导后开始；可在设置中关闭。提醒默认 30 分钟一次，间隔可调。
- **离开时暂停，回来时确认。** 睡眠、屏幕睡眠、切换用户或连续 30 分钟无键鼠操作时暂停；回来后选择跳过或保留这段时间。
- **直接写刚才做了什么。** 每段记录包含起止时间与自由文字，长文本自动换行，支持多行。
- **时间线与回顾。** 今日最新片段在最上面，保存后立即显示，跨午夜自动更新日期；可以按日期查看、搜索、修改历史记录，也可以手动补记。
- **漏填也能补。** 点「稍后」保留待填写时间段；不需要记录的空白片段可以直接丢弃。
- **草稿自动保存。** 提醒文字保留在待补记里，新建和修改记录的编辑草稿会在重新打开应用时恢复。
- **应用回忆线索。** 记录时保存应用处于前台的停留时间，提醒和后续编辑都能查看这一段的应用摘要。
- **本地保存与导出。** JSON 日志自动保存，保留上一次成功保存的备份，支持 CSV / JSON 导出。
- **随时从菜单栏操作。** 查看状态、打开日志、开始或结束记录。
- **清楚的选择控件。** 日期与时间使用专用弹层，小时和分钟分开选择；外观和中英文语言选项在设置中并排展示。
- **记录中也能更新。** 配置更新源的版本可在应用内检查、下载并安装 GitHub 上的新版本，更新重启后接续当前记录和提醒节奏。

## 安装

正式版本发布后，可在 [Releases](https://github.com/AbyssSkb/justnow/releases) 选择通用版 DMG，打开后将 JustNow 拖入 Applications。ZIP 包也包含同一个应用。最低系统版本是 **macOS 14 Sonoma**。

**签名状态：** 本仓库默认构建和 CI 附件使用 ad-hoc 签名，尚未经过 Apple 公证。从网络下载后 Gatekeeper 可能阻止打开；这与本机编译运行不同。正常的公开分发需要发布者使用 Developer ID Application 证书签名并经过 Apple 公证，请以对应 Release 的签名说明为准。当前没有可承诺无警告安装的已公证版本。

你也可以直接从源码构建：

```sh
git clone https://github.com/AbyssSkb/justnow.git
cd justnow
swift test
python3 scripts/check-editor-wrapping.py
./scripts/build-app.sh
open dist/JustNow.app
```

需要 Xcode Command Line Tools（Swift 5.9+）；`xcode-select --install` 可安装。Swift Package Manager 会下载用于安全更新的 [Sparkle](https://sparkle-project.org/) 二进制框架。构建脚本会生成 `dist/JustNow.app`、通用 ZIP、DMG 与 SHA-256 校验文件。

## 应用内更新

从 0.1.8 起，发布者配置了更新源与签名公钥的版本可以在菜单或设置中「检查更新」。应用会定期检查 GitHub 更新源，发现新版后由你决定是否下载和安装。未配置更新源的本地构建会显示尚未配置；不会连接示例地址。

安装前，应用先保存当前会话和正在填写的提醒、编辑草稿。新版重启后恢复当前会话、草稿与原来的下一次提醒时间，更新用时仍归入正在记录的时间段，不会产生一段额外记录。已经暂停的会话保持暂停，等待你回来后确认。更新接续只允许在保存交接状态后的 5 分钟内生效，过期后按普通启动处理；普通启动是否开始新一轮由设置决定。

## 怎么记录

1. 打开 JustNow，完成首次引导后自动开始；关闭启动记录设置后可点击「开始记录」。
2. 到时间后，弹窗显示刚结束的时间段。输入文字，点击保存。
3. 忙的时候可以点「稍后」，之后从时间线补写。
4. 工作告一段落，点击「停止记录」；不足一个间隔的最后一段也可以填写。如果刚开始就停止、这段没有需要记的内容，可以在空白提醒里点击「不记录这段」。

计时从本轮开始的时刻计算，而不是对齐钟表刻度。例如 09:07 开始、间隔 30 分钟，第一段是 09:07–09:37，第二段是 09:37–10:07。**填写和保存不会推迟下一次提醒**。更改间隔对下一次开始记录生效。

应用退出后再次启动时，默认开始一轮新的记录，可以在设置中关闭；手动停止后只重新打开已有窗口，不会重新开始。普通退出会保存最后一段，异常退出则按最近保存的状态恢复，避免自动补计整个停机时段。

### 离开与回来

Mac 进入睡眠、屏幕睡眠或切换到其他用户会话时暂停。默认开启的「离开时自动暂停」还会在检测到连续 30 分钟没有键鼠操作时暂停，可在设置中关闭。这项规则从检测时刻暂停，不会回删此前已经记录的时间；它只读取系统汇总的空闲时长，不读取输入内容。

实际回来后，选择「刚才离开了，从现在继续」会从当前时刻开始新的记录；选择「仍在做事，保留这段时间」会把间隙恢复为可补写的时间段，应用线索无法观测的部分仍显示为未统计。暂停状态会跨退出、异常退出和更新保留；重开应用不会自动把整晚算入记录，也不会在你确认前接续这段间隙。

### 草稿与回忆线索

提醒中的文字会自动保存到对应的待补记记录，普通启动后可以从待补记继续填写。新建或修改记录时，文字、日期和时间会作为编辑草稿自动保存；重新打开应用会恢复编辑窗口。普通退出前会立即保存，异常退出后恢复最近一次成功保存的草稿。点击「保存记录」才提交对已完成记录的修改；「取消」会丢弃编辑草稿，待补记文字此前已自动保存的部分仍保留。

「应用使用线索」默认开启，可在设置中关闭。它只在正在记录的会话内采集前台应用的名称、应用标识与停留时间，暂停和停止时不采集。摘要按每段记录保存，提醒弹窗与之后的记录编辑都能查看。占比按整个采集时段计算，无法观测的部分单列为「未统计」，不会把已知应用凑成 100%，也不会自动替你写记录。

已有旧记录不会补造应用线索；关闭采集会影响之后的记录，已保存的摘要保留。编辑起止时间后，应用摘要仍保留原始采集范围。JSON 导出包含这些摘要，CSV 保持原有的文字、时间与状态字段。

## 你的数据

日志保存在：

```text
~/Library/Application Support/JustNow/
```

数据采用本地 JSON 文件，保留上一次成功保存的备份。可通过应用导出 CSV 或 JSON，方便迁移、长期备份和自己的分析。上一次保存备份不能替代跨设备备份；请按需要将导出文件保存在自己的备份位置。

JustNow **不采集截图、窗口标题、网页地址、浏览器历史、文件内容或按键内容，不包含遥测，不需要账号**。应用回忆线索只保存记录会话中的前台应用名称、标识和时间；无操作暂停只读取系统汇总的空闲时长。日志与摘要都留在本机。网络仅用于已配置的版本检查更新和下载安装包，不上传你的记录。应用不提供云同步；你拥有原始数据。

## 发布签名与公证

本地使用可以直接构建。准备公开发布时，需要提供 `notarytool` / `stapler` 的 Xcode 工具、Apple Developer Program 的 Developer ID Application 证书，以及保存在 macOS Keychain 中的 `notarytool` 凭据配置；**不要把证书、密码或私钥提交到 GitHub**。

```sh
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
VERSION=0.1.9 ./scripts/build-app.sh

SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='justnow-notary' ./scripts/notarize.sh
```

先按照 [Apple 的公证流程](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) 创建 Keychain profile。脚本会检查 Developer ID 签名、hardened runtime 与时间戳；提交 ZIP、等待通过后将票据附加到 app，再重新生成 ZIP / DMG，提交并附加 DMG 票据，最后验证与更新校验文件。ZIP 本身不能附加票据，分发的 ZIP 内包含已附加票据的 app。

GitHub Actions 在 push / PR 时测试与构建；推送 `v0.1.9` 这类标签会创建一个带安装包的**草稿 Release**。CI 未配置签名凭据，附件会明确标为 ad-hoc / 未公证。正式发布前，用公证后的安装包替换草稿附件。没有证书时，仍可分享源码和清楚标注签名状态的构建。

若要让 CI 构建包含更新配置，在 GitHub Actions 的仓库变量中同时设置 `UPDATE_FEED_URL` 和 `UPDATE_PUBLIC_ED_KEY`。签名私钥仍由发布者保管，当前工作流不会生成或发布更新源。

### 发布 GitHub 更新源

更新安装使用 Sparkle 的 Ed25519 签名验证下载包。发布者需先确定 GitHub 仓库，并用 Sparkle 自带的 `generate_keys` 生成一次签名密钥。私钥默认保存在登录 Keychain，只把输出的公钥用于构建；不要把私钥、Keychain 或导出的密钥文件提交到仓库。工具随 SwiftPM 二进制依赖下载，在构建后位于 `.build-release/arm64/artifacts/sparkle/Sparkle/bin/`。详见 [Sparkle 官方设置说明](https://sparkle-project.org/documentation/)。

```sh
.build-release/arm64/artifacts/sparkle/Sparkle/bin/generate_keys

UPDATE_FEED_URL='https://github.com/OWNER/justnow/releases/latest/download/appcast.xml' \
UPDATE_PUBLIC_ED_KEY='GENERATE_KEYS_PRINTED_PUBLIC_KEY' \
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
VERSION=0.1.9 ./scripts/build-app.sh

SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='justnow-notary' ./scripts/notarize.sh

DOWNLOAD_URL_PREFIX='https://github.com/OWNER/justnow/releases/download/v0.1.9/' \
./scripts/generate-update-feed.sh
```

将 `OWNER` 替换为实际发布账号；更新源和公钥必须同时提供。每次发布先构建、公证，最后运行生成更新源的脚本，由官方 `generate_appcast` 从 Keychain 读取私钥并签名。它会生成 `dist/update-feed/appcast.xml`，保留已有更新条目，并关闭差分包生成。若密钥保存在受保护的文件中，可用 `SPARKLE_ED_KEY_FILE` 指定文件路径；工具在其他位置时可用 `SPARKLE_BIN_DIR` 指定其 `bin` 目录。

把 `appcast.xml` 与 `JustNow-0.1.9-universal.zip` 上传到同一个 `v0.1.9` GitHub Release，再发布为最新正式版。下个版本改用新的版本号和对应的下载前缀，保持已发版本的附件地址与字节不变。可在生成前把与 ZIP 同名的 `.html` 或 `.md` 更新说明放入 `dist/update-feed/`。CI 草稿附件没有更新签名，不应直接当作应用内更新源；完成签名、公证后再上传更新源。脚本不创建或发布 GitHub Release。

## 参与开发

详见 [CONTRIBUTING.md](CONTRIBUTING.md)。macOS Dock 和 Finder 图标使用白色圆角底板上的紫色文档与时钟轮廓，源图是 `Resources/AppIcon-macOS-source.png`，编辑提示词是 `Resources/AppIcon-macOS-prompt.txt`。

应用内使用透明紫色轮廓标识，源图仍是 `Resources/AppIcon-source.png`，提示词是 `Resources/AppIcon-outline-prompt.txt`；`Resources/AppIcon-prompt.txt` 保留为设计历史。

`scripts/generate-icon.swift` 使用原生 AppKit 从这两张 PNG 缩放生成 macOS ICNS、预览图和透明品牌资源。运行以下命令可重现图标资源，无需下载素材或安装第三方包：

```sh
swift scripts/generate-icon.swift Resources
```

许可采用 [MIT](LICENSE)。

---

## English

**What did you do just now?**

JustNow is a native, local-first activity journal for macOS 14+. Recording starts on launch by default; receive a prompt every 30 minutes and describe the previous interval in your own words. No projects or tasks to set up. Apple Silicon and Intel are supported by the same universal build.

- Adjustable intervals; saving an entry does not reset the timer. Launch recording is enabled by default, begins after first-run onboarding, and can be disabled. Reopening an existing window after a manual stop does not restart recording.
- Custom date and time popovers with separate hour and minute selection; appearance and language options displayed directly in Settings.
- Free text wraps automatically. Today shows new entries immediately, newest first, and follows the current date across midnight. Browse daily history, search, edit, backfill, and return to pending entries when you choose Later.
- Reminder text is saved with pending entries. Editor drafts, including dates and times, recover on relaunch; an unexpected exit restores the last successful autosave. Cancelling discards the editor draft while previously saved pending text remains.
- Optional foreground-app clues are enabled by default and collected only during active recording sessions. App names, bundle identifiers and durations stay local with each interval and remain available when editing later. Unobserved time is shown separately; clues do not write your entry for you.
- Stop captures the final partial interval; blank pending moments can be discarded. Sleep, display sleep, user-session inactivity or 30 minutes without keyboard/mouse activity pause recording. On return, choose to skip the gap and start now, or retain it as intervals to fill in. Idle detection pauses at detection time rather than trimming earlier records; the setting can be disabled.
- Paused state survives quits, crashes and updates until you confirm how to handle the gap. An in-app update restores the session, draft and original reminder schedule within a five-minute handoff window, including any paused state.
- Local JSON journal with previous-save backup, plus CSV / JSON export.
- No account, telemetry, screenshots, window titles, URLs, browsing history, file contents or keystroke contents. Idle pause reads only the system's aggregate idle duration. Network access is limited to configured update checks and downloads; journal data and app summaries stay local. JSON export includes summaries; CSV retains its text/time/status fields.
- Built-in GitHub updates use Sparkle archive signatures, with installation confirmed by the user. Update checks remain unavailable in builds without a feed URL and public key.

Validate with `swift test` and `python3 scripts/check-editor-wrapping.py`, then build with `./scripts/build-app.sh` and open `dist/JustNow.app`. Requires Xcode Command Line Tools and Swift 5.9+. Data lives in `~/Library/Application Support/JustNow/`.

**Distribution:** Default builds are ad-hoc signed and **not notarized**; Gatekeeper may block downloaded copies. A verified public release requires a Developer ID Application certificate and Apple notarization. Set `SIGNING_IDENTITY` when building, then run `scripts/notarize.sh` with the same identity and a `NOTARY_PROFILE` stored in Keychain. Tag builds create draft releases, so maintainers can replace CI assets with notarized packages before publishing. For in-app updates, generate an Ed25519 key with Sparkle's `generate_keys`, build with both `UPDATE_FEED_URL` and `UPDATE_PUBLIC_ED_KEY`, then run `scripts/generate-update-feed.sh` after notarization with an HTTPS `DOWNLOAD_URL_PREFIX`. Publish its signed `appcast.xml` alongside the versioned ZIP on GitHub Releases. Keep private keys outside the repository.

Free and open source under the MIT license. Contributions welcome.
