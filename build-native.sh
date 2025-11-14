#!/bin/bash
# 编译原生悬浮窗口应用

echo "正在编译 float-window..."

clang -framework Cocoa -framework Carbon -framework Vision -framework QuartzCore -framework ImageIO -o float-window FloatWindow.m

if [ $? -eq 0 ]; then
    echo "编译成功！"
    chmod +x float-window
else
    echo "编译失败！"
    exit 1
fi

