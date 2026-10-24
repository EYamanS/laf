// LAF OS Library
// Copyright (C) 2026  Emir Yaman Sivrikaya
//
// This file is released under the terms of the MIT license.
// Read LICENSE.txt for more information.

#ifdef HAVE_CONFIG_H
  #include "config.h"
#endif

#include "os/ios/view.h"

#include "os/event.h"
#include "os/event_queue.h"
#include "os/ios/keys.h"
#include "os/ios/system.h"
#include "os/ios/window.h"

#include <QuartzCore/QuartzCore.h>

#include <algorithm>
#include <cmath>

namespace os {

// Defined in system.mm
void ios_dispatch_gesture(IOSGesture gesture);

namespace {

LafViewIOS* __weak g_mainView = nil;
LafViewControllerIOS* __weak g_mainViewController = nil;

// Last known pointer position in screen pixels
gfx::Point g_lastMousePos;

// Time (in seconds) to wait to know if a finger touch is a tap, a
// drag, or the beginning of a gesture with more fingers.
constexpr NSTimeInterval kLongPressDelay = 0.5;
// Distance (in points) that a finger must be moved to start dragging.
constexpr CGFloat kDragThreshold = 6.0;
// Maximum duration/movement of a multi-finger tap (undo/redo)
constexpr NSTimeInterval kMultiTapMaxDuration = 0.35;
constexpr CGFloat kMultiTapMaxMovement = 20.0;
// Delay to send the MouseLeave event after the finger/pencil is
// released (we cannot send it immediately because widgets like
// buttons must process the MouseUp with the mouse over them).
constexpr NSTimeInterval kMouseLeaveDelay = 0.25;

constexpr NSTimeInterval kKeyRepeatDelay = 0.4;
constexpr NSTimeInterval kKeyRepeatInterval = 0.05;

enum class FingerState {
  None,     // No fingers
  Pending,  // One finger touching, we don't know yet what it is
  Dragging, // One finger dragging (left mouse button pressed)
  Gesture,  // Two or more fingers (pan/zoom/undo/redo)
  Ignored,  // The rest of the touch sequence is ignored
};

bool is_modifier_scancode(KeyScancode scancode)
{
  return (scancode >= kKeyFirstModifierScancode || scancode == kKeySpace);
}

// Returns true if the given scancode generates a character that
// depends on the keyboard layout (letters, numbers, punctuation).
bool is_layout_scancode(KeyScancode scancode)
{
  return ((scancode >= kKeyA && scancode <= kKey9) || scancode == kKeyTilde ||
          scancode == kKeyMinus || scancode == kKeyEquals || scancode == kKeyOpenbrace ||
          scancode == kKeyClosebrace || scancode == kKeyColon || scancode == kKeyQuote ||
          scancode == kKeyBackslash || scancode == kKeyBackslash2 || scancode == kKeyComma ||
          scancode == kKeyStop || scancode == kKeySlash || scancode == kKeySemicolon ||
          scancode == kKeyBackquote);
}

// Returns true if the key doesn't generate text (so it must be
// handled by us even in text input mode).
bool is_special_scancode(KeyScancode scancode)
{
  return (scancode == kKeyNil || (scancode >= kKeyF1 && scancode <= kKeyF12) ||
          scancode == kKeyEsc || scancode == kKeyTab || scancode == kKeyEnter ||
          scancode == kKeyEnterPad || scancode == kKeyBackspace ||
          (scancode >= kKeyInsert && scancode <= kKeyDown) || is_modifier_scancode(scancode));
}

int unicode_for_special_scancode(KeyScancode scancode)
{
  switch (scancode) {
    case kKeyBackspace: return 8;
    case kKeyTab:       return 9;
    case kKeyEnter:
    case kKeyEnterPad:  return 13;
    case kKeyEsc:       return 27;
    default:            return 0;
  }
}

KeyModifiers modifiers_from_uikey(UIKey* key)
{
  KeyModifiers modifiers = ios_key_modifiers();
  if (key) {
    const UIKeyModifierFlags flags = key.modifierFlags;
    if (flags & UIKeyModifierShift)
      modifiers |= kKeyShiftModifier;
    if (flags & UIKeyModifierControl)
      modifiers |= kKeyCtrlModifier;
    if (flags & UIKeyModifierAlternate)
      modifiers |= kKeyAltModifier;
    if (flags & UIKeyModifierCommand)
      modifiers |= kKeyCmdModifier;
  }
  return modifiers;
}

CGFloat distance(const CGPoint& a, const CGPoint& b)
{
  return std::hypot(a.x - b.x, a.y - b.y);
}

} // anonymous namespace

gfx::Point ios_last_mouse_position()
{
  return g_lastMousePos;
}

// Generates a KeyDown + KeyUp sequence for the given key
void ios_queue_key_press(KeyScancode scancode, int unicodeChar, KeyModifiers modifiers)
{
  LafViewIOS* view = g_mainView;
  for (int i = 0; i < 2; ++i) {
    Event ev;
    ev.setType(i == 0 ? Event::KeyDown : Event::KeyUp);
    ev.setScancode(scancode);
    ev.setModifiers(modifiers);
    ev.setUnicodeChar(unicodeChar);
    ev.setRepeat(0);
    if (view && [view impl])
      [view impl]->queueEvent(ev);
    else
      queue_event(ev);
  }
}

} // namespace os

using namespace os;

LafViewIOS* ios_main_view()
{
  return g_mainView;
}

LafViewControllerIOS* ios_main_view_controller()
{
  return g_mainViewController;
}

//////////////////////////////////////////////////////////////////////
// LafTextInputIOS: hidden view used to show the software keyboard
// and receive text when the app is waiting for text input.

@interface LafTextInputIOS : UIView <UIKeyInput>
@property (nonatomic, weak) LafViewIOS* owner;
@property (nonatomic) UITextAutocapitalizationType autocapitalizationType;
@property (nonatomic) UITextAutocorrectionType autocorrectionType;
@property (nonatomic) UITextSpellCheckingType spellCheckingType;
@property (nonatomic) UITextSmartQuotesType smartQuotesType;
@property (nonatomic) UITextSmartDashesType smartDashesType;
@property (nonatomic) UITextSmartInsertDeleteType smartInsertDeleteType;
@property (nonatomic) UIKeyboardType keyboardType;
@property (nonatomic) UIReturnKeyType returnKeyType;
@end

