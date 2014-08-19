//
//  MODFunction.m
//  MongoObjCDriver
//
//  Created by Jérôme Lebel on 12/06/2014.
//
//

#import "MOD_internal.h"

@implementation MODFunction

@synthesize function = _function;

- (id)initWithFunction:(NSString *)function
{
    if (self = [self init]) {
        self.function = function;
    }
    return self;
}

- (void)dealloc
{
    self.function = nil;
    [super dealloc];
}

- (NSString *)jsonValueWithPretty:(BOOL)pretty strictJSON:(BOOL)strictJSON
{
    if (!strictJSON) {
        return [NSString stringWithFormat:@"Function(\"%@\")", [MODClient escapeQuotesForString:self.function]];
    } else if (pretty) {
        return [NSString stringWithFormat:@"{ \"$function\" : \"%@\" }", [MODClient escapeQuotesForString:self.function]];
    } else {
        return [NSString stringWithFormat:@"{\"$function\":\"%@\"}", [MODClient escapeQuotesForString:self.function]];
    }
}

- (BOOL)isEqual:(id)object
{
    if ([object isKindOfClass:[self class]]) {
        return [self.function isEqualToString:[object function]];
    }
    return NO;
}

@end
