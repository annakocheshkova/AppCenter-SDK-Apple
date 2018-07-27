#import <XCTest/XCTest.h>
#import "MSTestFrameworks.h"
#import "MSAssetsTelemetryManager.h"
#import "MSAssetsSettingManager.h"

static NSString *const kAppVersion = @"1.6.2";

@interface MSAssetsTelemetryManagerTests : XCTestCase

@property (nonatomic) MSAssetsTelemetryManager *sut;
@property id mockSettingManager;

@end

@implementation MSAssetsTelemetryManagerTests

- (void)setUp {
    [super setUp];

    _mockSettingManager = OCMClassMock([MSAssetsSettingManager class]);
    self.sut = [[MSAssetsTelemetryManager alloc] initWithSettingManager:_mockSettingManager];
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (NSDictionary *)getAssetsPackageDictionary {
    return [[NSDictionary alloc] initWithObjectsAndKeys:
            kAppVersion, @"appVersion",
            @"X0s3Jrpp7TBLmMe5x_UG0b8hf-a8SknGZWL7Q", @"deploymentKey",
            @"descriptionText", @"description",
            @NO, @"failedInstall",
            @NO, @"isMandatory",
            @"labelText", @"label",
            @"packageHashData", @"packageHash",
            nil];
}

- (MSAssetsPackage *)getPackage {
    return [[MSAssetsPackage alloc] initWithDictionary:[self getAssetsPackageDictionary]];
}

- (void)testMSAssetsTelemetryManagerInitialization {
    XCTAssertNotNil(self.sut);
}

- (void)testBuildBinaryUpdateReportWithAppVersionNoStatusReportidentifier {
    
    MSAssetsStatusReportIdentifier *statusReportIdentifier = 
    OCMStub([_mockSettingManager getPreviousStatusReportIdentifier]).andReturn(nil);
    MSAssetsDeploymentStatusReport *deploymentStatusReport = [self.sut buildBinaryUpdateReportWithAppVersion:kAppVersion];
    XCTAssertNotNil(deploymentStatusReport);
    XCTAssertEqualObjects(deploymentStatusReport.appVersion, kAppVersion);
    XCTAssertEqualObjects(deploymentStatusReport.label, @"");
    XCTAssertEqual(deploymentStatusReport.status, MSAssetsDeploymentStatusSucceeded);
}

- (void)testBuildBinaryUpdateReportWithAppVersionAndStatusReportidentifierWithDeploymentKey {
    
    NSString *fakeDeploymentKey = @"DEP-KEY";
    MSAssetsStatusReportIdentifier *statusReportIdentifier = [[MSAssetsStatusReportIdentifier alloc] initWithAppVersion:kAppVersion andDeploymentKey:fakeDeploymentKey];

    OCMStub([_mockSettingManager getPreviousStatusReportIdentifier]).andReturn(statusReportIdentifier);
    MSAssetsDeploymentStatusReport *deploymentStatusReport = [self.sut buildBinaryUpdateReportWithAppVersion:kAppVersion];
    XCTAssertNotNil(deploymentStatusReport);
    XCTAssertEqualObjects(deploymentStatusReport.appVersion, kAppVersion);
    XCTAssertEqualObjects(deploymentStatusReport.previousDeploymentKey, fakeDeploymentKey);
    XCTAssertEqualObjects(deploymentStatusReport.previousLabelOrAppVersion, kAppVersion);
    XCTAssertEqual(deploymentStatusReport.status, MSAssetsDeploymentStatusSucceeded);
}

- (void)testBuildBinaryUpdateReportWithAppVersionAndStatusReportidentifierAnotherAppVersion {
    NSString *anotherVersion = @"anotherAppVersion";
    MSAssetsStatusReportIdentifier *statusReportIdentifier = [[MSAssetsStatusReportIdentifier alloc] initWithAppVersion:anotherVersion];
    OCMStub([_mockSettingManager getPreviousStatusReportIdentifier]).andReturn(statusReportIdentifier);
    MSAssetsDeploymentStatusReport *deploymentStatusReport = [self.sut buildBinaryUpdateReportWithAppVersion:kAppVersion];
    XCTAssertNotNil(deploymentStatusReport);
    XCTAssertEqualObjects(deploymentStatusReport.appVersion, kAppVersion);
    XCTAssertEqualObjects(deploymentStatusReport.previousLabelOrAppVersion, anotherVersion);
}

- (void)testBuildUpdateReportWithPackageNil {
    XCTAssertNil([self.sut buildUpdateReportWithPackage:nil]);
}


- (void)testBuildUpdateReportWithPackageWithNilPreviousStatusReportIdentifier {
    OCMStub([_mockSettingManager getPreviousStatusReportIdentifier]).andReturn(nil);
    MSAssetsLocalPackage *localPackage = [MSAssetsLocalPackage createLocalPackageWithPackage:[self getPackage] failedInstall:NO isFirstRun:NO isPending:NO isDebugOnly:NO entryPoint:@"entryPoint"];
    MSAssetsDeploymentStatusReport *deploymentStatusReport = [self.sut buildUpdateReportWithPackage:localPackage];
    
    XCTAssertNotNil(deploymentStatusReport);
    XCTAssertEqualObjects(deploymentStatusReport.assetsPackage, localPackage);
    XCTAssertEqual(deploymentStatusReport.status, MSAssetsDeploymentStatusSucceeded);
}

- (void)testBuildUpdateReportWithPackageWithPreviousIdentifierHasDeploymentKey {
    NSString *previousDeploymentKey = @"prevDepKey";
    NSString *previousVersionLabel = @"1.0";
    MSAssetsStatusReportIdentifier *statusReportIdentifier = [[MSAssetsStatusReportIdentifier alloc] initWithAppVersion:previousVersionLabel andDeploymentKey:previousDeploymentKey];
    OCMStub([_mockSettingManager getPreviousStatusReportIdentifier]).andReturn(statusReportIdentifier);
    
    MSAssetsLocalPackage *localPackage = [MSAssetsLocalPackage createLocalPackageWithPackage:[self getPackage] failedInstall:NO isFirstRun:NO isPending:NO isDebugOnly:NO entryPoint:@"entryPoint"];
    MSAssetsDeploymentStatusReport *deploymentStatusReport = [self.sut buildUpdateReportWithPackage:localPackage];
    
    XCTAssertNotNil(deploymentStatusReport);
    XCTAssertEqualObjects(deploymentStatusReport.assetsPackage, localPackage);
    XCTAssertEqual(deploymentStatusReport.status, MSAssetsDeploymentStatusSucceeded);
    XCTAssertEqualObjects(deploymentStatusReport.previousDeploymentKey, previousDeploymentKey);
    XCTAssertEqualObjects(deploymentStatusReport.previousLabelOrAppVersion, previousVersionLabel);
}

- (void)testBuildUpdateReportWithPackageWithPreviousIdentifierWithoutDeploymentKey {
    NSString *previousVersionLabel = @"1.0";
    MSAssetsStatusReportIdentifier *statusReportIdentifier = [[MSAssetsStatusReportIdentifier alloc] initWithAppVersion:previousVersionLabel];
    OCMStub([_mockSettingManager getPreviousStatusReportIdentifier]).andReturn(statusReportIdentifier);
    
    MSAssetsLocalPackage *localPackage = [MSAssetsLocalPackage createLocalPackageWithPackage:[self getPackage] failedInstall:NO isFirstRun:NO isPending:NO isDebugOnly:NO entryPoint:@"entryPoint"];
    MSAssetsDeploymentStatusReport *deploymentStatusReport = [self.sut buildUpdateReportWithPackage:localPackage];
    
    XCTAssertNotNil(deploymentStatusReport);
    XCTAssertEqualObjects(deploymentStatusReport.assetsPackage, localPackage);
    XCTAssertEqual(deploymentStatusReport.status, MSAssetsDeploymentStatusSucceeded);
    XCTAssertEqualObjects(deploymentStatusReport.previousLabelOrAppVersion, previousVersionLabel);
}

- (void)testBuildRollbackReportWithFailedPackage {
    MSAssetsPackage *failedPackage = [self getPackage];
    MSAssetsDeploymentStatusReport *deploymentStatusReport = [self.sut buildRollbackReportWithFailedPackage:failedPackage];
    XCTAssertNotNil(deploymentStatusReport);
    XCTAssertEqualObjects(deploymentStatusReport.assetsPackage, failedPackage);
    XCTAssertEqual(deploymentStatusReport.status, MSAssetsDeploymentStatusFailed);
}

- (void)testBuildRollbackReportWithNilPackage {
    MSAssetsDeploymentStatusReport *deploymentStatusReport = [self.sut buildRollbackReportWithFailedPackage:nil];
    XCTAssertNotNil(deploymentStatusReport);
    XCTAssertEqualObjects(deploymentStatusReport.assetsPackage, nil);
    XCTAssertEqual(deploymentStatusReport.status, MSAssetsDeploymentStatusFailed);
}

- (MSAssetsDeploymentStatusReport *)getDeploymentStatusReport {
    NSDictionary *assetsPackage = [self getAssetsPackageDictionary];
    NSDictionary *dictIn = [[NSDictionary alloc] initWithObjectsAndKeys:
                            @"clientUniqueIdData", @"clientUniqueId",
                            @"deploymentKeyData", @"deploymentKey",
                            @"labelData", @"label",
                            kAppVersion, @"appVersion",
                            @"previousDeploymentKeyData", @"previousDeploymentKey",
                            @"previousLabelOrAppVersionData", @"previousLabelOrAppVersion",
                            @"DeploymentSucceeded", @"status",
                            assetsPackage, @"package",
                            nil];
    MSAssetsDeploymentStatusReport *deploymentStatusReport = [[MSAssetsDeploymentStatusReport alloc] initWithDictionary:dictIn];
    return deploymentStatusReport;
}

- (void)testSaveReportedStatusWithFailedPackage {
    MSAssetsDeploymentStatusReport *deploymentStatusReport = [self getDeploymentStatusReport];
    deploymentStatusReport.status = MSAssetsDeploymentStatusFailed;
    [self.sut saveReportedStatus:deploymentStatusReport];
    OCMReject([_mockSettingManager saveIdentifierOfReportedStatus:OCMOCK_ANY]);
}

- (void)testSaveReportedStatus {
    MSAssetsDeploymentStatusReport *deploymentStatusReport = [self getDeploymentStatusReport];
    [self.sut saveReportedStatus:deploymentStatusReport];
    OCMVerify([_mockSettingManager saveIdentifierOfReportedStatus:OCMOCK_ANY]);
}



@end
