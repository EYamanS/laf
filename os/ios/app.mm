// LAF OS Library
// Copyright (C) 2026  Emir Yaman Sivrikaya
//
// This file is released under the terms of the MIT license.
// Read LICENSE.txt for more information.

#ifdef HAVE_CONFIG_H
  #include "config.h"
#endif

#include "os/ios/app.h"

#include "base/paths.h"
#include "os/event.h"
#include "os/event_queue.h"
#include "os/ios/system.h"
#include "os/ios/view.h"

#include <UIKit/UIKit.h>

#include <cstdlib>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace {

int g_argc = 0;
char** g_argv = nullptr;
os::AppMainFunc g_appMain = nullptr;
bool g_appMainStarted = false;

// Files to open passed to app_main() as arguments (files opened from
// other apps before the app was started)
std::vector<std::string> g_initialFiles;

std::mutex g_backgroundMutex;
std::shared_ptr<std::function<void()>> g_backgroundHandler;

std::string path_from_url(NSURL* url)
{
  if (!url || !url.isFileURL)
    return std::string();

  // Files outside our sandbox (opened in place from the Files app)
  // need a security-scoped access. We keep the access during the
  // whole life of the app to be able to save the file too.
  [url startAccessingSecurityScopedResource];
  return std::string(url.path.fileSystemRepresentation);
}

void open_urls(NSSet<UIOpenURLContext*>* contexts)
{
  base::paths files;
  for (UIOpenURLContext* ctx in contexts) {
    std::string fn = path_from_url(ctx.URL);
    if (!fn.empty())
      files.push_back(fn);
  }
  if (files.empty())
    return;

  if (!g_appMainStarted) {
    g_initialFiles.insert(g_initialFiles.end(), files.begin(), files.end());
    return;
  }

  os::Event ev;
  ev.setType(os::Event::DropFiles);
  ev.setFiles(files);
  os::queue_event(ev);
}

void start_app_main()
{
  if (g_appMainStarted)
    return;
  g_appMainStarted = true;

  std::vector<char*> args(g_argv, g_argv + g_argc);
  for (const auto& fn : g_initialFiles)
    args.push_back(strdup(fn.c_str()));
  args.push_back(nullptr);
  g_initialFiles.clear();

  const int code = g_appMain(int(args.size() - 1), args.data());
  std::exit(code);
}

} // anonymous namespace

//////////////////////////////////////////////////////////////////////

@interface LafSceneDelegateIOS : UIResponder <UIWindowSceneDelegate>
@property (strong, nonatomic) UIWindow* window;
@end

@implementation LafSceneDelegateIOS

- (void)scene:(UIScene*)scene
  willConnectToSession:(UISceneSession*)session
               options:(UISceneConnectionOptions*)options
{
  if (![scene isKindOfClass:[UIWindowScene class]])
    return;

  // Only one scene is supported
  if (ios_main_view())
    return;

  UIWindowScene* windowScene = (UIWindowScene*)scene;
  self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
  self.window.rootViewController = [[LafViewControllerIOS alloc] init];
  [self.window makeKeyAndVisible];

  open_urls(options.URLContexts);

  // Start the app main loop once UIKit has finished connecting the
  // scene (this callback must return first).
  [self performSelector:@selector(startApp) withObject:nil afterDelay:0.0];
}

- (void)startApp
{
  start_app_main();
}

- (void)scene:(UIScene*)scene openURLContexts:(NSSet<UIOpenURLContext*>*)contexts
{
  open_urls(contexts);
}

- (void)sceneWillResignActive:(UIScene*)scene
{
  // Keys released while the app is inactive will not generate
  // pressesEnded events.
  [ios_main_view() resetInputState];
}

- (void)sceneDidEnterBackground:(UIScene*)scene
{
  std::shared_ptr<std::function<void()>> handler;
  {
    const std::lock_guard lock(g_backgroundMutex);
    handler = g_backgroundHandler;
  }
  if (!handler)
    return;

  // Ask for some time to complete the handler before the app is
  // suspended.
  UIApplication* app = [UIApplication sharedApplication];
  auto task = std::make_shared<UIBackgroundTaskIdentifier>(UIBackgroundTaskInvalid);
  auto endTask = [app, task] {
    if (*task != UIBackgroundTaskInvalid) {
      [app endBackgroundTask:*task];
      *task = UIBackgroundTaskInvalid;
    }
  };
  *task = [app beginBackgroundTaskWithExpirationHandler:^{
    endTask();
  }];

  os::Event ev;
  ev.setType(os::Event::Callback);
  ev.setCallback([handler, endTask] {
    (*handler)();
    endTask();
  });
  os::queue_event(ev);
}

@end

//////////////////////////////////////////////////////////////////////

@interface LafAppDelegateIOS : UIResponder <UIApplicationDelegate>
@end

@implementation LafAppDelegateIOS

- (BOOL)application:(UIApplication*)application
  didFinishLaunchingWithOptions:(NSDictionary<UIApplicationLaunchOptionsKey, id>*)launchOptions
{
  return YES;
}

- (UISceneConfiguration*)application:(UIApplication*)application
  configurationForConnectingSceneSession:(UISceneSession*)session
                                 options:(UISceneConnectionOptions*)options
{
  UISceneConfiguration* config = [[UISceneConfiguration alloc] initWithName:@"Default"
                                                                sessionRole:session.role];
  config.delegateClass = [LafSceneDelegateIOS class];
  return config;
}

@end

//////////////////////////////////////////////////////////////////////

namespace os {

void ios_set_background_handler(std::function<void()>&& handler)
{
  const std::lock_guard lock(g_backgroundMutex);
  if (handler)
    g_backgroundHandler = std::make_shared<std::function<void()>>(std::move(handler));
  else
    g_backgroundHandler.reset();
}

int ios_main(int argc, char* argv[], AppMainFunc appMain)
{
  g_argc = argc;
  g_argv = argv;
  g_appMain = appMain;

  // The working directory is the Documents folder (the only folder
  // visible to the user)
  @autoreleasepool {
    NSArray* dirs =
      NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (dirs.count > 0)
      [[NSFileManager defaultManager] changeCurrentDirectoryPath:dirs.firstObject];
  }

  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([LafAppDelegateIOS class]));
  }
}

} // namespace os
