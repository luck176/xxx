# 小红书私信通 · 私信提醒插件（XHSNotifyTweak）

收到新私信时 **播放提示音 + 弹出顶部横幅（或系统弹窗）**，音效、文案、震动、语音播报都能自己换。

- 目标 App：**小红书私信通 1.29**（Bundle ID `com.xingin.messagepro`，可执行文件 `MessagePro`，arm64）
- 产物：**一个纯 dylib**，不依赖 mobilesubstrate / libhooker，因此**越狱机和非越狱（TrollStore / 自签）都能用**，用 TrollFools、轻松签、Sideloadly 之类注入即可。
- 挂载点是按这份 IPA 的二进制逆向出来的（见下文「技术说明」），不是靠猜的类名。

---

## 一、功能清单

| 功能 | 说明 |
|---|---|
| 提示音 | 系统提示音（可改 ID）或 **你自己的音频文件**（`.caf / .wav / .mp3 / .m4a`） |
| 弹窗 | 顶部横幅（仿系统通知条，可点击关闭）或系统弹窗，或只发本地通知 |
| 文案自定义 | `{name}` 发送人、`{content}` 内容、`{time}` 时间，模板随便改 |
| 震动 | 可开关 |
| 语音播报 | 可选，把「谁 + 内容」读出来（做客服时很实用） |
| 过滤 | 最小间隔限流、去重、忽略自己发的、关键词白/黑名单、按会话类型跳过 |
| 设置面板 | 应用内三指双击，或点横幅右上角「设置」，可视化改完即时生效 |

---

## 二、目录结构

```
xhs-notify-tweak/
├── Makefile                 # Theos 工程（LIBRARY，产出 dylib）
├── control                  # 可选打 deb 时用
├── Hooks.m                  # 挂载点：收到私信 → 触发提醒
├── NYConfig.h/.m            # 配置读写（JSON）
├── NYNotifier.h/.m          # 横幅 / 弹窗 / 音效 / 震动 / 播报 / 本地通知
├── NYSettings.h/.m          # 应用内设置面板
├── config.example.json      # 配置示例
├── .github/workflows/build.yml   # 云端编译（不需要 Mac）
└── README.md
```

---

## 三、编译（二选一）

### 方案 A：GitHub Actions（推荐，不需要 Mac）

1. 新建一个 GitHub 仓库，把本目录全部文件推上去（注意保留 `.github/workflows/build.yml`）。
2. 推上去后自动开始编译；也可以在 Actions 页面点 **Run workflow**。
3. 编译完成后在该次运行的 **Artifacts** 里下载 `XHSNotifyTweak-dylib`，解压得到 `XHSNotifyTweak.dylib`。

### 方案 B：本机 macOS + Theos

```bash
export THEOS=~/theos
git clone --recursive https://github.com/theos/theos.git "$THEOS"
cd xhs-notify-tweak
make FINALPACKAGE=1
# 产物：.theos/obj/XHSNotifyTweak.dylib
```

> 编译机需要 Xcode（提供 iPhoneOS SDK）。`make package` 可以额外打出 deb 包（`control` 已备好）。

---

## 四、注入 / 安装

### 方式 1：TrollFools（无越狱，最省事）

1. 手机上用 **TrollFools**（TrollStore 生态）选择已安装的「小红书私信通」。
2. 点「注入」，选择编译出来的 `XHSNotifyTweak.dylib`。
3. 重新打开 App 即生效（TrollFools 会自动签名）。

### 方式 2：重打包 IPA（轻松签 / eSign / Sideloadly）

1. 把 `XHSNotifyTweak.dylib` 放进 `Payload/MessagePro.app/` 目录。
2. 用注入工具（轻松签「注入 dylib」、Sideloadly 的 dylib 选项、或 `optool` / `insert_dylib`）往
   `Payload/MessagePro.app/MessagePro` 写入 `LC_LOAD_DYLIB`，路径填 `@executable_path/XHSNotifyTweak.dylib`。
