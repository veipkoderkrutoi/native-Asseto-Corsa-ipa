#import <UIKit/UIKit.h>

/// AC-styled modal for importing a user-owned AC folder or Content Pack.
/// Handles the real UIDocumentPicker, structure validation, scoped access and
/// file-by-file copying into the app's Documents/AC-iOS directory.
@interface ACImportPopup : UIView <UIDocumentPickerDelegate>

- (instancetype)initWithPresenter:(UIViewController *)presenter
                       completion:(void (^)(NSURL * _Nullable root, NSUInteger cars,
                                            NSUInteger tracks, NSError * _Nullable error))completion;
- (void)showInView:(UIView *)view;
- (void)dismiss;

@end
