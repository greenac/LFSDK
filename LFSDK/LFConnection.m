//
//  LFConnection.m
//  LFProxy3
//
//  Created by Andre Green on 7/16/14.
//  Copyright (c) 2014 Andre Green. All rights reserved.
//

#import "LFConnection.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/types.h>
#include <sys/un.h>
#include <ifaddrs.h>
#include <net/if.h>

@interface LFConnection()

@property(nonatomic, strong)NSInputStream *inputStream;
@property(nonatomic, strong)NSOutputStream *outputStream;

@property(nonatomic, assign)NSUInteger bytesRead;
@property(nonatomic, assign)NSUInteger bytesWritten;


-(void)pairStreams:(CFReadStreamRef*)readStream writeStream:(CFWriteStreamRef*)writeStream;

@end


static NSUInteger const MAX_BUFFER_SIZE = 1024;
static NSUInteger ider = 0;
static NSString const *LF_HTTP_PROXY_IP = @"https://54.225.180.246";
static NSString const *LF_HTTPS_PROXY_IP = @"https://54.22.180.246";
static int const LF_PROXY_PORT = 8080;

@implementation LFConnection

-(id)initWithServerAddressData:(NSData *)addData request:(NSURLRequest *)request protocol:(NSString *)protocol{
    
    self = [super init];
    
    if (self) {
        
        
        _serverAddressData  = addData;
        _hostName           = nil;
        _port               = -1;
        
        _inData             = [[NSMutableData alloc] init];
        _outData            = [[NSMutableData alloc] init];
        
        _bytesRead          = 0;
        _bytesWritten       = 0;
        _protocolType       = protocol.lowercaseString;
        _outgoingRequest    = request;
        _idNumber           = ++ider;
    }
    
    return self;
}

-(id)initWithHostName:(NSString *)hostName port:(int)port andProtocol:(NSString *)protocol{
    
    self = [super init];
    
    if (self) {
        
        _hostName           = hostName;
        _port               = port;
        
        _inData             = [[NSMutableData alloc] init];
        _outData            = [[NSMutableData alloc] init];
        
        _bytesRead          = 0;
        _bytesWritten       = 0;
        _protocolType       = protocol.lowercaseString;
        _idNumber           = ++ider;
    }
    
    return self;
}

-(void)connect{
    
    
    CFReadStreamRef inStream;
    CFWriteStreamRef outStream;
    
    if (self.hostName) {
        // creates streams to final destination of request
        CFStreamCreatePairWithSocketToHost(CFAllocatorGetDefault(), (__bridge CFStringRef)self.outgoingRequest.URL.host, self.port, &inStream, &outStream);
        
        [self setProxyInfoForReadStream:&inStream andWriteStream:&outStream];
    }
    else{
        //creates streams to local proxy
        self.outData = [[self dataFromNSURLRequest:self.outgoingRequest] mutableCopy];

        CFSocketSignature signature = {PF_INET, SOCK_STREAM, IPPROTO_TCP, (__bridge CFDataRef)self.serverAddressData};

        CFStreamCreatePairWithPeerSocketSignature(CFAllocatorGetDefault(), &signature, &inStream, &outStream);
    }
    
    
    NSRunLoop *currentLoop = [NSRunLoop currentRunLoop];
    
    self.outputStream = (__bridge_transfer NSOutputStream*)outStream;
    self.outputStream.delegate = self;
    [self.outputStream scheduleInRunLoop:currentLoop forMode:NSDefaultRunLoopMode];
    [self.outputStream open];
    
    self.inputStream = (__bridge_transfer NSInputStream*)inStream;
    self.inputStream.delegate = self;
    [self.inputStream scheduleInRunLoop:currentLoop forMode:NSDefaultRunLoopMode];
    [self.inputStream open];

    [currentLoop run];
}



-(void)setProxyInfoForReadStream:(CFReadStreamRef *)readStream andWriteStream:(CFWriteStreamRef *)writeStream{
    
    // create proxy setting
    NSString *host = (NSString *)kCFStreamPropertyHTTPProxyHost;
    NSString *port = (NSString *)kCFStreamPropertyHTTPProxyPort;
    NSString *serverAddress = (NSString*)LF_HTTP_PROXY_IP;
    NSNumber *serverPort = [NSNumber numberWithInt:LF_PROXY_PORT];
    
    if ([self.protocolType isEqualToString:@"https"]) {
        
        host = (NSString *)kCFStreamPropertyHTTPSProxyHost;
        port = (NSString *)kCFStreamPropertyHTTPSProxyPort;
        serverAddress = (NSString*)LF_HTTPS_PROXY_IP;
    }
    
    // apply settings
    CFWriteStreamSetProperty(*writeStream, (__bridge CFStringRef)host, (__bridge CFStringRef)serverAddress);
    CFWriteStreamSetProperty(*writeStream, (__bridge CFStringRef)port, (__bridge CFNumberRef)serverPort);
    
    CFReadStreamSetProperty(*readStream, (__bridge CFStringRef)host, (__bridge CFStringRef)serverAddress);
    CFReadStreamSetProperty(*readStream, (__bridge CFStringRef)port, (__bridge CFNumberRef)serverPort);
}

