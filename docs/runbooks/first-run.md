# 首次运行

## 当前本机安装

日用候选位置：`~/Applications/LocalPaste.app`。它是菜单栏应用，不显示 Dock 图标。不要运行旧 Debug 构建或从构建目录反复覆盖已确认安装版。

仓库不附带签名 App。新机器需要自行编译并完成签名授权，不代表已公证或可公开分发。

## 构建与签名

先按根目录 README 构建 Release。构建到 `~/Library/Caches/` 可避免部分 Desktop 文件元数据引起的签名错误。

查看本机可用身份：

```sh
security find-identity -v -p codesigning
```

在单独候选路径安装产物后，使用自己的有效身份签名；环境变量 `SIGNING_IDENTITY` 必须由开发者明确指定：

```sh
CANDIDATE="$HOME/Applications/LocalPaste-Candidate.app"
# 仅当候选路径不存在时复制，避免覆盖已确认版本。
test ! -e "$CANDIDATE" || exit 1
ditto --norsrc \
  "$HOME/Library/Caches/LocalPasteBuildRelease/Build/Products/Release/LocalPaste.app" \
  "$CANDIDATE"
# 确認这是自己的新候选文件后再签名。
codesign --force --options runtime --timestamp=none \
  --identifier com.prince.LocalPaste --sign "${SIGNING_IDENTITY:?Specify a valid local signing identity}" \
  "$CANDIDATE"
codesign --verify --deep --strict "$CANDIDATE"
codesign -d -r- "$CANDIDATE"
```

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

历史存于本地 SwiftData；文件只存引用。来源识别存在系统限制，排除应用是尽力保护。处理敏感信息前请暂停采集。本机历史、证书、原始测试截图和日志不上传 GitHub。
