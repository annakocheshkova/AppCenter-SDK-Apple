#import "MSAssetsTelemetryManager.h"
#import "MSAssetsLocalPackage.h"
#import "MSAssetsPackage.h"
#import "MSAssetsDeploymentStatusReport.h"
#import "MSAssetsStatusReportIdentifier.h"

@interface MSAssetsTelemetryManager ()

// Private Access
@property MSAssetsSettingManager *settingManager;

@end


@implementation MSAssetsTelemetryManager

- (id)initWithSettingManager: (MSAssetsSettingManager *)settingManager {
    self = [super init];
    if (self) {
        self.settingManager = settingManager;
    }
    return self;
}

- (MSAssetsDeploymentStatusReport *)buildBinaryUpdateReportWithAppVersion:(NSString * _Nonnull)appVersion {
    MSAssetsStatusReportIdentifier *previousStatusReportIdentifier = [[self settingManager] getPreviousStatusReportIdentifier];
    MSAssetsDeploymentStatusReport *report = nil;
    if (previousStatusReportIdentifier == nil) {
        
        /* There was no previous status report */
        report = [MSAssetsDeploymentStatusReport new];
        [report setAppVersion:appVersion];
        [report setLabel:@""];
        [report setStatus:MSAssetsDeploymentStatusSucceeded];
    } else {
        BOOL identifierHasDeploymentKey = [previousStatusReportIdentifier hasDeploymentKey];
        NSString *identifierLabel = [previousStatusReportIdentifier versionLabelOrEmpty];
        if (identifierHasDeploymentKey || ![identifierLabel isEqualToString:appVersion]) {
            report = [MSAssetsDeploymentStatusReport new];
            if (identifierHasDeploymentKey) {
                NSString *previousDeploymentKey = [previousStatusReportIdentifier deploymentKey];
                NSString *previousLabel = [previousStatusReportIdentifier versionLabel];
                report = [MSAssetsDeploymentStatusReport new];
                [report setAppVersion:appVersion];
                [report setPreviousDeploymentKey:previousDeploymentKey];
                [report setPreviousLabelOrAppVersion:previousLabel];
            } else {
                
                /* Previous status report was with a binary app version. */
                [report setAppVersion:appVersion];
                [report setPreviousLabelOrAppVersion:[previousStatusReportIdentifier versionLabel]];
            }
        }
    }
    return report;
}

- (MSAssetsDeploymentStatusReport *)buildUpdateReportWithPackage:(MSAssetsPackage * _Nonnull)currentPackage {
    MSAssetsStatusReportIdentifier *currentPackageIdentifier = [self  buildPackageStatusReportIdentifier:currentPackage];
    MSAssetsStatusReportIdentifier *previousStatusReportIdentifier = [[self settingManager] getPreviousStatusReportIdentifier];
    MSAssetsDeploymentStatusReport *report = nil;
    if (currentPackageIdentifier != nil) {
        if (previousStatusReportIdentifier == nil) {
            report = [MSAssetsDeploymentStatusReport new];
            [report setAssetsPackage:currentPackage];
            [report setStatus:MSAssetsDeploymentStatusSucceeded];
        } else {
            /* Compare identifiers as strings for simplicity */
            if (![[previousStatusReportIdentifier toString] isEqualToString:[currentPackageIdentifier toString]]) {
                report = [MSAssetsDeploymentStatusReport new];
                [report setAssetsPackage:currentPackage];
                [report setStatus:MSAssetsDeploymentStatusSucceeded];
                NSString *previousLabel = [previousStatusReportIdentifier versionLabel];
                [report setPreviousLabelOrAppVersion:previousLabel];
                if ([previousStatusReportIdentifier hasDeploymentKey]) {
                    NSString *previousDeploymentKey = [previousStatusReportIdentifier deploymentKey];
                    [report setPreviousDeploymentKey:previousDeploymentKey];
                }
            }
        }
    }
    return report;
}

- (MSAssetsStatusReportIdentifier *)buildPackageStatusReportIdentifier:(MSAssetsPackage *)updatePackage {
    
    /* Because deploymentKeys can be dynamically switched, we use a
     combination of the deploymentKey and label as the packageIdentifier. */
    NSString *deploymentKey = [updatePackage deploymentKey];
    NSString *label = [updatePackage label];
    if (deploymentKey != nil && label != nil) {
        return [[MSAssetsStatusReportIdentifier alloc] initWithAppVersion:label andDeploymentKey:deploymentKey];
    } else {
        return nil;
    }
}

- (MSAssetsDeploymentStatusReport *)buildRollbackReportWithFailedPackage:(MSAssetsPackage * _Nonnull)failedPackage {
    MSAssetsDeploymentStatusReport *report = [MSAssetsDeploymentStatusReport new];
    [report setAssetsPackage:failedPackage];
    [report setStatus:MSAssetsDeploymentStatusFailed];
    return report;
}

- (void)saveReportedStatus:(MSAssetsDeploymentStatusReport *)report {
    if (report.status == MSAssetsDeploymentStatusFailed) {
        return;
    }
    MSAssetsStatusReportIdentifier *identifier;
    if (report.appVersion.length != 0) {
        identifier = [[MSAssetsStatusReportIdentifier alloc] initWithAppVersion:report.appVersion];
    } else if (report.assetsPackage != nil) {
        identifier = [self buildPackageStatusReportIdentifier:report.assetsPackage];
    }
    if (identifier) {
        [[self settingManager] saveIdentifierOfReportedStatus:identifier];
    }
}

@end
