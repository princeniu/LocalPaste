# Clipmori 展示文案

以下为可编辑草稿，尚未发布。封面中的界面以当前中文版本为基础；英文介绍不代表应用已提供英文界面。

## 个人网站 · 中文项目卡片

**拾贴 · Clipmori**

随手复制，随时找回。

从个人日常需求出发制作的原生 macOS 剪贴板历史工具。通过横向卡片、搜索和预览找回复制过的内容，再以原格式或纯文本粘贴回应用。无需账号，历史保存在本机。

标签：macOS / 交互设计 / SwiftUI / AppKit / 开源

[查看源码](https://github.com/princeniu/LocalPaste) · [下载安装包](https://github.com/princeniu/LocalPaste/releases/latest)

## Personal website · English project card

**Clipmori**

Copy now. Find it later.

A native macOS clipboard history app built around a personal everyday need. Browse horizontal cards, search and preview earlier clips, then paste them back with their original formatting or as plain text. No account required; history stays on your Mac.

Tags: macOS / Interaction design / SwiftUI / AppKit / Open source

[View source](https://github.com/princeniu/LocalPaste) · [Download](https://github.com/princeniu/LocalPaste/releases/latest)

## 个人网站 · 中文短案例

### 从日常需求出发

拾贴起源于一个简单需求：找回之前复制过的内容。项目范围围绕“复制—找回—再次粘贴”展开，把这一日常操作做成可以实际使用的 macOS 工具。

### 三个设计取舍

- **快速浏览与精确查找并用。** 屏幕底部的横向卡片提供内容概览，搜索用于定位具体内容，空格预览用于确认完整内容。
- **保留内容，也保留选择。** 支持文字、图片、富文本和文件引用；再次使用时可以选择原格式或纯文本粘贴。文件记录保存引用，不复制原始文件。
- **让数据管理过程可见。** 历史保存在本机，可暂停记录或排除应用；备份恢复先展示导入预览，合并时保留本机已有记录。

### 实现与验证

使用 SwiftUI、AppKit 和 SwiftData 实现，配有隔离回归测试、实机验证记录和安装包构建流程。公开提供源码与签名、公证的 DMG。

目前是早期版本，界面以简体中文为主；尚未提供自动更新。历史和备份未加密。项目展示的是实际产品实现与交互取舍，尚无可引用的用户研究或量化效率提升结论。

## Personal website · English short case study

### An everyday starting point

Clipmori began with a simple personal need: finding something copied earlier. Its scope centers on a familiar sequence—copy, find, and paste again—and brings that sequence into a working native macOS tool.

### Three design decisions

- **Support both browsing and targeted search.** Horizontal cards at the bottom of the screen provide an overview. Search locates specific clips, and a Space-key preview reveals the full content.
- **Preserve content and offer a formatting choice.** The app supports text, images, rich text, and file references, with original-format and plain-text paste options. File entries retain references rather than copying the files themselves.
- **Make data management visible.** History stays on the Mac, with controls to pause collection or exclude apps. Backup imports show a preview before merging and preserve existing local records.

### Implementation and validation

Built with SwiftUI, AppKit, and SwiftData, with isolated regression tests, documented on-device checks, and an installer build workflow. Source code and a signed, notarized DMG are available publicly.

This is an early release with a primarily Simplified Chinese interface and no automatic updates yet. History and backup files are not encrypted. The project demonstrates implementation and interaction decisions; it does not yet have user-research findings or measured productivity gains to report.

## LinkedIn · 英文配文

I built Clipmori, a small native macOS clipboard history app, to make it easier to find something I copied earlier.

It keeps earlier clips in horizontal cards, with search, previews, and a choice between original-format and plain-text paste. History stays on the Mac, and backups can be previewed before importing.

Working on it meant thinking through details beyond the main screen: keyboard focus, switching back to the target app, and what should happen if new content is copied before a paste completes.

The early release is open source, with a signed and notarized installer. The current interface is primarily in Simplified Chinese.

Source and download: https://github.com/princeniu/LocalPaste

## LinkedIn / 中文分享配文

最近做了一个小工具：拾贴 · Clipmori，一款原生 macOS 剪贴板历史应用。

它起源于自己的日常需求：找回之前复制过的内容。打开底部的横向卡片，可以搜索、预览，再选择原格式或纯文本粘贴。历史保存在本机，也支持备份与导入预览。

做这个项目时，我也逐步处理了主界面以外的细节：键盘焦点、粘贴时切回目标应用，以及用户中途复制了新内容时该如何处理。

目前是早期版本，源码已经开放，也提供了签名、公证的安装包。

源码与下载：https://github.com/princeniu/LocalPaste

## 使用说明（不必随文发布）

- 网站列表使用项目卡片文案；详情页可使用短案例，按版面压缩。
- 英文内容配 `clipmori-cover.png`，中文内容配 `clipmori-cover-zh.png`。
- 封面是 AI 合成展示图；需要精确呈现界面细节时使用 `clipmori-real-ui.png`。
- 发布前按实际分工调整第一人称表述；如介绍开发过程，可如实补充 AI 辅助的范围。
- 已补充中英文各 20 秒的无声功能导览（`clipmori-demo-zh.mp4` / `clipmori-demo-en.mp4`）。使用当前产品视图和内存示例数据生成场景，依次展示浏览、搜索、预览与收藏；属于界面场景剪辑，不是鼠标键盘操作录屏，不展示或证明跨应用粘贴。没有代为发布网站或 LinkedIn 内容。
