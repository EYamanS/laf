// LAF OS Library
// Copyright (C) 2026  Emir Yaman Sivrikaya
//
// This file is released under the terms of the MIT license.
// Read LICENSE.txt for more information.

#ifndef OS_SKIA_SKIA_WINDOW_IOS_INCLUDED
#define OS_SKIA_SKIA_WINDOW_IOS_INCLUDED
#pragma once

#include "base/disable_copying.h"
#include "os/ios/window.h"
#include "os/skia/skia_window_base.h"

#include <string>

namespace os {

class SkiaWindowIOS : public SkiaWindowBase<WindowIOS> {
public:
  SkiaWindowIOS(const WindowSpec& spec);
  ~SkiaWindowIOS();

  void invalidateRegion(const gfx::Region& rgn) override;

  std::string getLayout() override { return ""; }
  void setLayout(const std::string& layout) override {}
  void setTextInput(bool state, const gfx::Point& screenCaretPos = {});

  // WindowIOS overrides
  void onPresent() override;

private:
  DISABLE_COPYING(SkiaWindowIOS);
};

} // namespace os

#endif
