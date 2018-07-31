#import "MSDeploymentInstanceTests.h"
#import "MSAssetsDeploymentInstance.h"
#import "MSTestFrameworks.h"
#import "MSAssets.h"

@interface MSDeploymentInstanceTests (Sync)

@end

@implementation MSDeploymentInstanceTests (Sync)

//#pragma MARK: Sync tests
- (void)testSyncNotCalled {
    
    // If
    id serviceMock = OCMClassMock([MSAssets class]);
    OCMStub(ClassMethod([serviceMock isEnabled])).andReturn(NO);
    id assetsMock = OCMPartialMock(self.sut);
    
    // When
    [assetsMock sync:[MSAssetsSyncOptions new]];
    
    // Then
    OCMReject([[assetsMock ignoringNonObjectArgs] notifyAboutSyncStatusChange:0 instanceState:OCMOCK_ANY]);
    OCMVerifyAll(assetsMock);
    [assetsMock stopMocking];
}

- (void)testSyncInProgress {
    
    //If
    id assetsMock = OCMPartialMock(self.sut);
    MSAssetsDeploymentInstanceState *instanceState = [MSAssetsDeploymentInstanceState new];
    instanceState.syncInProgress = YES;
    [assetsMock setInstanceState:instanceState];
    id delegateMock = [self mockSyncDelegate];
    [assetsMock setDelegate:delegateMock];
    
    //When
    [assetsMock sync:[MSAssetsSyncOptions new]];
    
    //Then
    OCMVerify([delegateMock syncStatusChanged:MSAssetsSyncStatusSyncInProgress]);
}

- (void)testSyncError {
    
    //If
    NSError *remoteError = [[NSError alloc] init];
    MSAssetsSyncOptions *syncOptions = [MSAssetsSyncOptions new];
    [syncOptions setDeploymentKey:kMSDeploymentKey];
    MSAssetsConfiguration *configuration = [MSAssetsConfiguration new];
    id delegateMock = [self mockSyncDelegate];
    
    //When
    [self syncWithSyncOptions:syncOptions
             andDeploymentKey:nil
             andConfiguration:configuration
              andLocalPackage:nil
                  andDelegate:delegateMock
             andRemotePackage:nil
               andRemoteError:remoteError
      downloadAndInstallError:nil
                       dialog:nil];
    
    //Then
    OCMVerify([delegateMock syncStatusChanged:MSAssetsSyncStatusCheckingForUpdate]);
    OCMVerify([delegateMock syncStatusChanged:MSAssetsSyncStatusUnknownError]);
}

- (void)testSyncSyncOptionsNil {
    
    //If
    NSError *remoteError = [[NSError alloc] init];
    MSAssetsSyncOptions *syncOptions = [MSAssetsSyncOptions new];
    [syncOptions setDeploymentKey:kMSDeploymentKey];
    MSAssetsConfiguration *configuration = [MSAssetsConfiguration new];
    id delegateMock = [self mockSyncDelegate];
    
    //When
    [self syncWithSyncOptions:nil
             andDeploymentKey: kMSDeploymentKey
             andConfiguration:configuration
              andLocalPackage:nil
                  andDelegate:delegateMock
             andRemotePackage:nil
               andRemoteError:remoteError
      downloadAndInstallError:nil
                       dialog:nil];
    
    //Then
    OCMVerify([delegateMock syncStatusChanged:MSAssetsSyncStatusCheckingForUpdate]);
    OCMVerify([delegateMock syncStatusChanged:MSAssetsSyncStatusUnknownError]);
}

