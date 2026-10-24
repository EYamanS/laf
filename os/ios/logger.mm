// LAF OS Library
// Copyright (C) 2026  Emir Yaman Sivrikaya
//
// This file is released under the terms of the MIT license.
// Read LICENSE.txt for more information.

#ifdef HAVE_CONFIG_H
  #include "config.h"
#endif

#include "os/ios/logger.h"

#include <Foundation/Foundation.h>

namespace os {

void LoggerIOS::logError(const char* error)
{
  NSLog(@"%@", [NSString stringWithUTF8String:error]);
}

} // namespace os
