// LAF OS Library
// Copyright (C) 2026  Emir Yaman Sivrikaya
//
// This file is released under the terms of the MIT license.
// Read LICENSE.txt for more information.

#ifndef OS_IOS_APP_H_INCLUDED
#define OS_IOS_APP_H_INCLUDED
#pragma once

namespace os {

using AppMainFunc = int (*)(int argc, char* argv[]);

// Starts UIKit (UIApplicationMain) and calls appMain() from the main
// thread once the first window scene is connected. When appMain()
// returns, the process is terminated with its exit code.
int ios_main(int argc, char* argv[], AppMainFunc appMain);

} // namespace os

#endif
