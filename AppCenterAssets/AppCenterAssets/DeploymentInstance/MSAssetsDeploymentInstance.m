#import "MSAssets.h"
#import "MSAssetsDeploymentInstanceState.h"
#import "MSAssetsUpdateUtilities+JWT.h"
#import "MSAssetsLocalPackage.h"
#import "MSAssetsErrors.h"
#import "MSAssetsErrorUtils.h"
#import "MSLogger.h"
#import "MSUtility+File.h"
#import "MSAssetsDownloadHandler.h"
#import <UIKit/UIKit.h>
#import "MSAssetsSettingManager.h"
#import "MSUtility+File.h"
#import "MSAssetsInstallMode.h"
#import "MSAssetsSyncOptions.h"
#import "MSAssetsSyncStatus.h"
#import "MSAssetsRemotePackage.h"
#import "MSAlertController.h"
#import "MF_Base64Additions.h"

@implementation MSAssetsDeploymentInstance {
    BOOL _didUpdateProgress;
    NSString *_entryPoint;
    NSString *_publicKey;
    NSString *_deploymentKey;
    BOOL _isDebugMode;
    NSString *_serverUrl;
    NSString *_appVersion;
}

@synthesize delegate = _delegate;
static NSString *const DownloadFileName = @"download.zip";
static NSString *const UpdateMetadataFileName = @"app.json";

// We must reference all the categories here so that they are not cleaned because of the current optimization level.
__attribute__((used)) static void importCategories() {
    [NSString stringWithFormat:@"%@ %@", BundleJWTFile, CategoryReference];
}

static BOOL isRunningBinaryVersion = NO;
//static BOOL needToReportRollback = NO;
//static BOOL testConfigurationFlag = NO;

- (instancetype)initWithEntryPoint:(NSString *)entryPoint
                         publicKey:(NSString *)publicKey
                     deploymentKey:(NSString *)deploymentKey
                       inDebugMode:(BOOL)isDebugMode
                         serverUrl:(NSString *)serverUrl
                           baseDir:(NSString *)baseDir
                           appName:(NSString *)appName
                        appVersion:(NSString *)appVersion
                  platformInstance:(id<MSAssetsPlatformSpecificImplementation>)platformInstance
                         withError:(NSError *__autoreleasing *)error {
    if ((self = [super init])) {
        _entryPoint = entryPoint;
        _publicKey = publicKey;
        _deploymentKey = deploymentKey;
        _isDebugMode = isDebugMode;
        if (serverUrl) {
            _serverUrl = serverUrl;
        } else {
            _serverUrl = @"https://codepush.azurewebsites.net/";
        }

        if (appVersion) {
            _appVersion = appVersion;
        } else {
            NSDictionary *infoDictionary = [[NSBundle bundleForClass:[self class]] infoDictionary];
            _appVersion = [infoDictionary objectForKey:@"CFBundleShortVersionString"];
        }

        if (!_appVersion) {
            *error = [MSAssetsErrorUtils getNoAppVersionError];
            return nil;
        }

        _downloadHandler = nil;

        if (!appName) appName = @"Assets";

        _settingManager = [[MSAssetsSettingManager alloc] initWithAppName:appName];

        _updateUtilities = [[MSAssetsUpdateUtilities alloc] initWithSettingManager:_settingManager];

        NSString *appNameWithDeploymentKey = [appName stringByAppendingPathComponent:_deploymentKey];

        _updateManager = [[MSAssetsUpdateManager alloc] initWithUpdateUtils:_updateUtilities andBaseDir:baseDir andAppName:appNameWithDeploymentKey];
        
        _acquisitionManager = [[MSAssetsAcquisitionManager alloc] init];
        _telemetryManager = [[MSAssetsTelemetryManager alloc] initWithSettingManager:_settingManager];
        _restartManager = [[MSAssetsRestartManager alloc] initWithRestartHandler:^(BOOL onlyIfUpdateIsPending, MSAssetsRestartListener restartListener) {
            [self restartInternal:restartListener onlyIfUpdateIsPending:onlyIfUpdateIsPending];
        }];
        _instanceState = [[MSAssetsDeploymentInstanceState alloc] init];
        _platformInstance = platformInstance;
        if (_isDebugMode && [_settingManager isPendingUpdate:nil]) {
            [_platformInstance clearDebugCacheWithError:error];
            if (*error) {
                return nil;
            }
        }
        [self initializeUpdateAfterRestartWithError:error];
        if (*error) {
            return nil;
        }
    }
    return self;
}

