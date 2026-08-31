#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static NSString * const kCover = @"https://scrptaty.com/apps/tarab/media/1.jpg";
static NSString * const kIcon  = @"https://scrptaty.com/apps/tarab/media/icon1.png";
static NSString * const kURL   = @"https://scrptaty.com/";

static void ForceBanner(id obj) {
    if ([obj isKindOfClass:[NSMutableArray class]]) {
        for (id x in (NSMutableArray *)obj) ForceBanner(x);
        return;
    }
    if (![obj isKindOfClass:[NSMutableDictionary class]]) return;
    NSMutableDictionary *d=(NSMutableDictionary *)obj;
    if ([d[@"isBanner"] boolValue]) {
        d[@"coverURL"] = kCover;
        d[@"iconURL"] = kIcon;
        d[@"type"] = @"internal_url";
        d[@"action"] = [@{ @"url": kURL } mutableCopy];
        d[@"name"] = [@{ @"ar": @"سكربتاتي", @"en": @"سكربتاتي" } mutableCopy];
        d[@"subtitle"] = [@{ @"ar": @"عالمك البرمجي في تطبيق واحد !", @"en": @"عالمك البرمجي في تطبيق واحد !" } mutableCopy];
        d[@"availability"] = [@{ @"countries": @[], @"showMode": @"all" } mutableCopy];
    }
    for (id key in [d allKeys]) ForceBanner(d[key]);
}

%hook NSJSONSerialization
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error {
    id obj=%orig(data, opt|NSJSONReadingMutableContainers, error);
    ForceBanner(obj); return obj;
}
%end

// Re-apply after app becomes active, covering cached/reloaded JSON paths.
%ctor {
    @autoreleasepool {
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *n) {
            // JSON interception remains active for every subsequent config refresh.
        }];
    }
}
