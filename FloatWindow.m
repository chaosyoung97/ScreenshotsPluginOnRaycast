#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <QuartzCore/QuartzCore.h>
#import <Vision/Vision.h>
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>

@interface TextActionHandler : NSObject
@property (nonatomic, copy) NSString *recognizedText;
@property (nonatomic, assign) NSView *panelView;
- (instancetype)initWithText:(NSString *)text;
- (void)copyText:(id)sender;
- (void)pasteText:(id)sender;
- (void)togglePanel:(id)sender;
@end

@implementation TextActionHandler
- (instancetype)initWithText:(NSString *)text {
    self = [super init];
    if (self) {
        _recognizedText = [text copy];
    }
    return self;
}

- (void)copyText:(id)sender {
    if (self.recognizedText.length == 0) {
        return;
    }
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:self.recognizedText forType:NSPasteboardTypeString];
}

- (void)pasteText:(id)sender {
    if (self.recognizedText.length == 0) {
        return;
    }
    [self copyText:nil];
    
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateCombinedSessionState);
    if (!source) {
        return;
    }
    CGEventRef keyDown = CGEventCreateKeyboardEvent(source, (CGKeyCode)kVK_ANSI_V, true);
    CGEventSetFlags(keyDown, kCGEventFlagMaskCommand);
    CGEventRef keyUp = CGEventCreateKeyboardEvent(source, (CGKeyCode)kVK_ANSI_V, false);
    CGEventSetFlags(keyUp, kCGEventFlagMaskCommand);
    
    CGEventPost(kCGAnnotatedSessionEventTap, keyDown);
    CGEventPost(kCGAnnotatedSessionEventTap, keyUp);
    
    CFRelease(keyDown);
    CFRelease(keyUp);
    CFRelease(source);
}

- (void)togglePanel:(id)sender {
    if (!self.panelView) {
        return;
    }
    
    BOOL shouldShow = self.panelView.isHidden || self.panelView.alphaValue < 1.0;
    if (shouldShow && self.panelView.superview) {
        [self.panelView.superview addSubview:self.panelView positioned:NSWindowAbove relativeTo:nil];
    }
    
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        context.duration = 0.18;
        context.allowsImplicitAnimation = YES;
        if (shouldShow) {
            self.panelView.hidden = NO;
            self.panelView.alphaValue = 1.0;
        } else {
            self.panelView.alphaValue = 0.0;
        }
    } completionHandler:^{
        if (!shouldShow) {
            self.panelView.hidden = YES;
        }
    }];
}
@end

