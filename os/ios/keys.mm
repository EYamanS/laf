// LAF OS Library
// Copyright (C) 2026  Emir Yaman Sivrikaya
//
// This file is released under the terms of the MIT license.
// Read LICENSE.txt for more information.

#ifdef HAVE_CONFIG_H
  #include "config.h"
#endif

#include "os/ios/keys.h"

#include <UIKit/UIKit.h>

#include <iterator>

namespace os {

namespace {

// Internal array of pressed keys used in isKeyPressed(). Each item
// contains the unicode char of the pressed key (or 1 if the key
// doesn't have an unicode char associated).
int g_pressedKeys[kKeyScancodes];
bool g_stickyKeys[kKeyScancodes];

} // anonymous namespace

KeyScancode ios_scancode_from_char(int chr)
{
  if (chr >= 'a' && chr <= 'z')
    return (KeyScancode)(kKeyA + (chr - 'a'));
  if (chr >= 'A' && chr <= 'Z')
    return (KeyScancode)(kKeyA + (chr - 'A'));
  if (chr >= '1' && chr <= '9')
    return (KeyScancode)(kKey1 + (chr - '1'));

  switch (chr) {
    case '0':  return kKey0;
    case 8:    return kKeyBackspace;
    case 9:    return kKeyTab;
    case 10:
    case 13:   return kKeyEnter;
    case 27:   return kKeyEsc;
    case ' ':  return kKeySpace;
    case '\'': return kKeyQuote;
    case ',':  return kKeyComma;
    case '-':  return kKeyMinus;
    case '.':  return kKeyStop;
    case '/':  return kKeySlash;
    case ':':  return kKeyColon;
    case ';':  return kKeySemicolon;
    case '=':  return kKeyEquals;
    case '[':
    case '{':  return kKeyOpenbrace;
    case '\\':
    case '|':  return kKeyBackslash;
    case ']':
    case '}':  return kKeyClosebrace;
    case '^':  return kKeyCircumflex;
    case '`':  return kKeyBackquote;
    case '~':  return kKeyTilde;
    case 127:  return kKeyDel;
  }
  return kKeyNil;
}

KeyScancode ios_scancode_from_hid_usage(long usage)
{
  if (usage >= UIKeyboardHIDUsageKeyboardA && usage <= UIKeyboardHIDUsageKeyboardZ)
    return (KeyScancode)(kKeyA + (usage - UIKeyboardHIDUsageKeyboardA));
  if (usage >= UIKeyboardHIDUsageKeyboard1 && usage <= UIKeyboardHIDUsageKeyboard9)
    return (KeyScancode)(kKey1 + (usage - UIKeyboardHIDUsageKeyboard1));
  if (usage >= UIKeyboardHIDUsageKeypad1 && usage <= UIKeyboardHIDUsageKeypad9)
    return (KeyScancode)(kKey1Pad + (usage - UIKeyboardHIDUsageKeypad1));
  if (usage >= UIKeyboardHIDUsageKeyboardF1 && usage <= UIKeyboardHIDUsageKeyboardF12)
    return (KeyScancode)(kKeyF1 + (usage - UIKeyboardHIDUsageKeyboardF1));

  switch (usage) {
    case UIKeyboardHIDUsageKeyboard0:                  return kKey0;
    case UIKeyboardHIDUsageKeypad0:                    return kKey0Pad;
    case UIKeyboardHIDUsageKeyboardReturnOrEnter:      return kKeyEnter;
    case UIKeyboardHIDUsageKeyboardEscape:             return kKeyEsc;
    case UIKeyboardHIDUsageKeyboardDeleteOrBackspace:  return kKeyBackspace;
    case UIKeyboardHIDUsageKeyboardTab:                return kKeyTab;
    case UIKeyboardHIDUsageKeyboardSpacebar:           return kKeySpace;
    case UIKeyboardHIDUsageKeyboardHyphen:             return kKeyMinus;
    case UIKeyboardHIDUsageKeyboardEqualSign:          return kKeyEquals;
    case UIKeyboardHIDUsageKeyboardOpenBracket:        return kKeyOpenbrace;
    case UIKeyboardHIDUsageKeyboardCloseBracket:       return kKeyClosebrace;
    case UIKeyboardHIDUsageKeyboardBackslash:          return kKeyBackslash;
    case UIKeyboardHIDUsageKeyboardNonUSPound:         return kKeyBackslash2;
    case UIKeyboardHIDUsageKeyboardSemicolon:          return kKeySemicolon;
    case UIKeyboardHIDUsageKeyboardQuote:              return kKeyQuote;
    case UIKeyboardHIDUsageKeyboardGraveAccentAndTilde: return kKeyTilde;
    case UIKeyboardHIDUsageKeyboardComma:              return kKeyComma;
    case UIKeyboardHIDUsageKeyboardPeriod:             return kKeyStop;
    case UIKeyboardHIDUsageKeyboardSlash:              return kKeySlash;
    case UIKeyboardHIDUsageKeyboardCapsLock:           return kKeyCapsLock;
    case UIKeyboardHIDUsageKeyboardPrintScreen:        return kKeyPrtscr;
    case UIKeyboardHIDUsageKeyboardScrollLock:         return kKeyScrLock;
    case UIKeyboardHIDUsageKeyboardPause:              return kKeyPause;
    case UIKeyboardHIDUsageKeyboardInsert:             return kKeyInsert;
    case UIKeyboardHIDUsageKeyboardHome:               return kKeyHome;
    case UIKeyboardHIDUsageKeyboardPageUp:             return kKeyPageUp;
    case UIKeyboardHIDUsageKeyboardDeleteForward:      return kKeyDel;
    case UIKeyboardHIDUsageKeyboardEnd:                return kKeyEnd;
    case UIKeyboardHIDUsageKeyboardPageDown:           return kKeyPageDown;
    case UIKeyboardHIDUsageKeyboardRightArrow:         return kKeyRight;
    case UIKeyboardHIDUsageKeyboardLeftArrow:          return kKeyLeft;
    case UIKeyboardHIDUsageKeyboardDownArrow:          return kKeyDown;
    case UIKeyboardHIDUsageKeyboardUpArrow:            return kKeyUp;
    case UIKeyboardHIDUsageKeypadNumLock:              return kKeyNumLock;
    case UIKeyboardHIDUsageKeypadSlash:                return kKeySlashPad;
    case UIKeyboardHIDUsageKeypadAsterisk:             return kKeyAsterisk;
    case UIKeyboardHIDUsageKeypadHyphen:               return kKeyMinusPad;
    case UIKeyboardHIDUsageKeypadPlus:                 return kKeyPlusPad;
    case UIKeyboardHIDUsageKeypadEnter:                return kKeyEnterPad;
    case UIKeyboardHIDUsageKeypadPeriod:               return kKeyDelPad;
    case UIKeyboardHIDUsageKeyboardNonUSBackslash:     return kKeyBackslash2;
    case UIKeyboardHIDUsageKeyboardApplication:        return kKeyMenu;
    case UIKeyboardHIDUsageKeypadEqualSign:            return kKeyEqualsPad;
    case UIKeyboardHIDUsageKeyboardInternational1:     return kKeyAbntC1;
    case UIKeyboardHIDUsageKeyboardInternational3:     return kKeyYen;
    case UIKeyboardHIDUsageKeyboardLeftControl:        return kKeyLControl;
    case UIKeyboardHIDUsageKeyboardLeftShift:          return kKeyLShift;
    case UIKeyboardHIDUsageKeyboardLeftAlt:            return kKeyAlt;
    case UIKeyboardHIDUsageKeyboardLeftGUI:            return kKeyCommand;
    case UIKeyboardHIDUsageKeyboardRightControl:       return kKeyRControl;
    case UIKeyboardHIDUsageKeyboardRightShift:         return kKeyRShift;
    case UIKeyboardHIDUsageKeyboardRightAlt:           return kKeyAltGr;
    case UIKeyboardHIDUsageKeyboardRightGUI:           return kKeyCommand;
  }
  return kKeyNil;
}

bool ios_is_key_pressed(KeyScancode scancode)
{
  if (scancode >= 0 && scancode < kKeyScancodes)
    return (g_pressedKeys[scancode] != 0 || g_stickyKeys[scancode]);
  return false;
}

void ios_set_key_pressed(KeyScancode scancode, int unicodeChar)
{
  if (scancode >= 0 && scancode < kKeyScancodes)
    g_pressedKeys[scancode] = unicodeChar;
}

void ios_reset_key_pressed()
{
  for (int i = 0; i < int(std::size(g_pressedKeys)); ++i)
    g_pressedKeys[i] = 0;
}

int ios_get_unicode_from_scancode(KeyScancode scancode)
{
  if (scancode >= 0 && scancode < kKeyScancodes)
    return g_pressedKeys[scancode];
  return 0;
}

bool ios_is_sticky_key(KeyScancode scancode)
{
  if (scancode >= 0 && scancode < kKeyScancodes)
    return g_stickyKeys[scancode];
  return false;
}

void ios_set_sticky_key(KeyScancode scancode, bool state)
{
  if (scancode >= 0 && scancode < kKeyScancodes)
    g_stickyKeys[scancode] = state;
}

KeyModifiers ios_key_modifiers()
{
  KeyModifiers modifiers = kKeyNoneModifier;
  if (ios_is_key_pressed(kKeyLShift) || ios_is_key_pressed(kKeyRShift))
    modifiers |= kKeyShiftModifier;
  if (ios_is_key_pressed(kKeyLControl) || ios_is_key_pressed(kKeyRControl))
    modifiers |= kKeyCtrlModifier;
  if (ios_is_key_pressed(kKeyAlt))
    modifiers |= kKeyAltModifier;
  if (ios_is_key_pressed(kKeyAltGr))
    modifiers |= KeyModifiers(kKeyCtrlModifier | kKeyAltModifier);
  if (ios_is_key_pressed(kKeyCommand))
    modifiers |= kKeyCmdModifier;
  if (ios_is_key_pressed(kKeySpace))
    modifiers |= kKeySpaceModifier;
  return modifiers;
}

} // namespace os