/**
 * Initializes update after app restart.
 *
 * @param error initialization error.
 */
- (void)initializeUpdateAfterRestartWithError:(NSError * __autoreleasing *)error {
    
    /* Reset the state which indicates that the app was just freshly updated. */
    [[self instanceState] setDidUpdate:NO];
    MSAssetsPendingUpdate *pendingUpdate = [[self settingManager] getPendingUpdate];
    if (pendingUpdate == nil) {
        return;
    }
    MSAssetsLocalPackage *packageMetadata = [[self updateManager] getCurrentPackage:error];
    if (*error) {
        return;
    }
    if (packageMetadata == nil || ([[self platformInstance] isPackageLatest:packageMetadata appVersion:_appVersion]
                                   && ! [_appVersion isEqualToString:[packageMetadata appVersion]])) {
        MSLogInfo([MSAssets logTag], @"Skipping initializeUpdateAfterRestart(), binary version is newer.");
        return;
    }
    BOOL updateIsLoading = [pendingUpdate isLoading];
    if (updateIsLoading) {
        
        /* Pending update was initialized, but notifyApplicationReady was not called.
         * Therefore, deduce that it is a broken update and rollback. */
        MSLogInfo([MSAssets logTag], @"Update did not finish loading the last time, rolling back to a previous version.");
        [[self instanceState] setNeedToReportRollback:YES];
        [self rollbackPackage];
    } else {
        
        /* There is in fact a new update running for the first
         * time, so update the local state to ensure the client knows. */
        [[self instanceState] setDidUpdate:YES];
        
        /* Mark that we tried to initialize the new update, so that if it crashes,
         * we will know that we need to rollback when the app next starts. */
        [[self settingManager] savePendingUpdate:pendingUpdate];
    }
}

- (void) notifyApplicationReady {
    [[self settingManager] removePendingUpdate];
    NSError *error = nil;
    MSAssetsDeploymentStatusReport *report = [self getNewStatusReportWithError:&error];
    if (error) {
        MSLogInfo([MSAssets logTag], @"An error occurred during obtaining new status report. %@", [error localizedDescription]);
        return;
    }
    if (report) {
        [self reportStatus:report];
    }
}

- (void)reportStatus:(MSAssetsDeploymentStatusReport *)report {
    NSError *error = nil;
    MSAssetsConfiguration *configuration = [self getConfigurationWithError:&error];
    if (report.appVersion.length == 0) {
        MSLogInfo([MSAssets logTag], @"Reporting binary update (%@)", report.appVersion);
    } else {
        NSString *label = report.assetsPackage != nil ? report.assetsPackage.label : report.label;
        if (report.status == MSAssetsDeploymentStatusSucceeded) {
            MSLogInfo([MSAssets logTag], @"Reporting update success (%@)", label);
        } else {
            MSLogInfo([MSAssets logTag], @"Reporting update rollback (%@)", label);
        }
        [configuration setDeploymentKey:report.assetsPackage == nil ? report.deploymentKey : report.assetsPackage.deploymentKey];
    }
    [[self acquisitionManager] reportDeploymentStatus:report withConfiguration:configuration];
    [[self telemetryManager] saveReportedStatus:report];
}

- (void) rollbackPackage {
    //TODO: Sync up with Patrick on rollbacks.
}

- (BOOL)restartInternal:(MSAssetsRestartListener)assetsRestartListener onlyIfUpdateIsPending:(BOOL)onlyIfUpdateIsPending {
    
    /* If this is an unconditional restart request, or there
     * is current pending update, then reload the app. */
    if (!onlyIfUpdateIsPending || [[self settingManager] isPendingUpdate:nil]) {
        [[self platformInstance] loadApp:assetsRestartListener];
        return YES;
    }
    return NO;
}

