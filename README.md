# LocalPaste

原生 macOS 本地剪贴板工具。独立实现底部横向卡片、历史搜索、预览、收藏分类和跨应用粘贴；不复制 Paste 的品牌或素材。

当前状态：个人自用开发基线。常用内容往返、暂停/排除及主要键盘路径已实机验证；上限与清空保留收藏已通过隔离存储及独立 App 的 GUI 验证。进入日用观察，不是正式发行版，也不代表全部边界测试通过。

## 已实现

- 文本、链接、PNG/TIFF、RTF/HTML 和 Finder 多文件引用采集。
- 底部卡片、搜索、键盘选择、预览、原格式与纯文本粘贴。
- 收藏、分类管理、本地 SwiftData 持久化、普通历史上限。
- 暂停采集、排除应用、跳过 concealed/transient 剪贴板类型。
- 菜单栏常驻；默认快捷键 `⌘⇧V`，设置中可调整。
- 登录时启动及 macOS 批准状态提示。
- 独立数据目录、保留旧库的迁移、离线 HTML 正文提取和缓存搜索。
- 通用、隐私、分类、关于四个设置页面；明确的记录状态、可点击修改的快捷键及按需展开的版本信息。

## 隐私与限制

- 不提供账号、云同步、遥测、AI 或联网功能。
- 本地数据库不是加密保险箱。macOS 无法可靠证明所有剪贴板写入来源，排除应用是尽力保护，不保证绝不记录敏感内容；复制敏感内容前请暂停采集。
- 文件只保存引用，不备份文件本体。原文件移动或删除后引用可能失效。
- 自动粘贴需要用户在系统设置中授予辅助功能权限；未授权时只能恢复到剪贴板并提示手动粘贴。
- 部分功能虽然已实现，尚未完成安装版 UI 验收；详见 [验证状态](docs/verification/STATUS.md)。

## 开发

依赖：macOS 14+、支持相应 SDK 的 Xcode、XcodeGen。当前基线使用 Xcode 26 构建。

```sh
scripts/build-release.sh
```

脚本在独立缓存目录产出 Release App、ZIP 和 `build-info.json`，记录版本、构建号、提交及源码摘要。构建号默认采用提交计数，可用 `LOCALPASTE_BUILD_NUMBER` 指定；未提交改动会在修订中标记 `dirty`。设置 `LOCALPASTE_BUILD_OUTPUT` 可选择新的输出目录。

默认产物未签名。日用安装可通过 `LOCALPASTE_SIGNING_IDENTITY` 指定本机稳定身份完成签名，脚本不会自行替换已安装的 App。详见 [首次运行](docs/runbooks/first-run.md)。

必要回归可执行 `scripts/run-regressions.sh`。它使用人工旧库、临时数据库和独立命名剪贴板，覆盖迁移、暂停、粘贴竞争、分类和搜索；不读取日用历史、不发送系统粘贴按键。说明见 [回归验证](Tests/README.md)。HTML 提取使用 macOS SDK 自带的 libxml2，无新增第三方包。

生成的 Xcode 工程、构建产物、证书、私人剪贴板数据、原始运行日志及截图均不进入仓库。`project.yml` 是工程配置来源。

PR 的 macOS 工作流运行同一套回归与构建脚本，保留未签名产物和构建摘要供检查。

## 下一阶段

先完成本地首版验收，再按日用反馈打磨；不同时扩展 OCR、AI 或跨设备同步。详见 [下一阶段](docs/plans/next-phase.md)。

## 文档

- [原始设计](docs/specs/2026-09-10-localpaste-design.md)
- [初版实现计划（历史记录）](docs/plans/2026-09-10-localpaste-implementation.md)
- [验证状态](docs/verification/STATUS.md)
- [首次运行与签名说明](docs/runbooks/first-run.md)
