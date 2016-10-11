//
//  ViewController.m
//  BeautifyFaceDemo
//
//  Created by guikz on 16/4/27.
//  Copyright © 2016年 guikz. All rights reserved.
//

#import "ViewController.h"
#import <GPUImage/GPUImage.h>
#import "GPUImageBeautifyFilter.h"
#import <Masonry/Masonry.h>

@interface ViewController ()<GPUImageVideoCameraDelegate>
{
    CMSampleTimingInfo                  _timimgInfo;
    CMTime                              _lastSampleTime;
}

@property (nonatomic, strong) GPUImageVideoCamera *videoCamera;
@property (nonatomic, strong) GPUImageView *filterView;
@property (nonatomic, strong) UIButton *beautifyButton;

@property (nonatomic, strong) GPUImageBeautifyFilter *beautifyFilter;/**< 美颜滤镜 */
@property (nonatomic,copy) NSString *filePath;
@property (nonatomic,strong) AVAssetWriter *writer;
@property (nonatomic,strong) AVAssetWriterInput *writerInput;
@property (atomic,strong) NSFileManager *fileManager;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    self.videoCamera = [[GPUImageVideoCamera alloc] initWithSessionPreset:AVCaptureSessionPreset1280x720 cameraPosition:AVCaptureDevicePositionFront];
    self.videoCamera.delegate = self;
    self.videoCamera.outputImageOrientation = UIInterfaceOrientationPortrait;
    self.videoCamera.horizontallyMirrorFrontFacingCamera = YES;
    self.filterView = [[GPUImageView alloc] initWithFrame:self.view.frame];
    self.filterView.center = self.view.center;
    
    [self.view addSubview:self.filterView];
    [self.videoCamera addTarget:self.filterView];
    [self.videoCamera startCameraCapture];
    
    self.beautifyButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.beautifyButton.backgroundColor = [UIColor whiteColor];
    [self.beautifyButton setTitle:@"开启" forState:UIControlStateNormal];
    [self.beautifyButton setTitle:@"关闭" forState:UIControlStateSelected];
    [self.beautifyButton setTitleColor:[UIColor blueColor] forState:UIControlStateNormal];
    [self.beautifyButton addTarget:self action:@selector(beautify) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.beautifyButton];
    [self.beautifyButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.bottom.equalTo(self.view).offset(-20);
        make.width.equalTo(@100);
        make.height.equalTo(@40);
        make.centerX.equalTo(self.view);
    }];

}

- (void)beautify {
    if (self.beautifyButton.selected) {
        self.beautifyButton.selected = NO;
        [self.videoCamera removeAllTargets];
        [self.videoCamera addTarget:self.filterView];
    }
    else {
        self.beautifyButton.selected = YES;
        [self.videoCamera removeAllTargets];
        GPUImageBeautifyFilter *beautifyFilter = [[GPUImageBeautifyFilter alloc] init];
        [self.videoCamera addTarget:beautifyFilter];
        [beautifyFilter addTarget:self.filterView];
        self.beautifyFilter = beautifyFilter;
        
        CGSize outputSize = {720.0f, 1280.0f};
        GPUImageRawDataOutput *rawDataOutput = [[GPUImageRawDataOutput alloc] initWithImageSize:CGSizeMake(outputSize.width, outputSize.height) resultsInBGRAFormat:YES];
        [self.beautifyFilter addTarget:rawDataOutput];
        __weak GPUImageRawDataOutput *weakOutput = rawDataOutput;
        __weak typeof(self) weakSelf = self;
        
        [rawDataOutput setNewFrameAvailableBlock:^{
            __strong GPUImageRawDataOutput *strongOutput = weakOutput;
            [strongOutput lockFramebufferForReading];
            
            // 这里就可以获取到添加滤镜的数据了
            GLubyte *outputBytes = [strongOutput rawBytesForImage];
            NSInteger bytesPerRow = [strongOutput bytesPerRowInOutput];
            CVPixelBufferRef pixelBuffer = NULL;
            CVPixelBufferCreateWithBytes(kCFAllocatorDefault, outputSize.width, outputSize.height, kCVPixelFormatType_32BGRA, outputBytes, bytesPerRow, nil, nil, nil, &pixelBuffer);
            
            
            // 之后可以利用VideoToolBox进行硬编码再结合rtmp协议传输视频流了
            [weakSelf encodeWithCVPixelBufferRef:pixelBuffer];
            [strongOutput unlockFramebufferAfterReading];
            CFRelease(pixelBuffer);
            
        }];
    }
}

- (void)willOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer{
    CMSampleBufferGetSampleTimingInfo(sampleBuffer, 0, &_timimgInfo);
//    UIImage *image = [self imageFromSampleBuffer:sampleBuffer];
//    [self appendSampleBuffer:sampleBuffer];
}

