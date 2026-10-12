#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` and returns the Objective-C exception it raised, or nil. Swift can't catch these,
/// and one unwinding through Swift code crashes the app.
NSException *_Nullable ObjCCatch(NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END