@implementation LafTextInputIOS {
  // Presses that we've forwarded to the owner view
  NSMutableSet<UIPress*>* m_forwarded;
}

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    m_forwarded = [NSMutableSet set];
    self.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.autocorrectionType = UITextAutocorrectionTypeNo;
    self.spellCheckingType = UITextSpellCheckingTypeNo;
    self.smartQuotesType = UITextSmartQuotesTypeNo;
    self.smartDashesType = UITextSmartDashesTypeNo;
    self.smartInsertDeleteType = UITextSmartInsertDeleteTypeNo;
    self.keyboardType = UIKeyboardTypeDefault;
    self.returnKeyType = UIReturnKeyDone;
    self.userInteractionEnabled = NO;
  }
  return self;
}

- (BOOL)canBecomeFirstResponder
{
  return YES;
}

- (BOOL)hasText
{
  // Always YES so deleteBackward is called with empty text too
  return YES;
}

- (UITextInputAssistantItem*)inputAssistantItem
{
  UITextInputAssistantItem* item = [super inputAssistantItem];
  item.leadingBarButtonGroups = @[];
  item.trailingBarButtonGroups = @[];
  return item;
}

- (void)insertText:(NSString*)text
{
  LafViewIOS* owner = self.owner;
  if (!owner)
    return;

  const KeyModifiers modifiers = ios_key_modifiers();
  [text enumerateSubstringsInRange:NSMakeRange(0, text.length)
                           options:NSStringEnumerationByComposedCharacterSequences
                        usingBlock:^(NSString* substring, NSRange, NSRange, BOOL*) {
                          uint32_t cp = 0;
                          if (![substring getBytes:&cp
                                         maxLength:sizeof(cp)
                                        usedLength:nullptr
                                          encoding:NSUTF32LittleEndianStringEncoding
                                           options:0
                                             range:NSMakeRange(0, substring.length)
                                    remainingRange:nullptr])
                            return;

                          if (cp == '\n' || cp == '\r') {
                            [owner queueKey:kKeyEnter unicode:13 modifiers:modifiers];
                          }
                          else {
                            KeyScancode scancode = (cp < 128 ? ios_scancode_from_char(cp) :
                                                               kKeyNil);
                            [owner queueKey:scancode unicode:int(cp) modifiers:modifiers];
                          }
                        }];
}

- (void)deleteBackward
{
  if (LafViewIOS* owner = self.owner)
    [owner queueKey:kKeyBackspace unicode:8 modifiers:ios_key_modifiers()];
}

- (BOOL)shouldForwardPress:(UIPress*)press
{
  UIKey* key = press.key;
  if (!key)
    return NO;

  // Shortcuts are handled by the app
  if (key.modifierFlags & (UIKeyModifierCommand | UIKeyModifierControl))
    return YES;

  return is_special_scancode(ios_scancode_from_hid_usage(key.keyCode));
}

- (void)pressesBegan:(NSSet<UIPress*>*)presses withEvent:(UIPressesEvent*)event
{
  NSMutableSet<UIPress*>* rest = [NSMutableSet set];
  for (UIPress* press in presses) {
    if ([self shouldForwardPress:press]) {
      [m_forwarded addObject:press];
      [self.owner handleKey:press.key down:YES];
    }
    else
      [rest addObject:press];
  }
  if (rest.count > 0)
    [super pressesBegan:rest withEvent:event];
}

- (void)endPresses:(NSSet<UIPress*>*)presses withEvent:(UIPressesEvent*)event cancelled:(BOOL)cancelled
{
  NSMutableSet<UIPress*>* rest = [NSMutableSet set];
  for (UIPress* press in presses) {
    if ([m_forwarded containsObject:press]) {
      [m_forwarded removeObject:press];
      [self.owner handleKey:press.key down:NO];
    }
    else
      [rest addObject:press];
  }
  if (rest.count > 0) {
    if (cancelled)
      [super pressesCancelled:rest withEvent:event];
    else
      [super pressesEnded:rest withEvent:event];
  }
}

- (void)pressesEnded:(NSSet<UIPress*>*)presses withEvent:(UIPressesEvent*)event
{
  [self endPresses:presses withEvent:event cancelled:NO];
}

- (void)pressesCancelled:(NSSet<UIPress*>*)presses withEvent:(UIPressesEvent*)event
{
  [self endPresses:presses withEvent:event cancelled:YES];
}

@end

//////////////////////////////////////////////////////////////////////
// LafViewIOS

@implementation LafViewIOS {
  WindowIOS* m_impl;
  CALayer* m_contentLayer;
  BOOL m_needsPresent;
  gfx::Size m_lastPixelSize;

  // Apple Pencil or mouse/trackpad pointer touch
  UITouch* __weak m_pointerTouch;
  PointerType m_pointerType;
  Event::MouseButton m_pointerButton;
  BOOL m_hovering;

  // Fingers
  NSMutableArray<UITouch*>* m_fingers;
  FingerState m_fingerState;
  CGPoint m_fingerStartPos;
  CGPoint m_fingerLastPos;
  NSUInteger m_fingerTapCount;
  NSTimer* m_longPressTimer;

  // Multi-finger gesture
  NSTimeInterval m_gestureStartTime;
  NSUInteger m_gestureMaxFingers;
  BOOL m_gestureCanTap;
  CGFloat m_gestureMovement;
  CGFloat m_gestureZoom;
  CGPoint m_gestureLastCentroid;
  CGFloat m_gestureLastDistance;
  CGPoint m_wheelRemainder;

  // Trackpad/mouse wheel scroll
  CGPoint m_lastScrollTranslation;
  CGFloat m_lastPinchScale;

  NSTimer* m_mouseLeaveTimer;

  // Text input
  LafTextInputIOS* m_textInput;
  BOOL m_textInputActive;

  // Key auto-repeat
  NSTimer* m_keyRepeatTimer;
  long m_keyRepeatUsage;
  KeyScancode m_keyRepeatScancode;
  int m_keyRepeatUnicode;
}

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    m_impl = nullptr;
    m_needsPresent = NO;
    m_pointerType = PointerType::Unknown;
    m_pointerButton = Event::NoneButton;
    m_hovering = NO;
    m_fingers = [NSMutableArray array];
    m_fingerState = FingerState::None;
    m_textInputActive = NO;
    m_keyRepeatUsage = 0;

    self.multipleTouchEnabled = YES;
    self.exclusiveTouch = NO;
    self.backgroundColor = [UIColor blackColor];
    self.clipsToBounds = YES;

    m_contentLayer = [CALayer layer];
    m_contentLayer.anchorPoint = CGPointZero;
    m_contentLayer.position = CGPointZero;
    m_contentLayer.magnificationFilter = kCAFilterNearest;
    m_contentLayer.minificationFilter = kCAFilterNearest;
    m_contentLayer.contentsGravity = kCAGravityResize;
    m_contentLayer.opaque = YES;
    m_contentLayer.actions = @{ @"contents" : [NSNull null],
                                @"bounds" : [NSNull null],
                                @"position" : [NSNull null] };
    [self.layer addSublayer:m_contentLayer];

    m_textInput = [[LafTextInputIOS alloc] initWithFrame:CGRectMake(0, 0, 1, 1)];
    m_textInput.owner = self;
    m_textInput.hidden = YES;
    [self addSubview:m_textInput];

    // Mouse/trackpad pointer and Apple Pencil hover
    UIHoverGestureRecognizer* hover =
      [[UIHoverGestureRecognizer alloc] initWithTarget:self action:@selector(onHover:)];
    hover.delegate = self;
    [self addGestureRecognizer:hover];

    // Mouse wheel and trackpad two-finger scroll
    UIPanGestureRecognizer* scroll =
      [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onScroll:)];
    scroll.allowedScrollTypesMask = UIScrollTypeMaskAll;
    scroll.allowedTouchTypes = @[];
    scroll.cancelsTouchesInView = NO;
    scroll.delaysTouchesBegan = NO;
    scroll.delaysTouchesEnded = NO;
    scroll.delegate = self;
    [self addGestureRecognizer:scroll];

    // Trackpad pinch
    UIPinchGestureRecognizer* pinch =
      [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(onTrackpadPinch:)];
    pinch.allowedTouchTypes = @[ @(UITouchTypeIndirectPointer) ];
    pinch.cancelsTouchesInView = NO;
    pinch.delaysTouchesBegan = NO;
    pinch.delaysTouchesEnded = NO;
    pinch.delegate = self;
    [self addGestureRecognizer:pinch];

    // Apple Pencil double-tap/squeeze
    UIPencilInteraction* pencil = [[UIPencilInteraction alloc] init];
    pencil.delegate = self;
    [self addInteraction:pencil];
  }
  return self;
}

