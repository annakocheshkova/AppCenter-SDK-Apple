#import "MSAssets.h"
#import "MSAssetsUpdateState.h"
#import "MSLocalPackage.h"
#import "MSAssetsErrors.h"
#import "MSAssetsErrorUtils.h"
#import "MSLogger.h"
#import "MSUtility+File.h"
#import "MSAssetsDownloadHandler.h"
#import <UIKit/UIKit.h>
#import "MSAssetsSettingManager.h"
#import "MSAssetsFileUtils.h"

@implementation MSAssetsDeploymentInstance {
    BOOL _didUpdateProgress;
    NSString *_entryPoint;
    NSString *_publicKey;
}

@synthesize delegate = _delegate;
static NSString *const DownloadFileName = @"download.zip";
static NSString *const UpdateMetadataFileName = @"app.json";


static BOOL isRunningBinaryVersion = NO;
//static BOOL needToReportRollback = NO;
//static BOOL testConfigurationFlag = NO;

- (instancetype)initWithEntryPoint:(NSString *)entryPoint
                         publicKey:(NSString *)publicKey{
    if ((self = [super init])) {
        _entryPoint = entryPoint;
        _publicKey = publicKey;
        _downloadHandler = [[MSAssetsDownloadHandler alloc] initWithOperationQueue: dispatch_get_main_queue()];
        _updateUtilities = [[MSAssetsUpdateUtilities alloc] init];
        _updateManager = [[MSAssetsUpdateManager alloc] init];
        _acquisitionManager = [[MSAssetsAcquisitionManager alloc] init];
        _settingManager = [[MSAssetsSettingManager alloc] init];
        _telemetryManager = [[MSAssetsTelemetryManager alloc] init];
    }
    return self;
}

- (void)checkForUpdate:(NSString *)deploymentKey {

    if (deploymentKey){
        [self setDeploymentKey:deploymentKey];
    }

    MSAssetsConfiguration *config = [self getConfiguration];
    if (deploymentKey)
        config.deploymentKey = deploymentKey;

    MSLocalPackage *localPackage = [[self getCurrentPackage] mutableCopy];

    MSLocalPackage *queryPackage;
    if (localPackage){
        MSLogInfo([MSAssets logTag], @"Got local package");
        queryPackage = localPackage;
    }
    else{
        queryPackage = [MSLocalPackage createLocalPackageWithAppVersion:config.appVersion];
    }

    [[self acquisitionManager] queryUpdateWithCurrentPackage:queryPackage withConfiguration:config andCompletionHandler:^( MSRemotePackage *update,  NSError * _Nullable error){
        if (error) {
            if ([[self delegate] respondsToSelector:@selector(didFailToQueryRemotePackageOnCheckForUpdate:)])
                [[self delegate] didFailToQueryRemotePackageOnCheckForUpdate:error];
            return;
        }
        
        if (!update)
        {
            if ([[self delegate] respondsToSelector:@selector(didReceiveRemotePackageOnUpdateCheck:)])
                [[self delegate] didReceiveRemotePackageOnUpdateCheck:nil];
            return;
        }

        if (!update || update.updateAppVersion ||
            (localPackage && ([update.packageHash isEqualToString:localPackage.packageHash])) ||
            ((!localPackage || localPackage.isDebugOnly) && [config.packageHash isEqualToString:update.packageHash] )){

            if (update && update.updateAppVersion){
                if ([[self delegate] respondsToSelector:@selector(didFailToQueryRemotePackageOnCheckForUpdate:)])
                {
                    NSError *newError = [MSAssetsErrorUtils getUpdateNotTargetingBinaryError];
                    [[self delegate] didFailToQueryRemotePackageOnCheckForUpdate:newError];
                }

            }
        } else {
            update.failedInstall = [[self settingManager] existsFailedUpdate:update.packageHash];
            if (deploymentKey){
                update.deploymentKey = deploymentKey;
            } else {
                update.deploymentKey = config.deploymentKey;
            }
        }
        if ([[self delegate] respondsToSelector:@selector(didReceiveRemotePackageOnUpdateCheck:)])
            [[self delegate] didReceiveRemotePackageOnUpdateCheck:update];
    }];

    MSLogInfo([MSAssets logTag], @"Check for update called");
}

