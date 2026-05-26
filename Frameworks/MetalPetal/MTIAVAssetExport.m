//
//  MTIAVAssetExport.m
//  MetalPetal
//

#import "MTIAVAssetExport.h"

static NSDictionary<NSString *, id> *MTIAVVideoColorPropertiesForHDRContentType(MTIHDRContentType contentType) {
    switch (contentType) {
        case MTIHDRContentTypeHDR_PQ:
            return @{
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_SMPTE_ST_2084_PQ,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020
            };
        case MTIHDRContentTypeHDR_HLG:
            return @{
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020
            };
        case MTIHDRContentTypeSDR:
            return @{
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            };
        case MTIHDRContentTypeExtendedSDR:
            if (@available(iOS 16.0, tvOS 16.0, macOS 13.0, macCatalyst 16.0, *)) {
                return @{
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_P3_D65,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_Linear,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
                };
            }
            return @{
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_P3_D65,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            };
        case MTIHDRContentTypeLog_Apple:
        case MTIHDRContentTypeLog_AppleLog2:
        case MTIHDRContentTypeLog_Other:
        case MTIHDRContentTypeUnknown:
            return nil;
    }
}

AVVideoCodecType MTIAVVideoCodecTypeForProResProfile(MTIProResProfile profile) {
    switch (profile) {
        case MTIProResProfile422:
            return AVVideoCodecTypeAppleProRes422;
        case MTIProResProfile422LT:
            return AVVideoCodecTypeAppleProRes422LT;
        case MTIProResProfile422HQ:
            return AVVideoCodecTypeAppleProRes422HQ;
        case MTIProResProfile422Proxy:
            return AVVideoCodecTypeAppleProRes422Proxy;
        case MTIProResProfile4444:
            return AVVideoCodecTypeAppleProRes4444;
    }
}

NSDictionary<NSString *, id> *MTIAVAssetWriterVideoSettingsForProRes(CGSize size,
                                                                     MTIProResProfile profile,
                                                                     MTIHDRContentType contentType) {
    NSMutableDictionary<NSString *, id> *settings = [@{
        AVVideoCodecKey: MTIAVVideoCodecTypeForProResProfile(profile),
        AVVideoWidthKey: @((NSInteger)llround(size.width)),
        AVVideoHeightKey: @((NSInteger)llround(size.height))
    } mutableCopy];
    NSDictionary<NSString *, id> *colorProperties = MTIAVVideoColorPropertiesForHDRContentType(contentType);
    if (colorProperties) {
        settings[AVVideoColorPropertiesKey] = colorProperties;
    }
    return settings;
}

NSDictionary<NSString *, id> *MTIAVAssetWriterInputPixelBufferAttributesForProRes(CGSize size,
                                                                                  MTIHDRContentType contentType) {
    OSType pixelFormatType = MTIHDRContentTypeIsHighDynamicRange(contentType) ? kCVPixelFormatType_64RGBAHalf : kCVPixelFormatType_32BGRA;
    return @{
        (id)kCVPixelBufferPixelFormatTypeKey: @(pixelFormatType),
        (id)kCVPixelBufferWidthKey: @((NSInteger)llround(size.width)),
        (id)kCVPixelBufferHeightKey: @((NSInteger)llround(size.height)),
        (id)kCVPixelBufferMetalCompatibilityKey: @YES,
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };
}

void MTIApplyHDRContentMetadataToCVPixelBuffer(CVPixelBufferRef pixelBuffer, MTIHDRContentType contentType) {
    if (pixelBuffer == NULL) {
        return;
    }
    switch (contentType) {
        case MTIHDRContentTypeHDR_PQ:
            CVBufferSetAttachment(pixelBuffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_2020, kCVAttachmentMode_ShouldPropagate);
            CVBufferSetAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ, kCVAttachmentMode_ShouldPropagate);
            CVBufferSetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_2020, kCVAttachmentMode_ShouldPropagate);
            break;
        case MTIHDRContentTypeHDR_HLG:
            CVBufferSetAttachment(pixelBuffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_2020, kCVAttachmentMode_ShouldPropagate);
            CVBufferSetAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_2100_HLG, kCVAttachmentMode_ShouldPropagate);
            CVBufferSetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_2020, kCVAttachmentMode_ShouldPropagate);
            break;
        case MTIHDRContentTypeLog_Apple:
            CVBufferSetAttachment(pixelBuffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_2020, kCVAttachmentMode_ShouldPropagate);
            CVBufferSetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_2020, kCVAttachmentMode_ShouldPropagate);
            if (@available(iOS 17.2, tvOS 17.2, macOS 14.2, macCatalyst 17.2, *)) {
                CVBufferSetAttachment(pixelBuffer, kCVImageBufferLogTransferFunctionKey, kCVImageBufferLogTransferFunction_AppleLog, kCVAttachmentMode_ShouldPropagate);
            }
            break;
        case MTIHDRContentTypeLog_AppleLog2:
            CVBufferSetAttachment(pixelBuffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_2020, kCVAttachmentMode_ShouldPropagate);
            CVBufferSetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_2020, kCVAttachmentMode_ShouldPropagate);
            if (@available(iOS 26.0, tvOS 26.0, macOS 26.0, macCatalyst 26.0, *)) {
                CVBufferSetAttachment(pixelBuffer, kCVImageBufferLogTransferFunctionKey, kCVImageBufferLogTransferFunction_AppleLog2, kCVAttachmentMode_ShouldPropagate);
            }
            break;
        case MTIHDRContentTypeExtendedSDR:
            if (@available(iOS 16.0, tvOS 16.0, macOS 13.0, macCatalyst 16.0, *)) {
                CVBufferSetAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_Linear, kCVAttachmentMode_ShouldPropagate);
            }
            break;
        case MTIHDRContentTypeSDR:
            CVBufferSetAttachment(pixelBuffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
            CVBufferSetAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
            CVBufferSetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
            break;
        case MTIHDRContentTypeLog_Other:
        case MTIHDRContentTypeUnknown:
            break;
    }
}
