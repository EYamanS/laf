// LAF OS Library
// Copyright (C) 2026  Emir Yaman Sivrikaya
//
// This file is released under the terms of the MIT license.
// Read LICENSE.txt for more information.

#ifndef OS_IOS_SYSTEM_H
#define OS_IOS_SYSTEM_H
#pragma once

#include "os/common/system.h"

#include <functional>

namespace os {

// Special touch/stylus gestures that don't have a mouse/keyboard
// equivalent.
enum class IOSGesture {
  Undo,            // Two-finger tap or toolbar button
  Redo,            // Three-finger tap or toolbar button
  PencilDoubleTap, // Apple Pencil (2nd gen/Pro) double-tap
  PencilSqueeze,   // Apple Pencil Pro squeeze
};

// Sets the function to handle special gestures. The handler is called
// from the main thread through an os::Event::Callback event (i.e. from
// the app event loop). If there is no handler, Undo/Redo gestures are
// converted to Cmd+Z/Cmd+Shift+Z key events.
void ios_set_gesture_handler(std::function<void(IOSGesture)>&& handler);

// Sets a function to be called (through an os::Event::Callback) when
// the app goes to background. It's useful to save the app state as
// iOS can terminate the app while it's in background.
void ios_set_background_handler(std::function<void()>&& handler);

// Returns true if one finger can be used to draw on the canvas. When
// it's false (the default) only the Apple Pencil (or a mouse) can
// draw, and the app should use one-finger drags to scroll the canvas
// (finger events have PointerType::Touch). It's changed from the
// toolbar and saved in the user defaults.
bool ios_is_finger_drawing_enabled();
void ios_set_finger_drawing_enabled(bool state);

// Shows/hides the native toolbar with modifier keys.
void ios_set_toolbar_visible(bool state);
bool ios_is_toolbar_visible();

// Path of the "Documents" folder of the app sandbox (visible from the
// Files app).
std::string ios_documents_path();

class SystemIOS : public CommonSystem {
public:
  SystemIOS();
  ~SystemIOS();

  Logger* logger() override;

  bool isKeyPressed(KeyScancode scancode) override;
  void resetKeyPressed() override;
  int getUnicodeFromScancode(KeyScancode scancode) override;

  gfx::Point mousePosition() const override;

  ScreenRef primaryScreen() override;
  void listScreens(ScreenList& list) override;
};

} // namespace os

#endif
