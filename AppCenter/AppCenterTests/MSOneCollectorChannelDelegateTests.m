#import "MSChannelUnitConfiguration.h"
#import "MSChannelUnitProtocol.h"
#import "MSChannelUnitDefault.h"
#import "MSChannelGroupProtocol.h"
#import "MSOneCollectorChannelDelegatePrivate.h"
#import "MSStorage.h"
#import "MSSender.h"
#import "MSTestFrameworks.h"

static NSString *const kMSBaseGroupId = @"baseGroupId";

@interface MSOneCollectorChannelDelegateTests : XCTestCase

@property(nonatomic) MSOneCollectorChannelDelegate *sut;
@property(nonatomic) id<MSSender> senderMock;
@property(nonatomic) id<MSStorage> storageMock;
@property(nonatomic) dispatch_queue_t logsDispatchQueue;
@property(nonatomic) MSChannelUnitConfiguration *baseUnitConfigMock;

@end

@implementation MSOneCollectorChannelDelegateTests

- (void)setUp {
  [super setUp];
  self.sut = [MSOneCollectorChannelDelegate new];
  self.senderMock = OCMProtocolMock(@protocol(MSSender));
  self.storageMock = OCMProtocolMock(@protocol(MSStorage));
  self.logsDispatchQueue = dispatch_get_main_queue();
  self.baseUnitConfigMock = [[MSChannelUnitConfiguration alloc] initWithGroupId:kMSBaseGroupId
                                                                       priority:MSPriorityDefault
                                                                  flushInterval:3.0
                                                                 batchSizeLimit:1024
                                                            pendingBatchesLimit:60];
}

- (void)testDidAddChannelUnitWithBaseGroupId {

  // Test adding a base channel unit on MSChannelGroupDefault will also add a One Collector channel unit.

  // If
  id<MSChannelUnitProtocol> channelUnitMock = OCMProtocolMock(@protocol(MSChannelUnitProtocol));
  NSString *expectedGroupId = @"baseGroupId/one";

  OCMStub([channelUnitMock configuration]).andReturn(self.baseUnitConfigMock);
  id channelGroupMock = OCMProtocolMock(@protocol(MSChannelGroupProtocol));
  __block id<MSChannelUnitProtocol> expectedChannelUnitMock = OCMProtocolMock(@protocol(MSChannelUnitProtocol));
  __block MSChannelUnitConfiguration *oneCollectorChannelConfig = nil;
  OCMStub([channelGroupMock addChannelUnitWithConfiguration:OCMOCK_ANY withSender:OCMOCK_ANY])
      .andDo(^(NSInvocation *invocation) {
        [invocation retainArguments];
        [invocation getArgument:&oneCollectorChannelConfig atIndex:2];
        [invocation setReturnValue:&expectedChannelUnitMock];
      });

  // When
  [self.sut channelGroup:channelGroupMock didAddChannelUnit:channelUnitMock];

  // Then
  XCTAssertNotNil(self.sut.oneCollectorChannels[kMSBaseGroupId]);
  XCTAssertTrue([self.sut.oneCollectorChannels count] == 1);
  XCTAssertEqual(expectedChannelUnitMock, self.sut.oneCollectorChannels[kMSBaseGroupId]);
  XCTAssertTrue([oneCollectorChannelConfig.groupId isEqualToString:expectedGroupId]);
  OCMVerifyAll(channelGroupMock);
}

- (void)testDidAddChannelUnitWithOneCollectorGroupId {

  /*
   * Test adding an One Collector channel unit on MSChannelGroupDefault won't do anything on
   * MSOneCollectorChannelDelegate
   * because it's already an One Collector group Id.
   */

  // If
  id<MSChannelUnitProtocol> channelUnitMock = OCMProtocolMock(@protocol(MSChannelUnitProtocol));
  NSString *groupId = @"baseGroupId/one";
  MSChannelUnitConfiguration *unitConfig = [[MSChannelUnitConfiguration alloc] initWithGroupId:groupId
                                                                                      priority:MSPriorityDefault
                                                                                 flushInterval:3.0
                                                                                batchSizeLimit:1024
                                                                           pendingBatchesLimit:60];
  OCMStub([channelUnitMock configuration]).andReturn(unitConfig);
  id channelGroupMock = OCMProtocolMock(@protocol(MSChannelGroupProtocol));
  OCMReject([channelGroupMock addChannelUnitWithConfiguration:OCMOCK_ANY]);

  // When
  [self.sut channelGroup:channelGroupMock didAddChannelUnit:channelUnitMock];

  // Then
  XCTAssertNotNil(self.sut.oneCollectorChannels);
  XCTAssertTrue([self.sut.oneCollectorChannels count] == 0);
  OCMVerifyAll(channelGroupMock);
}

