#import "ACImportPopup.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

typedef NS_ENUM(NSInteger, ACImportState) {
    ACImportReady = 0,
    ACImportFolderSelected,
    ACImportImporting,
    ACImportCompleted,
    ACImportFailed,
};

@interface ACImportPopup ()
@property (nonatomic, weak) UIViewController *presenter;
@property (nonatomic, copy) void (^completion)(NSURL *, NSUInteger, NSUInteger, NSError *);
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *bodyLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIProgressView *progress;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) UIButton *chooseButton;
@property (nonatomic, assign) ACImportState state;
@property (nonatomic, strong) NSURL *pickedURL;
@end

@implementation ACImportPopup

- (instancetype)initWithPresenter:(UIViewController *)presenter
                       completion:(void (^)(NSURL *, NSUInteger, NSUInteger, NSError *))completion {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _presenter = presenter;
        _completion = completion;
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.72];
        _card = [[UIView alloc] initWithFrame:CGRectZero];
        _card.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1.0];
        _card.layer.cornerRadius = 6.0;
        _card.layer.borderWidth = 1.0;
        _card.layer.borderColor = [UIColor colorWithRed:0.78 green:0.10 blue:0.10 alpha:0.8].CGColor;
        [self addSubview:_card];

        _titleLabel = [self label:@"IMPORT ASSETTO CORSA CONTENT" size:15 bold:YES];
        _titleLabel.textColor = [UIColor colorWithRed:0.88 green:0.14 blue:0.14 alpha:1.0];
        _subtitleLabel = [self label:@"Bring your cars and tracks into Assetto Corsa Mobile." size:12 bold:NO];
        _subtitleLabel.textColor = [UIColor colorWithWhite:0.80 alpha:1.0];
        _bodyLabel = [self label:@"" size:11 bold:NO];
        _bodyLabel.numberOfLines = 0;
        _bodyLabel.textColor = [UIColor colorWithWhite:0.68 alpha:1.0];
        _statusLabel = [self label:@"" size:11 bold:YES];
        _statusLabel.textColor = [UIColor colorWithWhite:0.85 alpha:1.0];
        _progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        _progress.progressTintColor = [UIColor colorWithRed:0.78 green:0.10 blue:0.10 alpha:1.0];
        _progress.hidden = YES;

        _cancelButton = [self button:@"CANCEL" accent:NO];
        [_cancelButton addTarget:self action:@selector(cancelTapped)
                forControlEvents:UIControlEventTouchUpInside];
        _chooseButton = [self button:@"CHOOSE FOLDER" accent:YES];
        [_chooseButton addTarget:self action:@selector(chooseTapped)
                forControlEvents:UIControlEventTouchUpInside];

        for (UIView *v in @[_titleLabel, _subtitleLabel, _bodyLabel, _statusLabel,
                            _progress, _cancelButton, _chooseButton]) [_card addSubview:v];
        [self setState:ACImportReady];
    }
    return self;
}

- (UILabel *)label:(NSString *)text size:(CGFloat)size bold:(BOOL)bold {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.text = text;
    l.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    l.textColor = UIColor.whiteColor;
    return l;
}

- (UIButton *)button:(NSString *)title accent:(BOOL)accent {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.backgroundColor = accent ? [UIColor colorWithRed:0.78 green:0.10 blue:0.10 alpha:0.95]
                               : [UIColor colorWithWhite:0.16 alpha:1.0];
    b.layer.cornerRadius = 4;
    return b;
}

- (void)showInView:(UIView *)view {
    self.frame = view.bounds;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    CGFloat cw = MIN(520, view.bounds.size.width - 40);
    CGFloat ch = MIN(340, view.bounds.size.height - 40);
    _card.frame = CGRectMake((view.bounds.size.width - cw) / 2, (view.bounds.size.height - ch) / 2, cw, ch);
    CGFloat x = 18, w = cw - 36;
    _titleLabel.frame = CGRectMake(x, 16, w, 22);
    _subtitleLabel.frame = CGRectMake(x, 42, w, 20);
    _bodyLabel.frame = CGRectMake(x, 70, w, 130);
    _statusLabel.frame = CGRectMake(x, 204, w, 18);
    _progress.frame = CGRectMake(x, 226, w, 8);
    _cancelButton.frame = CGRectMake(cw - 178, ch - 52, 150, 36);
    _chooseButton.frame = CGRectMake(cw - 344, ch - 52, 150, 36);
    [view addSubview:self];
}

- (void)dismiss {
    if (_pickedURL) [_pickedURL stopAccessingSecurityScopedResource];
    _pickedURL = nil;
    [self removeFromSuperview];
}

