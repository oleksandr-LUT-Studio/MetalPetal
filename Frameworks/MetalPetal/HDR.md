# MetalPetal HDR / Log Support

End-to-end plan and changes for adding HDR (PQ / HLG) and Log (Apple Log, S-Log, V-Log, ARRI LogC,
Canon C-Log) support to MetalPetal. Branch: `HDR-input-output-fix`.

## Problem

MetalPetal forces all inputs and outputs to 8-bit SDR at every decision point. HDR / 10-bit / Log
content gets truncated to `MTLPixelFormatBGRA8Unorm` + sRGB, with visible banding and clipped
highlights.

The root cause is hardcoded SDR defaults in seven places:

1. `MTIContext.workingPixelFormat = MTLPixelFormatBGRA8Unorm` (every kernel fallback).
2. `MTICVPixelBufferPromise` maps 10-bit YUV (`x420`/`xf20`) → `MTLPixelFormatBGRA8Unorm`.
3. `MTITextureLoader` forces every loaded `CGImage` through an sRGB / 8-bit `kCVPixelFormatType_32BGRA` buffer.
4. `MTIContext+Rendering` CGImage/CVPixelBuffer export creates `kCVPixelFormatType_32BGRA` only.
5. `MTICIImageRenderingOptions` defaults pixel format to `BGRA8Unorm` + `CGColorSpaceCreateDeviceRGB`.
6. `MTIImageView` / `MTIThreadSafeImageView` never set `wantsExtendedDynamicRangeContent` or wide-gamut layer format.
7. `MTIVideoComposition` advertises only 8-bit YUV / BGRA in its source & output pixel-format lists.

This document describes the end-to-end fix.

---

## Public API additions

### `MTIHDRDetection.h` — new

Classification helper used at every input boundary. Pure C function, no allocations on the hot path
beyond CF/CG calls.

```objc
typedef NS_ENUM(NSInteger, MTIHDRContentType) {
    MTIHDRContentTypeUnknown,       // could not classify — treat as SDR
    MTIHDRContentTypeSDR,           // Rec.709 / sRGB / DisplayP3 gamma
    MTIHDRContentTypeExtendedSDR,   // wide-gamut linear, extendedSRGB, scRGB
    MTIHDRContentTypeHDR_PQ,        // SMPTE ST 2084
    MTIHDRContentTypeHDR_HLG,       // ITU-R BT.2100 HLG
    MTIHDRContentTypeLog_Apple,     // Apple Log (iOS 17+)
    MTIHDRContentTypeLog_Other      // heuristic — third-party Log
};

BOOL MTIHDRContentTypeIsHighDynamicRange(MTIHDRContentType);
MTIHDRContentType MTIHDRContentTypeFromCVPixelBuffer(CVPixelBufferRef);
MTIHDRContentType MTIHDRContentTypeFromCGColorSpace(CGColorSpaceRef, size_t bpc, BOOL floatComponents);
MTIHDRContentType MTIHDRContentTypeFromAVAssetTrack(AVAssetTrack *);
MTLPixelFormat   MTIRecommendedMTLPixelFormatForHDRContentType(MTIHDRContentType);
CGColorSpaceRef  MTIRecommendedCGColorSpaceForHDRContentType(MTIHDRContentType) CF_RETURNS_RETAINED;
```

Detection sources:

| Input | What is read |
|---|---|
| `CVPixelBuffer` | `kCVImageBufferTransferFunctionKey`, `kCVImageBufferColorPrimariesKey`, pixel format type |
| `CGColorSpace` | `CGColorSpaceUsesITUR_2100TF` (iOS 14+), `CGColorSpaceIsHDR`, `CGColorSpaceGetName`, bpc + float flag |
| `AVAssetTrack` | `CMFormatDescriptionExtension_TransferFunction`, `CMFormatDescriptionExtension_ColorPrimaries`, `AVMediaCharacteristicContainsHDRVideo` |

Recognized transfer-function constants:
`kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ`,
`kCVImageBufferTransferFunction_ITU_R_2100_HLG`,
`kCVImageBufferTransferFunction_Linear`,
`kCVImageBufferTransferFunction_AppleLog` (iOS 17+).

