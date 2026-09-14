# 首次运行

## 当前本机安装

日用候选位置：`~/Applications/LocalPaste.app`。它是菜单栏应用，不显示 Dock 图标。不要运行旧 Debug 构建或从构建目录反复覆盖已确认安装版。

产品现名「拾贴 · Clipmori」，新构建包为 `Clipmori.app`。本机沿用原安装路径就地升级，应用内显示新品牌；Bundle ID 与数据目录保持不变。

[GitHub Releases](https://github.com/princeniu/LocalPaste/releases/latest) 提供 Developer ID 签名并通过 Apple 公证的 Universal DMG。新用户可下载后拖入 Applications；已有用户先备份并退出旧版，避免同时运行两个版本。自行构建的产物不自动继承发行包的公证状态。

## 构建与签名

先按根目录 README 构建 Release。构建到 `~/Library/Caches/` 可避免部分 Desktop 文件元数据引起的签名错误。

查看本机可用身份：

```sh
security find-identity -v -p codesigning
```

选择本机稳定的签名身份，然后构建新的候选产物：

```sh
LOCALPASTE_SIGNING_IDENTITY="你的有效签名身份" scripts/build-release.sh
```

脚本打印 App 路径；同目录包含 ZIP、构建日志和 `build-info.json`。可用 `LOCALPASTE_BUILD_OUTPUT` 指定新的输出目录；已含 App 的目录不会被覆盖。`project.yml` 管理产品版本，构建号默认来自提交计数，也可通过 `LOCALPASTE_BUILD_NUMBER` 显式指定。设置中的“关于 → 版本详情”可查看构建与修订；`dirty` 表示构建时含未提交修改。

仓库的 macOS CI 仅生成未签名检查产物。本机签名仍由本机密钥链完成，不上传证书或日用数据库。

不要同时运行同 bundle ID 的多个构建。候选验收通过后再安排替换，替换前保留原安装版，不在该说明中自动覆盖。

## 使用

1. 从未排除应用复制人工文字、图片或 Finder 文件。
2. `⌘⇧V` 呼出底部面板；搜索、点击卡片可恢复历史并尝试自动粘贴。
3. 非文本编辑焦点下，方向键选择、Enter 粘贴、Space 预览、Esc 关闭。
4. 设置可暂停采集、修改上限和快捷键、添加排除应用、管理分类。

## 辅助功能授权

自动粘贴需要用户在“系统设置 → 隐私与安全性 → 辅助功能”中授权当前安装版。未授权时内容仍可恢复到剪贴板，界面提示手动 Command-V。

ad-hoc 构建的授权可能绑定旧二进制哈希：开关显示开启不代表当前构建已获授权。先检查运行路径、签名要求与重复构建；不要反复重编译或要求用户反复开关。

仅当用户明确同意定向清除旧授权时，才执行 `tccutil reset Accessibility com.prince.LocalPaste`，然后由用户重新添加正确路径。不要重置其他 App 的权限或编辑 TCC 数据库。授权是否生效必须通过目标应用实际粘贴回读确认。

## 数据与安全

历史存于本地 SwiftData：当前正式 Bundle ID 的路径为 `~/Library/Application Support/com.prince.LocalPaste/default.store`，其他 Bundle ID 使用各自目录。文件只存引用。来源识别存在系统限制，排除应用是尽力保护。处理敏感信息前请暂停采集。本机历史、证书、原始测试截图和日志不上传 GitHub。

首次升级时，如果新目录不存在且旧的 `~/Library/Application Support/default.store` 存在，App 会检查旧库模型是否精确匹配 LocalPaste，再用 Core Data 的存储复制 API 复制数据库、日志及外部附件到暂存目录。所有历史内容可读取后才发布新目录；旧库保留，不自动删除。其他 Bundle ID 的验证副本不会默认访问旧共享路径。

升级前正常退出旧 LocalPaste；新版本检测到同 Bundle ID 的其他进程时会停止启动，避免迁移后旧进程继续写旧库。模型不匹配、迁移失败或数据目录不完整时，会显示错误并停止，不会静默创建空历史。不要手工删除旧库来绕过该提示，也不要只复制 SQLite 主文件而遗漏日志与外部资源。

迁移完成后旧库作为保留副本不再更新；回退旧版本只能看到迁移前的历史。数据库迁移代码和人工样例验证通过不代表当前机器已经执行了安装版迁移。