static NSString *RecognizedTextFromImage(NSImage *image) {
    if (!image) {
        return nil;
    }
    
    CGImageRef cgImage = [image CGImageForProposedRect:NULL context:nil hints:nil];
    BOOL shouldReleaseCGImage = NO;
    if (!cgImage) {
        NSData *tiffData = [image TIFFRepresentation];
        if (tiffData) {
            CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)tiffData, NULL);
            if (source) {
                cgImage = CGImageSourceCreateImageAtIndex(source, 0, NULL);
                shouldReleaseCGImage = (cgImage != NULL);
                CFRelease(source);
            }
        }
    }
    
    if (!cgImage) {
        return nil;
    }
    
    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] init];
    request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = YES;
    
    NSError *visionError = nil;
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cgImage options:@{}];
    BOOL success = [handler performRequests:@[request] error:&visionError];
    
    if (!success || visionError) {
        if (shouldReleaseCGImage && cgImage) {
            CGImageRelease(cgImage);
        }
        return nil;
    }
    
    NSMutableString *recognized = [NSMutableString string];
    for (VNRecognizedTextObservation *observation in request.results) {
        VNRecognizedText *topCandidate = [[observation topCandidates:1] firstObject];
        if (topCandidate) {
            if (recognized.length > 0) {
                [recognized appendString:@"\n"];
            }
            [recognized appendString:topCandidate.string];
        }
    }
    
    if (shouldReleaseCGImage && cgImage) {
        CGImageRelease(cgImage);
    }
    
    NSString *trimmed = [recognized stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.length > 0 ? trimmed : nil;
}

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
        
        // 获取图片像素尺寸（而不是点尺寸），以便实现 1:1 显示
        NSSize imageSize = [image size];
        NSSize pixelSize = imageSize;
        for (NSImageRep *rep in [image representations]) {
            if ([rep isKindOfClass:[NSBitmapImageRep class]]) {
                pixelSize.width = [(NSBitmapImageRep *)rep pixelsWide];
                pixelSize.height = [(NSBitmapImageRep *)rep pixelsHigh];
                break;
            }
        }
        
        NSScreen *screen = [NSScreen mainScreen];
        CGFloat scaleFactor = screen ? [screen backingScaleFactor] : 1.0;
        if (scaleFactor <= 0.0) {
            scaleFactor = 1.0;
        }
        
        // 按照当前屏幕的缩放因子换算为点尺寸，确保视觉上 1:1
        NSSize displaySize = NSMakeSize(pixelSize.width / scaleFactor, pixelSize.height / scaleFactor);
        NSRect screenFrame = screen ? [screen frame] : NSMakeRect(0, 0, 1920, 1080);
        
        // 计算窗口位置（居中）
        CGFloat windowX = (screenFrame.size.width - displaySize.width) / 2;
        CGFloat windowY = (screenFrame.size.height - displaySize.height) / 2;
        
        // 创建无边框窗口
        NSRect windowRect = NSMakeRect(windowX, windowY, displaySize.width, displaySize.height);
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
        NSView *containerView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, displaySize.width, displaySize.height)];
        
        // 创建图片视图（点击穿透）
        ClickThroughImageView *imageView = [[ClickThroughImageView alloc] initWithFrame:NSMakeRect(0, 0, displaySize.width, displaySize.height)];
        [imageView setImage:image];
        [imageView setImageScaling:NSImageScaleAxesIndependently];
        [imageView setEditable:NO];
        
        // 检测图片中的文字
        NSString *recognizedText = RecognizedTextFromImage(image);
        TextActionHandler *textHandler = nil;
        if (recognizedText.length > 0) {
            textHandler = [[TextActionHandler alloc] initWithText:recognizedText];
            objc_setAssociatedObject(window, "TextActionHandler", textHandler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        
        // 创建拖动区域（窗口边缘 10px，不点击穿透，用于拖动）
        CGFloat dragAreaSize = 10.0;
        NSView *dragArea = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, displaySize.width, displaySize.height)];
        [dragArea setWantsLayer:YES];
        dragArea.layer.backgroundColor = [[NSColor clearColor] CGColor];
        
        // 拖动区域可以拖动窗口
        [dragArea addTrackingArea:[[NSTrackingArea alloc] 
            initWithRect:NSMakeRect(0, 0, displaySize.width, dragAreaSize)
            options:NSTrackingActiveInKeyWindow | NSTrackingMouseEnteredAndExited | NSTrackingInVisibleRect
            owner:dragArea
            userInfo:nil]];
        
        // 实现拖动
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDragged handler:^NSEvent *(NSEvent *event) {
            NSPoint location = [event locationInWindow];
            // 如果鼠标在边缘区域，允许拖动
            if (location.y < dragAreaSize || location.y > displaySize.height - dragAreaSize ||
                location.x < dragAreaSize || location.x > displaySize.width - dragAreaSize) {
                [window performWindowDragWithEvent:event];
            }
            return event;
        }];
        
        [containerView addSubview:imageView];
        [containerView addSubview:dragArea positioned:NSWindowAbove relativeTo:imageView];
        
        if (textHandler && displaySize.width > 140.0 && displaySize.height > 100.0) {
            CGFloat panelWidth = MIN(280.0, displaySize.width - 20.0);
            CGFloat panelHeight = 110.0;
            CGFloat panelX = displaySize.width - panelWidth - 10.0;
            CGFloat panelY = 16.0 + 36.0; // leave space for badge
            
            NSVisualEffectView *panel = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(panelX, panelY, panelWidth, panelHeight)];
            [panel setMaterial:NSVisualEffectMaterialSidebar];
            [panel setBlendingMode:NSVisualEffectBlendingModeWithinWindow];
            [panel setState:NSVisualEffectStateActive];
            [panel setWantsLayer:YES];
            panel.layer.cornerRadius = 12.0;
            panel.hidden = YES;
            panel.alphaValue = 0.0;
            textHandler.panelView = panel;
            
            NSTextField *titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(12.0, panelHeight - 26.0, panelWidth - 24.0, 18.0)];
            [titleLabel setStringValue:@"检测到图片文字"];
            [titleLabel setEditable:NO];
            [titleLabel setBordered:NO];
            [titleLabel setDrawsBackground:NO];
            [titleLabel setFont:[NSFont boldSystemFontOfSize:13.0]];
            
            NSString *previewString = [recognizedText stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
            if (previewString.length > 80) {
                previewString = [[previewString substringToIndex:80] stringByAppendingString:@"…"];
            }
            
            NSTextField *previewLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(12.0, 50.0, panelWidth - 24.0, 40.0)];
            [previewLabel setStringValue:previewString];
            [previewLabel setEditable:NO];
            [previewLabel setBordered:NO];
            [previewLabel setDrawsBackground:NO];
            [previewLabel setLineBreakMode:NSLineBreakByWordWrapping];
            [previewLabel setFont:[NSFont systemFontOfSize:12.0]];
            
            CGFloat buttonWidth = (panelWidth - 36.0) / 2.0;
            NSButton *copyButton = [NSButton buttonWithTitle:@"复制文字" target:textHandler action:@selector(copyText:)];
            [copyButton setFrame:NSMakeRect(12.0, 14.0, buttonWidth, 28.0)];
            [copyButton setBezelStyle:NSBezelStyleRounded];
            
            NSButton *pasteButton = [NSButton buttonWithTitle:@"粘贴文字" target:textHandler action:@selector(pasteText:)];
            [pasteButton setFrame:NSMakeRect(24.0 + buttonWidth, 14.0, buttonWidth, 28.0)];
            [pasteButton setBezelStyle:NSBezelStyleRounded];
            
            [panel addSubview:titleLabel];
            [panel addSubview:previewLabel];
            [panel addSubview:copyButton];
            [panel addSubview:pasteButton];
            
            [containerView addSubview:panel positioned:NSWindowAbove relativeTo:imageView];
            
            CGFloat badgeSize = 36.0;
            CGFloat badgeX = displaySize.width - badgeSize - 12.0;
            CGFloat badgeY = 12.0;
            NSVisualEffectView *badgeView = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(badgeX, badgeY, badgeSize, badgeSize)];
            [badgeView setMaterial:NSVisualEffectMaterialHUDWindow];
            [badgeView setBlendingMode:NSVisualEffectBlendingModeWithinWindow];
            [badgeView setState:NSVisualEffectStateActive];
            [badgeView setWantsLayer:YES];
            badgeView.layer.cornerRadius = 8.0;
            badgeView.layer.masksToBounds = YES;
            
            NSColor *lineColor = [[NSColor whiteColor] colorWithAlphaComponent:0.92];
            NSArray<NSDictionary *> *lineConfigs = @[
                @{@"width": @(badgeSize - 14.0), @"y": @(badgeSize - 11.0)},
                @{@"width": @(badgeSize - 18.0), @"y": @(badgeSize - 19.0)},
                @{@"width": @(badgeSize - 24.0), @"y": @(badgeSize - 27.0)}
            ];
            for (NSDictionary *config in lineConfigs) {
                CALayer *lineLayer = [CALayer layer];
                lineLayer.backgroundColor = lineColor.CGColor;
                lineLayer.cornerRadius = 1.0;
                CGFloat width = [config[@"width"] doubleValue];
                CGFloat y = [config[@"y"] doubleValue];
                lineLayer.frame = CGRectMake((badgeSize - width) / 2.0, y, width, 2.0);
                [badgeView.layer addSublayer:lineLayer];
            }
            
            NSButton *badgeButton = [NSButton buttonWithTitle:@"" target:textHandler action:@selector(togglePanel:)];
            [badgeButton setBordered:NO];
            [badgeButton setFrame:badgeView.bounds];
            [badgeButton setTransparent:YES];
            [badgeView addSubview:badgeButton];
            
            [containerView addSubview:badgeView positioned:NSWindowAbove relativeTo:imageView];
        }
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