- (void)cancelTapped {
    if (self.completion) self.completion(nil, 0, 0, nil);
    [self dismiss];
}

- (void)setState:(ACImportState)state {
    _state = state;
    switch (state) {
        case ACImportReady:
            _bodyLabel.text = @"Choose the root folder of your Assetto Corsa installation (it must contain "
                "content/cars and content/tracks), or a prepared AC-iOS Content Pack.\n\n"
                "Only your own locally installed content is read. Nothing is downloaded, nothing is deleted, "
                "and all files are copied into this app's private Documents storage.";
            _statusLabel.text = @"READY TO IMPORT";
            _chooseButton.enabled = YES;
            _progress.hidden = YES;
            break;
        case ACImportFolderSelected:
            _statusLabel.text = @"FOLDER SELECTED — VALIDATING…";
            break;
        case ACImportImporting:
            _statusLabel.text = @"IMPORTING — PLEASE WAIT";
            _progress.hidden = NO;
            _progress.progress = 0;
            _cancelButton.enabled = NO;
            _chooseButton.enabled = NO;
            break;
        case ACImportCompleted:
            _statusLabel.text = @"IMPORT COMPLETED";
            _progress.hidden = YES;
            _chooseButton.enabled = YES;
            break;
        case ACImportFailed:
            _statusLabel.text = @"IMPORT FAILED";
            _progress.hidden = YES;
            _chooseButton.enabled = YES;
            break;
    }
}

- (void)chooseTapped {
    UTType *folderType = [UTType typeWithIdentifier:@"public.folder"];
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ folderType ] asCopy:NO];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self.presenter presentViewController:picker animated:YES completion:nil];
}

#pragma mark - Document picker

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    [self setState:ACImportReady];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
 didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *picked = urls.firstObject;
    if (!picked) return;
    [self setState:ACImportFolderSelected];
    if (![picked startAccessingSecurityScopedResource]) {
        [self fail:@"The selected folder could not be accessed."];
        return;
    }
    _pickedURL = picked;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [weakSelf importFrom:picked];
    });
}

/// Finds the actual content root inside the picked folder. Accepts an AC root
/// (content/cars + content/tracks), a prepared pack root (cars + tracks), or a
/// direct parent containing one of those one level down.
- (NSURL *)resolveContentRoot:(NSURL *)picked {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray *candidates = @[ picked,
        [picked URLByAppendingPathComponent:@"AC-iOS" isDirectory:YES],
        [picked URLByAppendingPathComponent:@"content" isDirectory:YES] ];
    for (NSURL *c in candidates) {
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:c.path isDirectory:&isDir] || !isDir) continue;
        NSString *carsA = [c.path stringByAppendingPathComponent:@"content/cars"];
        NSString *tracksA = [c.path stringByAppendingPathComponent:@"content/tracks"];
        NSString *carsB = [c.path stringByAppendingPathComponent:@"cars"];
        NSString *tracksB = [c.path stringByAppendingPathComponent:@"tracks"];
        if ([fm fileExistsAtPath:carsA] && [fm fileExistsAtPath:tracksA]) return c;
        if ([fm fileExistsAtPath:carsB] && [fm fileExistsAtPath:tracksB]) return c;
    }
    return nil;
}

- (NSArray<NSURL *> *)itemsIn:(NSURL *)dir {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray *names = [fm contentsOfDirectoryAtPath:dir.path error:nil] ?: @[];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *name in names) {
        if ([name hasPrefix:@"."]) continue;
        NSURL *u = [dir URLByAppendingPathComponent:name isDirectory:YES];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:u.path isDirectory:&isDir] && isDir) [out addObject:u];
    }
    return out;
}

- (NSUInteger)fileCountIn:(NSURL *)dir {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray *all = [fm subpathsOfDirectoryAtPath:dir.path error:nil] ?: @[];
    NSUInteger n = 0;
    for (NSString *p in all) {
        BOOL isDir = NO;
        if (![p hasPrefix:@"."] && [fm fileExistsAtPath:[dir.path stringByAppendingPathComponent:p] isDirectory:&isDir] && !isDir) n++;
    }
    return n;
}