- (void)testSyncUpdateInstalled {
    
    //If
    MSAssetsRemotePackage *remotePackage = [MSAssetsRemotePackage createDefaultRemotePackageWithAppVersion:kMSAppVersion updateAppVersion:NO];
    [remotePackage setFailedInstall:YES];
    MSAssetsSyncOptions *syncOptions = [MSAssetsSyncOptions new];
    [syncOptions setIgnoreFailedUpdates:YES];
    [syncOptions setDeploymentKey:kMSDeploymentKey];
    MSAssetsLocalPackage *localPackage = [MSAssetsLocalPackage createLocalPackageWithAppVersion:kMSAppVersion];
    [localPackage setIsPending:YES];
    MSAssetsConfiguration *configuration = [MSAssetsConfiguration new];
    id delegateMock = [self mockSyncDelegate];
    
    //When
    [self syncWithSyncOptions:syncOptions
             andDeploymentKey:nil
             andConfiguration:configuration
              andLocalPackage:localPackage
                  andDelegate:delegateMock
             andRemotePackage:remotePackage
               andRemoteError:nil
      downloadAndInstallError:nil
                       dialog:nil];
    
    //Then
    OCMVerify([delegateMock syncStatusChanged:MSAssetsSyncStatusCheckingForUpdate]);
    OCMVerify([delegateMock syncStatusChanged:MSAssetsSyncStatusUpdateInstalled]);
}

- (void)testSyncUpToDate {
    
    //If
    MSAssetsRemotePackage *remotePackage = [MSAssetsRemotePackage createDefaultRemotePackageWithAppVersion:kMSAppVersion updateAppVersion:NO];
    [remotePackage setFailedInstall:YES];
    MSAssetsSyncOptions *syncOptions = [MSAssetsSyncOptions new];
    [syncOptions setIgnoreFailedUpdates:YES];
    [syncOptions setDeploymentKey:kMSDeploymentKey];
    MSAssetsConfiguration *configuration = [MSAssetsConfiguration new];
    id delegateMock = [self mockSyncDelegate];
    
    //When
    [self syncWithSyncOptions:syncOptions
             andDeploymentKey:nil
             andConfiguration:configuration
              andLocalPackage:nil
                  andDelegate:delegateMock
             andRemotePackage:remotePackage
               andRemoteError:nil
      downloadAndInstallError:nil
                       dialog:nil];
    
    //Then
    OCMVerify([delegateMock syncStatusChanged:MSAssetsSyncStatusCheckingForUpdate]);
    OCMVerify([delegateMock syncStatusChanged:MSAssetsSyncStatusUpToDate]);
}

- (void)testSyncDoDownloadAndInstallError {
    
    //If
    NSError *doDownloadAndInstallError = [[NSError alloc] init];
    MSAssetsRemotePackage *remotePackage = [MSAssetsRemotePackage createDefaultRemotePackageWithAppVersion:kMSAppVersion updateAppVersion:NO];
    [remotePackage setFailedInstall:YES];
    MSAssetsSyncOptions *syncOptions = [MSAssetsSyncOptions new];
    [syncOptions setIgnoreFailedUpdates:NO];
    [syncOptions setDeploymentKey:kMSDeploymentKey];
    MSAssetsConfiguration *configuration = [MSAssetsConfiguration new];
    id delegateMock = [self mockSyncDelegate];
    
    //When
    [self syncWithSyncOptions:syncOptions
             andDeploymentKey:nil
             andConfiguration:configuration
              andLocalPackage:nil
                  andDelegate:delegateMock
             andRemotePackage:remotePackage
               andRemoteError:nil
      downloadAndInstallError:doDownloadAndInstallError
                       dialog:nil];
    
    //Then
    OCMVerify([delegateMock syncStatusChanged:MSAssetsSyncStatusCheckingForUpdate]);
    OCMVerify([delegateMock syncStatusChanged:MSAssetsSyncStatusUnknownError]);
}

