// LAF OS Library
// Copyright (C) 2026  Emir Yaman Sivrikaya
//
// This file is released under the terms of the MIT license.
// Read LICENSE.txt for more information.

#ifdef HAVE_CONFIG_H
  #include "config.h"
#endif

#include "os/ios/window.h"

#include "base/debug.h"
#include "os/event.h"
#include "os/ios/view.h"
#include "os/system.h"

#include <algorithm>
#include <vector>

namespace os {

namespace {

// All the created windows (generally just one)
std::vector<WindowIOS*> g_windows;

} // anonymous namespace

void ios_present_windows()
{
  for (WindowIOS* window : g_windows) {
    LafViewIOS* view = (__bridge LafViewIOS*)window->nativeHandle();
    if (view && [view needsPresent])
      window->onPresent();
  }
}

WindowIOS::WindowIOS()
{
  g_windows.push_back(this);
}

WindowIOS::~WindowIOS()
{
  auto it = std::find(g_windows.begin(), g_windows.end(), this);
  if (it != g_windows.end())
    g_windows.erase(it);

  destroyWindow();
}

void WindowIOS::createWindow(const os::WindowSpec& spec)
{
  m_scale = std::max(1, spec.scale());
  m_view = ios_main_view();
  if (!m_view)
    throw WindowCreationException("The main UIView wasn't created");

  // The last created window takes the main view (there is no support
  // for multiple windows on iOS).
  [m_view setImpl:this];
}

void WindowIOS::destroyWindow()
{
  if (m_view) {
    if ([m_view impl] == this)
      [m_view setImpl:nullptr];
    m_view = nil;
  }
}

gfx::Size WindowIOS::clientSize() const
{
  if (m_view)
    return [m_view pixelSize];
  return gfx::Size(1, 1);
}

gfx::Rect WindowIOS::frame() const
{
  return contentRect();
}

void WindowIOS::setFrame(const gfx::Rect& bounds)
{
  // Do nothing, the window always fills the whole view
}

gfx::Rect WindowIOS::contentRect() const
{
  if (!m_view)
    return gfx::Rect(0, 0, 1, 1);

  // Origin of the view in the screen in pixels
  CGPoint origin = [m_view convertPoint:CGPointZero toCoordinateSpace:m_view.window.screen.coordinateSpace];
  const CGFloat s = m_view.contentScaleFactor;
  const gfx::Size size = clientSize();
  return gfx::Rect(int(origin.x * s), int(origin.y * s), size.w, size.h);
}

gfx::Rect WindowIOS::restoredFrame() const
{
  return frame();
}

void WindowIOS::activate()
{
}

void WindowIOS::maximize()
{
}

void WindowIOS::minimize()
{
}

bool WindowIOS::isMaximized() const
{
  return true;
}

bool WindowIOS::isMinimized() const
{
  return false;
}

bool WindowIOS::isTransparent() const
{
  return false;
}

bool WindowIOS::isFullscreen() const
{
  return true;
}

void WindowIOS::setFullscreen(bool state)
{
}

std::string WindowIOS::title() const
{
  return m_title;
}

void WindowIOS::setTitle(const std::string& title)
{
  m_title = title;
  if (m_view && m_view.window.windowScene)
    m_view.window.windowScene.title = [NSString stringWithUTF8String:title.c_str()];
}

void WindowIOS::captureMouse()
{
}

void WindowIOS::releaseMouse()
{
}

void WindowIOS::setMousePosition(const gfx::Point& position)
{
  // It's not possible to move the pointer on iOS
}

void WindowIOS::performWindowAction(const WindowAction action, const Event* event)
{
}

os::ScreenRef WindowIOS::screen() const
{
  return System::instance()->primaryScreen();
}

os::ColorSpaceRef WindowIOS::colorSpace() const
{
  if (auto cs = Window::colorSpace())
    return cs;
  if (auto scr = screen())
    return scr->colorSpace();
  return nullptr;
}

int WindowIOS::scale() const
{
  return m_scale;
}

void WindowIOS::setScale(int scale)
{
  scale = std::max(1, scale);
  if (m_scale == scale)
    return;

  m_scale = scale;
  onResize(clientSize());
}

bool WindowIOS::isVisible() const
{
  return true;
}

void WindowIOS::setVisible(bool visible)
{
}

bool WindowIOS::setCursor(NativeCursor cursor)
{
  // The system pointer (if there is a mouse/trackpad) is used, we
  // don't want the app to paint its own cursor.
  return true;
}

bool WindowIOS::setCursor(const CursorRef& cursor)
{
  return true;
}

void* WindowIOS::nativeHandle() const
{
  return (__bridge void*)m_view;
}

void WindowIOS::setTextInputMode(bool state)
{
  if (m_view)
    [m_view setTextInputActive:(state ? YES : NO)];
}

} // namespace os
