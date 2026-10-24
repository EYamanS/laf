// LAF Base Library
// Copyright (c) 2026  Emir Yaman Sivrikaya
//
// This file is released under the terms of the MIT license.
// Read LICENSE.txt for more information.

#ifndef BASE_SECURITY_SCOPE_IOS_H_INCLUDED
#define BASE_SECURITY_SCOPE_IOS_H_INCLUDED
#pragma once

namespace base {

// Files/folders picked by the user outside the app sandbox (e.g. in
// iCloud Drive) can only be accessed while their security-scoped URL
// is "accessed". This starts the access to the given NSURL* and saves
// a bookmark so the access can be restored in future sessions.
void ios_keep_access(void* nsurl);

// Restores the access to all the files/folders saved with
// ios_keep_access(). Called once at startup.
void ios_restore_access();

} // namespace base

#endif