- (void)testSyncUpdateDialogDecline {
    
    //If
    MSAssetsRemotePackage *remotePackage = [MSAssetsRemotePackage createDefaultRemotePackageWithAppVersion:kMSAppVersion updateAppVersion:NO];
    [remotePackage setFailedInstall:YES];
    MSAssetsSyncOptions *syncOptions = [MSAssetsSyncOptions new];
    [syncOptions setIgnoreFailedUpdates:NO];
    [syncOptions setDeploymentKey:kMSDeploymentKey];
    MSAssetsConfiguration *configuration = [MSAssetsConfiguration new];
    id delegateMock = [self mockSyncDelegate];
    
    MSAssetsUpdateDialog *dialog = [MSAssetsUpdateDialog new];
    [remotePackage setIsMandatory:NO];
    [dialog setTitle:@"fake-title"];
    [dialog setOptionalUpdateMessage:@"fake-update-message"];
    [dialog setOptionalIgnoreButtonLabel:@"fake-ignore-btn"];
    [dialog setOptionalInstallButtonLabel:@"fake-install-btn"];
    
    //When
    [self syncWithSyncOptions:syncOptions
             andDeploymentKey:nil
             andConfiguration:configuration
              andLocalPackage:nil
                  andDelegate:delegateMock
             andRemotePackage:remotePackage
               andRemoteError:nil
      downloadAndInstallError:nil
                       dialog:dialog];
    
    //Then
    OCMVerify([delegateMock syncStatusChanged:MSAssetsSyncStatusCheckingForUpdate]);
    OCMVerify([delegateMock syncStatusChanged:MSAssetsSyncStatusAwaitingUserAction]);
    OCMVerify([delegateMock syncStatusChanged:MSAssetsSyncStatusUpdateIgnored]);
}

- (void)testSyncUpdateDialogAccept {
    
    //If
    MSAssetsRemotePackage *remotePackage = [MSAssetsRemotePackage createDefaultRemotePackageWithAppVersion:kMSAppVersion updateAppVersion:NO];
    [remotePackage setFailedInstall:YES];
    MSAssetsSyncOptions *syncOptions = [MSAssetsSyncOptions new];
    [syncOptions setIgnoreFailedUpdates:NO];
    [syncOptions setDeploymentKey:kMSDeploymentKey];
    MSAssetsConfiguration *configuration = [MSAssetsConfiguration new];
    id delegateMock = [self mockSyncDelegate];
    
    MSAssetsUpdateDialog *dialog = [MSAssetsUpdateDialog new];
    [remotePackage setIsMandatory:YES];
    [remotePackage setUpdateDescription:@"non-empty-description"];
    [dialog setTitle:@"fake-title"];
    [dialog setAppendReleaseDescription:YES];
    [dialog setDescriptionPrefix:@"fake-prefix"];
    [dialog setMandatoryUpdateMessage:@"fake-update-message"];
    [dialog setMandatoryContinueButtonLabel:@"fake-install-btn"];
    
    //When
    [self syncWithSyncOptions:syncOptions
             andDeploymentKey:nil
             andConfiguration:configuration
              andLocalPackage:nil
                  andDelegate:delegateMock
             andRemotePackage:remotePackage
               andRemoteError:nil
      downloadAndInstallError:nil
                       dialog:dialog];
    
    //Then
    OCMVerify([delegateMock syncStatusChanged:MSAssetsSyncStatusCheckingForUpdate]);
    OCMVerify([delegateMock syncStatusChanged:MSAssetsSyncStatusAwaitingUserAction]);
    OCMReject([delegateMock syncStatusChanged:MSAssetsSyncStatusUpdateIgnored]);
    OCMVerifyAll(delegateMock);
}

- (void)testSyncUpdateDialogAcceptDownloadError {
    
    //If
    MSAssetsRemotePackage *remotePackage = [MSAssetsRemotePackage createDefaultRemotePackageWithAppVersion:kMSAppVersion updateAppVersion:NO];
    [remotePackage setFailedInstall:YES];
    MSAssetsSyncOptions *syncOptions = [MSAssetsSyncOptions new];
    [syncOptions setIgnoreFailedUpdates:NO];
    [syncOptions setDeploymentKey:kMSDeploymentKey];
    MSAssetsConfiguration *configuration = [MSAssetsConfiguration new];
    id delegateMock = [self mockSyncDelegate];
    
    NSError *downloadError = [[NSError alloc] init];
    MSAssetsUpdateDialog *dialog = [MSAssetsUpdateDialog new];
    [remotePackage setIsMandatory:YES];
    [dialog setTitle:@"fake-title"];
    [dialog setMandatoryUpdateMessage:@"fake-update-message"];
    [dialog setMandatoryContinueButtonLabel:@"fake-install-btn"];
    
    //When
    [self syncWithSyncOptions:syncOptions
             andDeploymentKey:nil
             andConfiguration:configuration
              andLocalPackage:nil
                  andDelegate:delegateMock
             andRemotePackage:remotePackage
               andRemoteError:nil
      downloadAndInstallError:downloadError
                       dialog:dialog];
    
    //Then
    OCMVerify([delegateMock syncStatusChanged:MSAssetsSyncStatusCheckingForUpdate]);
    OCMVerify([delegateMock syncStatusChanged:MSAssetsSyncStatusAwaitingUserAction]);
    OCMVerify([delegateMock syncStatusChanged:MSAssetsSyncStatusUnknownError]);
}

