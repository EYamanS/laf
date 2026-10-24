// LAF OS Library
// Copyright (C) 2026  Emir Yaman Sivrikaya
//
// This file is released under the terms of the MIT license.
// Read LICENSE.txt for more information.

#ifdef HAVE_CONFIG_H
  #include "config.h"
#endif

#include "os/ios/event_queue.h"

#include "os/ios/window.h"

#include <Foundation/Foundation.h>

#include <algorithm>

namespace os {

namespace {

// The source doesn't need to do anything, it's only used to make
// CFRunLoopRunInMode() return when an event is queued.
void wake_up_source_perform(void*)
{
}

} // anonymous namespace

EventQueueIOS::EventQueueIOS()
{
}

EventQueueIOS::~EventQueueIOS()
{
  if (m_wakeUpSource) {
    CFRunLoopSourceInvalidate(m_wakeUpSource);
    CFRelease(m_wakeUpSource);
  }
}

void EventQueueIOS::getEvent(Event& ev, double timeout)
{
  ev.setType(Event::None);
  ev.setWindow(nullptr);

  // The event queue is always used from the main thread, so we can
  // create the wake-up run loop source here.
  if (!m_wakeUpSource) {
    CFRunLoopSourceContext ctx = {};
    ctx.perform = wake_up_source_perform;

    const std::lock_guard lock(m_mutex);
    m_mainRunLoop = CFRunLoopGetMain();
    m_wakeUpSource = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &ctx);
    CFRunLoopAddSource(m_mainRunLoop, m_wakeUpSource, kCFRunLoopCommonModes);
  }

  @autoreleasepool {
    // The app has finished processing the previous events (and
    // painting), so we can show the new content of windows on the
    // screen.
    ios_present_windows();

    const CFAbsoluteTime deadline =
      (timeout == kWithoutTimeout ? 0.0 : CFAbsoluteTimeGetCurrent() + std::max(0.0, timeout));

    // Process all pending UIKit events (touches, keys, etc.) without
    // waiting.
    while (CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, true) == kCFRunLoopRunHandledSource) {
    }

    for (;;) {
      if (popEvent(ev))
        return;

      CFTimeInterval secs;
      if (timeout == kWithoutTimeout) {
        secs = 60.0 * 60.0;
      }
      else {
        secs = deadline - CFAbsoluteTimeGetCurrent();
        if (secs <= 0.0)
          return;
      }

      // Wait for UIKit events or a wake-up signal (queueEvent())
      CFRunLoopRunInMode(kCFRunLoopDefaultMode, secs, true);
    }
  }
}

bool EventQueueIOS::popEvent(Event& ev)
{
  const std::lock_guard lock(m_mutex);
  if (m_events.empty())
    return false;

  ev = m_events.front();
  m_events.pop_front();
  return true;
}

void EventQueueIOS::queueEvent(const Event& ev)
{
  const std::lock_guard lock(m_mutex);
  m_events.push_back(ev);
  wakeUpQueue();
}

void EventQueueIOS::wakeUpQueue()
{
  if (m_wakeUpSource) {
    CFRunLoopSourceSignal(m_wakeUpSource);
    CFRunLoopWakeUp(m_mainRunLoop);
  }
}

void EventQueueIOS::clearEvents()
{
  const std::lock_guard lock(m_mutex);
  m_events.clear();
}

} // namespace os