- (void)checkForUpdate:(nullable NSString *)deploymentKey {
    if (![MSAssets isEnabled])
        return;
    [self checkForUpdate:deploymentKey withCompletionHandler:^( MSAssetsRemotePackage *update,  NSError * _Nullable error){
        if (error) {
            if ([self.delegate respondsToSelector:@selector(didFailToQueryRemotePackageOnCheckForUpdate:)])
                [self.delegate didFailToQueryRemotePackageOnCheckForUpdate:error];
        } else {
            if ([self.delegate respondsToSelector:@selector(didReceiveRemotePackageOnCheckForUpdate:)])
                [self.delegate didReceiveRemotePackageOnCheckForUpdate:update];
        }

    }];
}

- (void)checkForUpdate:(NSString *)deploymentKey withCompletionHandler:(MSCheckForUpdateCompletionHandler)handler {
    if (deploymentKey){
        [self setDeploymentKey:deploymentKey];
    }
    NSError *configError = nil;
    MSAssetsConfiguration *config = [self getConfigurationWithError:&configError];
    if (configError) {
        handler(nil, configError);
        return;
    }
    if (deploymentKey)
        config.deploymentKey = deploymentKey;

    MSAssetsLocalPackage *localPackage = [self getCurrentPackage];

    MSAssetsLocalPackage *queryPackage;
    if (localPackage){
        MSLogInfo([MSAssets logTag], @"Got local package");
        queryPackage = localPackage;
    }
    else{
        queryPackage = [MSAssetsLocalPackage createLocalPackageWithAppVersion:config.appVersion];
    }
    [[self acquisitionManager] queryUpdateWithCurrentPackage:queryPackage withConfiguration:config andCompletionHandler:^( MSAssetsRemotePackage *update,  NSError * _Nullable error){
        if (error) {
            handler(nil, error);
            return;
        }
        if (!update || update.updateAppVersion ||
            (localPackage && ([update.packageHash isEqualToString:localPackage.packageHash])) ||
            ((!localPackage || localPackage.isDebugOnly) && [config.packageHash isEqualToString:update.packageHash] )){
            if (update && update.updateAppVersion){
                MSLogInfo([MSAssets logTag], @"An update is available but it is not targeting the binary version of your app.");
                [self.delegate handleBinaryVersionMismatchCallback];
            }
            handler(nil, nil);
            return;
        } else {
            update.failedInstall = [[self settingManager] existsFailedUpdate:update.packageHash];
            if (deploymentKey){
                update.deploymentKey = deploymentKey;
            } else {
                update.deploymentKey = config.deploymentKey;
            }
        }
        handler(update, nil);
    }];
    MSLogInfo([MSAssets logTag], @"Check for update called");
}

- (NSString *)getCurrentUpdateEntryPoint {
    return [[self updateManager] getCurrentUpdatePath: _entryPoint];
}