Recognized CG colorspace names:
`kCGColorSpaceITUR_2100_PQ`, `kCGColorSpaceITUR_2100_HLG`,
`kCGColorSpaceDisplayP3_PQ`, `kCGColorSpaceDisplayP3_HLG`,
`kCGColorSpaceExtendedLinearSRGB`, `kCGColorSpaceExtendedSRGB`,
`kCGColorSpaceExtendedLinearDisplayP3`, `kCGColorSpaceExtendedLinearITUR_2020`.

### `MTIImageProperties`

```objc
@property (nonatomic, readonly) MTIHDRContentType hdrContentType;
```

Computed lazily from the `CGColorSpace` already retained by `MTIImageProperties`, combined with
`bitsPerComponent` and `floatComponents`. Zero extra storage.

### `MTIContextOptions` / `MTIContext`

```objc
// MTIContextOptions
@property (nonatomic) MTLPixelFormat workingPixelFormat;   // now documented for HDR usage
@property (nonatomic) BOOL preservesHDRContent;            // new; default NO

// MTIContext (readonly mirror)
@property (nonatomic, readonly) BOOL preservesHDRContent;
```

Setting `workingPixelFormat = MTLPixelFormatRGBA16Float` causes every kernel fallback to render
into RGBA16Float instead of BGRA8Unorm. Setting `preservesHDRContent = YES` causes input loaders
(CGImage / CVPixelBuffer / texture loader) to detect HDR/Log and load into RGBA16Float with the
source colorspace preserved rather than forcing through 8-bit sRGB.

The two flags are independent. Most HDR pipelines want both YES.

---

## Implementation status

### Completed

| File | Change |
|---|---|
| `Core/MTIHDRDetection.h` (new) | Detection enum + functions. |
| `Core/MTIHDRDetection.m` (new) | Implementation; uses `CVBufferGetAttachment`, `CGColorSpaceUsesITUR_2100TF`, `CMFormatDescriptionGetExtensions`. |
| `Core/MetalPetal.h` | Added `#import "MTIHDRDetection.h"` to umbrella. |
| `Core/MTIImageProperties.h` | Imports MTIHDRDetection; added `hdrContentType` property. |
| `Core/MTIImageProperties.m` | `hdrContentType` reads CGColorSpace + bpc + floatComponents. |
| `Core/MTIContext.h` (`MTIContextOptions`) | Added documentation to `workingPixelFormat`; added `preservesHDRContent` property. |

### Pending wiring (apply the patches below)

| File | Status | Why |
|---|---|---|
| `Core/MTIContext.h` `MTIContext` interface | Add `preservesHDRContent` readonly | Mirror the option. |
| `Core/MTIContext.m` | Init from options + `copyWithZone:` | Persist the new flag. |
| `Core/MTICVPixelBufferPromise.m` | 10-bit YUV HDR → `RGBA16Float` | Stops 10-bit input being clipped to 8-bit. |
| `Core/MTITextureLoader.m` | Preserve source colorspace; `RGBA16Float` for HDR | Stops every CGImage being forced into sRGB. |
| `Core/MTIImagePromise.m` | Same as TextureLoader | Same chokepoint, alternate path. |
| `Core/MTIContext+Rendering.m/.h` | Accept HDR pixel-buffer formats; pass colorspace | Stops CGImage export being 32BGRA. |
| `Core/MTICoreImageRendering.h/.m` | HDR-aware defaults | Stops CI output being DeviceRGB. |
| `Core/UI/MTIImageView.h/.m` | `wantsExtendedDynamicRangeContent` | Display path enables EDR. |
| `Core/UI/MTIThreadSafeImageView.h/.m` | `wantsExtendedDynamicRangeContent` | Same. |
| `Swift/MTIVideoComposition.swift` | Include 10-bit YUV + RGBA16Float in source/output lists | Stops AVFoundation negotiating 8-bit. |

---

## Patches for the pending wiring

### 1. `MTIContext.h` (readonly on the context)

```diff
 @property (nonatomic, readonly) MTLPixelFormat workingPixelFormat;
+
+/// Mirrors `MTIContextOptions.preservesHDRContent`.
+@property (nonatomic, readonly) BOOL preservesHDRContent;

 @property (nonatomic, readonly) BOOL isRenderGraphOptimizationEnabled;
```

### 2. `MTIContext.m`

```diff
 - (instancetype)init {
     if (self = [super init]) {
         _coreImageContextOptions = nil;
         _workingPixelFormat = MTLPixelFormatBGRA8Unorm;
+        _preservesHDRContent = NO;
         _enablesRenderGraphOptimization = NO;
```