- (void)importFrom:(NSURL *)picked {
    NSURL *root = [self resolveContentRoot:picked];
    if (!root) {
        [self failOnMain:@"That folder does not contain content/cars and content/tracks. "
                          "Select your AC installation root or the AC-iOS Content Pack folder."];
        return;
    }
    NSURL *srcCars = [root.path hasSuffix:@"/content"]
        ? [root URLByAppendingPathComponent:@"cars" isDirectory:YES]
        : [root URLByAppendingPathComponent:@"content/cars" isDirectory:YES];
    NSURL *srcTracks = [root.path hasSuffix:@"/content"]
        ? [root URLByAppendingPathComponent:@"tracks" isDirectory:YES]
        : [root URLByAppendingPathComponent:@"content/tracks" isDirectory:YES];

    NSArray<NSURL *> *cars = [self itemsIn:srcCars];
    NSArray<NSURL *> *tracks = [self itemsIn:srcTracks];
    if (cars.count == 0 && tracks.count == 0) {
        [self failOnMain:@"The selected folder contains no cars or tracks."];
        return;
    }

    NSURL *docs = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory
                                                       inDomains:NSUserDomainMask].firstObject;
    NSURL *destRoot = [docs URLByAppendingPathComponent:@"AC-iOS" isDirectory:YES];
    NSURL *destCars = [destRoot URLByAppendingPathComponent:@"content/cars" isDirectory:YES];
    NSURL *destTracks = [destRoot URLByAppendingPathComponent:@"content/tracks" isDirectory:YES];
    NSFileManager *fm = NSFileManager.defaultManager;
    if ([[root.path stringByStandardizingPath] isEqualToString:[destRoot.path stringByStandardizingPath]]) {
        // The user selected the app's own already-imported folder: nothing to copy.
        [self setState:ACImportCompleted];
        _bodyLabel.text = [NSString stringWithFormat:@"This folder is already the app's content store. "
                           "%lu cars and %lu tracks are available.",
                           (unsigned long)cars.count, (unsigned long)tracks.count];
        if (self.completion) self.completion(destRoot, cars.count, tracks.count, nil);
        return;
    }
    [fm createDirectoryAtPath:destCars.path withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:destTracks.path withIntermediateDirectories:YES attributes:nil error:nil];

    NSUInteger total = 0;
    for (NSURL *u in cars) total += [self fileCountIn:u];
    for (NSURL *u in tracks) total += [self fileCountIn:u];
    if (total == 0) total = 1;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self setState:ACImportImporting];
        _bodyLabel.text = [NSString stringWithFormat:@"Copying %lu cars and %lu tracks…",
                           (unsigned long)cars.count, (unsigned long)tracks.count];
    });

    __block NSUInteger done = 0;
    __block NSError *copyError = nil;
    void (^copyOne)(NSURL *, NSURL *) = ^(NSURL *src, NSURL *dst) {
        if (copyError) return;
        NSError *e = nil;
        if ([fm fileExistsAtPath:dst.path]) {
            [fm removeItemAtURL:dst error:&e];
            e = nil;
        }
        if (![fm copyItemAtURL:src toURL:dst error:&e]) {
            copyError = e;
            return;
        }
        done += [self fileCountIn:dst];
        dispatch_async(dispatch_get_main_queue(), ^{
            _progress.progress = (float)done / (float)total;
        });
    };
    for (NSURL *car in cars) copyOne(car, [destCars URLByAppendingPathComponent:car.lastPathComponent isDirectory:YES]);
    for (NSURL *track in tracks) copyOne(track, [destTracks URLByAppendingPathComponent:track.lastPathComponent isDirectory:YES]);

    if (copyError) {
        [self failOnMain:[NSString stringWithFormat:@"Copy failed: %@", copyError.localizedDescription]];
        return;
    }
    // Verify the destination really has the imported structure.
    if (![fm fileExistsAtPath:[destCars.path stringByAppendingPathComponent:cars.firstObject.lastPathComponent ?: @""]]
        && cars.count > 0) {
        [self failOnMain:@"Files were copied but could not be verified. Please try again."];
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self setState:ACImportCompleted];
        _bodyLabel.text = [NSString stringWithFormat:@"Imported %lu cars and %lu tracks into the app's "
                           "private Documents storage. Your original game folder was not modified.",
                           (unsigned long)cars.count, (unsigned long)tracks.count];
        if (self.completion) self.completion(destRoot, cars.count, tracks.count, nil);
        [self.pickedURL stopAccessingSecurityScopedResource];
        self.pickedURL = nil;
    });
}

- (void)fail:(NSString *)message {
    [self failOnMain:message];
}

- (void)failOnMain:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setState:ACImportFailed];
        _bodyLabel.text = message;
        if (self.completion) self.completion(nil, 0, 0,
            [NSError errorWithDomain:@"ACImport" code:1 userInfo:@{NSLocalizedDescriptionKey: message}]);
    });
}

@end