- (void)sync:(MSAssetsSyncOptions *)syncOptions {
    if (![MSAssets isEnabled])
        return;
    
    if (self.instanceState.syncInProgress){
        MSLogInfo([MSAssets logTag], @"Sync already in progress.");
        [self notifyAboutSyncStatusChange: MSAssetsSyncStatusSyncInProgress instanceState:[self instanceState]];
        return;
    }

    if (!syncOptions)
        syncOptions = [[MSAssetsSyncOptions alloc] init];
    if (!syncOptions.deploymentKey)
        syncOptions.deploymentKey = self.deploymentKey;
    if (!syncOptions.installMode)
        syncOptions.installMode = MSAssetsInstallModeOnNextRestart;
    if (!syncOptions.mandatoryInstallMode)
        syncOptions.mandatoryInstallMode = MSAssetsInstallModeImmediate;
    if (!syncOptions.checkFrequency)
        syncOptions.checkFrequency = MSAssetsCheckFrequencyOnAppStart;

    NSError *configError = nil;
    MSAssetsConfiguration *config = [self getConfigurationWithError:&configError];

    if (syncOptions.deploymentKey)
        config.deploymentKey = syncOptions.deploymentKey;

    self.instanceState.syncInProgress = YES;

    [self notifyAboutSyncStatusChange: MSAssetsSyncStatusCheckingForUpdate instanceState:[self instanceState]];

    __weak typeof(self) weakSelf = self;
    [self checkForUpdate:syncOptions.deploymentKey withCompletionHandler:^( MSAssetsRemotePackage *remotePackage,  NSError * _Nullable error) {

        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        if (error) {
            MSLogInfo([MSAssets logTag], @"Error during CheckForUpdate");
            [strongSelf notifyAboutSyncStatusChange:MSAssetsSyncStatusUnknownError instanceState:[strongSelf instanceState]];
            strongSelf.instanceState.syncInProgress = NO;
            return;
        }

        BOOL updateShouldBeIgnored = remotePackage && remotePackage.failedInstall && syncOptions.ignoreFailedUpdates;

        if (!remotePackage || updateShouldBeIgnored){
            if (updateShouldBeIgnored){
                MSLogInfo([MSAssets logTag], @"An update is available, but it is being ignored due to having been previously rolled back.");
            }
            MSAssetsLocalPackage *currentPackage = [strongSelf getCurrentPackage];
            if (currentPackage && currentPackage.isPending) {
                [strongSelf notifyAboutSyncStatusChange:MSAssetsSyncStatusUpdateInstalled instanceState:[strongSelf instanceState]];
            } else {
                [strongSelf notifyAboutSyncStatusChange:MSAssetsSyncStatusUpToDate instanceState:[strongSelf instanceState]];
            }
            strongSelf.instanceState.syncInProgress = NO;
        }
        else if (syncOptions.updateDialog) {
            MSAssetsUpdateDialog *updateDialogOptions = syncOptions.updateDialog;
            NSString *message;
            NSString *acceptButtonText;
            NSString *declineButtonText = updateDialogOptions.optionalIgnoreButtonLabel;
            if (remotePackage.isMandatory) {
                message = updateDialogOptions.mandatoryUpdateMessage;
                acceptButtonText = updateDialogOptions.mandatoryContinueButtonLabel;
            } else {
                message = updateDialogOptions.optionalUpdateMessage;
                acceptButtonText = updateDialogOptions.optionalInstallButtonLabel;
            }
            if (updateDialogOptions.appendReleaseDescription && (remotePackage.description.length == 0)) {
                message = [updateDialogOptions.descriptionPrefix stringByAppendingFormat:@" %@", remotePackage.description];
            }
            [strongSelf notifyAboutSyncStatusChange:MSAssetsSyncStatusAwaitingUserAction instanceState:[strongSelf instanceState]];

            MSAlertController *alert = [MSAlertController alertControllerWithTitle:updateDialogOptions.title message:message preferredStyle:UIAlertControllerStyleAlert];

            [alert.presentingViewController dismissViewControllerAnimated:YES completion:nil];

            UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:acceptButtonText style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction * action) {
                __weak typeof(strongSelf) weakSelfLvl2 = strongSelf;
                [strongSelf doDownloadAndInstall:remotePackage syncOptions:syncOptions configuration:config handler:^(NSError * _Nullable error_internal) {
                    if (error_internal) {
                        [[MSAssetsSettingManager new] saveFailedUpdate:remotePackage];
                    }
                    typeof(self) strongSelfLvl2 = weakSelfLvl2;
                    if (!strongSelfLvl2) {
                        return;
                    }
                    strongSelfLvl2.instanceState.syncInProgress = NO;
                    if (error_internal) {
                        MSLogInfo([MSAssets logTag], @"Error during doDownloadAndInstall");
                        [strongSelfLvl2 notifyAboutSyncStatusChange:MSAssetsSyncStatusUnknownError instanceState:[strongSelfLvl2 instanceState]];
                        return;
                    };
                }];
            }];
            [alert addAction:defaultAction];

            if (!remotePackage.isMandatory) {
                UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:declineButtonText style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction * action) {
                    strongSelf.instanceState.syncInProgress = NO;
                    [strongSelf notifyAboutSyncStatusChange:MSAssetsSyncStatusUpdateIgnored instanceState:[strongSelf instanceState]];
                }];
                [alert addAction:cancelAction];
            }

            [alert show];
        }
        else {
            MSLogInfo([MSAssets logTag], @"Do download and install");
            __weak typeof(strongSelf) weakSelfLvl2 = strongSelf;
            [strongSelf doDownloadAndInstall:remotePackage syncOptions:syncOptions configuration:config handler:^(NSError * _Nullable error_internal) {
                if (error_internal) {
                    [[MSAssetsSettingManager new] saveFailedUpdate:remotePackage];
                }
                typeof(self) strongSelfLvl2 = weakSelfLvl2;
                if (!strongSelfLvl2) {
                    return;
                }
                strongSelf.instanceState.syncInProgress = NO;
                if (error_internal) {
                    MSLogInfo([MSAssets logTag], @"Error during doDownloadAndInstall");
                    [[MSAssetsSettingManager new] saveFailedUpdate:remotePackage];
                    [strongSelfLvl2 notifyAboutSyncStatusChange:MSAssetsSyncStatusUnknownError instanceState:[strongSelfLvl2 instanceState]];
                    return;
                };
            }];
        }
    }];
}


