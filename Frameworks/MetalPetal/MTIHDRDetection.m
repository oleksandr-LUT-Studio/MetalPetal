//
//  MTIHDRDetection.m
//  MetalPetal
//

#import "MTIHDRDetection.h"
#import <CoreMedia/CoreMedia.h>

BOOL MTIHDRContentTypeIsHighDynamicRange(MTIHDRContentType type) {
    switch (type) {
        case MTIHDRContentTypeUnknown:
        case MTIHDRContentTypeSDR:
            return NO;
        case MTIHDRContentTypeExtendedSDR:
        case MTIHDRContentTypeHDR_PQ:
        case MTIHDRContentTypeHDR_HLG:
        case MTIHDRContentTypeLog_Apple:
        case MTIHDRContentTypeLog_AppleLog2:
        case MTIHDRContentTypeLog_Other:
            return YES;
    }
}

static MTIHDRContentType MTIHDRContentTypeFromCVTransferFunctionString(CFStringRef tf) {
    if (tf == NULL) {
        return MTIHDRContentTypeUnknown;
    }
    if (CFEqual(tf, kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ)) {
        return MTIHDRContentTypeHDR_PQ;
    }
    if (CFEqual(tf, kCVImageBufferTransferFunction_ITU_R_2100_HLG)) {
        return MTIHDRContentTypeHDR_HLG;
    }
    if (CFEqual(tf, kCVImageBufferTransferFunction_Linear)) {
        return MTIHDRContentTypeExtendedSDR;
    }
    return MTIHDRContentTypeUnknown;
}

static MTIHDRContentType MTIHDRContentTypeFromCVLogTransferFunctionString(CFStringRef logTF) {
    if (logTF == NULL) {
        return MTIHDRContentTypeUnknown;
    }
    if (@available(iOS 17.2, tvOS 17.2, macOS 14.2, macCatalyst 17.2, *)) {
        if (CFEqual(logTF, kCVImageBufferLogTransferFunction_AppleLog)) {
            return MTIHDRContentTypeLog_Apple;
        }
    }
    if (@available(iOS 26.0, tvOS 26.0, macOS 26.0, macCatalyst 26.0, *)) {
        if (CFEqual(logTF, kCVImageBufferLogTransferFunction_AppleLog2)) {
            return MTIHDRContentTypeLog_AppleLog2;
        }
    }
    return MTIHDRContentTypeLog_Other;
}

MTIHDRContentType MTIHDRContentTypeFromCVPixelBuffer(CVPixelBufferRef pixelBuffer) {
    if (pixelBuffer == NULL) {
        return MTIHDRContentTypeUnknown;
    }
    CFTypeRef tf = CVBufferGetAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey, NULL);
    MTIHDRContentType detected = MTIHDRContentTypeFromCVTransferFunctionString((CFStringRef)tf);
    if (detected != MTIHDRContentTypeUnknown) {
        return detected;
    }
    if (@available(iOS 17.2, tvOS 17.2, macOS 14.2, macCatalyst 17.2, *)) {
        CFTypeRef logTF = CVBufferGetAttachment(pixelBuffer, kCVImageBufferLogTransferFunctionKey, NULL);
        if (logTF != NULL) {
            return MTIHDRContentTypeFromCVLogTransferFunctionString((CFStringRef)logTF);
        }
    }
    CFTypeRef primaries = CVBufferGetAttachment(pixelBuffer, kCVImageBufferColorPrimariesKey, NULL);
    if (primaries != NULL && CFEqual(primaries, kCVImageBufferColorPrimaries_ITU_R_2020)) {
        // BT.2020 primaries without explicit transfer — assume HLG by convention used by AVFoundation capture.
        return MTIHDRContentTypeHDR_HLG;
    }
    OSType type = CVPixelBufferGetPixelFormatType(pixelBuffer);
    switch (type) {
        case kCVPixelFormatType_64RGBAHalf:
        case kCVPixelFormatType_128RGBAFloat:
            return MTIHDRContentTypeExtendedSDR;
        default:
            return MTIHDRContentTypeSDR;
    }
}

