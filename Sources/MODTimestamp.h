//
//  MODTimestamp.h
//  mongo-objc-driver
//
//  Created by Jérôme Lebel on 24/09/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MODTimestamp : NSObject
{
    uint32_t                    _tValue;
    uint32_t                    _iValue;
}

- (id)initWithTValue:(uint32_t)tValue iValue:(uint32_t)iValue;
- (NSString *)jsonValueWithPretty:(BOOL)pretty strictJSON:(BOOL)strictJSON;
- (NSDate *)dateValue;

@property(nonatomic, readonly, assign) uint32_t tValue;
@property(nonatomic, readonly, assign) uint32_t iValue;

@end
