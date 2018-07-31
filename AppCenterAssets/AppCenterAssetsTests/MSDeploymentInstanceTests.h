#import "MSTestFrameworks.h"
#import "MSAssetsDeploymentInstance.h"
NS_ASSUME_NONNULL_BEGIN
static NSString *const kMSDeploymentKey = @"11111111-0000-1111-0000-111111111111";
static NSString *const kMSPackageHash = @"00000000-1111-0000-1111-000000000000";
static NSString *const kMSAppVersion = @"1.6.2";

// Make private method available for mocking.
@interface MSAssetsDeploymentInstance (Test)

- (void)checkForUpdate:(NSString *)deploymentKey withCompletionHandler:(MSCheckForUpdateCompletionHandler)handler;
- (MSAssetsLocalPackage *)getCurrentPackage;
- (void) doDownloadAndInstall:(MSAssetsRemotePackage *)remotePackage
                    syncOptions:(MSAssetsSyncOptions *)syncOptions
                  configuration:(MSAssetsConfiguration *)configuration
                        handler:(MSAssetsDownloadInstallHandler)handler;
- (void) notifyAboutSyncStatusChange:(MSAssetsSyncStatus)syncStatus instanceState:(MSAssetsDeploymentInstanceState *)instanceState;
- (void) showDialogWithAcceptText:(NSString *)acceptButtonText
                   andDeclineText:(NSString *)declineButtonText
                         andTitle:(NSString *)title
                       andMessage:(NSString *)message
                  addCancelButton:(BOOL)addCancelAction
                       andHandler:(void (^ __nullable)())handler
                 andCancelHandler:(void (^ __nullable)())cancelHandler;
- (void) rollbackPackage;
- (void)downloadUpdate:(MSAssetsRemotePackage *)updatePackage
       completeHandler:(MSAssetsPackageDownloadHandler)completeHandler;
- (NSError *)installUpdate:(MSAssetsLocalPackage*)updatePackage
               installMode:(MSAssetsInstallMode)installMode
 minimumBackgroundDuration:(int)minimumBackgroundDuration;
- (BOOL)isFirstRun:(NSString *)packageHash error:(NSError *__autoreleasing *)error;
@end

@interface MSDeploymentInstanceTests : XCTestCase

- (void)checkForUpdateCallWithDeploymentKey: (nullable NSString *)deploymentKey
                            andLocalPackage: (nullable MSAssetsLocalPackage *) localPackage
                                  andConfig: (nullable MSAssetsConfiguration *)configuration
                           andRemotePackage: (nullable MSAssetsRemotePackage *)rmPackage
                             andRemoteError: (nullable NSError *)remoteError
                                andDelegate: (nullable id<MSAssetsDelegate>)delegate
                      andCallbackCompletion: (nullable MSCheckForUpdateCompletionHandler)handler;

-(id)mockSyncDelegate;
@property (nonatomic) MSAssetsDeploymentInstance *sut;
@end

NS_ASSUME_NONNULL_END