- (void)testSyncDoDownloadAndInstall {
    
    //If
    MSAssetsRemotePackage *remotePackage = [MSAssetsRemotePackage createDefaultRemotePackageWithAppVersion:kMSAppVersion updateAppVersion:NO];
    [remotePackage setFailedInstall:YES];
    MSAssetsSyncOptions *syncOptions = [MSAssetsSyncOptions new];
    [syncOptions setIgnoreFailedUpdates:NO];
    [syncOptions setDeploymentKey:kMSDeploymentKey];
    MSAssetsConfiguration *configuration = [MSAssetsConfiguration new];
    id delegateMock = [self mockSyncDelegate];
    
    //When
    [self syncWithSyncOptions:syncOptions
             andDeploymentKey:nil
             andConfiguration:configuration
              andLocalPackage:nil
                  andDelegate:delegateMock
             andRemotePackage:remotePackage
               andRemoteError:nil
      downloadAndInstallError:nil
                       dialog:nil];
    
    //Then
    OCMReject([delegateMock syncStatusChanged:MSAssetsSyncStatusUnknownError]);
    OCMVerify([delegateMock syncStatusChanged:MSAssetsSyncStatusCheckingForUpdate]);
    OCMVerifyAll(delegateMock);
}

- (void)testSyncNoRemotePackage {
    
    //If
    MSAssetsSyncOptions *syncOptions = [MSAssetsSyncOptions new];
    [syncOptions setIgnoreFailedUpdates:NO];
    [syncOptions setDeploymentKey:kMSDeploymentKey];
    MSAssetsConfiguration *configuration = [MSAssetsConfiguration new];
    id delegateMock = [self mockSyncDelegate];
    
    //When
    [self syncWithSyncOptions:syncOptions
             andDeploymentKey:nil
             andConfiguration:configuration
              andLocalPackage:nil
                  andDelegate:delegateMock
             andRemotePackage:nil
               andRemoteError:nil
      downloadAndInstallError:nil
                       dialog:nil];
    
    //Then
    OCMVerify([delegateMock syncStatusChanged:MSAssetsSyncStatusCheckingForUpdate]);
    OCMVerify([delegateMock syncStatusChanged:MSAssetsSyncStatusUpToDate]);
}

/**
 * A helper method to test `MSAssetsDeploymentInstance#sync`.
 *
 * @param syncOptions `MSAssetsSyncOptions`, which will be passed to sync method.
 * @param deploymentKey deployment key which, if passed, will be set as instance property.
 * @param configuration `MSAssetsConfiguration` instance which, if passed, will be returned in a `getConfigurationWithError` method.
 * @param localPackage `MSAssetsLocalPackage` instance which will be returned in `getCurrentPackage` method.
 * @param delegate mocked delegate.
 * @param rmPackage `MSAssetsRemotePackage` instance to be returned in a `checkForUpdate` callback.
 * @param remoteError error to be returned in a `checkForUpdate` callback.
 * @param downloadAndInstallError error to be returned in a `doDownloadAndInstall` callback.
 * @param dialog `MSAssetsUpdateDialog`: if passed, will allow to mock `showDialogWithAcceptText`,
 * which, in turn, will call either handler or cancelHandler depending on whether the rmPackage is mandatory.
 */
