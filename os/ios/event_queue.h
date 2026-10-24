// LAF OS Library
// Copyright (C) 2026  Emir Yaman Sivrikaya
//
// This file is released under the terms of the MIT license.
// Read LICENSE.txt for more information.

#ifndef OS_IOS_EVENT_QUEUE_INCLUDED
#define OS_IOS_EVENT_QUEUE_INCLUDED
#pragma once

#include "os/event.h"
#include "os/event_queue.h"

#include <CoreFoundation/CoreFoundation.h>

#include <deque>
#include <mutex>

namespace os {

// The app_main() function runs inside the UIKit main run loop (it's
// called from a UIKit callback), so to get events we run the main
// CFRunLoop in a nested way until we receive some os::Event.
class EventQueueIOS : public EventQueue {
public:
  EventQueueIOS();
  ~EventQueueIOS();

  void getEvent(Event& ev, double timeout) override;
  void queueEvent(const Event& ev) override;
  void clearEvents() override;

private:
  bool popEvent(Event& ev);
  void wakeUpQueue();

  std::deque<Event> m_events;
  mutable std::mutex m_mutex;

  // Run loop source used to wake up the nested CFRunLoopRunInMode()
  // call when a new event is queued (from any thread).
  CFRunLoopSourceRef m_wakeUpSource = nullptr;
  CFRunLoopRef m_mainRunLoop = nullptr;
};

using EventQueueImpl = EventQueueIOS;

} // namespace os

#endif
