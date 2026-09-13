# 制作安装包

安装包为包含 App 与 Applications 快捷入口的只读 DMG，适用于 macOS 14+，同时包含 arm64 与 x86_64。构建不替换日用安装、不读取剪贴板数据库。

## 构建与打包

使用自己的 Developer ID Application 签名身份。Release 构建开启 hardened runtime，并取得 Apple 安全时间戳，需要网络。

```sh
LOCALPASTE_SIGNING_IDENTITY="你的 Developer ID Application 身份" \
  LOCALPASTE_BUILD_OUTPUT="$HOME/Library/Caches/ClipmoriRelease/build" \
  scripts/build-release.sh

LOCALPASTE_SIGNING_IDENTITY="你的 Developer ID Application 身份" \
  scripts/package-dmg.sh "$HOME/Library/Caches/ClipmoriRelease/build/Clipmori.app" \
  "$HOME/Library/Caches/ClipmoriRelease/installer"
```

每次选择新的构建与安装包目录。打包脚本拒绝缺少 Developer ID、安全时间戳、hardened runtime 或双架构的 App。产出 `Clipmori-版本-构建号-universal.dmg` 与 `SHA256SUMS`。

## 公证

钥匙串配置名称不是密码。已有配置可直接使用；没有时在本机终端运行以下命令并按交互提示配置，勿将密码或 API 密钥写进仓库或聊天。

```sh
xcrun notarytool store-credentials Clipmori
```

将实际 DMG 路径与配置名称传入：

```sh
scripts/notarize-dmg.sh /path/to/Clipmori-version-build-universal.dmg Clipmori
```

脚本提交给 Apple，保存提交 ID，等待 Accepted，再把票据附加到 DMG、验证票据和 Gatekeeper，并重新生成 SHA-256。公证通过的是此 DMG 容器；不要把构建阶段未附加票据的 ZIP 当作等价发行包。

若超时或失败，保留输出文件。使用 `notarytool info` / `wait` 查询同一提交；使用 `notarytool log` 获取失败原因，不盲目重复提交。已 Accepted 但附加票据失败时，可手动运行 `stapler staple`、`stapler validate`、Gatekeeper 检查并重新生成 SHA-256。

## 发布前

挂载只读 DMG，确认 App、Applications 链接、说明和许可证完整；核对包内签名与双架构。全新机器上的首次安装、授权和启动仍需独立验收。签名、打包成功不等于公证成功，公证成功也不代表全部功能无缺陷。

发布只上传已公证 DMG、SHA256SUMS 和发布说明；不上传钥匙串、公证认证、私人构建日志或数据库。旧 LocalPaste 用户应先备份并退出旧版，保持原安装路径可减少系统集成变更。
