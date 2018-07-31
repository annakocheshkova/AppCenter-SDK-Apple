#import "MSDeploymentInstanceTests.h"
#import "MSAssetsDeploymentInstance.h"
#import "MSTestFrameworks.h"
#import "MSAssets.h"

@interface MSDeploymentInstanceTests (DownloadAndInstall)

@end

@implementation MSDeploymentInstanceTests (DownloadAndInstall)

- (void)testDoDownloadAndInstallError {
    NSError *downloadError = [[NSError alloc] init];
    id delegateMock = [self mockSyncDelegate];
    id mockRestartManager = [self doDownloadAndInstallWithSyncOptions:[MSAssetsSyncOptions new]
                             andRemotePackage:[MSAssetsRemotePackage new]
                             andConfiguration:[MSAssetsConfiguration new]
                         andDownloadedPackage:nil
                             andDownloadError:downloadError
                              andInstallError:nil
                                  andDelegate:delegateMock
                        andCallbackCompletion:^(NSError * _Nullable error) {
                            XCTAssertEqualObjects(error, downloadError);
                        }];
    
    [mockRestartManager stopMocking];
}

- (void)testDoDownloadAndInstallErrorInstall {
    NSString *label = @"LABEL";
    NSString *clientUniqueId = @"ABC";
    MSAssetsLocalPackage *localPackage = [MSAssetsLocalPackage createLocalPackageWithAppVersion:kMSAppVersion];
    [localPackage setLabel:label];
    MSAssetsConfiguration *configuration = [MSAssetsConfiguration new];
    [configuration setClientUniqueId:clientUniqueId];
    [configuration setDeploymentKey:kMSDeploymentKey];
    NSError *installError = [[NSError alloc] init];
    id delegateMock = [self mockSyncDelegate];
    id mockRestartManager = [self doDownloadAndInstallWithSyncOptions:[MSAssetsSyncOptions new]
                             andRemotePackage:[MSAssetsRemotePackage new]
                             andConfiguration:configuration
                         andDownloadedPackage:localPackage
                             andDownloadError:nil
                              andInstallError:installError
                                  andDelegate:delegateMock
                        andCallbackCompletion:^(NSError * _Nullable error) {
                            XCTAssertEqualObjects(error, installError);
                        }];
    OCMVerify([delegateMock syncStatusChanged:MSAssetsSyncStatusInstallingUpdate]);
    
    [mockRestartManager stopMocking];
}

- (void)testDoDownloadAndInstallImmediate {
    NSString *clientUniqueId = @"ABC";
    MSAssetsLocalPackage *localPackage = [MSAssetsLocalPackage createLocalPackageWithAppVersion:kMSAppVersion];
    [localPackage setLabel:nil];
    [localPackage setIsMandatory:YES];
    MSAssetsConfiguration *configuration = [MSAssetsConfiguration new];
    [configuration setClientUniqueId:clientUniqueId];
    [configuration setDeploymentKey:kMSDeploymentKey];
    MSAssetsSyncOptions *syncOptions = [MSAssetsSyncOptions new];
    [syncOptions setMandatoryInstallMode:MSAssetsInstallModeImmediate];
    id delegateMock = [self mockSyncDelegate];
    id restartMock = [self doDownloadAndInstallWithSyncOptions:syncOptions
                             andRemotePackage:[MSAssetsRemotePackage new]
                             andConfiguration:configuration
                         andDownloadedPackage:localPackage
                             andDownloadError:nil
                              andInstallError:nil
                                  andDelegate:delegateMock
                        andCallbackCompletion:^(NSError * _Nullable error) {
                            XCTAssertNil(error);
                        }];
    OCMReject([restartMock restartAppOnlyIfUpdateIsPending:NO]);
    OCMVerifyAll(restartMock);
    OCMVerify([restartMock clearPendingRestarts]);
    OCMVerify([delegateMock syncStatusChanged:MSAssetsSyncStatusInstallingUpdate]);
    OCMVerify([delegateMock syncStatusChanged:MSAssetsSyncStatusUpdateInstalled]);
    
    [restartMock stopMocking];
}