- (WindowIOS*)impl
{
  return m_impl;
}

- (void)setImpl:(WindowIOS*)impl
{
  m_impl = impl;
  m_lastPixelSize = [self pixelSize];
  if (m_impl)
    m_needsPresent = YES;
}

- (CGFloat)pixelScale
{
  CGFloat s = self.traitCollection.displayScale;
  if (s <= 0.0 && self.window)
    s = self.window.screen.scale;
  return (s > 0.0 ? s : 2.0);
}

- (gfx::Size)pixelSize
{
  const CGFloat s = [self pixelScale];
  return gfx::Size(std::max(1, int(std::floor(self.bounds.size.width * s))),
                   std::max(1, int(std::floor(self.bounds.size.height * s))));
}

- (void)layoutSubviews
{
  [super layoutSubviews];

  const gfx::Size size = [self pixelSize];
  if (size != m_lastPixelSize) {
    m_lastPixelSize = size;
    if (m_impl) {
      m_impl->onResize(size);
      m_needsPresent = YES;
    }
  }
}

- (void)didMoveToWindow
{
  [super didMoveToWindow];
  if (self.window && !m_textInputActive)
    [self becomeFirstResponder];
}

- (void)setNeedsPresent
{
  m_needsPresent = YES;
}

- (BOOL)needsPresent
{
  return m_needsPresent;
}

- (void)presentImage:(CGImageRef)image surfaceSize:(gfx::Size)size scale:(int)scale
{
  m_needsPresent = NO;

  const CGFloat s = [self pixelScale];
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  m_contentLayer.frame = CGRectMake(0, 0, size.w * scale / s, size.h * scale / s);
  m_contentLayer.contents = (__bridge id)image;
  [CATransaction commit];
  [CATransaction flush];
}

// ----------------------------------------------------------------------
// Events

- (void)queueEvent:(Event&)ev
{
  if (m_impl)
    m_impl->queueEvent(ev);
  else
    queue_event(ev);
}

- (gfx::Point)surfacePoint:(CGPoint)pt
{
  const CGFloat s = [self pixelScale];
  const int scale = (m_impl ? m_impl->scale() : 1);

  // Update the global mouse position (in screen pixels)
  gfx::Point origin = (m_impl ? m_impl->contentRect().origin() : gfx::Point(0, 0));
  g_lastMousePos = gfx::Point(origin.x + int(pt.x * s), origin.y + int(pt.y * s));

  return gfx::Point(int(std::floor(pt.x * s / scale)), int(std::floor(pt.y * s / scale)));
}

- (void)queueMouse:(Event::Type)type
          position:(CGPoint)pt
            button:(Event::MouseButton)button
           pointer:(PointerType)pointerType
          pressure:(float)pressure
{
  Event ev;
  ev.setType(type);
  ev.setPosition([self surfacePoint:pt]);
  ev.setButton(button);
  ev.setModifiers(ios_key_modifiers());
  ev.setPointerType(pointerType);
  ev.setPressure(pressure);
  [self queueEvent:ev];
}

- (void)queueKey:(KeyScancode)scancode unicode:(int)chr modifiers:(KeyModifiers)modifiers
{
  for (int i = 0; i < 2; ++i) {
    Event ev;
    ev.setType(i == 0 ? Event::KeyDown : Event::KeyUp);
    ev.setScancode(scancode);
    ev.setModifiers(modifiers);
    ev.setUnicodeChar(chr);
    ev.setRepeat(0);
    [self queueEvent:ev];
  }
}

// Sends MouseEnter + MouseMove events when a touch starts
- (void)enterAt:(CGPoint)pt pointer:(PointerType)pointerType
{
  [self cancelMouseLeave];
  if (!m_hovering)
    [self queueMouse:Event::MouseEnter
            position:pt
              button:Event::NoneButton
             pointer:pointerType
            pressure:0.0f];
  [self queueMouse:Event::MouseMove
          position:pt
            button:Event::NoneButton
           pointer:pointerType
          pressure:0.0f];
}

- (void)scheduleMouseLeave
{
  [self cancelMouseLeave];
  if (m_hovering)
    return;

  LafViewIOS* __weak weakSelf = self;
  m_mouseLeaveTimer = [NSTimer scheduledTimerWithTimeInterval:kMouseLeaveDelay
                                                      repeats:NO
                                                        block:^(NSTimer*) {
                                                          [weakSelf onMouseLeaveTimer];
                                                        }];
}

- (void)cancelMouseLeave
{
  if (m_mouseLeaveTimer) {
    [m_mouseLeaveTimer invalidate];
    m_mouseLeaveTimer = nil;
  }
}