- (MSAssetsConfiguration *)getConfigurationWithError:(NSError * __autoreleasing*)error {

    MSAssetsConfiguration *configuration = [MSAssetsConfiguration new];
    NSString *clientId = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    if (clientId == nil) {
        clientId = @"";
    }
    configuration.appVersion = _appVersion;
    configuration.clientUniqueId = clientId;
    configuration.deploymentKey = [self deploymentKey];
    configuration.serverUrl = [self serverUrl];
    configuration.packageHash = [[self updateManager] getCurrentPackageHash:error];
    return configuration;
}

- (MSAssetsLocalPackage *)getUpdateMetadataForState:(MSAssetsUpdateState)updateState
                 withError:(NSError * __autoreleasing *)error {
    NSError *__autoreleasing internalError;
    MSAssetsLocalPackage *package = [[self updateManager] getCurrentPackage:&internalError];
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

- (MSAssetsLocalPackage *)getCurrentPackage {
    NSError *error;
    MSAssetsLocalPackage *currentPackage = [self getUpdateMetadataForState:MSAssetsUpdateStateLatest withError:&error];
    if (error){
        MSLogInfo([MSAssets logTag], @"An error occured: %@", [error localizedDescription]);
        return nil;
    }
    return currentPackage;
}

/**
 * Downloads update.
 *
 * @param updatePackage update to download.
 * @param completeHandler completion handler to deliver results/errors to.
 */
- (void)downloadUpdate:(MSAssetsRemotePackage *)updatePackage
       completeHandler:(MSAssetsPackageDownloadHandler)completeHandler {
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
    self.downloadHandler = [[MSAssetsDownloadHandler alloc] initWithOperationQueue: dispatch_get_main_queue()];
    __weak typeof(self) weakSelf = self;
    [[self downloadHandler] downloadWithUrl:[updatePackage downloadUrl]
                                     toPath:downloadFile
                       withProgressCallback:^(long long expectedContentLength, long long receivedContentLength) {
                           typeof(self) strongSelf = weakSelf;
                           if (!strongSelf) {
                               return;
                           }
                           if ([[strongSelf delegate] respondsToSelector:@selector(didReceiveBytesForPackageDownloadProgress:totalBytes:)]) {
                               [[strongSelf delegate] didReceiveBytesForPackageDownloadProgress:receivedContentLength totalBytes:expectedContentLength];
                           }
                       } andCompletionHandler:^(MSAssetsDownloadPackageResult *downloadResult, NSError *err) {
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
                               BOOL result = [MSUtility moveFile:downloadFile toFolder:newUpdateFolderPath withNewName:strongSelf->_entryPoint];
                               if (!result) {
                                   error = [MSAssetsErrorUtils getFileMoveError:downloadFile destination:newUpdateFolderPath];
                                   completeHandler(nil, error);
                                   return;
                               }
                           }
                           MSAssetsLocalPackage *localPackage = [MSAssetsLocalPackage createLocalPackageWithPackage:updatePackage
                                                                                          failedInstall:NO
                                                                                             isFirstRun: NO
                                                                                              isPending:YES
                                                                                            isDebugOnly:NO
                                                                                             entryPoint: entryPoint];                           
                           [localPackage setBinaryModifiedTime: [NSString stringWithFormat:@"%ld", [[strongSelf platformInstance] getBinaryResourcesModifiedTime]]];
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

/**
 * Downloads and installs update.
 *
 * @param remotePackage update to use.
 * @param syncOptions   sync options.
 * @param configuration configuration to use.
 * @param handler handler to deliver errors to.
 */
- (void) doDownloadAndInstall:(MSAssetsRemotePackage *)remotePackage
                  syncOptions:(MSAssetsSyncOptions *)syncOptions
                configuration:(MSAssetsConfiguration *)configuration
                      handler:(MSAssetsDownloadInstallHandler)handler {
    [self notifyAboutSyncStatusChange:MSAssetsSyncStatusDownloadingPackage instanceState:[self instanceState]];
    __weak typeof(self) weakSelf = self;
    [self downloadUpdate:remotePackage completeHandler:^(MSAssetsLocalPackage * _Nullable downloadedPackage, NSError * _Nullable error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        
        // Destroy the handler because each time a new handler should be created.
        strongSelf.downloadHandler = nil;
        if (error) {
            [[strongSelf settingManager] saveFailedUpdate:remotePackage];
            handler(error);
            return;
        }
        NSString *label = [downloadedPackage label];
        if (!label) {
            label = @"";
        }
        MSAssetsDownloadStatusReport *report = [[MSAssetsDownloadStatusReport alloc] initReportWithLabel:label
                                                                                    deviceId:[configuration clientUniqueId]
                                                                            andDeploymentKey:[configuration deploymentKey]];
        [[strongSelf acquisitionManager] reportDownloadStatus:report withConfiguration:configuration];
        MSAssetsInstallMode resolvedInstallMode = [downloadedPackage isMandatory] ? [syncOptions mandatoryInstallMode] : [syncOptions installMode];
        [[strongSelf instanceState] setCurrentInstallMode:resolvedInstallMode];
        [strongSelf notifyAboutSyncStatusChange:MSAssetsSyncStatusInstallingUpdate instanceState:[strongSelf instanceState]];
        NSError *installError = [strongSelf installUpdate:downloadedPackage installMode:resolvedInstallMode minimumBackgroundDuration:[syncOptions minimumBackgroundDuration]];
        if (installError) {
            handler(installError);
            return;
        }
        [strongSelf notifyAboutSyncStatusChange:MSAssetsSyncStatusUpdateInstalled instanceState:[strongSelf instanceState]];
        [[strongSelf instanceState] setSyncInProgress:NO];
        if (resolvedInstallMode == MSAssetsInstallModeImmediate && [syncOptions shouldRestart]) {
            [[strongSelf restartManager] restartAppOnlyIfUpdateIsPending:NO];
        } else {
            [[strongSelf restartManager] clearPendingRestarts];
        }
        handler(nil);
    }];
}

/**
 * Notifies listeners about changed sync status and log it.
 *
 * @param syncStatus sync status.
 */
- (void) notifyAboutSyncStatusChange:(MSAssetsSyncStatus)syncStatus instanceState:(MSAssetsDeploymentInstanceState *)instanceState{
    if ([[self delegate] respondsToSelector:@selector(syncStatusChanged:)]) {
        [[self delegate] syncStatusChanged:syncStatus];
    }
    switch (syncStatus) {
        case MSAssetsSyncStatusCheckingForUpdate:
            MSLogInfo([MSAssets logTag], @"Checking for update.");
            break;
        case MSAssetsSyncStatusAwaitingUserAction:
            MSLogInfo([MSAssets logTag], @"Awaiting user action.");
            break;
        case MSAssetsSyncStatusDownloadingPackage:
            MSLogInfo([MSAssets logTag], @"Downloading package.");
            break;
        case MSAssetsSyncStatusInstallingUpdate:
            MSLogInfo([MSAssets logTag], @"Installing update.");
            break;
        case MSAssetsSyncStatusUpToDate:
            MSLogInfo([MSAssets logTag], @"App is up to date.");
            break;
        case MSAssetsSyncStatusSyncInProgress:
            MSLogInfo([MSAssets logTag], @"Sync is in progress.");
            break;
        case MSAssetsSyncStatusUpdateIgnored:
            MSLogInfo([MSAssets logTag], @"User cancelled the update.");
            break;
        case MSAssetsSyncStatusUnknownError:
            MSLogInfo([MSAssets logTag], @"An unknown error occurred.");
            break;
        case MSAssetsSyncStatusUpdateInstalled:
            switch (instanceState.currentInstallMode) {
                case MSAssetsInstallModeImmediate:
                    MSLogInfo([MSAssets logTag], @"Update is installed and will be run right now.");
                    break;
                case MSAssetsInstallModeOnNextRestart:
                    MSLogInfo([MSAssets logTag], @"Update is installed and will be run on the next app restart.");
                    break;
                case MSAssetsInstallModeOnNextResume:
                    MSLogInfo([MSAssets logTag], @"Update is installed and will be run when the app next resumes.");
                    break;
                case MSAssetsInstallModeOnNextSuspend:
                    MSLogInfo([MSAssets logTag], @"Update is installed and will be run after the app has been in the background for at least %d seconds.", instanceState.minimumBackgroundDuration);
                    break;
            }
            break;
    }
}

/**
 * Installs update.
 *
 * @param updatePackage             update to install.
 * @param installMode               installation mode.
 * @param minimumBackgroundDuration minimum background duration value
 * @see `MSAssetsSyncOptions->minimumBackgroundDuration`.
 * @return error installation error.
 */
- (NSError *)installUpdate:(MSAssetsLocalPackage*)updatePackage
          installMode:(MSAssetsInstallMode)installMode
minimumBackgroundDuration:(int)minimumBackgroundDuration {
    NSString *packageHash = [updatePackage packageHash];
    if (packageHash == nil) {
        return [MSAssetsErrorUtils getNoPackageHashToInstallError];
    }
    NSError *installError = [[self updateManager] installPackage:[updatePackage packageHash]
                                   removePendingUpdate:[[self settingManager] isPendingUpdate:[updatePackage packageHash]]];
    if (installError) {
        return installError;
    }
    MSAssetsPendingUpdate *pendingUpdate = [MSAssetsPendingUpdate new];
    [pendingUpdate setPendingUpdateHash:packageHash];
    [pendingUpdate setIsLoading:NO];
    [[self settingManager] savePendingUpdate:pendingUpdate];
    if (installMode == MSAssetsInstallModeOnNextResume ||
        
        /* We also add the resume listener if the installMode is IMMEDIATE, because
         * if the current activity is backgrounded, we want to reload the bundle when
         * it comes back into the foreground. */
        installMode == MSAssetsInstallModeImmediate ||
        installMode == MSAssetsInstallModeOnNextSuspend) {
        
        /* Store the minimum duration on the native module as an instance
         * variable instead of relying on a closure below, so that any
         * subsequent resume-based installs could override it. */
        [[self instanceState] setMinimumBackgroundDuration:minimumBackgroundDuration];
        [[self platformInstance] handleInstallModesForUpdateInstall:installMode];
    }
    return nil;
}

/**
 * Retrieves status report for sending.
 *
 * @param error error, if occurred.
 * @return status report for sending.
 */
- (MSAssetsDeploymentStatusReport *)getNewStatusReportWithError:(NSError * __autoreleasing *)error {
    if (self.instanceState.needToReportRollback) {
        self.instanceState.needToReportRollback = NO;
        NSArray<MSAssetsPackage *> *failedUpdates = [[self settingManager] getFailedUpdates];
        if (failedUpdates && failedUpdates.count > 0) {
            MSAssetsPackage *failedPackage = failedUpdates.lastObject;
            if (failedPackage) {
                return [[self telemetryManager] buildRollbackReportWithFailedPackage:failedPackage];
            }
        }
    } else if (self.instanceState.didUpdate) {
        MSAssetsLocalPackage *localPackage = [[self updateManager] getCurrentPackage:error];
        if (*error) {
            return nil;
        }
        if (localPackage != nil) {
            return [[self telemetryManager] buildUpdateReportWithPackage:localPackage];
        }
    } else if (self.instanceState.isRunningBinaryVersion) {
        return [[self telemetryManager] buildBinaryUpdateReportWithAppVersion:_appVersion];
    }
    return nil;
}
@end