- (MSAssetsConfiguration *)getConfiguration {
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];

    MSAssetsConfiguration *configuration = [MSAssetsConfiguration new];
    configuration.appVersion = [infoDictionary objectForKey:@"CFBundleShortVersionString"];
    configuration.clientUniqueId = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    configuration.deploymentKey = [self deploymentKey];
    configuration.serverUrl = [self serverUrl];
    NSError *error;
    configuration.packageHash = [[self updateManager] getCurrentPackageHash:&error];

    return configuration;
}

- (MSLocalPackage *)getUpdateMetadataForState:(MSAssetsUpdateState)updateState
                 currentPackageGettingError:(NSError * __autoreleasing *)error {
    NSError *__autoreleasing internalError;

    MSLocalPackage *package = [[[self updateManager] getCurrentPackage:&internalError] mutableCopy];
    if (internalError){
        error = &internalError;
        return nil;
    }

    if (package == nil){
        // The app hasn't downloaded any CodePush updates yet,
        // so we simply return nil regardless if the user
        // wanted to retrieve the pending or running update.
        return nil;
    }

    // We have a CodePush update, so let's see if it's currently in a pending state.

    BOOL currentUpdateIsPending = [[self settingManager] isPendingUpdate:package.packageHash];

    if (updateState == MSAssetsUpdateStatePending && !currentUpdateIsPending) {
        
        // The caller wanted a pending update
        // but there isn't currently one.
        return nil;
    } else if (updateState == MSAssetsUpdateStateRunning && currentUpdateIsPending) {
        
        // The caller wants the running update, but the current
        // one is pending, so we need to grab the previous.
        package = [[self updateManager] getPreviousPackage:&internalError];
        if (internalError){
            error = &internalError;
            return nil;
        }
        else
            return package;
    } else {
        
        // The current package satisfies the request:
        // 1) Caller wanted a pending, and there is a pending update
        // 2) Caller wanted the running update, and there isn't a pending
        // 3) Caller wants the latest update, regardless if it's pending or not
        if (isRunningBinaryVersion) {
            
            // This only matters in Debug builds. Since we do not clear "outdated" updates,
            // we need to indicate to the JS side that somehow we have a current update on
            // disk that is not actually running.
            package.isDebugOnly = true;
        }
        
        // Enable differentiating pending vs. non-pending updates
        package.isPending = currentUpdateIsPending;
        return package;
    }

}

- (MSLocalPackage *)getCurrentPackage {
    NSError *error;
    MSLocalPackage *currentPackage = [self getUpdateMetadataForState:MSAssetsUpdateStateLatest currentPackageGettingError:&error];
    if (error){
        MSLogInfo([MSAssets logTag], @"An error occured: %@", [error localizedDescription]);
        return nil;
    }
    return currentPackage;
}

//TODO: saveFailedUpdate on err!
/**
 * Downloads update.
 *
 * @param updatePackage update to download.
 * @param completeHandler completion handler to deliver results/errors to.
 */