- (void)onMouseLeaveTimer
{
  m_mouseLeaveTimer = nil;
  if (m_pointerTouch || m_fingerState != FingerState::None || m_hovering)
    return;

  Event ev;
  ev.setType(Event::MouseLeave);
  ev.setModifiers(ios_key_modifiers());
  [self queueEvent:ev];
}

static float pencil_pressure(UITouch* touch)
{
  if (touch.type == UITouchTypePencil && touch.maximumPossibleForce > 0.0)
    return std::clamp(float(touch.force / touch.maximumPossibleForce), 0.0f, 1.0f);
  return 1.0f;
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
  for (UITouch* touch in touches) {
    switch (touch.type) {
      case UITouchTypePencil:
      case UITouchTypeIndirectPointer: [self pointerBegan:touch event:event]; break;
      case UITouchTypeDirect:          [self fingerBegan:touch event:event]; break;
      default:                         break;
    }
  }
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
  BOOL fingersMoved = NO;
  for (UITouch* touch in touches) {
    if (touch == m_pointerTouch)
      [self pointerMoved:touch event:event];
    else if ([m_fingers containsObject:touch])
      fingersMoved = YES;
  }
  if (fingersMoved)
    [self fingersMoved:touches event:event];
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
  for (UITouch* touch in touches) {
    if (touch == m_pointerTouch)
      [self pointerEnded:touch cancelled:NO];
    else if ([m_fingers containsObject:touch])
      [self fingerEnded:touch cancelled:NO];
  }
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
  for (UITouch* touch in touches) {
    if (touch == m_pointerTouch)
      [self pointerEnded:touch cancelled:YES];
    else if ([m_fingers containsObject:touch])
      [self fingerEnded:touch cancelled:YES];
  }
}

// ----------------------------------------------------------------------
// Apple Pencil & mouse/trackpad

- (void)pointerBegan:(UITouch*)touch event:(UIEvent*)event
{
  if (m_pointerTouch)
    return;

  // The stylus has priority over fingers (palm rejection)
  [self cancelFingers];

  m_pointerTouch = touch;
  if (touch.type == UITouchTypePencil) {
    m_pointerType = PointerType::Pen;
    m_pointerButton = Event::LeftButton;
  }
  else {
    m_pointerType = PointerType::Mouse;
    const UIEventButtonMask mask = event.buttonMask;
    if (mask & UIEventButtonMaskSecondary)
      m_pointerButton = Event::RightButton;
    else if (mask & UIEventButtonMaskForButtonNumber(3))
      m_pointerButton = Event::MiddleButton;
    else
      m_pointerButton = Event::LeftButton;
  }

  const CGPoint pt = [touch preciseLocationInView:self];
  [self enterAt:pt pointer:m_pointerType];
  [self queueMouse:((touch.tapCount % 2) == 0 ? Event::MouseDoubleClick : Event::MouseDown)
          position:pt
            button:m_pointerButton
           pointer:m_pointerType
          pressure:pencil_pressure(touch)];
}

- (void)pointerMoved:(UITouch*)touch event:(UIEvent*)event
{
  NSArray<UITouch*>* coalesced = [event coalescedTouchesForTouch:touch];
  if (!coalesced || coalesced.count == 0)
    coalesced = @[ touch ];

  for (UITouch* t in coalesced) {
    [self queueMouse:Event::MouseMove
            position:[t preciseLocationInView:self]
              button:m_pointerButton
             pointer:m_pointerType
            pressure:pencil_pressure(t)];
  }
}

- (void)pointerEnded:(UITouch*)touch cancelled:(BOOL)cancelled
{
  [self queueMouse:Event::MouseUp
          position:[touch preciseLocationInView:self]
            button:m_pointerButton
           pointer:m_pointerType
          pressure:0.0f];

  m_pointerTouch = nil;
  m_pointerButton = Event::NoneButton;
  if (m_pointerType == PointerType::Pen)
    [self scheduleMouseLeave];
}

// ----------------------------------------------------------------------
// Fingers

- (void)fingerBegan:(UITouch*)touch event:(UIEvent*)event
{
  // Ignore fingers while the pencil is used (palm rejection)
  if (m_pointerTouch)
    return;

  [m_fingers addObject:touch];
  const NSUInteger n = m_fingers.count;

  if (n == 1) {
    if (m_fingerState == FingerState::None) {
      m_fingerState = FingerState::Pending;
      m_fingerStartPos = m_fingerLastPos = [touch locationInView:self];
      m_fingerTapCount = touch.tapCount;
      m_gestureStartTime = touch.timestamp;
      [self startLongPressTimer];
    }
  }
  else {
    if (m_fingerState == FingerState::Pending) {
      [self stopLongPressTimer];
      m_gestureCanTap = YES;
      [self beginGesture];
    }
    else if (m_fingerState == FingerState::Dragging) {
      // A second finger ends the current drag (e.g. the user started
      // drawing and now wants to scroll/zoom).
      [self queueMouse:Event::MouseUp
              position:m_fingerLastPos
                button:Event::LeftButton
               pointer:PointerType::Touch
              pressure:0.0f];
      m_gestureStartTime = touch.timestamp;
      m_gestureCanTap = NO;
      [self beginGesture];
    }
    else if (m_fingerState == FingerState::Gesture) {
      m_gestureMaxFingers = std::max(m_gestureMaxFingers, n);
      [self resetGestureReference];
    }
  }
}

- (void)beginGesture
{
  m_fingerState = FingerState::Gesture;
  m_gestureMaxFingers = m_fingers.count;
  m_gestureMovement = 0.0;
  m_gestureZoom = 0.0;
  m_wheelRemainder = CGPointZero;
  [self resetGestureReference];

  // Mouse wheel/magnify messages are sent to the widget below the
  // mouse, so we have to move the mouse to the gesture position.
  [self enterAt:m_gestureLastCentroid pointer:PointerType::Touch];
}

- (void)resetGestureReference
{
  if (m_fingers.count >= 2) {
    const CGPoint a = [m_fingers[0] locationInView:self];
    const CGPoint b = [m_fingers[1] locationInView:self];
    m_gestureLastCentroid = CGPointMake((a.x + b.x) / 2.0, (a.y + b.y) / 2.0);
    m_gestureLastDistance = std::max(1.0, distance(a, b));
  }
}

