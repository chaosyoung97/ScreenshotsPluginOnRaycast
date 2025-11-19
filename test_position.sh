#!/bin/bash
# 测试截图位置修复效果

echo "测试截图位置修复效果"
echo "显示图片: test.png"
echo "位置: x=100, y=100"
echo "尺寸: 800x600"

# 启动悬浮窗口
/Users/chaos/.config/raycast/extensions/screenshots-plugin/float-window /Users/chaos/Documents/WorkSpace/chaos/ScreenshotsPluginOnRaycast/test.png 100 100 800 600 &

echo "悬浮窗口已启动，按 Enter 键关闭..."
read
pkill float-window
echo "测试完成"