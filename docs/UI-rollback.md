# UI 优化前的恢复点

保存日期：2026-10-22。

- 已认可版本：`504fbf6c95758dbbe4f04ce39919b63cad4a4042`。
- Git 标签：`before-ui-refinement-2026-10-22`，已保存到 origin。
- 本轮分支：`codex/refine-reading-collection-ui`，与 main 分开。
- 旧版应用：`/Users/alex.jiang/.codex/backups/birdy/Birdy-before-ui-refinement-2026-10-22.zip`。
- 改版前截图：本机 `artifacts/ui-refinement-before/`（不上传）。

## 直接使用旧应用

退出 Birdy，将 ZIP 解压到独立文件夹，打开其中的 Birdy.app。先退出新应用，避免同一应用标识的两个进程同时写本机数据。

## 从源代码恢复

先提交或妥善保存当前未提交改动，再切换到保留的版本并构建：

```sh
git switch --detach before-ui-refinement-2026-10-22
make app
open dist/Birdy.app
```

返回本轮新版：

```sh
git switch codex/refine-reading-collection-ui
make app
open dist/Birdy.app
```

回退仅替换应用代码与布局。不删除、重置或覆盖 Application Support 中的记录、词条、句式、文章与截图。本轮没有数据格式迁移。
