// LAF OS Library
// Copyright (C) 2026  Emir Yaman Sivrikaya
//
// This file is released under the terms of the MIT license.
// Read LICENSE.txt for more information.

#ifndef OS_IOS_KEYS_H_INCLUDED
#define OS_IOS_KEYS_H_INCLUDED
#pragma once

#include "os/keys.h"

namespace os {

// Converts an ASCII character (as reported by the hardware keyboard
// layout or the software keyboard) into a KeyScancode.
KeyScancode ios_scancode_from_char(int chr);

// Converts a UIKeyboardHIDUsage value into a KeyScancode. Used for
// keys that don't generate a character (arrows, function keys, etc.)
KeyScancode ios_scancode_from_hid_usage(long usage);

bool ios_is_key_pressed(KeyScancode scancode);
void ios_set_key_pressed(KeyScancode scancode, int unicodeChar);
void ios_reset_key_pressed();
int ios_get_unicode_from_scancode(KeyScancode scancode);

// Keys locked from the on-screen toolbar (e.g. Shift/Ctrl/Alt). A
// sticky key is reported as pressed until it's unlocked.
bool ios_is_sticky_key(KeyScancode scancode);
void ios_set_sticky_key(KeyScancode scancode, bool state);

// Returns the current modifiers (hardware keyboard + sticky keys)
KeyModifiers ios_key_modifiers();

} // namespace os

#endif