- (void)startDraggingFinger
{
  [self stopLongPressTimer];
  m_fingerState = FingerState::Dragging;

  [self enterAt:m_fingerStartPos pointer:PointerType::Touch];
  [self queueMouse:((m_fingerTapCount % 2) == 0 ? Event::MouseDoubleClick : Event::MouseDown)
          position:m_fingerStartPos
            button:Event::LeftButton
           pointer:PointerType::Touch
          pressure:1.0f];
}

- (void)fingersMoved:(NSSet<UITouch*>*)touches event:(UIEvent*)event
{
  switch (m_fingerState) {
    case FingerState::Pending: {
      UITouch* touch = m_fingers.firstObject;
      const CGPoint pt = [touch locationInView:self];
      if (distance(pt, m_fingerStartPos) < kDragThreshold)
        break;

      [self startDraggingFinger];
      [[fallthrough]];
    }

    case FingerState::Dragging: {
      UITouch* touch = m_fingers.firstObject;
      NSArray<UITouch*>* coalesced = [event coalescedTouchesForTouch:touch];
      if (!coalesced || coalesced.count == 0)
        coalesced = @[ touch ];

      for (UITouch* t in coalesced) {
        m_fingerLastPos = [t locationInView:self];
        [self queueMouse:Event::MouseMove
                position:m_fingerLastPos
                  button:Event::LeftButton
                 pointer:PointerType::Touch
                pressure:1.0f];
      }
      break;
    }

    case FingerState::Gesture: {
      if (m_fingers.count < 2)
        break;

      const CGPoint a = [m_fingers[0] locationInView:self];
      const CGPoint b = [m_fingers[1] locationInView:self];
      const CGPoint centroid = CGPointMake((a.x + b.x) / 2.0, (a.y + b.y) / 2.0);
      const CGFloat dist = std::max(1.0, distance(a, b));

      const CGFloat dx = centroid.x - m_gestureLastCentroid.x;
      const CGFloat dy = centroid.y - m_gestureLastCentroid.y;
      const CGFloat zoom = dist / m_gestureLastDistance;

      m_gestureMovement += std::hypot(dx, dy);
      m_gestureZoom += std::fabs(std::log(zoom));

      m_gestureLastCentroid = centroid;
      m_gestureLastDistance = dist;

      [self queueMouse:Event::MouseMove
              position:centroid
                button:Event::NoneButton
               pointer:PointerType::Touch
              pressure:0.0f];


      // Pan as a precise mouse wheel (like a trackpad)
      [self queueWheelDelta:CGPointMake(dx, dy) at:centroid];

      // Pinch to zoom
      if (std::fabs(zoom - 1.0) > 0.0005)
        [self queueMagnify:(zoom - 1.0) at:centroid pointer:PointerType::Touch];
      break;
    }

    default: break;
  }
}

- (void)fingerEnded:(UITouch*)touch cancelled:(BOOL)cancelled
{
  [m_fingers removeObject:touch];
  const NSUInteger n = m_fingers.count;

  switch (m_fingerState) {
    case FingerState::Pending:
      [self stopLongPressTimer];
      if (!cancelled) {
        // Tap = click
        [self enterAt:m_fingerStartPos pointer:PointerType::Touch];
        [self queueMouse:((touch.tapCount % 2) == 0 ? Event::MouseDoubleClick : Event::MouseDown)
                position:m_fingerStartPos
                  button:Event::LeftButton
                 pointer:PointerType::Touch
                pressure:1.0f];
        [self queueMouse:Event::MouseUp
                position:m_fingerStartPos
                  button:Event::LeftButton
                 pointer:PointerType::Touch
                pressure:0.0f];
      }
      m_fingerState = FingerState::None;
      [self scheduleMouseLeave];
      break;

    case FingerState::Dragging:
      [self queueMouse:Event::MouseUp
              position:m_fingerLastPos
                button:Event::LeftButton
               pointer:PointerType::Touch
              pressure:0.0f];
      m_fingerState = FingerState::None;
      [self scheduleMouseLeave];
      break;

    case FingerState::Gesture:
      if (n == 0) {
        if (!cancelled && m_gestureCanTap &&
            touch.timestamp - m_gestureStartTime < kMultiTapMaxDuration &&
            m_gestureMovement < kMultiTapMaxMovement && m_gestureZoom < 0.1) {
          if (m_gestureMaxFingers == 2)
            ios_dispatch_gesture(IOSGesture::Undo);
          else if (m_gestureMaxFingers == 3)
            ios_dispatch_gesture(IOSGesture::Redo);
        }
        m_fingerState = FingerState::None;
        [self scheduleMouseLeave];
      }
      else {
        [self resetGestureReference];
      }
      break;

    case FingerState::Ignored:
      if (n == 0)
        m_fingerState = FingerState::None;
      break;

    case FingerState::None: break;
  }
}

- (void)cancelFingers
{
  [self stopLongPressTimer];
  if (m_fingerState == FingerState::Dragging) {
    [self queueMouse:Event::MouseUp
            position:m_fingerLastPos
              button:Event::LeftButton
             pointer:PointerType::Touch
            pressure:0.0f];
  }
  if (m_fingers.count > 0)
    m_fingerState = FingerState::Ignored;
  else
    m_fingerState = FingerState::None;
}

- (void)startLongPressTimer
{
  [self stopLongPressTimer];
  LafViewIOS* __weak weakSelf = self;
  m_longPressTimer = [NSTimer scheduledTimerWithTimeInterval:kLongPressDelay
                                                     repeats:NO
                                                       block:^(NSTimer*) {
                                                         [weakSelf onLongPress];
                                                       }];
}

- (void)stopLongPressTimer
{
  if (m_longPressTimer) {
    [m_longPressTimer invalidate];
    m_longPressTimer = nil;
  }
}

