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
    
    // 设置识别语言，支持中文和英文
    request.recognitionLanguages = @[@"zh-Hans", @"zh-Hant", @"en-US", @"en-GB"];
    
    // 设置其他参数以提高识别准确率
    request.usesLanguageCorrection = YES;
    request.minimumTextHeight = 0; // 自动检测文本高度
    
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
        // 获取置信度最高的候选文本
        NSArray *candidates = [observation topCandidates:3]; // 获取前3个候选
        if (candidates.count > 0) {
            VNRecognizedText *topCandidate = candidates[0];
            // 只有当置信度足够高时才添加到结果中
            if (topCandidate.confidence > 0.1) { // 设置置信度阈值
                if (recognized.length > 0) {
                    [recognized appendString:@"\n"];
                }
                [recognized appendString:topCandidate.string];
            }
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
        fprintf(stderr, "用法: FloatWindow <图片路径> [截图X坐标] [截图Y坐标] [截图宽度] [截图高度]\n");
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
        
        // 计算窗口位置
        CGFloat windowX, windowY;
        
        // 如果提供了截图区域，则使用截图区域作为窗口位置
        if (argc >= 6) {
            CGFloat screenshotX = atof(argv[2]);
            CGFloat screenshotY = atof(argv[3]);
            CGFloat screenshotWidth = atof(argv[4]);
            CGFloat screenshotHeight = atof(argv[5]);
            // 日志输出出来 argv中的所有信息
            NSLog(@"[ScreenshotPlugin] 调试信息 argv中的信息: %s, %s, %s, %s, %s, %s, %s", argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6]);
            
            // 使用截图的原始位置
            windowX = screenshotX;
            // 修复Y轴位置问题：根据用户反馈，Y轴位置错位了一个截图高度
            // 需要将Y坐标向上移动一个截图高度
            // windowY = screenshotY;
            // 可能的修复方式
            NSLog(@"[ScreenshotPlugin] 调试信息 windowY， screenshotY， displaySize.height分别是:%.2f, %.2f, %.2f", windowY, screenshotY, displaySize.height);
            
            windowY = screenshotY + screenshotHeight - displaySize.height;
            NSLog(@"[ScreenshotPlugin] 计算结果为：%.2f", windowY);
            // 添加调试日志
            // NSLog(@"调试信息 - 屏幕尺寸: %.2f x %.2f", screenFrame.size.width, screenFrame.size.height);
            // NSLog(@"调试信息 - 图片尺寸: %.2f x %.2f", displaySize.width, displaySize.height);
            // NSLog(@"调试信息 - 截图区域: X=%.2f, Y=%.2f, W=%.2f, H=%.2f", screenshotX, screenshotY, screenshotWidth, screenshotHeight);

            // NSLog(@"调试信息 - 初始窗口位置: X=%.2f, Y=%.2f", windowX, windowY);

            // // 在边界检查后添加
            // NSLog(@"调试信息 - 最终窗口位置: X=%.2f, Y=%.2f", windowX, windowY);

            
            // 确保窗口不会超出屏幕边界
            if (windowX < 0) windowX = 0;
            if (windowY < 0) windowY = 0;
            if (windowX + displaySize.width > screenFrame.size.width) {
                windowX = screenFrame.size.width - displaySize.width;
            }
            if (windowY + displaySize.height > screenFrame.size.height) {
                // windowY = screenFrame.size.height - displaySize.height;
                // 修复Y轴位置问题：需要考虑坐标系统的差异
                windowY = screenFrame.size.height - screenshotY - displaySize.height;
            }
            
            // 如果截图尺寸与图片尺寸不匹配，使用图片的实际尺寸
            // 但保持位置不变
        } else {
            // 默认居中显示
            windowX = (screenFrame.size.width - displaySize.width) / 2;
            windowY = (screenFrame.size.height - displaySize.height) / 2;
        }
        
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
        
        // 在图片右侧显示文字识别结果
        // 即使没有识别到文字，也显示一个空的面板，方便用户知道OCR功能存在
        // 移除尺寸限制，确保面板总是显示
        // 文字面板宽度
        CGFloat panelWidth = MIN(300.0, screenFrame.size.width - displaySize.width - 50.0);
        if (panelWidth < 100.0) panelWidth = 100.0;
        
        // 文字面板高度，根据文字内容自适应
        CGFloat panelHeight = MIN(400.0, displaySize.height - 40.0);
        if (panelHeight < 100.0) panelHeight = 100.0;
        
        // 文字面板位置（在图片右侧）
        CGFloat panelX = displaySize.width + 10.0;
        CGFloat panelY = (displaySize.height - panelHeight) / 2.0;
        
        // 确保面板不会超出屏幕边界
        if (panelX + panelWidth > screenFrame.size.width) {
            panelX = screenFrame.size.width - panelWidth - 10.0;
        }
        if (panelY < 10.0) panelY = 10.0;
        if (panelY + panelHeight > screenFrame.size.height) {
            panelY = screenFrame.size.height - panelHeight - 10.0;
        }
        
        NSVisualEffectView *panel = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(panelX, panelY, panelWidth, panelHeight)];
        [panel setMaterial:NSVisualEffectMaterialSidebar];
        [panel setBlendingMode:NSVisualEffectBlendingModeWithinWindow];
        [panel setState:NSVisualEffectStateActive];
        [panel setWantsLayer:YES];
        panel.layer.cornerRadius = 12.0;
        panel.hidden = NO; // 默认显示
        panel.alphaValue = 1.0;
        
        NSTextField *titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(12.0, panelHeight - 30.0, panelWidth - 24.0, 20.0)];
        [titleLabel setStringValue:recognizedText && recognizedText.length > 0 ? @"识别到的文字" : @"未识别到文字"];
        [titleLabel setEditable:NO];
        [titleLabel setBordered:NO];
        [titleLabel setDrawsBackground:NO];
        [titleLabel setFont:[NSFont boldSystemFontOfSize:14.0]];
        
        if (recognizedText && recognizedText.length > 0) {
            textHandler = [[TextActionHandler alloc] initWithText:recognizedText];
            objc_setAssociatedObject(window, "TextActionHandler", textHandler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            textHandler.panelView = panel;
            
            // 创建可滚动的文本视图来显示完整文字内容
            NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(12.0, 40.0, panelWidth - 24.0, panelHeight - 70.0)];
            scrollView.hasVerticalScroller = YES;
            scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            
            NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, panelWidth - 24.0, panelHeight - 70.0)];
            [textView setString:recognizedText];
            [textView setEditable:NO];
            [textView setFont:[NSFont systemFontOfSize:13.0]];
            [textView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
            
            // 保留换行格式
            textView.textContainer.lineFragmentPadding = 0;
            textView.textContainerInset = NSMakeSize(0, 0);
            
            [scrollView setDocumentView:textView];
            
            CGFloat buttonWidth = (panelWidth - 36.0) / 2.0;
            NSButton *copyButton = [NSButton buttonWithTitle:@"复制文字" target:textHandler action:@selector(copyText:)];
            [copyButton setFrame:NSMakeRect(12.0, 10.0, buttonWidth, 28.0)];
            [copyButton setBezelStyle:NSBezelStyleRounded];
            
            NSButton *pasteButton = [NSButton buttonWithTitle:@"粘贴文字" target:textHandler action:@selector(pasteText:)];
            [pasteButton setFrame:NSMakeRect(24.0 + buttonWidth, 10.0, buttonWidth, 28.0)];
            [pasteButton setBezelStyle:NSBezelStyleRounded];
            
            [panel addSubview:titleLabel];
            [panel addSubview:scrollView];
            [panel addSubview:copyButton];
            [panel addSubview:pasteButton];
        } else {
            // 没有识别到文字时显示提示信息
            NSTextField *infoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(12.0, panelHeight/2 - 20.0, panelWidth - 24.0, 40.0)];
            [infoLabel setStringValue:@"图片中未检测到可识别的文字"];
            [infoLabel setEditable:NO];
            [infoLabel setBordered:NO];
            [infoLabel setDrawsBackground:NO];
            [infoLabel setFont:[NSFont systemFontOfSize:13.0]];
            [infoLabel setTextColor:[NSColor secondaryLabelColor]];
            [infoLabel setAlignment:NSTextAlignmentCenter];
            
            [panel addSubview:titleLabel];
            [panel addSubview:infoLabel];
        }
        
        // 将文字面板添加到窗口内容视图
        [containerView addSubview:panel positioned:NSWindowAbove relativeTo:imageView];
        
        [window setContentView:containerView];
        [window setIgnoresMouseEvents:NO];  // 允许边缘区域响应鼠标事件
        [window makeKeyAndOrderFront:nil];
        
        // 创建应用
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular]; // 改为Regular以确保窗口可见
        [app activateIgnoringOtherApps:YES]; // 确保应用激活
        
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