```diff
 - (id)copyWithZone:(NSZone *)zone {
     ...
     options.workingPixelFormat = _workingPixelFormat;
+    options.preservesHDRContent = _preservesHDRContent;
     options.enablesRenderGraphOptimization = _enablesRenderGraphOptimization;
```

```diff
 _label = options.label;
 _workingPixelFormat = options.workingPixelFormat;
+_preservesHDRContent = options.preservesHDRContent;
 _isRenderGraphOptimizationEnabled = options.enablesRenderGraphOptimization;
```

### 3. `MTICVPixelBufferPromise.m`

Goal: when `preservesHDRContent == YES` AND the buffer is 10-bit YUV with an HDR transfer function,
render the YCbCr → RGB conversion into RGBA16Float instead of BGRA8Unorm.

Add at top:
```objc
#import "MTIHDRDetection.h"
```

Replace the fallback color-conversion render target at the line marked
`// Render Pipeline\nMTLPixelFormat pixelFormat = MTLPixelFormatBGRA8Unorm;` with:

```objc
MTLPixelFormat pixelFormat = MTLPixelFormatBGRA8Unorm;
if (renderingContext.context.preservesHDRContent &&
    MTIHDRContentTypeIsHighDynamicRange(MTIHDRContentTypeFromCVPixelBuffer(self.pixelBuffer))) {
    pixelFormat = MTLPixelFormatRGBA16Float;
}
```

Also update `MTIMTLPixelFormatForCVPixelFormatType` so the `kCVPixelFormatType_420YpCbCr10*`
cases can return `RGBA16Float` when HDR is detected. Because that function is `static` and called
from the designated initializer where the context isn't reachable, the cleanest approach is to
keep the function and add an HDR variant called by both `resolveWithContext_MTI` and
`coreImageRendererDefaultTextureDescriptor` lazy creation. The simpler short-term fix is to leave
the texture descriptor at BGRA8Unorm for the legacy CI path and only upgrade the MTI render path
as above; this keeps backward behavior for the CI fallback and unblocks HDR for the common case.

### 4. `MTITextureLoader.m`

