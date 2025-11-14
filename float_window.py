#!/usr/bin/env python3
"""
悬浮窗口显示图片，支持点击穿透
"""
import sys
import os
from AppKit import (
    NSApplication, NSWindow, NSImageView, NSImage, 
    NSRect, NSScreen, NSWindowStyleMaskBorderless,
    NSBackingStoreBuffered, NSWindowLevelFloating,
    NSEvent, NSKeyDownMask, NSApplicationActivationPolicyAccessory
)

class FloatingWindow(NSWindow):
    def canBecomeKey(self):
        return False
    
    def canBecomeMain(self):
        return False

def create_floating_window(image_path):
    """创建悬浮窗口"""
    # 读取图片
    image = NSImage.alloc().initWithContentsOfFile_(image_path)
    if not image:
        print(f"无法加载图片: {image_path}", file=sys.stderr)
        sys.exit(1)
    
    image_size = image.size()
    screen = NSScreen.mainScreen()
    screen_frame = screen.frame() if screen else NSRect(0, 0, 1920, 1080)
    
    # 计算窗口位置（居中）
    window_x = (screen_frame.size.width - image_size.width) / 2
    window_y = (screen_frame.size.height - image_size.height) / 2
    
    # 创建无边框窗口
    window_rect = NSRect(window_x, window_y, image_size.width, image_size.height)
    window = FloatingWindow.alloc().initWithContentRect_styleMask_backing_defer_(
        window_rect,
        NSWindowStyleMaskBorderless,
        NSBackingStoreBuffered,
        False
    )
    
    # 设置窗口属性
    window.setLevel_(NSWindowLevelFloating)
    window.setOpaque_(False)
    window.setBackgroundColor_(NSApplication.sharedApplication().keyWindow().backgroundColor().colorWithAlphaComponent_(0.0))
    window.setHasShadow_(True)
    window.setIgnoresMouseEvents_(True)  # 点击穿透
    window.setCollectionBehavior_(0x80)  # NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary
    
    # 创建图片视图
    image_view = NSImageView.alloc().initWithFrame_(NSRect(0, 0, image_size.width, image_size.height))
    image_view.setImage_(image)
    image_view.setImageScaling_(0)  # NSImageScaleNone
    
    window.setContentView_(image_view)
    window.makeKeyAndOrderFront_(None)
    
    return window

def main():
    if len(sys.argv) < 2:
        print("用法: float_window.py <图片路径>", file=sys.stderr)
        sys.exit(1)
    
    image_path = sys.argv[1]
    
    if not os.path.exists(image_path):
        print(f"图片文件不存在: {image_path}", file=sys.stderr)
        sys.exit(1)
    
    # 创建应用
    app = NSApplication.sharedApplication()
    app.setActivationPolicy_(NSApplicationActivationPolicyAccessory)
    
    # 创建窗口
    window = create_floating_window(image_path)
    
    # 监听 ESC 键
    def handle_key_event(event):
        if event.keyCode() == 53:  # ESC 键
            app.terminate_(None)
        return None
    
    # 设置全局事件监听
    NSEvent.addGlobalMonitorForEventsMatchingMask_handler_(
        NSKeyDownMask,
        handle_key_event
    )
    
    # 运行应用
    app.run()

if __name__ == "__main__":
    main()

