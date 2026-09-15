# Clipmori portfolio cover

- `clipmori-demo-zh.mp4` / `clipmori-demo-en.mp4`: 20-second silent, 1080p H.264 feature walkthroughs, assembled from native view renders. Covers browsing, search, preview, and favorites. These are staged view-state sequences, not screen recordings or cross-app paste verification.
- `RenderDemo.swift`: reproducible native scene renderer using current product views and an in-memory sample store; system clipboard, global hotkeys, and paste delivery are not used.
- `demo-frames/`: rendered scenes and FFmpeg concat manifests (local intermediates, not versioned).

- `project-copy.md`: bilingual website cards, short case studies, and LinkedIn draft posts. Website copy is live at https://princeniu.com/projects/clipmori and https://princeniu.com/zh/projects/clipmori. LinkedIn Projects includes an English description and cover; no feed post was published.
- `clipmori-cover-zh.png`: Chinese companion cover.
- `prompt-zh.txt`: exact Chinese localization prompt.

- `clipmori-cover.png`: portfolio cover created using the built-in image_gen tool.
- `clipmori-real-ui.png`: current production HistoryView rendered with synthetic data and an in-memory SwiftData store. No personal clipboard was read. Actions are inactive in the rendering harness.
- `RenderCover.swift`: isolated source for reproducing the UI render, compiled alongside product sources without LocalPasteApp.swift.
- `prompt.txt`: exact image generation prompt.

The cover is an AI-composited presentation image. The standalone UI render is the source of truth for pixel-accurate interface details.
