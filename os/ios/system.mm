// LAF OS Library
// Copyright (C) 2026  Emir Yaman Sivrikaya
//
// This file is released under the terms of the MIT license.
// Read LICENSE.txt for more information.

#ifdef HAVE_CONFIG_H
  #include "config.h"
#endif

#include "os/ios/system.h"

#include "gfx/color_space.h"
#include "os/event.h"
#include "os/event_queue.h"
#include "os/ios/keys.h"
#include "os/ios/logger.h"
#include "os/ios/view.h"
#include "os/screen.h"

#include <UIKit/UIKit.h>

#include <memory>
#include <mutex>

namespace os {

// Defined in view.mm
gfx::Point ios_last_mouse_position();
void ios_queue_key_press(KeyScancode scancode, int unicodeChar, KeyModifiers modifiers);

namespace {

std::mutex g_gestureMutex;
std::shared_ptr<std::function<void(IOSGesture)>> g_gestureHandler;

UIScreen* main_screen()
{
  LafViewIOS* view = ios_main_view();
  if (view && view.window && view.window.windowScene)
    return view.window.windowScene.screen;
  return [UIScreen mainScreen];
}

class ScreenIOS : public Screen {
public:
  ScreenIOS(UIScreen* screen) : m_screen(screen)
  {
    const CGFloat s = screen.nativeScale;
    const CGRect rc = screen.bounds;
    m_bounds = gfx::Rect(0, 0, int(rc.size.width * s), int(rc.size.height * s));
  }

  bool isPrimary() const override { return true; }
  gfx::Rect bounds() const override { return m_bounds; }
  gfx::Rect workarea() const override { return m_bounds; }
  os::ColorSpaceRef colorSpace() const override
  {
    return System::instance()->makeColorSpace(gfx::ColorSpace::MakeSRGB());
  }
  void* nativeHandle() const override { return (__bridge void*)m_screen; }

private:
  UIScreen* m_screen;
  gfx::Rect m_bounds;
};

} // anonymous namespace

void ios_set_gesture_handler(std::function<void(IOSGesture)>&& handler)
{
  const std::lock_guard lock(g_gestureMutex);
  if (handler)
    g_gestureHandler = std::make_shared<std::function<void(IOSGesture)>>(std::move(handler));
  else
    g_gestureHandler.reset();
}

// Called from the view (main thread) when a gesture is detected.
void ios_dispatch_gesture(IOSGesture gesture)
{
  std::shared_ptr<std::function<void(IOSGesture)>> handler;
  {
    const std::lock_guard lock(g_gestureMutex);
    handler = g_gestureHandler;
  }

  if (handler) {
    Event ev;
    ev.setType(Event::Callback);
    ev.setCallback([handler, gesture] { (*handler)(gesture); });
    queue_event(ev);
    return;
  }

  // Default behavior without a handler
  switch (gesture) {
    case IOSGesture::Undo: ios_queue_key_press(kKeyZ, 'z', kKeyCmdModifier); break;
    case IOSGesture::Redo:
      ios_queue_key_press(kKeyZ, 'Z', KeyModifiers(kKeyCmdModifier | kKeyShiftModifier));
      break;
    default: break;
  }
}

static NSString* const kFingerDrawingKey = @"LafFingerDrawing";

bool ios_is_finger_drawing_enabled()
{
  return [[NSUserDefaults standardUserDefaults] boolForKey:kFingerDrawingKey];
}

void ios_set_finger_drawing_enabled(bool state)
{
  [[NSUserDefaults standardUserDefaults] setBool:(state ? YES : NO) forKey:kFingerDrawingKey];
}

void ios_set_toolbar_visible(bool state)
{
  if (LafViewControllerIOS* vc = ios_main_view_controller())
    [vc setToolbarVisible:(state ? YES : NO)];
}

bool ios_is_toolbar_visible()
{
  if (LafViewControllerIOS* vc = ios_main_view_controller())
    return [vc isToolbarVisible];
  return false;
}

std::string ios_documents_path()
{
  NSArray* dirs =
    NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
  if (dirs.count > 0)
    return std::string([dirs.firstObject UTF8String]);
  return std::string();
}

SystemIOS::SystemIOS()
{
}

SystemIOS::~SystemIOS()
{
  destroyInstance();
}

Logger* SystemIOS::logger()
{
  return new LoggerIOS;
}

bool SystemIOS::isKeyPressed(KeyScancode scancode)
{
  return ios_is_key_pressed(scancode);
}

void SystemIOS::resetKeyPressed()
{
  ios_reset_key_pressed();
}

int SystemIOS::getUnicodeFromScancode(KeyScancode scancode)
{
  return ios_get_unicode_from_scancode(scancode);
}

gfx::Point SystemIOS::mousePosition() const
{
  return ios_last_mouse_position();
}

ScreenRef SystemIOS::primaryScreen()
{
  return make_ref<ScreenIOS>(main_screen());
}

void SystemIOS::listScreens(ScreenList& list)
{
  list.push_back(make_ref<ScreenIOS>(main_screen()));
}

SystemRef System::makeIOS()
{
  return make_ref<SystemIOS>();
}

} // namespace os
