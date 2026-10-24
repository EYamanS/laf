// LAF Dialogs Library
// Copyright (C) 2026  Emir Yaman Sivrikaya
//
// This file is released under the terms of the MIT license.
// Read LICENSE.txt for more information.

#ifdef HAVE_CONFIG_H
  #include "config.h"
#endif

#include "dlgs/file_dialog.h"

#include "base/fs.h"
#include "base/security_scope_ios.h"

#include <UIKit/UIKit.h>
#include <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface LafDocumentPickerDelegate : NSObject <UIDocumentPickerDelegate>
@property (nonatomic) BOOL done;
@property (nonatomic, strong) NSArray<NSURL*>* urls;
@end

@implementation LafDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController*)controller
  didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls
{
  self.urls = urls;
  self.done = YES;
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController*)controller
{
  self.urls = nil;
  self.done = YES;
}

@end

namespace dlgs {

namespace {

// The dialogs are modal: we run the main run loop until the user
// closes them (the app is already running inside the UIKit run loop).
void run_until(BOOL (^condition)(void))
{
  while (!condition()) {
    @autoreleasepool {
      CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, true);
    }
  }
}

UIViewController* top_view_controller(UIView* view)
{
  UIViewController* vc = view.window.rootViewController;
  if (!vc) {
    for (UIScene* scene in [UIApplication sharedApplication].connectedScenes) {
      if ([scene isKindOfClass:[UIWindowScene class]]) {
        vc = ((UIWindowScene*)scene).keyWindow.rootViewController;
        if (vc)
          break;
      }
    }
  }
  while (vc.presentedViewController)
    vc = vc.presentedViewController;
  return vc;
}

void present(UIViewController* parent, UIViewController* vc)
{
  // Wait until a previous dialog is completely dismissed
  run_until(^BOOL {
    return parent.presentedViewController == nil;
  });
  [parent presentViewController:vc animated:YES completion:nil];
}

NSString* to_nsstring(const std::string& str)
{
  return [NSString stringWithUTF8String:str.c_str()];
}

} // anonymous namespace

class FileDialogIOS : public FileDialog {
public:
  std::string fileName() override { return (m_files.empty() ? m_filename : m_files.front()); }

  void getMultipleFileNames(base::paths& output) override { output = m_files; }

  void setFileName(const std::string& filename) override { m_filename = filename; }

  Result show(void* windowNative) override
  {
    @autoreleasepool {
      UIView* view = (__bridge UIView*)windowNative;
      UIViewController* parent = top_view_controller(view);
      if (!parent)
        return Result::Error;

      m_files.clear();
      Result result = (m_type == Type::SaveFile ? showSave(parent) : showOpen(parent));

      // Give the keyboard focus back to the app view
      run_until(^BOOL {
        return parent.presentedViewController == nil;
      });
      [view becomeFirstResponder];
      return result;
    }
  }

private:
  NSArray<UTType*>* contentTypes() const
  {
    if (m_type == Type::OpenFolder)
      return @[ UTTypeFolder ];

    NSMutableArray<UTType*>* types = [NSMutableArray array];
    for (const auto& filter : m_filters) {
      if (UTType* type = [UTType typeWithFilenameExtension:to_nsstring(filter.first)])
        [types addObject:type];
    }
    if (types.count == 0)
      [types addObject:UTTypeItem];
    return types;
  }

  NSURL* initialDirectory() const
  {
    std::string dir = m_filename;
    if (!dir.empty() && !base::is_directory(dir))
      dir = base::get_file_path(dir);
    if (dir.empty() || !base::is_directory(dir))
      return nil;
    return [NSURL fileURLWithPath:to_nsstring(dir) isDirectory:YES];
  }

  NSArray<NSURL*>* pick(UIViewController* parent,
                        NSArray<UTType*>* types,
                        bool multiple,
                        NSURL* directory)
  {
    LafDocumentPickerDelegate* delegate = [[LafDocumentPickerDelegate alloc] init];
    UIDocumentPickerViewController* picker =
      [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:NO];
    picker.delegate = delegate;
    picker.allowsMultipleSelection = (multiple ? YES : NO);
    picker.shouldShowFileExtensions = YES;
    picker.modalInPresentation = YES;
    if (directory)
      picker.directoryURL = directory;

    present(parent, picker);
    run_until(^BOOL {
      return delegate.done;
    });
    return delegate.urls;
  }

