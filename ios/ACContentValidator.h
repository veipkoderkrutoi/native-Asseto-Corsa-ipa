#import <Foundation/Foundation.h>

/// Checks the REAL dependency manifest generated from rustyAC's file logs before
/// DRIVE. Only relative paths are shipped; no game assets are embedded.
@interface ACContentValidator : NSObject

+ (instancetype)shared;

/// result: arrays of relative paths. Driver models are optional (renderer has
/// a safe no-driver fallback); everything else the real renderer read is required.
- (void)validateRoot:(NSURL *)root
                 car:(NSString *)car
               track:(NSString *)track
          completion:(void (^)(NSArray<NSString *> *missingRequired,
                               NSArray<NSString *> *missingOptional,
                               NSUInteger checked))completion;

/// All required relative paths across every car/track combination (for the importer).
- (NSArray<NSString *> *)allRequiredPaths;

@end
