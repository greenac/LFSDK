//
//  LFConnection.h
//  LFProxy3
//
//  Created by Andre Green on 7/16/14.
//  Copyright (c) 2014 Andre Green. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol LFConnectionDelegate;

@interface LFConnection : NSObject <NSStreamDelegate>


@property(nonatomic, strong)NSString *hostName;
@property(nonatomic, assign)int port;
@property(nonatomic, copy)NSMutableData *outData;
@property(nonatomic, copy)NSMutableData *inData;
@property(nonatomic, weak)NSData *serverAddressData;

@property(nonatomic, copy)NSString *protocolType;

@property(nonatomic, strong)NSURLRequest *outgoingRequest;
@property(nonatomic, strong)NSURLRequest *incomingRequest;

@property(nonatomic, assign)NSUInteger idNumber;

@property(nonatomic, weak)id <LFConnectionDelegate>delegate;

-(id)initWithServerAddressData:(NSData*)addData request:(NSURLRequest*)request protocol:(NSString*)protocol;

-(id)initWithHostName:(NSString*)hostName port:(int)port andProtocol:(NSString*)protocol;

-(void)connect;

@end


@protocol LFConnectionDelegate <NSObject>

-(void)connectionReceivedResponse:(LFConnection*)connection;
-(void)connectionHasReceivedData:(LFConnection*)connection;
-(void)connectionHasFailed:(LFConnection*)connection withError:(NSInteger)error;
-(void)connectionHasFinishedLoading:(LFConnection*)connection;
@end