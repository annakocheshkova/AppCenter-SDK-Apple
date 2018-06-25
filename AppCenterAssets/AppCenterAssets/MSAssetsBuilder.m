#import "MSAssetsBuilder.h"

@implementation MSAssetsBuilder

- (instancetype)init {
    if (self == [super init]) {
        _deploymentKey = nil;
        _serverUrl = nil;
        _updateSubFolder = nil;
    }
    return self;
}

@end