-(NSData*)dataFromNSURLRequest:(NSURLRequest*)request{
    
    //copy request into CFHTTPMessage
    
    CFHTTPMessageRef requestcf = CFHTTPMessageCreateRequest(CFAllocatorGetDefault(),
                                                            (__bridge CFStringRef)request.HTTPMethod,
                                                            (__bridge CFURLRef)request.URL.absoluteURL,
                                                            kCFHTTPVersion1_1);

    if (request.HTTPBody.length > 0) {
        
        CFHTTPMessageSetBody(requestcf, (__bridge CFDataRef)request.HTTPBody);
    }
    
    for (NSString *key in request.allHTTPHeaderFields) {
        
        NSString *value = [request.allHTTPHeaderFields objectForKey:key];
        CFHTTPMessageSetHeaderFieldValue(requestcf, (__bridge CFStringRef)key, (__bridge CFStringRef)value);
    }
    
    NSString *host = @"Host";
    
    CFHTTPMessageSetHeaderFieldValue(requestcf, (__bridge CFStringRef)host, (__bridge CFStringRef)request.URL.absoluteString);
    
    CFHTTPMessageSetHeaderFieldValue(requestcf, CFSTR("Lotus-Flare-Header"), CFSTR("Test-Header"));
    
    CFDataRef requestCFData = CFHTTPMessageCopySerializedMessage(requestcf);
    
    NSData *requestData = (__bridge_transfer NSData*)requestCFData;

    return requestData;
}

-(void)setIncomingRequestForReceivedData:(NSData*)data withErrorCode:(NSInteger)error{
    
    CFHTTPMessageRef response = CFHTTPMessageCreateResponse(CFAllocatorGetDefault(), [self getStautsCode:error], NULL, kCFHTTPVersion1_1);
    
    NSString *contentLength = [NSString stringWithFormat:@"%lu", (unsigned long)data.length];
    
    CFHTTPMessageSetHeaderFieldValue(response, CFSTR("Content-Length"), (__bridge CFStringRef)contentLength);
                                     
}

-(NSInteger)getStautsCode:(NSInteger)error{
    
    return (error == 0) ? 200 : 400;
}

-(NSNumber*)serverPort{
    
    struct sockaddr *add = (struct sockaddr*)[self.serverAddressData bytes];
    int port = (((struct sockaddr_in*)add)->sin_port);
    
    return [NSNumber numberWithInt:port];
}

-(NSString*)serverAddress{
    
    struct sockaddr_in *serverAddress = (struct sockaddr_in*)[self.serverAddressData bytes];
    
    char *ipstr = malloc(INET_ADDRSTRLEN);
    struct in_addr *ipv4addr = &serverAddress->sin_addr;
    ipstr = inet_ntoa(*ipv4addr);
    
    return [NSString stringWithFormat:@"%s", ipstr];
}

#pragma mark - NSStream delegate methods

-(void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode{
    
    NSString *streamType;
    if (stream == self.inputStream) {
        streamType = @"input stream";
    }
    else if(stream == self.outputStream){
        streamType = @"output stream";
    }
    
    NSLog(@"event code: %lu for %@", eventCode, streamType);
    
    switch (eventCode) {
            
        case NSStreamEventOpenCompleted:
            NSLog(@"stream event open completed for %@", streamType);
            break;
            
        case NSStreamEventHasSpaceAvailable:{
            
            NSLog(@"stream event has space available in %@", streamType);
            
            if (stream == self.outputStream) {
                
                NSInteger byteDifference = self.outData.length - self.bytesWritten;
                
                if (byteDifference > 0) {
                    
                    uint8_t *byteMarker = (uint8_t*)[[self.outData mutableCopy] mutableBytes];
                    *byteMarker += self.bytesWritten;
                    
                    NSUInteger size = (byteDifference < MAX_BUFFER_SIZE) ? byteDifference : MAX_BUFFER_SIZE;
                    
                    UInt8 buffer[size];
                    
                    memcpy(buffer, byteMarker, size);
                    
                    [self.outputStream write:buffer maxLength:size];
                    
                    self.bytesWritten += size;
                }
            }
            
            break;
        }
            
        case NSStreamEventHasBytesAvailable:{
            NSLog(@"stream has bytes available for %@", streamType);
            
            if (stream == self.inputStream) {
                
                UInt8 buffer[MAX_BUFFER_SIZE];
                NSUInteger len = 0;
                
                len = [self.inputStream read:buffer maxLength:MAX_BUFFER_SIZE];
                
                if (len) {
                    
                    [self.inData appendBytes:buffer length:len];
                    self.bytesRead += len;
                    
                    NSString *inString = [[NSString alloc] initWithData:self.inData encoding:NSUTF8StringEncoding];
                    NSLog(@"data read in from connection: %@", inString);
                }
                else{
                    
                    NSLog(@"Input stream not reading. length: %lu", (unsigned long)len);
                }
            }
            
            break;
        }
            
        case NSStreamEventEndEncountered:{
            
            NSLog(@"end of event encountered for %@", streamType);
            
            if (stream == self.outputStream) {
                NSLog(@"closing output stream");
                
                self.bytesWritten = 0;
            }
            else if (stream == self.inputStream) {
                
                NSLog(@"closing input stream");
                
                if ([self.delegate respondsToSelector:@selector(connectionHasReceivedData:)]) {
                    
                    [self.delegate connectionHasReceivedData:self];
                }
                
                self.bytesRead = 0;
                self.inData.length = 0;
            }
            
            [stream close];
            [stream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
            
            break;
        }
            
        case NSStreamEventErrorOccurred:{
            
            NSLog(@"stream error occured in %@", streamType);
            NSString* errorMessage = [NSString stringWithFormat:@"%@ (Code = %ld)", [stream.streamError localizedDescription], (long)[stream.streamError code]];
            NSLog(@"%@", errorMessage);
            break;
        }
            
        case NSStreamEventNone:
            NSLog(@"stream event none for %@", streamType);
            break;
            
        default:
            NSLog(@"hit default case in LFConnection for %@", streamType);
            break;
    }
}

@end
