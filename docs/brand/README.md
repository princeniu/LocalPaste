# 拾贴 · Clipmori

随手复制，随时找回。

「拾贴」呼应拾回复制过的片段；Clipmori 由 clip 与记忆的联想组成。日常界面使用「拾贴」，关于页展示中英双名，安装包使用 `Clipmori.app`。

图标延续暖橙色：两张叠放的纸片代表历史，回转箭头代表找回与再次使用。应用图标与界面品牌图使用同一原稿；菜单栏沿用单色剪贴板符号，保持小尺寸和深浅色菜单栏的辨识度。

- [图标原稿](clipmori-icon-source.png)
- [生成提示词](icon-prompt.md)
- `LocalPaste/Assets.xcassets/AppIcon.appiconset`：16–1024 像素的 macOS 图标。
- `LocalPaste/Assets.xcassets/BrandIcon.imageset`：面板与关于页使用的图标。

2026-09-11 对「拾贴」和「Clipmori」进行了公开网页及 App Store 定向检索，未发现明显同名剪贴板产品；此记录仅表示本次检索结果。

## 升级兼容

展示名称与发布包更名；Bundle ID `com.prince.LocalPaste`、可执行文件名、偏好键、数据目录与签名身份保持稳定。现有安装可在原 `LocalPaste.app` 路径就地升级，避免因移动路径干扰已配置的系统集成。开发工程和仓库继续使用 LocalPaste。
