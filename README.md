# Tensei

使用 Godot 开发，支持在 macOS 和 Windows 上通过同一个 GitHub 仓库协作。

## 开始开发

1. 两端安装相同版本的 Godot。当前 `project.godot` 标记为 4.7；请保持具体补丁版本或开发构建一致。
2. 克隆仓库：`git clone https://github.com/NanoShiki/Tensei.git`。
3. 在 Godot 项目管理器中导入 `project.godot`，等待资源导入完成。

项目目前为初始骨架，尚未设置可运行的主场景。

## 协作约定

- 开始开发前执行 `git pull`，完成后提交并执行 `git push`。
- 多人开发时使用独立分支，尽量避免同时编辑同一个场景。
- 提交场景、脚本、资源及对应的 `.uid` 和 `.import` 文件。
- `.godot/` 是本机生成的缓存，不提交到仓库。
- 使用 `res://` 和 `user://` 路径，避免写死操作系统绝对路径。
- 文件名与引用的大小写保持一致；文本换行由 `.gitattributes` 统一为 LF。
- 平台相关功能及渲染效果需要分别在 macOS 和 Windows 上验证。
