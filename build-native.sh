#!/bin/bash
# 编译原生悬浮窗口应用

echo "正在编译 float-window..."

clang -framework Cocoa -framework Carbon -framework Vision -framework QuartzCore -framework ImageIO -o float-window FloatWindow.m

if [ $? -eq 0 ]; then
    echo "float-window 编译成功！"
    chmod +x float-window
else
    echo "float-window 编译失败！"
    exit 1
fi

echo "正在编译 get_mouse_position..."

clang -framework Cocoa -o get_mouse_position get_mouse_position.m

if [ $? -eq 0 ]; then
    echo "get_mouse_position 编译成功！"
    chmod +x get_mouse_position
else
    echo "get_mouse_position 编译失败！"
    exit 1
fi