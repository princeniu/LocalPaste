# LocalPaste

原生 macOS 本地剪贴板工具。独立实现底部横向卡片、历史搜索、预览、收藏分类和跨应用粘贴；不复制 Paste 的品牌或素材。

当前状态：个人自用开发基线。常用内容往返已实机验证，隐私控制和部分界面验收尚未完成；不是正式发行版。

## 已实现

- 文本、链接、PNG/TIFF、RTF/HTML 和 Finder 多文件引用采集。
- 底部卡片、搜索、键盘选择、预览、原格式与纯文本粘贴。
- 收藏、分类管理、本地 SwiftData 持久化、普通历史上限。
- 暂停采集、排除应用、跳过 concealed/transient 剪贴板类型。
- 菜单栏常驻；默认快捷键 `⌘⇧V`，设置中可调整。

## 隐私与限制

- 不提供账号、云同步、遥测、AI 或联网功能。
- 本地数据库不是加密保险箱。macOS 无法可靠证明所有剪贴板写入来源，排除应用是尽力保护，不保证绝不记录敏感内容；复制敏感内容前请暂停采集。
- 文件只保存引用，不备份文件本体。原文件移动或删除后引用可能失效。
- 自动粘贴需要用户在系统设置中授予辅助功能权限；未授权时只能恢复到剪贴板并提示手动粘贴。
- 部分功能虽然已实现，尚未完成安装版 UI 验收；详见 [验证状态](docs/verification/STATUS.md)。

## 开发

依赖：macOS 14+、支持相应 SDK 的 Xcode、XcodeGen。当前基线使用 Xcode 26 构建。

```sh
xcodegen generate
xcodebuild -project LocalPaste.xcodeproj -scheme LocalPaste \
  -configuration Release \
  -derivedDataPath "$HOME/Library/Caches/LocalPasteBuildRelease" \
  CODE_SIGNING_ALLOWED=NO build
```

上述命令产出未签名的 Release `.app`，不代表已完成安装与授权。需要日用安装时，应使用本机有效且稳定的代码签名身份；不要给频繁变化的 ad-hoc 调试构建反复授权。详见 [首次运行](docs/runbooks/first-run.md)。

生成的 Xcode 工程、构建产物、证书、私人剪贴板数据、原始运行日志及截图均不进入仓库。`project.yml` 是工程配置来源。

## 下一阶段

先完成本地首版验收，再按日用反馈打磨；不同时扩展 OCR、AI 或跨设备同步。详见 [下一阶段](docs/plans/next-phase.md)。

## 文档

- [原始设计](docs/specs/2026-09-10-localpaste-design.md)
- [初版实现计划（历史记录）](docs/plans/2026-09-10-localpaste-implementation.md)
- [验证状态](docs/verification/STATUS.md)
- [首次运行与签名说明](docs/runbooks/first-run.md)