- (void)onLongPress
{
  m_longPressTimer = nil;
  if (m_fingerState != FingerState::Pending)
    return;

  // Long press = right click
  m_fingerState = FingerState::Ignored;

  UIImpactFeedbackGenerator* feedback =
    [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
  [feedback impactOccurred];

  [self enterAt:m_fingerStartPos pointer:PointerType::Touch];
  [self queueMouse:Event::MouseDown
          position:m_fingerStartPos
            button:Event::RightButton
           pointer:PointerType::Touch
          pressure:1.0f];
  [self queueMouse:Event::MouseUp
          position:m_fingerStartPos
            button:Event::RightButton
           pointer:PointerType::Touch
          pressure:0.0f];
}

- (void)queueWheelDelta:(CGPoint)delta at:(CGPoint)pt
{
  const CGFloat s = [self pixelScale];
  const int scale = (m_impl ? m_impl->scale() : 1);

  // Natural scrolling: content follows the fingers
  m_wheelRemainder.x += -delta.x * s / scale;
  m_wheelRemainder.y += -delta.y * s / scale;

  const int ix = int(m_wheelRemainder.x);
  const int iy = int(m_wheelRemainder.y);
  if (ix == 0 && iy == 0)
    return;

  m_wheelRemainder.x -= ix;
  m_wheelRemainder.y -= iy;

  Event ev;
  ev.setType(Event::MouseWheel);
  ev.setPosition([self surfacePoint:pt]);
  ev.setModifiers(ios_key_modifiers());
  ev.setPointerType(PointerType::Touchpad);
  ev.setWheelDelta(gfx::Point(ix, iy));
  ev.setPreciseWheel(true);
  [self queueEvent:ev];
}

- (void)queueMagnify:(CGFloat)magnification at:(CGPoint)pt pointer:(PointerType)pointerType
{
  Event ev;
  ev.setType(Event::TouchMagnify);
  ev.setMagnification(float(magnification));
  ev.setPosition([self surfacePoint:pt]);
  ev.setModifiers(ios_key_modifiers());
  ev.setPointerType(pointerType);
  [self queueEvent:ev];
}

// ----------------------------------------------------------------------
// Gesture recognizers (pointer hover, scroll wheel, trackpad pinch)

- (BOOL)gestureRecognizer:(UIGestureRecognizer*)a
  shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer*)b
{
  return YES;
}

- (void)onHover:(UIHoverGestureRecognizer*)recognizer
{
  // Ignore hover events while a touch is active
  if (m_pointerTouch || m_fingerState != FingerState::None)
    return;

  PointerType pointerType = PointerType::Mouse;
  if (@available(iOS 16.1, *)) {
    if (recognizer.zOffset > 0.0)
      pointerType = PointerType::Pen;
  }

  const CGPoint pt = [recognizer locationInView:self];
  switch (recognizer.state) {
    case UIGestureRecognizerStateBegan:
      [self cancelMouseLeave];
      m_hovering = YES;
      [self queueMouse:Event::MouseEnter
              position:pt
                button:Event::NoneButton
               pointer:pointerType
              pressure:0.0f];
      [[fallthrough]];
    case UIGestureRecognizerStateChanged:
      [self queueMouse:Event::MouseMove
              position:pt
                button:Event::NoneButton
               pointer:pointerType
              pressure:0.0f];
      break;
    case UIGestureRecognizerStateEnded:
    case UIGestureRecognizerStateCancelled:
      m_hovering = NO;
      [self scheduleMouseLeave];
      break;
    default: break;
  }
}

- (void)onScroll:(UIPanGestureRecognizer*)recognizer
{
  switch (recognizer.state) {
    case UIGestureRecognizerStateBegan:
      m_lastScrollTranslation = CGPointZero;
      m_wheelRemainder = CGPointZero;
      [[fallthrough]];
    case UIGestureRecognizerStateChanged: {
      const CGPoint t = [recognizer translationInView:self];
      const CGPoint delta =
        CGPointMake(t.x - m_lastScrollTranslation.x, t.y - m_lastScrollTranslation.y);
      m_lastScrollTranslation = t;
      [self queueWheelDelta:delta at:[recognizer locationInView:self]];
      break;
    }
    default: break;
  }
}

- (void)onTrackpadPinch:(UIPinchGestureRecognizer*)recognizer
{
  switch (recognizer.state) {
    case UIGestureRecognizerStateBegan: m_lastPinchScale = 1.0; [[fallthrough]];
    case UIGestureRecognizerStateChanged: {
      const CGFloat scale = recognizer.scale;
      if (m_lastPinchScale > 0.0) {
        [self queueMagnify:(scale / m_lastPinchScale - 1.0)
                        at:[recognizer locationInView:self]
                   pointer:PointerType::Touchpad];
      }
      m_lastPinchScale = scale;
      break;
    }
    default: break;
  }
}

// ----------------------------------------------------------------------
// Apple Pencil interactions

- (void)pencilInteractionDidTap:(UIPencilInteraction*)interaction
{
  if (UIPencilInteraction.preferredTapAction != UIPencilPreferredActionIgnore)
    ios_dispatch_gesture(IOSGesture::PencilDoubleTap);
}

- (void)pencilInteraction:(UIPencilInteraction*)interaction
            didReceiveTap:(UIPencilInteractionTap*)tap API_AVAILABLE(ios(17.5))
{
  if (UIPencilInteraction.preferredTapAction != UIPencilPreferredActionIgnore)
    ios_dispatch_gesture(IOSGesture::PencilDoubleTap);
}

- (void)pencilInteraction:(UIPencilInteraction*)interaction
        didReceiveSqueeze:(UIPencilInteractionSqueeze*)squeeze API_AVAILABLE(ios(17.5))
{
  if (squeeze.phase == UIPencilInteractionPhaseEnded &&
      UIPencilInteraction.preferredSqueezeAction != UIPencilPreferredActionIgnore)
    ios_dispatch_gesture(IOSGesture::PencilSqueeze);
}

// ----------------------------------------------------------------------
// Keyboard

- (BOOL)canBecomeFirstResponder
{
  return YES;
}

- (UIEditingInteractionConfiguration)editingInteractionConfiguration
{
  // We handle three-finger taps ourselves (redo)
  return UIEditingInteractionConfigurationNone;
}

- (void)setTextInputActive:(BOOL)state
{
  if (m_textInputActive == state)
    return;

  m_textInputActive = state;
  if (state)
    [m_textInput becomeFirstResponder];
  else
    [self becomeFirstResponder];
}

- (BOOL)isTextInputActive
{
  return m_textInputActive;
}

- (void)pressesBegan:(NSSet<UIPress*>*)presses withEvent:(UIPressesEvent*)event
{
  BOOL handled = NO;
  for (UIPress* press in presses) {
    if (press.key) {
      [self handleKey:press.key down:YES];
      handled = YES;
    }
  }
  if (!handled)
    [super pressesBegan:presses withEvent:event];
}

- (void)pressesEnded:(NSSet<UIPress*>*)presses withEvent:(UIPressesEvent*)event
{
  BOOL handled = NO;
  for (UIPress* press in presses) {
    if (press.key) {
      [self handleKey:press.key down:NO];
      handled = YES;
    }
  }
  if (!handled)
    [super pressesEnded:presses withEvent:event];
}