3. 重新签名安装。

### 方式 3：越狱机

把 dylib 放进 `/usr/lib/`，再用任意注入器（TrollFools 也支持越狱机）注入到 `MessagePro` 进程即可。
（本插件没有用 Logos，因此不需要 substrate；如果你更喜欢 substrate 过滤方式，把 `Makefile` 的
`library.mk` 换成 `tweak.mk` 并加一个 Filter plist 也可以，但没必要。）

---

## 五、使用

### 5.1 配置文件位置（按优先级自动寻找，找到即用）

1. `/var/mobile/Library/XHSNotifyTweak/config.json`
2. `/var/mobile/Documents/XHSNotifyTweak/config.json`
3. `<App沙盒>/Documents/XHSNotifyTweak/config.json`
4. `<App沙盒>/Library/XHSNotifyTweak/config.json`

**第一次启动会自动生成一份默认配置**（放在第一个可写目录）。设置面板底部会显示当前实际使用的路径。

> 不想手改 JSON 就用设置面板：**三指双击屏幕**（或点横幅右上角「设置」）。

### 5.2 换提示音

把音频文件放进**配置文件所在目录**（或该目录下的 `sounds/` 子目录），然后在设置面板 →「音效来源」选「自定义音频文件」→「音效文件」里选中它。
格式支持 `caf / wav / mp3 / m4a / aiff`，直接把你喜欢的铃声重命名丢进去就行。

也可以直接把路径写进配置：

```json
"sound": { "mode": "file", "file": "ding.caf", "volume": 1.0 }
```

系统音则用 `"mode": "system"` 加 `"systemSoundID"`，常见值：

| ID | 场景 |
|---|---|
| 1007 | 短信息提示音（三全音，最像「来了条消息」） |
| 1012 / 1013 | 通用提醒 |
| 1015 / 1016 | 邮件类提醒 |
| 1020–1023 | 各种短促提醒 |
| 1050 / 1057 / 1104 | 偏「叮」的提醒音 |
| 1300–1352 | 较长/较花哨的提示音 |

ID 不好挑就直接在设置面板里改数字 + 点「试听当前音效」。

### 5.3 配置项速查（`config.json`）

| 字段 | 说明 |
|---|---|
| `enabled` | 总开关 |
| `style` | `banner` 顶部横幅 / `alert` 系统弹窗 / `notify` 仅本地通知 / `none` 只响铃不弹 |
| `sound.enabled` | 是否播放音效 |
| `sound.mode` | `system` / `file` / `none` |
| `sound.file` | 自定义音频文件名（相对配置目录）或绝对路径 |
| `sound.systemSoundID` | 系统音 ID |
| `sound.volume` | 0 ~ 1 |
| `sound.vibrate` | 是否震动 |
| `sound.ignoreMute` | `true` = 手机静音键也不影响（用 Playback 音频会话） |
| `sound.speak` | `true` = 语音播报 |
| `banner.duration` | 横幅停留秒数 |
| `banner.titleTemplate` / `bodyTemplate` / `subtitleTemplate` | 文案模板，支持 `{name}` `{content}` `{time}` |
| `banner.maxBodyLength` | 正文最长字符数 |
| `banner.showSettingsButton` | 横幅右上角是否显示「设置」 |
| `alert.*` / `notify.*` | 弹窗、本地通知的文案模板 |
| `filter.minInterval` | 两条提醒最小间隔（秒），防轰炸 |
| `filter.ignoreSelf` | 忽略自己发出的消息 |
| `filter.selfUserID` | 手动指定自己的 UID（留空自动读登录态） |
| `filter.blacklist` / `whitelist` | 关键词数组（对「发送人 + 内容」匹配） |
| `filter.skipConvTypes` | 按会话类型跳过，例如 `[2]` 跳过群聊 |
| `filter.ignoreEmptyContent` | 空内容不提醒 |
| `filter.maxAgeSeconds` | 超过这个秒数的历史消息不提醒（防止拉取聊天记录时炸屏） |
| `debug.enabled` | 打开调试日志（排查用） |
| `debug.logPath` | 日志路径，默认配置目录下 `debug.log` |

