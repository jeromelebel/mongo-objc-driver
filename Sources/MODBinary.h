//
//  MODBinary.h
//  mongo-objc-driver
//
//  Created by Jérôme Lebel on 28/09/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MODBinary : NSObject
{
    NSData *_data;
    char _binaryType;
}

+ (BOOL)isValidDataType:(unsigned char)dataType;

- (id)initWithData:(NSData *)data binaryType:(unsigned char)binaryType;
- (id)initWithBytes:(const void *)bytes length:(NSUInteger)length binaryType:(unsigned char)binaryType;
- (NSString *)jsonValueWithPretty:(BOOL)pretty strictJSON:(BOOL)strictJSON;

@property(nonatomic, readonly, assign)char binaryType;
@property(nonatomic, readonly, assign)NSData *data;

@end