MTIHDRContentType MTIHDRContentTypeFromCGColorSpace(CGColorSpaceRef colorSpace,
                                                   size_t bitsPerComponent,
                                                   BOOL floatComponents) {
    if (colorSpace == NULL) {
        return MTIHDRContentTypeUnknown;
    }
    if (@available(iOS 14.0, tvOS 14.0, macOS 11.0, macCatalyst 14.0, *)) {
        if (CGColorSpaceUsesITUR_2100TF(colorSpace)) {
            CFStringRef name = CGColorSpaceGetName(colorSpace);
            if (name) {
                if (CFEqual(name, kCGColorSpaceITUR_2100_PQ) ||
                    CFEqual(name, kCGColorSpaceDisplayP3_PQ)) {
                    return MTIHDRContentTypeHDR_PQ;
                }
                if (CFEqual(name, kCGColorSpaceITUR_2100_HLG) ||
                    CFEqual(name, kCGColorSpaceDisplayP3_HLG)) {
                    return MTIHDRContentTypeHDR_HLG;
                }
            }
            return MTIHDRContentTypeHDR_PQ;
        }
        if (CGColorSpaceIsHDR(colorSpace)) {
            return MTIHDRContentTypeHDR_PQ;
        }
    }
    CFStringRef name = NULL;
    if (@available(iOS 10.0, tvOS 10.0, macOS 10.12, *)) {
        name = CGColorSpaceGetName(colorSpace);
    }
    if (name) {
        if (CFEqual(name, kCGColorSpaceExtendedLinearSRGB) ||
            CFEqual(name, kCGColorSpaceExtendedSRGB) ||
            CFEqual(name, kCGColorSpaceExtendedLinearDisplayP3) ||
            CFEqual(name, kCGColorSpaceExtendedLinearITUR_2020)) {
            return MTIHDRContentTypeExtendedSDR;
        }
    }
    if (floatComponents && bitsPerComponent >= 16) {
        return MTIHDRContentTypeExtendedSDR;
    }
    return MTIHDRContentTypeSDR;
}

MTIHDRContentType MTIHDRContentTypeFromAVAssetTrack(AVAssetTrack *track) {
    if (track == nil) {
        return MTIHDRContentTypeUnknown;
    }
    if (@available(iOS 14.0, tvOS 14.0, macOS 11.0, macCatalyst 14.0, *)) {
        if ([track hasMediaCharacteristic:AVMediaCharacteristicContainsHDRVideo]) {
            // Drill into format descriptions to distinguish PQ vs HLG vs Log.
        }
    }
    NSArray *formatDescriptions = track.formatDescriptions;
    for (id obj in formatDescriptions) {
        CMFormatDescriptionRef desc = (__bridge CMFormatDescriptionRef)obj;
        CFDictionaryRef ext = CMFormatDescriptionGetExtensions(desc);
        if (ext == NULL) {
            continue;
        }
        CFTypeRef tf = CFDictionaryGetValue(ext, kCMFormatDescriptionExtension_TransferFunction);
        MTIHDRContentType detected = MTIHDRContentTypeFromCVTransferFunctionString((CFStringRef)tf);
        if (detected != MTIHDRContentTypeUnknown) {
            return detected;
        }
        if (@available(iOS 17.2, tvOS 17.2, macOS 14.2, macCatalyst 17.2, *)) {
            CFTypeRef logTF = CFDictionaryGetValue(ext, kCMFormatDescriptionExtension_LogTransferFunction);
            if (logTF != NULL) {
                return MTIHDRContentTypeFromCVLogTransferFunctionString((CFStringRef)logTF);
            }
        }
        CFTypeRef primaries = CFDictionaryGetValue(ext, kCMFormatDescriptionExtension_ColorPrimaries);
        if (primaries != NULL && CFEqual(primaries, kCVImageBufferColorPrimaries_ITU_R_2020)) {
            return MTIHDRContentTypeHDR_HLG;
        }
    }
    if (@available(iOS 14.0, tvOS 14.0, macOS 11.0, macCatalyst 14.0, *)) {
        if ([track hasMediaCharacteristic:AVMediaCharacteristicContainsHDRVideo]) {
            return MTIHDRContentTypeHDR_HLG;
        }
    }
    return MTIHDRContentTypeUnknown;
}

MTLPixelFormat MTIRecommendedMTLPixelFormatForHDRContentType(MTIHDRContentType type) {
    if (MTIHDRContentTypeIsHighDynamicRange(type)) {
        return MTLPixelFormatRGBA16Float;
    }
    return MTLPixelFormatBGRA8Unorm;
}

CGColorSpaceRef MTIRecommendedCGColorSpaceForHDRContentType(MTIHDRContentType type) {
    if (@available(iOS 14.0, tvOS 14.0, macOS 11.0, macCatalyst 14.0, *)) {
        switch (type) {
            case MTIHDRContentTypeHDR_PQ:
                return CGColorSpaceCreateWithName(kCGColorSpaceITUR_2100_PQ);
            case MTIHDRContentTypeHDR_HLG:
                return CGColorSpaceCreateWithName(kCGColorSpaceITUR_2100_HLG);
            case MTIHDRContentTypeLog_Apple:
            case MTIHDRContentTypeLog_AppleLog2:
                return CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearITUR_2020);
            case MTIHDRContentTypeExtendedSDR:
                return CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearSRGB);
            case MTIHDRContentTypeLog_Other:
                return CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearITUR_2020);
            case MTIHDRContentTypeSDR:
                return CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            case MTIHDRContentTypeUnknown:
                return NULL;
        }
    }
    if (type == MTIHDRContentTypeSDR) {
        return CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    }
    return NULL;
}
