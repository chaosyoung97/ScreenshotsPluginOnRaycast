# Screenshots Plugin for Raycast

一个 Raycast 插件，可以快速截取屏幕并将图片悬浮显示在整个屏幕上。

## 功能特性

- 🖼️ 快速唤起 macOS 截图工具
- 📺 将截图以悬浮窗口形式显示在屏幕上（1:1 显示）
- 🖱️ 支持点击穿透，不影响底层应用操作（图片区域完全穿透）
- 🔝 窗口始终悬浮在最上层
- 🖱️ 窗口边缘 10px 区域可拖动窗口
- ⌨️ 按 ESC 键关闭悬浮窗口
- 🧹 自动清理临时文件

## 安装

1. 克隆或下载此仓库
2. 在 Raycast 中打开扩展设置
3. 选择"导入扩展"
4. 选择此项目目录

## 使用方法

1. 在 Raycast 中搜索 "Take Screenshot" 命令
2. 执行命令后，会唤起 macOS 的截图工具
3. 选择要截图的区域
4. 截图完成后，图片会以悬浮窗口形式显示在屏幕上
5. 按 ESC 键关闭悬浮窗口

## 开发

```bash
# 安装依赖
npm install

# 编译原生悬浮窗口应用（必需）
./build-native.sh

# 开发模式
npm run dev

# 构建
npm run build
```

## 技术实现

- 使用 macOS 的 `screencapture` 命令进行截图
- 使用原生 Objective-C 应用创建悬浮窗口（`float-window`）
- 支持点击穿透（`ignoresMouseEvents = YES`）
- 窗口始终在最上层（`NSFloatingWindowLevel`）
- 图片 1:1 显示，不缩放
- 图片区域完全点击穿透（不影响底层应用操作）
- 窗口边缘 10px 区域可拖动窗口
- 按 ESC 键关闭窗口

## 许可证

MIT

