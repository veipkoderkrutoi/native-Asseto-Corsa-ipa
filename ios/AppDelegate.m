#import "AppDelegate.h"
#import "GameViewController.h"
#import "ios_bridge.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

NSNotificationName const ACiOSRootDidChangeNotification = @"ACiOSRootDidChangeNotification";

static NSString *const kACRootBookmarkKey = @"ac.root.bookmark";

@implementation AppDelegate

+ (nullable NSData *)bookmarkForURL:(NSURL *)url {
    NSError *error = nil;
    // iOS has no NSURLBookmarkCreationWithSecurityScope: a security scope is
    // embedded implicitly in document-picker bookmarks (NSURL.h). Options 0.
    NSData *data = [url bookmarkDataWithOptions:0
                 includingResourceValuesForKeys:nil
                                  relativeToURL:nil
                                          error:&error];
    if (!data) {
        NSLog(@"AC bookmark creation failed: %@", error);
    }
    return data;
}

+ (nullable NSURL *)resolveBookmark:(NSData *)data {
    BOOL stale = NO;
    NSError *error = nil;
    NSURL *url = [NSURL URLByResolvingBookmarkData:data
                                          options:0
                                    relativeToURL:nil
                              bookmarkDataIsStale:&stale
                                            error:&error];
    if (!url) {
        NSLog(@"AC bookmark resolve failed: %@", error);
        return nil;
    }
    if (![url startAccessingSecurityScopedResource]) {
        NSLog(@"AC security scope could not be started: %@", url);
        return nil;
    }
    if (stale) {
        NSData *fresh = [AppDelegate bookmarkForURL:url];
        if (fresh) {
            [[NSUserDefaults standardUserDefaults] setObject:fresh forKey:kACRootBookmarkKey];
        }
    }
    return url;
}

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary<UIApplicationLaunchOptionsKey, id> *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

    NSData *bookmark = [[NSUserDefaults standardUserDefaults] dataForKey:kACRootBookmarkKey];
    if (bookmark) {
        self.acRootURL = [AppDelegate resolveBookmark:bookmark];
    }

    GameViewController *game = [[GameViewController alloc] init];
    game.acRootURL = self.acRootURL;
    self.window.rootViewController = game;
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)chooseACRootFrom:(UIViewController *)presenter {
    // iOS SDK does not expose UTType.folder as a class property; the public.folder
    // identifier is the canonical UTI (verified against iPhoneOS17.4 UTType.h).
    UTType *folderType = [UTType typeWithIdentifier:@"public.folder"];
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ folderType ]
                                                                   asCopy:NO];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [presenter presentViewController:picker animated:YES completion:nil];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;

    if (self.acRootURL) {
        [self.acRootURL stopAccessingSecurityScopedResource];
    }
    if (![url startAccessingSecurityScopedResource]) {
        NSLog(@"Could not access the selected AC folder: %@", url);
        return;
    }

    NSData *bookmark = [AppDelegate bookmarkForURL:url];
    if (bookmark) {
        [[NSUserDefaults standardUserDefaults] setObject:bookmark forKey:kACRootBookmarkKey];
    }
    self.acRootURL = url;
    [[NSNotificationCenter defaultCenter]
        postNotificationName:ACiOSRootDidChangeNotification object:url];
}

- (void)applicationWillResignActive:(UIApplication *)application {
    ac_ios_audio_suspend();
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    ac_ios_audio_resume();
}

@end