- (void)pressesCancelled:(NSSet<UIPress*>*)presses withEvent:(UIPressesEvent*)event
{
  BOOL handled = NO;
  for (UIPress* press in presses) {
    if (press.key) {
      [self handleKey:press.key down:NO];
      handled = YES;
    }
  }
  if (!handled)
    [super pressesCancelled:presses withEvent:event];
}

- (void)handleKey:(UIKey*)key down:(BOOL)down
{
  if (!key)
    return;

  const long usage = key.keyCode;
  KeyScancode scancode = ios_scancode_from_hid_usage(usage);

  // For keys that generate characters we use the keyboard layout to
  // get the scancode (e.g. for AZERTY or Dvorak layouts).
  if (scancode == kKeyNil || is_layout_scancode(scancode)) {
    NSString* chars = key.charactersIgnoringModifiers;
    if (chars.length == 1) {
      const int chr = [chars characterAtIndex:0];
      if (chr != ' ') {
        const KeyScancode code = ios_scancode_from_char(chr);
        if (code != kKeyNil)
          scancode = code;
      }
    }
  }

  int unicodeChar = unicode_for_special_scancode(scancode);
  if (!unicodeChar) {
    NSString* chars = key.characters;
    if (chars.length == 1) {
      const unichar c = [chars characterAtIndex:0];
      // Ignore control chars and private use area chars (used for
      // function keys)
      if (c >= 32 && c != 127 && (c < 0xE000 || c > 0xF8FF))
        unicodeChar = c;
    }
  }

  if (down)
    ios_set_key_pressed(scancode, (unicodeChar ? unicodeChar : 1));
  else
    ios_set_key_pressed(scancode, 0);

  Event ev;
  ev.setType(down ? Event::KeyDown : Event::KeyUp);
  ev.setScancode(scancode);
  ev.setModifiers(modifiers_from_uikey(key));
  ev.setUnicodeChar(unicodeChar);
  ev.setRepeat(0);
  [self queueEvent:ev];

  // Auto-repeat (UIKit doesn't send repeated key presses)
  if (down) {
    if (!is_modifier_scancode(scancode))
      [self startKeyRepeat:usage scancode:scancode unicode:unicodeChar];
  }
  else if (usage == m_keyRepeatUsage) {
    [self stopKeyRepeat];
  }
}

- (void)startKeyRepeat:(long)usage scancode:(KeyScancode)scancode unicode:(int)unicodeChar
{
  [self stopKeyRepeat];

  m_keyRepeatUsage = usage;
  m_keyRepeatScancode = scancode;
  m_keyRepeatUnicode = unicodeChar;

  LafViewIOS* __weak weakSelf = self;
  m_keyRepeatTimer = [NSTimer scheduledTimerWithTimeInterval:kKeyRepeatDelay
                                                     repeats:NO
                                                       block:^(NSTimer*) {
                                                         [weakSelf onKeyRepeatStart];
                                                       }];
}

- (void)onKeyRepeatStart
{
  LafViewIOS* __weak weakSelf = self;
  m_keyRepeatTimer = [NSTimer scheduledTimerWithTimeInterval:kKeyRepeatInterval
                                                     repeats:YES
                                                       block:^(NSTimer*) {
                                                         [weakSelf onKeyRepeat];
                                                       }];
  [self onKeyRepeat];
}

- (void)onKeyRepeat
{
  Event ev;
  ev.setType(Event::KeyDown);
  ev.setScancode(m_keyRepeatScancode);
  ev.setModifiers(ios_key_modifiers());
  ev.setUnicodeChar(m_keyRepeatUnicode);
  ev.setRepeat(1);
  [self queueEvent:ev];
}

- (void)stopKeyRepeat
{
  if (m_keyRepeatTimer) {
    [m_keyRepeatTimer invalidate];
    m_keyRepeatTimer = nil;
  }
  m_keyRepeatUsage = 0;
}

- (void)resetInputState
{
  [self stopKeyRepeat];
  ios_reset_key_pressed();
}

@end

//////////////////////////////////////////////////////////////////////
// LafToolbarIOS: on-screen modifier keys and some shortcuts

@interface LafToolbarIOS : UIView
@end