- (void)beauty{
    [self.videoCamera removeAllTargets];
    GPUImageBeautifyFilter *beautifyFilter = [[GPUImageBeautifyFilter alloc] init];
    [self.videoCamera addTarget:beautifyFilter];
    [beautifyFilter addTarget:self.filterView];
    self.beautifyFilter = beautifyFilter;
    
    CGSize outputSize = {720.0f, 1280.0f};
    GPUImageRawDataOutput *rawDataOutput = [[GPUImageRawDataOutput alloc] initWithImageSize:CGSizeMake(outputSize.width, outputSize.height) resultsInBGRAFormat:YES];
    [self.beautifyFilter addTarget:rawDataOutput];
    __weak GPUImageRawDataOutput *weakOutput = rawDataOutput;
    __weak typeof(self) weakSelf = self;
    
    [rawDataOutput setNewFrameAvailableBlock:^{
        __strong GPUImageRawDataOutput *strongOutput = weakOutput;
        [strongOutput lockFramebufferForReading];
        
        // 这里就可以获取到添加滤镜的数据了
        GLubyte *outputBytes = [strongOutput rawBytesForImage];
        NSInteger bytesPerRow = [strongOutput bytesPerRowInOutput];
        CVPixelBufferRef pixelBuffer = NULL;
        CVPixelBufferCreateWithBytes(kCFAllocatorDefault, outputSize.width, outputSize.height, kCVPixelFormatType_32BGRA, outputBytes, bytesPerRow, nil, nil, nil, &pixelBuffer);
        
        
        // 之后可以利用VideoToolBox进行硬编码再结合rtmp协议传输视频流了
        [weakSelf encodeWithCVPixelBufferRef:pixelBuffer];
        [strongOutput unlockFramebufferAfterReading];
        CFRelease(pixelBuffer);
        
    }];
}

- (void)encodeWithCVPixelBufferRef:(CVPixelBufferRef)pixelBufferRef{
    
    CFRetain(pixelBufferRef);
    CMSampleBufferRef newSampleBuffer = NULL;
    // time info
    CMTime frameTime = CMTimeMake(1, 25);
    CMTime currentTime = CMTimeAdd(_lastSampleTime, frameTime);
    CMSampleTimingInfo timing = {frameTime, currentTime, kCMTimeInvalid};
    
    // format
    OSStatus result = 0;
    CMVideoFormatDescriptionRef videoInfo = NULL;
    result = CMVideoFormatDescriptionCreateForImageBuffer(NULL, pixelBufferRef, &videoInfo);
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixelBufferRef, true, NULL, NULL, videoInfo, &_timimgInfo, &newSampleBuffer);
    CFRelease(pixelBufferRef);
    [self appendSampleBuffer:newSampleBuffer];
    UIImage *image = [self imageFromSampleBuffer:newSampleBuffer];
//    dispatch_async(dispatch_get_main_queue(), ^{
//        static times = 0;
//        times ++;
//        if (times != 50) {
//            return ;
//        }
//        //        UIImageView *imageV = [[UIImageView alloc] initWithImage:image];
//        //        [self.preView addSubview:imageV];
//        //        imageV.frame = CGRectMake(0, 0, 200, 400);
//    });
    _lastSampleTime = currentTime;
}

- (void)appendSampleBuffer:(CMSampleBufferRef)sampleBuffer{
    CFRetain(sampleBuffer);
    self.filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"param.mov"];
    self.fileManager = [[NSFileManager alloc] init];
    
    [self cleanFileAtPath:self.filePath];
    
    NSURL* url = [NSURL fileURLWithPath:self.filePath];
    
    self.writer = [AVAssetWriter assetWriterWithURL:url fileType:AVFileTypeQuickTimeMovie error:nil];
    
    NSDictionary *compressionProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                 [NSNumber numberWithInteger: 500], AVVideoAverageBitRateKey,
                                 @"H264_High_4_1", AVVideoProfileLevelKey,
                                 @(30), AVVideoMaxKeyFrameIntervalKey,
                                 [NSNumber numberWithBool: NO], AVVideoAllowFrameReorderingKey,
                                 nil];
    
    NSDictionary *videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                   AVVideoCodecH264, AVVideoCodecKey,
                                   [NSNumber numberWithInteger:360.0f /*width default:360*/], AVVideoWidthKey,
                                   [NSNumber numberWithInteger:640.0f /*height default:640*/], AVVideoHeightKey,
                                   compressionProperties, AVVideoCompressionPropertiesKey,
                                   AVVideoScalingModeResizeAspectFill, AVVideoScalingModeKey,
                                   nil];
    
    self.writerInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings: videoSettings];
    _writerInput.expectsMediaDataInRealTime = YES;
    
    [_writer addInput:_writerInput];
    if (![self.writer startWriting]) {
        return;
    }
    
    BOOL success = NO;
    [self.writer startSessionAtSourceTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
    
    if ( [self.writerInput isReadyForMoreMediaData] )
    {
        success = [self.writerInput appendSampleBuffer: sampleBuffer];
    }
    else
    {
        NSLog(@"sample buffer is busy waiting or will wait for finish");
    }
    if (!success) {
        NSLog(@"append sample buffer failed:%@", self.writer.error);
    }
    
    CFRelease(sampleBuffer);
}

- (UIImage *) imageFromSampleBuffer:(CMSampleBufferRef) sampleBuffer
{
    // Get a CMSampleBuffer's Core Video image buffer for the media data
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    // Lock the base address of the pixel buffer
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    // Get the number of bytes per row for the pixel buffer
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    
    // Get the number of bytes per row for the pixel buffer
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    // Get the pixel buffer width and height
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    
    //    NSLog(@"with = %ld", width);
    //    NSLog(@"height = %ld", height);
    
    //    width *= 0.5;
    //    height *= 0.5;
    // Create a device-dependent RGB color space
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    // Create a bitmap graphics context with the sample buffer data
    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8,
                                                 bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    // Create a Quartz image from the pixel data in the bitmap graphics context
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    // Unlock the pixel buffer
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    
    
    // Free up the context and color space
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    
    // Create an image object from the Quartz image
    UIImage *image = [UIImage imageWithCGImage:quartzImage];
    
    // Release the Quartz image
    CGImageRelease(quartzImage);
    
    return (image);
}

- (void)cleanFileAtPath:(NSString *)filePath
{
    if ( [self.fileManager fileExistsAtPath:filePath] )
    {
        [self.fileManager removeItemAtPath:filePath error:NULL];
    }
}

@end
