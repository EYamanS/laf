// LAF OS Library
// Copyright (C) 2026  Emir Yaman Sivrikaya
//
// This file is released under the terms of the MIT license.
// Read LICENSE.txt for more information.

#ifdef HAVE_CONFIG_H
  #include "config.h"
#endif

#include "os/skia/skia_window_ios.h"

#include "gfx/region.h"
#include "os/ios/view.h"
#include "os/skia/skia_surface.h"

#include "include/utils/mac/SkCGUtils.h"

#include <CoreGraphics/CoreGraphics.h>
#include <UIKit/UIKit.h>

namespace os {

SkiaWindowIOS::SkiaWindowIOS(const WindowSpec& spec)
{
  createWindow(spec);
  initColorSpace();
}

SkiaWindowIOS::~SkiaWindowIOS()
{
  destroyWindow();
}

void SkiaWindowIOS::invalidateRegion(const gfx::Region& rgn)
{
  // The whole surface is copied to the CALayer the next time the
  // event queue is checked (when the app finishes painting).
  if (m_view)
    [m_view setNeedsPresent];
}

void SkiaWindowIOS::setTextInput(bool state, const gfx::Point& screenCaretPos)
{
  setTextInputMode(state);
}

void SkiaWindowIOS::onPresent()
{
  if (!m_view || !isInitialized())
    return;

  SkiaSurface* surface = static_cast<SkiaSurface*>(this->surface());
  if (!surface || !surface->isValid())
    return;

  const SkBitmap& bitmap = surface->bitmap();
  const int w = bitmap.width();
  const int h = bitmap.height();
  if (w <= 0 || h <= 0 || !bitmap.getPixels())
    return;

  CGBitmapInfo info = 0;
  switch (bitmap.colorType()) {
    case kRGBA_8888_SkColorType:
      info = kCGBitmapByteOrder32Big | kCGImageAlphaNoneSkipLast;
      break;
    case kBGRA_8888_SkColorType:
      info = kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst;
      break;
    default: break;
  }

  @autoreleasepool {
    CGImageRef img = nullptr;
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);

    if (info != 0) {
      // Copy the pixels so the app can continue painting in the
      // surface while CoreAnimation uses this image.
      CFDataRef data = CFDataCreate(kCFAllocatorDefault,
                                    (const UInt8*)bitmap.getPixels(),
                                    bitmap.rowBytes() * h);
      if (data) {
        CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
        if (provider) {
          img = CGImageCreate(w,
                              h,
                              8,
                              32,
                              bitmap.rowBytes(),
                              cs,
                              info,
                              provider,
                              nullptr,
                              false,
                              kCGRenderingIntentDefault);
          CGDataProviderRelease(provider);
        }
        CFRelease(data);
      }
    }
    else {
      img = SkCreateCGImageRefWithColorspace(bitmap, cs);
    }

    if (img) {
      [m_view presentImage:img surfaceSize:gfx::Size(w, h) scale:scale()];
      CGImageRelease(img);
    }
    CGColorSpaceRelease(cs);
  }
}

} // namespace os
