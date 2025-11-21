#import <Cocoa/Cocoa.h>
#import <Vision/Vision.h>

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
        NSLog(@"OCR错误: %@", visionError.localizedDescription);
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

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSString *imagePath = [NSString stringWithUTF8String:argv[1]];
        NSImage *image = [[NSImage alloc] initWithContentsOfFile:imagePath];
        
        if (!image) {
            fprintf(stderr, "无法加载图片: %s\n", argv[1]);
            return 1;
        }
        
        NSString *recognizedText = RecognizedTextFromImage(image);
        if (recognizedText) {
            printf("识别到的文字:\n%s\n", [recognizedText UTF8String]);
        } else {
            printf("未识别到文字\n");
        }
    }
    return 0;
}