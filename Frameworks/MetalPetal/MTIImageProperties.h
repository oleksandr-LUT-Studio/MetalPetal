//
//  MTIImageProperties.h
//  Pods
//
//  Created by YuAo on 2018/6/22.
//

#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#if __has_include(<MetalPetal/MetalPetal.h>)
#import <MetalPetal/MTIHDRDetection.h>
#else
#import "MTIHDRDetection.h"
#endif

NS_ASSUME_NONNULL_BEGIN

__attribute__((objc_subclassing_restricted))
@interface MTIImageProperties : NSObject <NSCopying>

+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)init NS_UNAVAILABLE;

- (nullable instancetype)initWithImageSource:(CGImageSourceRef)imageSource index:(NSUInteger)index NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCGImage:(CGImageRef)image orientation:(CGImagePropertyOrientation)orientation NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCGImage:(CGImageRef)image;

- (nullable instancetype)initWithImageAtURL:(NSURL *)URL;

@property (nonatomic, readonly) CGImageAlphaInfo alphaInfo;
@property (nonatomic, readonly) CGImageByteOrderInfo byteOrderInfo;
@property (nonatomic, readonly) BOOL floatComponents;
@property (nonatomic, readonly, nullable) CGColorSpaceRef colorSpace;

@property (nonatomic, readonly) NSUInteger bitsPerComponent;

@property (nonatomic, readonly) NSUInteger pixelWidth;
@property (nonatomic, readonly) NSUInteger pixelHeight;

@property (nonatomic, readonly) CGImagePropertyOrientation orientation;

// Width and height with orientation applied.
@property (nonatomic, readonly) NSUInteger displayWidth;
@property (nonatomic, readonly) NSUInteger displayHeight;

@property (nonatomic, copy, readonly) NSDictionary *properties;

/// HDR/Log classification derived from the image's color space and bit depth.
@property (nonatomic, readonly) MTIHDRContentType hdrContentType;

@end

NS_ASSUME_NONNULL_END