---

## 六、技术说明（这份 IPA 逆向得出的结论）

分析对象：`小红书私信通_1.29.ipa` → `Payload/MessagePro.app/MessagePro`

- Mach-O：thin **arm64**，`LC_ENCRYPTION_INFO cryptid = 0`（**未加密**，可直接静态分析），最低 iOS 12.0，SDK 18.2
- ObjC 元数据：6176 个类，方言为 ObjC + Swift + React Native 混合
- 私信走 App 内置的长连接（`XYSocketManager` / `XYNCSocket` / `XYSK*` socket kit）

实际挂载的三个方法（签名都用 `__objc_methtype` 校验过）：

| 类 | 方法 | 类型编码 | 用途 |
|---|---|---|---|
| `XYSocketManager` | `messageFormIm:` | `@24@0:8@16` | 主挂载点：长连接读完 IM 数据后生成 `XYSKResponseModel` |
| `XYSKResponseModel` | `setGenericEvent:` | `v24@0:8@16` | 事件赋值时取 `XYSKGenericEvent` |
| `XYSKGenericEvent` | `setMessages:` | `v24@0:8@16` | 消息数组赋值（兜底） |
| `XYSocketManager` | `didReadIMData:` | `v24@0:8@16` | 仅在 `debug.enabled` 时打日志 |

消息对象 `XYSKGenericMessage` 的字段：`uuid` / `cid`(会话ID) / `content` / `contentType`(int) / `convType`(int) / `extension`(NSDictionary，发送人信息一般在这里) / `createAt`。
发送人昵称与 UID 从 `extension` 里按常见 key（`sender_name` / `nickname` / `sender_id` / `from_uid` …）做兼容读取；读不到时用会话 ID 兜底。
去重键用 `uuid`，没有就用「会话 + 发送人 + 内容」的哈希。

因为不依赖 Logos，所有 hook 都是 `method_setImplementation` 运行时替换，**装不上就是静默跳过、不会崩**。

### 换了新版本 App 怎么办

类名/方法名理论上不会变（这是 App 自研 IM 层，跨版本一直沿用 `XYSK*`）。万一失效：

1. 打开 `debug.enabled: true`，复现一次，把 `<配置目录>/debug.log` 发出来——日志会记录 hook 是否装上、`didReadIMData` 有没有收到数据。
2. 需要重新定位时，用 `class-dump`/`nm` 搜 `XYSocketManager`、`XYSKGenericMessage` 即可，思路和上面表格一致。

---

## 七、常见问题

- **完全没反应**：先确认 dylib 真的被注入了（TrollFools 里能看到注入记录）；再开 `debug.enabled` 看 `debug.log` 里 `hook 安装 ...` 那行是否全为 1。
- **有横幅没声音**：`sound.mode` 是 `none`？手机静音键按着？把 `sound.ignoreMute` 改 `true`。
- **自定义音频不出声**：路径/文件名不对（日志里会打印「找不到音效文件」）；或音频本身不是 iOS 能解码的格式，换 `.caf`/`.wav`。
- **提醒太频繁**：调大 `filter.minInterval`，或用 `blacklist` / `skipConvTypes`。
- **不想看横幅只想听声**：`style` 设 `none`。

---

## 八、说明与边界

- 本插件只监听「本机 App 收到消息」这一事件并做本地提醒，**不联网、不上传任何内容**，也不修改 App 的业务逻辑。
- 仅用于你自己账号的消息提醒；请遵守小红书平台规则与当地法律，不要用于批量骚扰、营销轰炸等用途。
- 若 App 后续版本改动内部实现导致失效，按「六、技术说明」的方法重新定位即可。
