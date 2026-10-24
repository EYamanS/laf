// LAF Base Library
// Copyright (c) 2026  Emir Yaman Sivrikaya
//
// This file is released under the terms of the MIT license.
// Read LICENSE.txt for more information.

#ifdef HAVE_CONFIG_H
  #include "config.h"
#endif

#include "base/security_scope_ios.h"

#include <Foundation/Foundation.h>

namespace base {

static NSString* const kBookmarksKey = @"LafSecurityScopedBookmarks";
static const NSUInteger kMaxBookmarks = 64;

static NSData* make_bookmark(NSURL* url)
{
  return [url bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark
       includingResourceValuesForKeys:nil
                        relativeToURL:nil
                                error:nil];
}

static void save_bookmark(NSString* path, NSData* data)
{
  NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
  NSMutableArray* list = [NSMutableArray array];
  [list addObject:@{ @"path" : path, @"data" : data }];

  // Most recent first, without duplicates
  for (NSDictionary* item in [defaults arrayForKey:kBookmarksKey]) {
    if (list.count >= kMaxBookmarks)
      break;
    if (![item isKindOfClass:[NSDictionary class]] || [item[@"path"] isEqual:path])
      continue;
    [list addObject:item];
  }
  [defaults setObject:list forKey:kBookmarksKey];
}

void ios_keep_access(void* nsurl)
{
  @autoreleasepool {
    NSURL* url = (__bridge NSURL*)nsurl;
    if (!url || !url.isFileURL)
      return;

    // Returns NO for files inside our sandbox, which don't need it
    if (![url startAccessingSecurityScopedResource])
      return;

    if (NSData* data = make_bookmark(url))
      save_bookmark(url.path, data);
  }
}

void ios_restore_access()
{
  @autoreleasepool {
    NSArray* list = [[NSUserDefaults standardUserDefaults] arrayForKey:kBookmarksKey];
    for (NSDictionary* item in list) {
      if (![item isKindOfClass:[NSDictionary class]])
        continue;

      NSData* data = item[@"data"];
      if (![data isKindOfClass:[NSData class]])
        continue;

      BOOL stale = NO;
      NSURL* url = [NSURL URLByResolvingBookmarkData:data
                                             options:0
                                       relativeToURL:nil
                                 bookmarkDataIsStale:&stale
                                               error:nil];
      if (!url || ![url startAccessingSecurityScopedResource])
        continue;

      if (stale) {
        if (NSData* newData = make_bookmark(url))
          save_bookmark(url.path, newData);
      }
    }
  }
}

} // namespace base
