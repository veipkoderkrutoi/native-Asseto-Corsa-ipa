#import <UIKit/UIKit.h>

/// Posted when the user picks a new Assetto Corsa folder.
extern NSNotificationName const ACiOSRootDidChangeNotification;

@interface AppDelegate : UIResponder <UIApplicationDelegate, UIDocumentPickerDelegate>
@property (nonatomic, strong) UIWindow *window;
/// Security-scoped URL of a user-imported, legally owned Assetto Corsa install.
@property (nonatomic, strong, nullable) NSURL *acRootURL;

/// Presents the iOS document picker for choosing the AC installation folder.
- (void)chooseACRootFrom:(UIViewController *)presenter;

/// Creates a security-scoped bookmark. Caller stores the returned data.
+ (nullable NSData *)bookmarkForURL:(NSURL *)url;

/// Resolves, validates and starts access to a stored security-scoped bookmark.
+ (nullable NSURL *)resolveBookmark:(NSData *)data;
@end
