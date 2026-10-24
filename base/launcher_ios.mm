// LAF Base Library
// Copyright (c) 2026  Emir Yaman Sivrikaya
//
// This file is released under the terms of the MIT license.
// Read LICENSE.txt for more information.

#ifdef HAVE_CONFIG_H
  #include "config.h"
#endif

#include <UIKit/UIKit.h>

#include <string>

namespace base { namespace launcher {

bool ios_open_url(const std::string& url, bool isFile)
{
  @autoreleasepool {
    NSString* str = [NSString stringWithUTF8String:url.c_str()];
    if (!str)
      return false;

    NSURL* nsurl = nil;
    if (isFile) {
      // Open the location in the Files app (shareddocuments:// scheme
      // shows the given folder of our app sandbox).
      NSURL* fileUrl = [NSURL fileURLWithPath:str];
      NSURLComponents* comps = [NSURLComponents componentsWithURL:fileUrl
                                          resolvingAgainstBaseURL:NO];
      comps.scheme = @"shareddocuments";
      nsurl = comps.URL;
    }
    else {
      nsurl = [NSURL URLWithString:str];
    }
    if (!nsurl)
      return false;

    UIApplication* app = [UIApplication sharedApplication];
    if (![app canOpenURL:nsurl] && !isFile)
      return false;

    [app openURL:nsurl options:@{} completionHandler:nil];
    return true;
  }
}

}} // namespace base::launcher