- (void)testDidSetEnabledAndDeleteDataOnDisabledWithBaseGroupId {

  /*
   * Test base channel unit's logs are cleared when the base channel unit is disabled.
   * First, add a base channel unit to the channel group.
   * Then, disable the base channel unit.
   * Lastly, verify the storage deletion is called for the base channel group id.
   */

  // If
  MSChannelUnitDefault *channelUnitMock = [[MSChannelUnitDefault alloc] initWithSender:self.senderMock
                                                                               storage:self.storageMock
                                                                         configuration:self.baseUnitConfigMock
                                                                     logsDispatchQueue:self.logsDispatchQueue];
  id channelGroupMock = OCMProtocolMock(@protocol(MSChannelGroupProtocol));
  OCMStub([channelGroupMock addChannelUnitWithConfiguration:self.baseUnitConfigMock]);
  OCMStub([channelUnitMock setEnabled:NO andDeleteDataOnDisabled:YES]);

  // When
  [self.sut channelGroup:channelGroupMock didAddChannelUnit:channelUnitMock];
  [self.sut channel:channelUnitMock didSetEnabled:NO andDeleteDataOnDisabled:YES];

  // Then
  [self enqueueChannelEndJobExpectation];
  [self waitForExpectationsWithTimeout:1
                               handler:^(NSError *error) {
                                 OCMVerify([self.storageMock deleteLogsWithGroupId:kMSBaseGroupId]);
                                 if (error) {
                                   XCTFail(@"Expectation Failed with error: %@", error);
                                 }
                               }];
}

- (void)testDidSetEnabledAndDeleteDataOnDisabledWithOneCollectorGroupId {

  /*
   * Test One Collector channel unit's logs are cleared when the One Collector channel unit is disabled.
   * Disable One Collector channel unit.
   * Verify the storage deletion is called for the One Collector channel group id.
   */

  // If
  NSString *oneCollectorGroupId = @"baseGroupId/one";
  MSChannelUnitConfiguration *oneCollectorUnitConfig =
      [[MSChannelUnitConfiguration alloc] initWithGroupId:oneCollectorGroupId
                                                 priority:MSPriorityDefault
                                            flushInterval:3.0
                                           batchSizeLimit:1024
                                      pendingBatchesLimit:60];

  MSChannelUnitDefault *oneCollectorChannelUnitMock =
      [[MSChannelUnitDefault alloc] initWithSender:self.senderMock
                                           storage:self.storageMock
                                     configuration:oneCollectorUnitConfig
                                 logsDispatchQueue:self.logsDispatchQueue];
  id channelGroupMock = OCMProtocolMock(@protocol(MSChannelGroupProtocol));
  OCMReject([channelGroupMock addChannelUnitWithConfiguration:OCMOCK_ANY]);
  OCMStub([oneCollectorChannelUnitMock setEnabled:NO andDeleteDataOnDisabled:YES]);

  // When
  [self.sut channel:oneCollectorChannelUnitMock didSetEnabled:NO andDeleteDataOnDisabled:YES];

  // Then
  XCTAssertTrue(self.sut.oneCollectorChannels.count == 0);
  [self enqueueChannelEndJobExpectation];
  [self waitForExpectationsWithTimeout:1
                               handler:^(NSError *error) {
                                 OCMVerify([self.storageMock deleteLogsWithGroupId:oneCollectorGroupId]);
                                 if (error) {
                                   XCTFail(@"Expectation Failed with error: %@", error);
                                 }
                               }];
}

// A helper method to initialize the test expectation
- (void)enqueueChannelEndJobExpectation {
  XCTestExpectation *channelEndJobExpectation = [self expectationWithDescription:@"Channel job should be finished"];
  dispatch_async(self.logsDispatchQueue, ^{
    [channelEndJobExpectation fulfill];
  });
}

@end