@implementation LafToolbarIOS {
  NSMutableDictionary<NSNumber*, UIButton*>* m_stickyButtons;
  UIButton* m_fingerButton;
}

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    m_stickyButtons = [NSMutableDictionary dictionary];
    self.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];

    UIStackView* left = [[UIStackView alloc] init];
    left.axis = UILayoutConstraintAxisHorizontal;
    left.spacing = 4;
    left.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView* right = [[UIStackView alloc] init];
    right.axis = UILayoutConstraintAxisHorizontal;
    right.spacing = 4;
    right.translatesAutoresizingMaskIntoConstraints = NO;

    m_fingerButton = [self buttonWithSymbol:@"hand.draw" title:@"Finger Draw"];
    [m_fingerButton addTarget:self
                       action:@selector(onFingerDraw:)
             forControlEvents:UIControlEventTouchUpInside];
    [self updateStickyButton:m_fingerButton state:ios_is_finger_drawing_enabled()];
    [left addArrangedSubview:m_fingerButton];

    UIView* separator = [[UIView alloc] init];
    [separator.widthAnchor constraintEqualToConstant:8].active = YES;
    [left addArrangedSubview:separator];

    [left addArrangedSubview:[self stickyButton:@"shift" title:@"Shift" scancode:kKeyLShift]];
    [left addArrangedSubview:[self stickyButton:@"control" title:@"Ctrl" scancode:kKeyLControl]];
    [left addArrangedSubview:[self stickyButton:@"option" title:@"Alt" scancode:kKeyAlt]];
    [left addArrangedSubview:[self stickyButton:@"command" title:@"Cmd" scancode:kKeyCommand]];
    [left addArrangedSubview:[self stickyButton:@"space" title:@"Space" scancode:kKeySpace]];

    [right addArrangedSubview:[self keyButton:@"escape" title:@"Esc" scancode:kKeyEsc unicode:27]];
    [right addArrangedSubview:[self keyButton:@"delete.left" title:@"Del" scancode:kKeyDel unicode:0]];
    [right addArrangedSubview:[self keyButton:@"return" title:@"Enter" scancode:kKeyEnter unicode:13]];
    [right addArrangedSubview:[self actionButton:@"arrow.uturn.backward"
                                           title:@"Undo"
                                          action:@selector(onUndo)]];
    [right addArrangedSubview:[self actionButton:@"arrow.uturn.forward"
                                           title:@"Redo"
                                          action:@selector(onRedo)]];
    [right addArrangedSubview:[self actionButton:@"keyboard"
                                           title:@"Keyboard"
                                          action:@selector(onKeyboard)]];

    [self addSubview:left];
    [self addSubview:right];
    [NSLayoutConstraint activateConstraints:@[
      [left.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
      [left.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [right.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
      [right.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [left.heightAnchor constraintEqualToAnchor:self.heightAnchor constant:-8],
      [right.heightAnchor constraintEqualToAnchor:self.heightAnchor constant:-8],
    ]];
  }
  return self;
}

- (UIButton*)buttonWithSymbol:(NSString*)symbol title:(NSString*)title
{
  UIButtonConfiguration* config = [UIButtonConfiguration grayButtonConfiguration];
  config.image = [UIImage systemImageNamed:symbol];
  config.title = title;
  config.imagePadding = 4;
  config.preferredSymbolConfigurationForImage =
    [UIImageSymbolConfiguration configurationWithPointSize:11];
  config.titleTextAttributesTransformer = ^NSDictionary*(NSDictionary* attrs) {
    NSMutableDictionary* out = [attrs mutableCopy];
    out[NSFontAttributeName] = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    return out;
  };
  config.contentInsets = NSDirectionalEdgeInsetsMake(2, 8, 2, 8);
  config.baseForegroundColor = [UIColor colorWithWhite:0.9 alpha:1.0];
  config.baseBackgroundColor = [UIColor colorWithWhite:0.22 alpha:1.0];

  UIButton* button = [UIButton buttonWithConfiguration:config primaryAction:nil];
  button.pointerInteractionEnabled = YES;
  return button;
}

- (UIButton*)stickyButton:(NSString*)symbol title:(NSString*)title scancode:(KeyScancode)scancode
{
  UIButton* button = [self buttonWithSymbol:symbol title:title];
  button.tag = scancode;
  [button addTarget:self action:@selector(onSticky:) forControlEvents:UIControlEventTouchUpInside];
  m_stickyButtons[@(scancode)] = button;
  return button;
}

- (UIButton*)keyButton:(NSString*)symbol
                 title:(NSString*)title
              scancode:(KeyScancode)scancode
               unicode:(int)unicodeChar
{
  UIButton* button = [self buttonWithSymbol:symbol title:title];
  button.tag = (scancode | (unicodeChar << 16));
  [button addTarget:self action:@selector(onKey:) forControlEvents:UIControlEventTouchUpInside];
  return button;
}

- (UIButton*)actionButton:(NSString*)symbol title:(NSString*)title action:(SEL)action
{
  UIButton* button = [self buttonWithSymbol:symbol title:title];
  [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
  return button;
}

- (void)updateStickyButton:(UIButton*)button state:(BOOL)state
{
  UIButtonConfiguration* config = button.configuration;
  config.baseBackgroundColor =
    (state ? [UIColor systemBlueColor] : [UIColor colorWithWhite:0.22 alpha:1.0]);
  config.baseForegroundColor = (state ? [UIColor whiteColor] : [UIColor colorWithWhite:0.9 alpha:1.0]);
  button.configuration = config;
}

- (void)onSticky:(UIButton*)button
{
  const KeyScancode scancode = (KeyScancode)button.tag;
  const bool state = !ios_is_sticky_key(scancode);
  ios_set_sticky_key(scancode, state);
  [self updateStickyButton:button state:state];

  Event ev;
  ev.setType(state ? Event::KeyDown : Event::KeyUp);
  ev.setScancode(scancode);
  ev.setModifiers(ios_key_modifiers());
  ev.setUnicodeChar(0);
  ev.setRepeat(0);
  if (LafViewIOS* view = ios_main_view(); view && [view impl])
    [view impl]->queueEvent(ev);
  else
    queue_event(ev);
}

- (void)onFingerDraw:(UIButton*)button
{
  const bool state = !ios_is_finger_drawing_enabled();
  ios_set_finger_drawing_enabled(state);
  [self updateStickyButton:button state:state];
}

- (void)onKey:(UIButton*)button
{
  const KeyScancode scancode = (KeyScancode)(button.tag & 0xffff);
  const int unicodeChar = int(button.tag >> 16);
  ios_queue_key_press(scancode, unicodeChar, ios_key_modifiers());
}

- (void)onUndo
{
  ios_dispatch_gesture(IOSGesture::Undo);
}

- (void)onRedo
{
  ios_dispatch_gesture(IOSGesture::Redo);
}

- (void)onKeyboard
{
  if (LafViewIOS* view = ios_main_view())
    [view setTextInputActive:![view isTextInputActive]];
}

@end

//////////////////////////////////////////////////////////////////////
// LafViewControllerIOS

@implementation LafViewControllerIOS {
  LafViewIOS* m_lafView;
  LafToolbarIOS* m_toolbar;
  BOOL m_toolbarVisible;
}

- (void)loadView
{
  UIView* root = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
  root.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];

  m_lafView = [[LafViewIOS alloc] initWithFrame:root.bounds];
  m_toolbar = [[LafToolbarIOS alloc] initWithFrame:CGRectZero];
  m_toolbarVisible = YES;

  [root addSubview:m_lafView];
  [root addSubview:m_toolbar];
  self.view = root;

  g_mainView = m_lafView;
  g_mainViewController = self;
}

- (LafViewIOS*)lafView
{
  return m_lafView;
}

- (void)viewDidLayoutSubviews
{
  [super viewDidLayoutSubviews];

  const CGRect bounds = self.view.bounds;
  const UIEdgeInsets safe = self.view.safeAreaInsets;
  const CGFloat toolbarHeight = (m_toolbarVisible ? 36.0 : 0.0);
  const CGFloat width = bounds.size.width - safe.left - safe.right;

  m_toolbar.hidden = !m_toolbarVisible;
  m_toolbar.frame = CGRectMake(safe.left, safe.top, width, toolbarHeight);
  m_lafView.frame = CGRectMake(safe.left,
                               safe.top + toolbarHeight,
                               width,
                               bounds.size.height - safe.top - safe.bottom - toolbarHeight);
}

- (void)setToolbarVisible:(BOOL)state
{
  if (m_toolbarVisible == state)
    return;
  m_toolbarVisible = state;
  [self.view setNeedsLayout];
}

- (BOOL)isToolbarVisible
{
  return m_toolbarVisible;
}

- (BOOL)prefersStatusBarHidden
{
  return YES;
}

- (UIEditingInteractionConfiguration)editingInteractionConfiguration
{
  return UIEditingInteractionConfigurationNone;
}

- (BOOL)prefersHomeIndicatorAutoHidden
{
  return YES;
}

- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures
{
  return UIRectEdgeAll;
}

@end
