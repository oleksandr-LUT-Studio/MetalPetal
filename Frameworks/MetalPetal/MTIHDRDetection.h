//
//  MTIHDRDetection.h
//  MetalPetal
//
//  HDR / Log content detection helpers for MetalPetal input paths.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>
#import <Metal/Metal.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Classification of the color/transfer content of an input.
typedef NS_ENUM(NSInteger, MTIHDRContentType) {
    /// Unknown — treat as SDR.
    MTIHDRContentTypeUnknown = 0,
    /// Standard dynamic range (Rec.709 / sRGB / DisplayP3, gamma-encoded, 8-bit class).
    MTIHDRContentTypeSDR,
    /// Wide-gamut / extended-range linear or extended sRGB (Display P3, extended sRGB, scRGB-style).
    MTIHDRContentTypeExtendedSDR,
    /// HDR with PQ transfer (SMPTE ST 2084), typically BT.2020 primaries.
    MTIHDRContentTypeHDR_PQ,
    /// HDR with HLG transfer (ITU-R BT.2100 HLG), typically BT.2020 primaries.
    MTIHDRContentTypeHDR_HLG,
    /// Apple Log transfer function (iOS 17.2+).
    MTIHDRContentTypeLog_Apple,
    /// Apple Log 2 transfer function (iOS 26+).
    MTIHDRContentTypeLog_AppleLog2,
    /// Other Log encoding (S-Log, V-Log, ARRI LogC, Canon C-Log). Detected heuristically; never relied upon.
    MTIHDRContentTypeLog_Other
};

/// YES when the content type carries dynamic range beyond standard sRGB (i.e. needs
/// >8-bit precision to render without banding/clipping).
FOUNDATION_EXPORT BOOL MTIHDRContentTypeIsHighDynamicRange(MTIHDRContentType type);

/// Detection from a CVPixelBuffer using its attachments (transfer function + color primaries)
/// combined with its pixel format. Returns Unknown if nothing can be determined.
FOUNDATION_EXPORT MTIHDRContentType MTIHDRContentTypeFromCVPixelBuffer(CVPixelBufferRef pixelBuffer);

/// Detection from a CGColorSpace, optionally augmented with bits-per-component and float flag.
/// Pass 0 / NO if those are unknown. Float components ≥16-bit are treated as extended range.
FOUNDATION_EXPORT MTIHDRContentType MTIHDRContentTypeFromCGColorSpace(CGColorSpaceRef _Nullable colorSpace,
                                                                     size_t bitsPerComponent,
                                                                     BOOL floatComponents);

/// Detection from an AVAsset track using its format description extensions.
/// Returns Unknown if track has no video format descriptions.
FOUNDATION_EXPORT MTIHDRContentType MTIHDRContentTypeFromAVAssetTrack(AVAssetTrack *track);

/// Recommended Metal pixel format for carrying content of the given type without lossy SDR conversion.
/// Returns MTLPixelFormatBGRA8Unorm for SDR, MTLPixelFormatRGBA16Float for HDR/Log/ExtendedSDR.
FOUNDATION_EXPORT MTLPixelFormat MTIRecommendedMTLPixelFormatForHDRContentType(MTIHDRContentType type);

/// Recommended CGColorSpace for the given content type. The caller owns the returned reference.
/// Returns NULL if it cannot recommend one. SDR returns sRGB; ExtendedSDR returns extendedLinearSRGB;
/// HDR_PQ returns ITUR_2100_PQ; HDR_HLG returns ITUR_2100_HLG. Apple Log returns extendedLinearITUR_2020.
FOUNDATION_EXPORT CGColorSpaceRef _Nullable MTIRecommendedCGColorSpaceForHDRContentType(MTIHDRContentType type) CF_RETURNS_RETAINED;

NS_ASSUME_NONNULL_END