- (void)testDoDownloadAndInstallImmediateRestart {
    NSString *clientUniqueId = @"ABC";
    MSAssetsLocalPackage *localPackage = [MSAssetsLocalPackage createLocalPackageWithAppVersion:kMSAppVersion];
    [localPackage setLabel:nil];
    [localPackage setIsMandatory:NO];
    MSAssetsConfiguration *configuration = [MSAssetsConfiguration new];
    [configuration setClientUniqueId:clientUniqueId];
    [configuration setDeploymentKey:kMSDeploymentKey];
    MSAssetsSyncOptions *syncOptions = [MSAssetsSyncOptions new];
    [syncOptions setInstallMode:MSAssetsInstallModeImmediate];
    [syncOptions setShouldRestart:YES];
    id delegateMock = [self mockSyncDelegate];
    id restartMock = [self doDownloadAndInstallWithSyncOptions:syncOptions
                             andRemotePackage:[MSAssetsRemotePackage new]
                             andConfiguration:configuration
                         andDownloadedPackage:localPackage
                             andDownloadError:nil
                              andInstallError:nil
                                  andDelegate:delegateMock
                        andCallbackCompletion:^(NSError * _Nullable error) {
                            XCTAssertNil(error);
                        }];
    OCMVerify([restartMock restartAppOnlyIfUpdateIsPending:NO]);
    OCMVerify([delegateMock syncStatusChanged:MSAssetsSyncStatusInstallingUpdate]);
    OCMVerify([delegateMock syncStatusChanged:MSAssetsSyncStatusUpdateInstalled]);
    
    [restartMock stopMocking];
}

/**
 * A helper method to test `MSAssetsDeploymentInstance#doDownloadAndInstall`.
 *
 * @param syncOptions `MSAssetsSyncOptions` instance which will be passed to `doDownloadAndInstall` method.
 * @param remotePackage `MSAssetsRemotePackage` instance which will be passed to `doDownloadAndInstall` method.
 * @param configuration `MSAssetsConfiguration` instance which will be passed to `doDownloadAndInstall` method.
 * @param localPackage `MSAssetsLocalPackage` to be returned in a `downloadUpdate` callback.
 * @param downloadError error to be returned in a `downloadUpdate` callback.
 * @param installError error to be returned by an `installUpdate` method.
 * @param delegate mocked delegate.
 * @param handler method containing assertions to be made after `doDownloadAndInstall` called its handler.
 */
- (id)doDownloadAndInstallWithSyncOptions:(MSAssetsSyncOptions *)syncOptions
                           andRemotePackage:(MSAssetsRemotePackage *)remotePackage
                           andConfiguration:(MSAssetsConfiguration *)configuration
                       andDownloadedPackage:(MSAssetsLocalPackage *)localPackage
                           andDownloadError:(NSError *)downloadError
                            andInstallError:(NSError *)installError
                                andDelegate:(id<MSAssetsDelegate>)delegate
                      andCallbackCompletion:(nullable MSAssetsDownloadInstallHandler)handler {
    
    // If
    id assetsMock = OCMPartialMock(self.sut);
    id mockSettingManager = OCMClassMock([MSAssetsSettingManager class]);
    OCMStub([mockSettingManager saveFailedUpdate:remotePackage]);
    id mockAcquisitionManager = OCMClassMock([MSAssetsAcquisitionManager class]);
    OCMStub([mockAcquisitionManager reportDownloadStatus:OCMOCK_ANY withConfiguration:configuration]);
    id mockRestartManager = OCMClassMock([MSAssetsRestartManager class]);
    OCMStub([mockRestartManager clearPendingRestarts]);
    OCMStub([[mockRestartManager ignoringNonObjectArgs] restartAppOnlyIfUpdateIsPending:0]);
    [assetsMock setDelegate:delegate];
    [assetsMock setAcquisitionManager:mockAcquisitionManager];
    [assetsMock setSettingManager:mockSettingManager];
    [assetsMock setRestartManager:mockRestartManager];
    XCTestExpectation *expectation = nil;
    expectation = [self expectationWithDescription:@"Completion called"];
    OCMStub([[assetsMock ignoringNonObjectArgs] installUpdate:localPackage installMode:0 minimumBackgroundDuration:0]).andReturn(installError);
    OCMStub([assetsMock downloadUpdate:remotePackage completeHandler:OCMOCK_ANY]).andDo(^(NSInvocation *invocation) {
        MSAssetsPackageDownloadHandler loadCallback;
        [invocation getArgument:&loadCallback atIndex:3];
        loadCallback(localPackage, downloadError);
    });
    
    // When
    [assetsMock doDownloadAndInstall:remotePackage syncOptions:syncOptions configuration:configuration handler:^(NSError * _Nullable error) {
        handler(error);
        [expectation fulfill];
    }];

    // Then
    [self waitForExpectationsWithTimeout:1 handler:nil];
    OCMVerify([delegate syncStatusChanged:MSAssetsSyncStatusDownloadingPackage]);
    if (downloadError) {
      OCMVerify([mockSettingManager saveFailedUpdate:remotePackage]);
    }
    XCTAssertFalse([[assetsMock instanceState] syncInProgress]);
    if (!downloadError) {
        OCMVerify([mockAcquisitionManager reportDownloadStatus:OCMOCK_ANY withConfiguration:configuration]);
    }
    [assetsMock stopMocking];
    [mockAcquisitionManager stopMocking];
    [mockSettingManager stopMocking];
    return mockRestartManager;
}
@end

