#import "Catch.h"

NSException *ObjCCatch(void (^block)(void)) {
    @try {
        block();
    } @catch (NSException *exception) {
        return exception;
    }
    return nil;
}