Goal: when `preservesHDRContent` is set on the context (the loader does not see the context
directly, so the gating uses the image's `hdrContentType` only) and the source CGImage is HDR /
Log / extended-range, draw into an RGBA16Float `CGBitmapContext` with the image's actual
colorspace.

Replace lines 66–93:

```objc
MTIHDRContentType hdrType = properties.hdrContentType;
BOOL useHDR = MTIHDRContentTypeIsHighDynamicRange(hdrType);

OSType cvFormat = useHDR ? kCVPixelFormatType_64RGBAHalf : kCVPixelFormatType_32BGRA;
CVPixelBufferRef pixelBuffer = nil;
CVPixelBufferCreate(kCFAllocatorDefault,
                    properties.displayWidth,
                    properties.displayHeight,
                    cvFormat,
                    (__bridge CFDictionaryRef)@{(id)kCVPixelBufferIOSurfacePropertiesKey: @{}},
                    &pixelBuffer);
// ...

CGColorSpaceRef colorSpace = useHDR
    ? MTIRecommendedCGColorSpaceForHDRContentType(hdrType)
    : CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
if (!colorSpace) {
    colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
}

CGBitmapInfo bitmapInfo = useHDR
    ? (kCGBitmapByteOrder16Little | kCGBitmapFloatComponents | kCGImageAlphaPremultipliedLast)
    : (kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
size_t bpc = useHDR ? 16 : 8;

CGContextRef cgContext = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pixelBuffer),
                                               properties.displayWidth,
                                               properties.displayHeight,
                                               bpc,
                                               CVPixelBufferGetBytesPerRow(pixelBuffer),
                                               colorSpace,
                                               bitmapInfo);
```

And update the texture descriptor at line 151:

```objc
MTLPixelFormat textureFormat;
if (useHDR) {
    textureFormat = MTLPixelFormatRGBA16Float;
} else {
    textureFormat = useSRGBTexture ? MTLPixelFormatBGRA8Unorm_sRGB : MTLPixelFormatBGRA8Unorm;
}
MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor
    texture2DDescriptorWithPixelFormat:textureFormat
    width:CVPixelBufferGetWidth(pixelBuffer)
    height:CVPixelBufferGetHeight(pixelBuffer)
    mipmapped:NO];
```

### 5. `MTIImagePromise.m`

Same idea as TextureLoader for the `MTICGImagePromise.resolveWithContext` path
(lines 233–294). Inspect `_properties.hdrContentType`; when HDR, allocate a
`kCVPixelFormatType_64RGBAHalf` buffer with the recommended colorspace and a 16-bpc float
bitmap context, then create the texture as `MTLPixelFormatRGBA16Float`.

### 6. `MTIContext+Rendering.m`

The CGImage export pair at lines 335 and 368 hardcodes `kCVPixelFormatType_32BGRA`. Add an
overload taking an explicit pixel format + colorspace:

```objc
// MTIContext+Rendering.h additions
- (nullable CGImageRef)createCGImageFromImage:(MTIImage *)image
                                  pixelFormat:(OSType)cvPixelFormat
                                   colorSpace:(nullable CGColorSpaceRef)colorSpace
                                        error:(NSError **)error CF_RETURNS_RETAINED;

- (nullable MTIRenderTask *)startTaskToCreateCGImage:(CF_RETURNS_RETAINED CGImageRef * __nonnull)outImage
                                            fromImage:(MTIImage *)image
                                          pixelFormat:(OSType)cvPixelFormat
                                           colorSpace:(nullable CGColorSpaceRef)colorSpace
                                                error:(NSError **)error
                                           completion:(nullable void (^)(MTIRenderTask *))completion;
```

Implementation reuses the existing logic but takes `cvPixelFormat` (e.g.
`kCVPixelFormatType_64RGBAHalf`) and the colorspace from the caller. The 16Float/32Float branches
already exist in `startTaskToRenderImage:toCVPixelBuffer:` at lines 196–201, so they just need to
be reachable from the CGImage export path.

### 7. `MTICoreImageRendering.h/.m`

Add an HDR-aware default:

```objc
@interface MTICIImageRenderingOptions (HDR)
+ (MTICIImageRenderingOptions *)HDRDefaultOptions;
@end
```

```objc
+ (MTICIImageRenderingOptions *)HDRDefaultOptions {
    static MTICIImageRenderingOptions *opts;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CGColorSpaceRef cs = NULL;
        if (@available(iOS 14.0, tvOS 14.0, macOS 11.0, macCatalyst 14.0, *)) {
            cs = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearSRGB);
        }
        opts = [[MTICIImageRenderingOptions alloc]
                initWithDestinationPixelFormat:MTLPixelFormatRGBA16Float
                colorSpace:cs
                flipped:YES];
        if (cs) CGColorSpaceRelease(cs);
    });
    return opts;
}
```

### 8. `MTIImageView.h/.m` and `MTIThreadSafeImageView.h/.m`

Add a property that forwards through to `CAMetalLayer.wantsExtendedDynamicRangeContent`. Note: only
available on `CAMetalLayer`, iOS 16+ / macOS 10.11+.

```objc
// MTIImageView.h additions
@property (nonatomic) BOOL wantsExtendedDynamicRangeContent API_AVAILABLE(ios(16.0), macCatalyst(16.0), tvos(16.0), macos(10.11));
@property (nonatomic, nullable) CGColorSpaceRef colorSpace;
```

```objc
// MTIImageView.m
- (void)setWantsExtendedDynamicRangeContent:(BOOL)edr {
    MTKView *renderView = _renderView;
    if ([renderView.layer isKindOfClass:CAMetalLayer.class]) {
        CAMetalLayer *layer = (CAMetalLayer *)renderView.layer;
        if (@available(iOS 16.0, macCatalyst 16.0, tvOS 16.0, macOS 10.11, *)) {
            layer.wantsExtendedDynamicRangeContent = edr;
        }
    }
    [self setNeedsRedraw];
}

- (void)setColorSpace:(CGColorSpaceRef)colorSpace {
    MTKView *renderView = _renderView;
    if ([renderView.layer isKindOfClass:CAMetalLayer.class]) {
        ((CAMetalLayer *)renderView.layer).colorspace = colorSpace;
        [self setNeedsRedraw];
    }
}
```

`MTIThreadSafeImageView` already exposes `colorSpace`; add `wantsExtendedDynamicRangeContent`
following the same locked pattern as `setColorPixelFormat:`.

Recommended caller usage for HDR display:
```objc
imageView.colorPixelFormat = MTLPixelFormatRGBA16Float;
imageView.colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearSRGB);
imageView.wantsExtendedDynamicRangeContent = YES;
```

### 9. `MTIVideoComposition.swift`

Replace the two lines at 267–269:

```swift
let sourcePixelBufferAttributes: [String : Any]? = [
    kCVPixelBufferPixelFormatTypeKey as String: [
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
        kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
        kCVPixelFormatType_32BGRA,
        kCVPixelFormatType_64RGBAHalf,
    ]
]

let requiredPixelBufferAttributesForRenderContext: [String : Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
]
```

The render context format stays 32BGRA when SDR; an HDR variant
`MTIVideoComposition.makeHDRAVVideoComposition()` should set the render context format to
`kCVPixelFormatType_64RGBAHalf` and set `colorPrimaries` / `colorTransferFunction` to BT.2020 / HLG
or PQ as appropriate.

---

## Recommended usage

### Static image, HDR throughput end-to-end

```objc
MTIContextOptions *options = [[MTIContextOptions alloc] init];
options.workingPixelFormat = MTLPixelFormatRGBA16Float;
options.preservesHDRContent = YES;
MTIContext *context = [[MTIContext alloc] initWithDevice:device options:options error:&error];

// Loading an HDR HEIC keeps its colorspace.
MTIImage *input = [[MTIImage alloc] initWithCGImage:hdrCGImage];

// Render to a 64-bit half-float CGImage with the source colorspace.
CGImageRef out = [context createCGImageFromImage:filteredImage
                                     pixelFormat:kCVPixelFormatType_64RGBAHalf
                                      colorSpace:input.properties.colorSpace
                                           error:&error];
```

### Video frame, PQ input → HDR display

```objc
CVPixelBufferRef frame = ...;   // 10-bit BT.2020 PQ
MTIHDRContentType t = MTIHDRContentTypeFromCVPixelBuffer(frame);  // → MTIHDRContentTypeHDR_PQ
MTIImage *image = [[MTIImage alloc] initWithCVPixelBuffer:frame alphaType:MTIAlphaTypeAlphaIsOne];

imageView.colorPixelFormat = MTLPixelFormatRGBA16Float;
imageView.wantsExtendedDynamicRangeContent = YES;
imageView.image = filtered;
```

### Apple Log video frame

```swift
let t = MTIHDRContentTypeFromAVAssetTrack(videoTrack)
// → .Log_Apple on iOS 17+ when the asset is Apple Log
```

---

## Backward compatibility

- All new properties default to the old behavior (`preservesHDRContent = NO`,
  `workingPixelFormat = BGRA8Unorm`). Existing code paths are unchanged.
- New methods on `MTIContext+Rendering` are additions, not replacements; the old
  `createCGImageFromImage:` signatures are untouched.
- The detector functions are pure — calling them from third-party code is safe.
- `MTIImageProperties.hdrContentType` is a derived computed property and adds no storage cost.

## Why these specific points

The complete SDR-truncation chain identified during the diagnostic phase was:

```
input → MTICVPixelBufferPromise (case x420/xf20 → BGRA8Unorm)
input → MTITextureLoader (32BGRA + kCGColorSpaceSRGB)
input → MTIImagePromise (32BGRA + DeviceRGB)
working → MTIContext.workingPixelFormat (BGRA8Unorm)
working → MTIRenderPipelineKernel / MPSKernel / ComputeKernel / MultilayerCompositeKernel (workingPixelFormat fallback)
working → MTICoreImageRendering (BGRA8Unorm + DeviceRGB)
output → MTIContext+Rendering CGImage paths (32BGRA only)
display → MTIImageView / MTIThreadSafeImageView (no EDR layer flags)
video  → MTIVideoComposition (8-bit YUV / 32BGRA only)
```

The fixes here cut HDR loss at every point in this chain by:

- Detecting HDR/Log on input (`MTIHDRDetection`).
- Selecting `RGBA16Float` + the source colorspace when HDR is detected (input loaders).
- Letting callers set the working format to `RGBA16Float` via `MTIContextOptions`.
- Letting callers request HDR pixel formats and colorspaces on export.
- Letting callers enable `wantsExtendedDynamicRangeContent` on display views.

No filter math is altered; the fixes are purely about pixel format and colorspace selection.
