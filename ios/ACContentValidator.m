#import "ACContentValidator.h"

@interface ACContentValidator ()
@property (nonatomic, strong) NSDictionary *combinations;
@end

@implementation ACContentValidator

+ (instancetype)shared {
    static ACContentValidator *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[ACContentValidator alloc] init]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURL *url = [[NSBundle mainBundle] URLForResource:@"content_requirements" withExtension:@"json"];
        NSError *error = nil;
        NSData *data = url ? [NSData dataWithContentsOfURL:url options:0 error:&error] : nil;
        if (!data) {
            NSLog(@"[PREFLIGHT] Manifest missing or unreadable: %@", error.localizedDescription);
            _combinations = @{};
        } else {
            NSDictionary *doc = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            NSDictionary *combos = doc[@"combinations"];
            _combinations = [combos isKindOfClass:NSDictionary.class] ? combos : @{};
            NSLog(@"[PREFLIGHT] Loaded %lu car/track dependency sets", (unsigned long)_combinations.count);
        }
    }
    return self;
}

- (BOOL)isOptionalPath:(NSString *)relative {
    // The renderer now returns Ok(None) when no driver model exists, so a
    // missing 3D driver is reported but does not block the scene.
    return [relative hasPrefix:@"content/driver/"] && [relative hasSuffix:@".kn5"];
}

- (void)validateRoot:(NSURL *)root
                 car:(NSString *)car
               track:(NSString *)track
          completion:(void (^)(NSArray<NSString *> *, NSArray<NSString *> *, NSUInteger))completion {
    NSString *key = [NSString stringWithFormat:@"%@|%@", car ?: @"", track ?: @""];
    NSDictionary *entry = self.combinations[key];
    NSArray<NSString *> *required = [entry isKindOfClass:NSDictionary.class] ? entry[@"required"] : nil;
    if (![required isKindOfClass:NSArray.class]) required = @[];

    NSLog(@"[PREFLIGHT] Selected car: %@", car ?: @"(none)");
    NSLog(@"[PREFLIGHT] Selected track: %@", track ?: @"(none)");
    NSLog(@"[PREFLIGHT] Required resources: %lu", (unsigned long)required.count);

    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray *missingRequired = [NSMutableArray array];
    NSMutableArray *missingOptional = [NSMutableArray array];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (NSString *relative in required) {
            NSString *full = [root.path stringByAppendingPathComponent:relative];
            if ([fm fileExistsAtPath:full]) continue;
            if ([self isOptionalPath:relative]) [missingOptional addObject:relative];
            else [missingRequired addObject:relative];
        }
        [missingRequired sortUsingSelector:@selector(compare:)];
        [missingOptional sortUsingSelector:@selector(compare:)];

        NSLog(@"[PREFLIGHT] Existing resources: %lu of %lu",
              (unsigned long)(required.count - missingRequired.count - missingOptional.count),
              (unsigned long)required.count);
        NSLog(@"[PREFLIGHT] Missing resources: %lu required, %lu optional",
              (unsigned long)missingRequired.count, (unsigned long)missingOptional.count);
        for (NSString *path in [missingRequired subarrayWithRange:NSMakeRange(0, MIN(10, missingRequired.count))]) {
            NSLog(@"[PREFLIGHT] Missing required: %@", path);
        }
        NSLog(@"[PREFLIGHT] Validation result: %@", missingRequired.count ? @"FAIL" : @"PASS");
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(missingRequired, missingOptional, required.count);
            });
        }
    });
}

- (NSArray<NSString *> *)allRequiredPaths {
    NSMutableSet *all = [NSMutableSet set];
    for (NSDictionary *entry in self.combinations.allValues) {
        NSArray *paths = entry[@"required"];
        if ([paths isKindOfClass:NSArray.class]) [all addObjectsFromArray:paths];
    }
    return [all.allObjects sortedArrayUsingSelector:@selector(compare:)];
}

@end
