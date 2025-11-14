#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

@interface FloatingWindow : NSWindow
@end

@implementation FloatingWindow
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }

// 按住 Cmd 键时可以拖动窗口
- (void)mouseDown:(NSEvent *)event {
    if ([event modifierFlags] & NSEventModifierFlagCommand) {
        [self performWindowDragWithEvent:event];
    }
}
@end

@interface ClickThroughImageView : NSImageView
@end

@implementation ClickThroughImageView
// 重写 hitTest 实现点击穿透
- (NSView *)hitTest:(NSPoint)point {
    return nil;  // 返回 nil 表示点击穿透
}
@end

int main(int argc, const char * argv[]) {
    if (argc < 2) {
        fprintf(stderr, "用法: FloatWindow <图片路径>\n");
        return 1;
    }
    
    @autoreleasepool {
        NSString *imagePath = [NSString stringWithUTF8String:argv[1]];
        NSImage *image = [[NSImage alloc] initWithContentsOfFile:imagePath];
        
        if (!image) {
            fprintf(stderr, "无法加载图片: %s\n", argv[1]);
            return 1;
        }
        
        NSSize imageSize = [image size];
        NSScreen *screen = [NSScreen mainScreen];
        NSRect screenFrame = screen ? [screen frame] : NSMakeRect(0, 0, 1920, 1080);
        
        // 计算窗口位置（居中）
        CGFloat windowX = (screenFrame.size.width - imageSize.width) / 2;
        CGFloat windowY = (screenFrame.size.height - imageSize.height) / 2;
        
        // 创建无边框窗口
        NSRect windowRect = NSMakeRect(windowX, windowY, imageSize.width, imageSize.height);
        FloatingWindow *window = [[FloatingWindow alloc] 
            initWithContentRect:windowRect
            styleMask:NSWindowStyleMaskBorderless
            backing:NSBackingStoreBuffered
            defer:NO];
        
        // 设置窗口属性
        [window setLevel:NSFloatingWindowLevel];
        [window setOpaque:NO];
        [window setBackgroundColor:[NSColor clearColor]];
        [window setHasShadow:YES];
        [window setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary];
        
        // 创建容器视图
        NSView *containerView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, imageSize.width, imageSize.height)];
        
        // 创建图片视图（点击穿透）
        ClickThroughImageView *imageView = [[ClickThroughImageView alloc] initWithFrame:NSMakeRect(0, 0, imageSize.width, imageSize.height)];
        [imageView setImage:image];
        [imageView setImageScaling:NSImageScaleNone];
        [imageView setEditable:NO];
        
        // 创建拖动区域（窗口边缘 10px，不点击穿透，用于拖动）
        CGFloat dragAreaSize = 10.0;
        NSView *dragArea = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, imageSize.width, imageSize.height)];
        [dragArea setWantsLayer:YES];
        dragArea.layer.backgroundColor = [[NSColor clearColor] CGColor];
        
        // 拖动区域可以拖动窗口
        [dragArea addTrackingArea:[[NSTrackingArea alloc] 
            initWithRect:NSMakeRect(0, 0, imageSize.width, dragAreaSize)
            options:NSTrackingActiveInKeyWindow | NSTrackingMouseEnteredAndExited | NSTrackingInVisibleRect
            owner:dragArea
            userInfo:nil]];
        
        // 实现拖动
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDragged handler:^NSEvent *(NSEvent *event) {
            NSPoint location = [event locationInWindow];
            // 如果鼠标在边缘区域，允许拖动
            if (location.y < dragAreaSize || location.y > imageSize.height - dragAreaSize ||
                location.x < dragAreaSize || location.x > imageSize.width - dragAreaSize) {
                [window performWindowDragWithEvent:event];
            }
            return event;
        }];
        
        [containerView addSubview:imageView];
        [containerView addSubview:dragArea positioned:NSWindowAbove relativeTo:imageView];
        [window setContentView:containerView];
        [window setIgnoresMouseEvents:NO];  // 允许边缘区域响应鼠标事件
        [window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:NO];
        
        // 创建应用
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        
        __block BOOL isDragging = NO;
        __block NSPoint dragOffset = NSZeroPoint;
        
        NSTimer *eventTimer = [NSTimer scheduledTimerWithTimeInterval:0.01 repeats:YES block:^(NSTimer * _Nonnull timer) {
            // ESC 键检测
            if (CGEventSourceKeyState(kCGEventSourceStateCombinedSessionState, kVK_Escape)) {
                [app terminate:nil];
                return;
            }
            
            // 拖动检测
            BOOL leftDown = CGEventSourceButtonState(kCGEventSourceStateCombinedSessionState, kCGMouseButtonLeft);
            NSPoint mouseLocation = [NSEvent mouseLocation];
            NSRect windowFrame = [window frame];
            
            if (!isDragging) {
                if (leftDown && NSPointInRect(mouseLocation, windowFrame)) {
                    isDragging = YES;
                    dragOffset = NSMakePoint(mouseLocation.x - windowFrame.origin.x, mouseLocation.y - windowFrame.origin.y);
                }
            }
            
            if (isDragging) {
                if (leftDown) {
                    NSPoint newOrigin = NSMakePoint(mouseLocation.x - dragOffset.x, mouseLocation.y - dragOffset.y);
                    [window setFrameOrigin:newOrigin];
                } else {
                    isDragging = NO;
                }
            }
        }];
        
        [[NSRunLoop mainRunLoop] addTimer:eventTimer forMode:NSRunLoopCommonModes];
        
        // 运行应用
        [app run];
    }
    
    return 0;
}