- (void)downloadUpdate:(MSRemotePackage *)updatePackage
       completeHandler:(MSDownloadHandler)completeHandler {
    NSString *packageHash = [updatePackage packageHash];
    NSString *newUpdateFolderPath = [[self updateManager] getPackageFolderPath:packageHash];
    NSString *newUpdateMetadataPath = [newUpdateFolderPath stringByAppendingPathComponent:UpdateMetadataFileName];
    if ([MSUtility fileExistsForPathComponent:newUpdateFolderPath]) {
        
        /* This removes any stale data in `newPackageFolderPath` that could have been left
         * uncleared due to a crash or error during the download or install process. */
        [MSUtility deleteItemForPathComponent:newUpdateFolderPath];
    }
    NSString *downloadFile = [[self updateManager] getDownloadFilePath];
    if (!downloadFile) {
        
        // Can not get or create a folder. The error will appear in the logs.
        completeHandler(nil, nil);
        return;
    }
    __weak typeof(self) weakSelf = self;
    [[self downloadHandler] downloadWithUrl:[updatePackage downloadUrl]
                                     toPath:downloadFile
                       withProgressCallback:^(long long expectedContentLength, long long receivedContentLength) {
                           typeof(self) strongSelf = weakSelf;
                           if (!strongSelf) {
                               return;
                           }
                           if ([[strongSelf delegate] respondsToSelector:@selector(packageDownloadProgress:totalBytes:)]) {
                               [[strongSelf delegate] packageDownloadProgress:receivedContentLength totalBytes:expectedContentLength];
                           }
                       } andCompletionHandler:^(MSDownloadPackageResult *downloadResult, NSError *err) {
                           typeof(self) strongSelf = weakSelf;
                           if (!strongSelf) {
                               return;
                           }
                           if (err) {
                               if (completeHandler != nil) {
                                   completeHandler(nil, err);
                               }
                               return;
                           }
                           NSError *error = nil;
                           NSString *entryPoint = nil;
                           BOOL isZip = [downloadResult isZip];
                           if (isZip) {
                               [[strongSelf updateManager] unzipPackage:downloadFile
                                                                  error:&error];
                               if (error) {
                                   completeHandler(nil, error);
                                   return;
                               }
                               entryPoint = [[strongSelf updateManager] mergeDiffWithNewUpdateFolder:newUpdateFolderPath
                                                                         newUpdateMetadataPath:newUpdateMetadataPath
                                                                                 newUpdateHash:[updatePackage packageHash]
                                                                               publicKeyString: strongSelf->_publicKey
                                                                    expectedEntryPointFileName:strongSelf->_entryPoint
                                                                                               error:&error];
                               if (error) {
                                   completeHandler(nil, error);
                                   return;                                   
                               }
                           } else {
                               BOOL result = [MSAssetsFileUtils moveFile:downloadFile toFolder:newUpdateFolderPath withNewName:strongSelf->_entryPoint];
                               if (!result) {
                                   error = [MSAssetsErrorUtils getFileMoveError:downloadFile destination:newUpdateFolderPath];
                                   completeHandler(nil, error);
                                   return;
                               }
                           }
                           MSLocalPackage *localPackage = [MSLocalPackage createLocalPackageWithPackage:updatePackage
                                                                                          failedInstall:NO
                                                                                             isFirstRun: NO
                                                                                              isPending:YES
                                                                                            isDebugOnly:NO
                                                                                             entryPoint: entryPoint];
                           NSURL *binaryBundleURL = [[NSBundle mainBundle] bundleURL];
                           if (binaryBundleURL != nil) {
                               [localPackage setBinaryModifiedTime:[[strongSelf updateUtilities] modifiedDateStringOfFileAtURL:binaryBundleURL]];
                           }
                           NSData *jsonData = [NSJSONSerialization dataWithJSONObject:[localPackage serializeToDictionary] options:NSJSONWritingPrettyPrinted error:&error];
                           if (error) {
                               completeHandler(nil, error);
                               return;
                           }
                           NSURL *createdFile = [MSUtility createFileAtPathComponent:newUpdateMetadataPath withData:jsonData atomically:YES forceOverwrite:NO];
                           if (createdFile == nil) {
                               completeHandler(nil, [MSAssetsErrorUtils getUpdateMetadataFailToCreateError]);
                               return;
                           }
                           completeHandler(localPackage, nil);
                       }];
}


@end