  Result showOpen(UIViewController* parent)
  {
    NSArray<NSURL*>* urls =
      pick(parent, contentTypes(), m_type == Type::OpenFiles, initialDirectory());
    if (urls.count == 0)
      return Result::Cancel;

    for (NSURL* url in urls) {
      base::ios_keep_access((__bridge void*)url);
      m_files.push_back(url.path.fileSystemRepresentation);
    }
    return Result::OK;
  }

  // Asks the file name, and then where to save it: in the app
  // Documents folder or in a folder picked with the Files app.
  Result showSave(UIViewController* parent)
  {
    enum { Cancel, Documents, ChooseFolder };
    __block int action = -1;
    __block NSString* name = nil;

    std::string initialName = base::get_file_name(m_filename);
    if (initialName.empty() && !m_defExtension.empty())
      initialName = "Untitled." + m_defExtension;

    UIAlertController* alert =
      [UIAlertController alertControllerWithTitle:(m_title.empty() ? @"Save" : to_nsstring(m_title))
                                          message:nil
                                   preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField* field) {
      field.text = to_nsstring(initialName);
      field.placeholder = @"File name";
      field.autocorrectionType = UITextAutocorrectionTypeNo;
      field.autocapitalizationType = UITextAutocapitalizationTypeNone;
      field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    UIAlertController* __weak weakAlert = alert;
    auto addAction = ^(NSString* title, UIAlertActionStyle style, int value) {
      [alert addAction:[UIAlertAction actionWithTitle:title
                                                style:style
                                              handler:^(UIAlertAction*) {
                                                name = weakAlert.textFields.firstObject.text;
                                                action = value;
                                              }]];
    };
    addAction(@"Save in Aseprite Folder", UIAlertActionStyleDefault, Documents);
    addAction(@"Choose Folder…", UIAlertActionStyleDefault, ChooseFolder);
    addAction(@"Cancel", UIAlertActionStyleCancel, Cancel);

    present(parent, alert);
    run_until(^BOOL {
      return action >= 0;
    });

    name = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (action == Cancel || name.length == 0)
      return Result::Cancel;

    std::string filename = name.fileSystemRepresentation;
    if (base::get_file_extension(filename).empty() && !m_defExtension.empty())
      filename += "." + m_defExtension;

    NSURL* folder = nil;
    if (action == ChooseFolder) {
      NSArray<NSURL*>* urls = pick(parent, @[ UTTypeFolder ], false, initialDirectory());
      if (urls.count == 0)
        return Result::Cancel;
      folder = urls.firstObject;
      base::ios_keep_access((__bridge void*)folder);
    }
    else {
      folder = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                                      inDomains:NSUserDomainMask]
                 .firstObject;
    }
    if (!folder)
      return Result::Error;

    std::string path = base::join_path(folder.path.fileSystemRepresentation, filename);
    if (base::is_file(path) && !confirmReplace(parent, filename))
      return Result::Cancel;

    m_files.push_back(path);
    return Result::OK;
  }

  bool confirmReplace(UIViewController* parent, const std::string& filename)
  {
    __block int answer = -1;
    UIAlertController* alert = [UIAlertController
      alertControllerWithTitle:[NSString stringWithFormat:@"\"%@\" already exists",
                                                          to_nsstring(filename)]
                       message:@"Do you want to replace it?"
                preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Replace"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction*) {
                                              answer = 1;
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction*) {
                                              answer = 0;
                                            }]];
    present(parent, alert);
    run_until(^BOOL {
      return answer >= 0;
    });
    return (answer == 1);
  }

  std::string m_filename;
  base::paths m_files;
};

FileDialogRef FileDialog::makeIOS(const Spec&)
{
  return base::make_ref<FileDialogIOS>();
}

} // namespace dlgs