- (void)syncWithSyncOptions:(MSAssetsSyncOptions *) syncOptions
           andDeploymentKey:(NSString *)deploymentKey
           andConfiguration:(MSAssetsConfiguration *)configuration
            andLocalPackage:(MSAssetsLocalPackage *)localPackage
                andDelegate:(id<MSAssetsDelegate>)delegate
           andRemotePackage:(MSAssetsRemotePackage *)rmPackage
             andRemoteError:(NSError *)remoteError
    downloadAndInstallError:(NSError *)downloadAndInstallError
                     dialog:(MSAssetsUpdateDialog *)dialog {
    
    // If
    id assetsMock = OCMPartialMock(self.sut);
    if (deploymentKey) {
        [assetsMock setDeploymentKey:deploymentKey];
    }
    NSString *message = rmPackage.isMandatory ? [dialog mandatoryUpdateMessage] : [dialog optionalUpdateMessage];
    if (dialog.appendReleaseDescription && (rmPackage.description.length != 0)) {
        message = [dialog.descriptionPrefix stringByAppendingFormat:@" %@", rmPackage.description];
    }
    if (dialog) {
        syncOptions.updateDialog = dialog;
        OCMStub([assetsMock showDialogWithAcceptText:rmPackage.isMandatory ? [dialog mandatoryContinueButtonLabel] : [dialog optionalInstallButtonLabel]
                                      andDeclineText:[dialog optionalIgnoreButtonLabel]
                                            andTitle:[dialog title]
                                          andMessage:message
                                     addCancelButton:!rmPackage.isMandatory
                                          andHandler:OCMOCK_ANY
                                    andCancelHandler:OCMOCK_ANY]).andDo(^(NSInvocation *invocation) {
            void (^loadCallback)();
            BOOL loadCancelCallback = !rmPackage.isMandatory;
            [invocation getArgument:&loadCallback atIndex: loadCancelCallback ? 8 : 7];
            loadCallback();
        });
    }
    OCMStub([assetsMock getCurrentPackage]).andReturn(localPackage);
    OCMStub([assetsMock getConfigurationWithError:(NSError * __autoreleasing *)[OCMArg anyPointer]]).andReturn(configuration);
    OCMStub([assetsMock checkForUpdate:syncOptions.deploymentKey ? syncOptions.deploymentKey : deploymentKey withCompletionHandler:OCMOCK_ANY]).andDo(^(NSInvocation *invocation) {
        MSCheckForUpdateCompletionHandler loadCallback;
        [invocation getArgument:&loadCallback atIndex:3];
        loadCallback(rmPackage, remoteError);
    });
    OCMStub([assetsMock doDownloadAndInstall:rmPackage syncOptions:syncOptions configuration:configuration handler:OCMOCK_ANY]).andDo(^(NSInvocation *invocation) {
        MSAssetsDownloadInstallHandler loadCallback;
        [invocation getArgument:&loadCallback atIndex:5];
        loadCallback(downloadAndInstallError);
    });
    if (delegate != nil) {
        [assetsMock setDelegate:delegate];
    }
    
    // When
    [assetsMock sync:syncOptions];
    
    // Then
    if (dialog) {
        OCMVerify([assetsMock showDialogWithAcceptText:rmPackage.isMandatory ? [dialog mandatoryContinueButtonLabel] : [dialog optionalInstallButtonLabel]
                                        andDeclineText:[dialog optionalIgnoreButtonLabel]
                                              andTitle:[dialog title]
                                            andMessage:message
                                       addCancelButton:!rmPackage.isMandatory
                                            andHandler:OCMOCK_ANY
                                      andCancelHandler:OCMOCK_ANY]);
    }
    OCMVerify([assetsMock checkForUpdate:syncOptions.deploymentKey ? syncOptions.deploymentKey : deploymentKey withCompletionHandler:OCMOCK_ANY]);
    XCTAssertEqual([assetsMock instanceState].syncInProgress, NO);
    [assetsMock stopMocking];
}

@end

