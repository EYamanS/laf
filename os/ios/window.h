// LAF OS Library
// Copyright (C) 2026  Emir Yaman Sivrikaya
//
// This file is released under the terms of the MIT license.
// Read LICENSE.txt for more information.

#ifndef OS_IOS_WINDOW_H_INCLUDED
#define OS_IOS_WINDOW_H_INCLUDED
#pragma once

#include "gfx/point.h"
#include "gfx/rect.h"
#include "gfx/size.h"
#include "os/native_cursor.h"
#include "os/screen.h"
#include "os/window.h"
#include "os/window_spec.h"

#include <string>

#ifdef __OBJC__
@class LafViewIOS;
using LafViewIOS_id = LafViewIOS*;
#else
  #include <objc/objc.h>
using LafViewIOS_id = id;
#endif

namespace os {

// Presents the content of all windows that were invalidated since the
// last call. Called from the event queue before waiting new events.
void ios_present_windows();

// On iOS there is only one native window: the full-screen UIView
// created by the app delegate when the scene is connected. Each
// WindowIOS is attached to that view.
class WindowIOS : public os::Window {
public:
  WindowIOS();
  ~WindowIOS();

  void createWindow(const os::WindowSpec& spec);
  void destroyWindow();

  // Size of the content in real pixels (not points)
  gfx::Size clientSize() const;

  gfx::Rect frame() const override;
  void setFrame(const gfx::Rect& bounds) override;
  gfx::Rect contentRect() const override;
  gfx::Rect restoredFrame() const override;

  void activate() override;
  void maximize() override;
  void minimize() override;
  bool isMaximized() const override;
  bool isMinimized() const override;
  bool isTransparent() const override;
  bool isFullscreen() const override;
  void setFullscreen(bool state) override;

  std::string title() const override;
  void setTitle(const std::string& title) override;

  void captureMouse() override;
  void releaseMouse() override;
  void setMousePosition(const gfx::Point& position) override;

  void performWindowAction(const WindowAction action, const Event* event) override;

  os::ScreenRef screen() const override;
  os::ColorSpaceRef colorSpace() const override;

  int scale() const override;
  void setScale(int scale) override;
  bool isVisible() const override;
  void setVisible(bool visible) override;

  bool setCursor(NativeCursor cursor) override;
  bool setCursor(const CursorRef& cursor) override;

  void* nativeHandle() const override;

  // Shows/hides the software keyboard
  void setTextInputMode(bool state);

  // Called by the LafViewIOS when its size changes (in pixels)
  virtual void onResize(const gfx::Size& size) = 0;

  // Called by ios_present_windows() to copy the window surface to the
  // UIView layer.
  virtual void onPresent() = 0;

protected:
  LafViewIOS_id __strong m_view = nullptr;
  int m_scale = 1;
  std::string m_title;
};

} // namespace os

#endif
