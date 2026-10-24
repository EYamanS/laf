// LAF OS Library
// Copyright (C) 2026  Emir Yaman Sivrikaya
//
// This file is released under the terms of the MIT license.
// Read LICENSE.txt for more information.

#ifndef OS_IOS_VIEW_H_INCLUDED
#define OS_IOS_VIEW_H_INCLUDED
#pragma once

#ifdef __OBJC__

  #include "gfx/size.h"
  #include "os/keys.h"

  #include <UIKit/UIKit.h>

namespace os {
class WindowIOS;
}

// The view where the os::Window surface is displayed. It receives
// all the input (touches, Apple Pencil, keyboard, pointer, etc.)
// and converts it to os::Event(s).
@interface LafViewIOS : UIView <UIPencilInteractionDelegate, UIGestureRecognizerDelegate>
- (os::WindowIOS*)impl;
- (void)setImpl:(os::WindowIOS*)impl;
- (gfx::Size)pixelSize;
- (void)setNeedsPresent;
- (BOOL)needsPresent;
- (void)presentImage:(CGImageRef)image surfaceSize:(gfx::Size)size scale:(int)scale;
- (void)setTextInputActive:(BOOL)state;
- (BOOL)isTextInputActive;
- (void)handleKey:(UIKey*)key down:(BOOL)down;
- (void)resetInputState;
- (void)queueKey:(os::KeyScancode)scancode unicode:(int)chr modifiers:(os::KeyModifiers)modifiers;
@end

// Root view controller, it contains the LafViewIOS and a small
// toolbar with modifier keys for devices without keyboard.
@interface LafViewControllerIOS : UIViewController
- (LafViewIOS*)lafView;
- (void)setToolbarVisible:(BOOL)state;
- (BOOL)isToolbarVisible;
@end

// Returns the view where the main window is displayed (nil if the
// scene isn't connected yet).
LafViewIOS* ios_main_view();
LafViewControllerIOS* ios_main_view_controller();

#endif // __OBJC__

#endif
