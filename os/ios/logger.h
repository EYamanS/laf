// LAF OS Library
// Copyright (C) 2026  Emir Yaman Sivrikaya
//
// This file is released under the terms of the MIT license.
// Read LICENSE.txt for more information.

#ifndef OS_IOS_LOGGER_H_INCLUDED
#define OS_IOS_LOGGER_H_INCLUDED
#pragma once

#include "os/logger.h"

namespace os {

class LoggerIOS : public Logger {
public:
  void logError(const char* error) override;
};

} // namespace os

#endif
