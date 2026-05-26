//
//  MTIAVAssetExport.h
//  MetalPetal
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>
#import <AVFoundation/AVFoundation.h>
#import <MetalPetal/MTIHDRDetection.h>

NS_ASSUME_NONNULL_BEGIN

/// Apple ProRes profiles suitable for AVAssetWriter video settings.
typedef NS_ENUM(NSInteger, MTIProResProfile) {
    MTIProResProfile422,
    MTIProResProfile422LT,
    MTIProResProfile422HQ,
    MTIProResProfile422Proxy,
    MTIProResProfile4444
};

/// Returns the AVFoundation codec constant for a ProRes profile.
FOUNDATION_EXPORT AVVideoCodecType MTIAVVideoCodecTypeForProResProfile(MTIProResProfile profile);

/// Builds AVAssetWriterInput output settings for exporting ProRes video.
///
/// For Apple Log output, AVFoundation does not provide an AVVideoTransferFunction value for
/// Apple Log. Use these settings with `MTIApplyHDRContentMetadataToCVPixelBuffer` on each
/// rendered source pixel buffer before appending it to an AVAssetWriter input adaptor.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *MTIAVAssetWriterVideoSettingsForProRes(CGSize size,
                                                                                       MTIProResProfile profile,
                                                                                       MTIHDRContentType contentType);

/// Builds source pixel-buffer attributes for AVAssetWriterInputPixelBufferAdaptor.
/// HDR and Log content use 16-bit floating-point RGBA buffers so MetalPetal can render without
/// flattening range before AVFoundation encodes ProRes.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *MTIAVAssetWriterInputPixelBufferAttributesForProRes(CGSize size,
                                                                                                    MTIHDRContentType contentType);

/// Applies color and transfer metadata to a rendered CVPixelBuffer before writing.
FOUNDATION_EXPORT void MTIApplyHDRContentMetadataToCVPixelBuffer(CVPixelBufferRef pixelBuffer,
                                                                MTIHDRContentType contentType);

NS_ASSUME_NONNULL_END
