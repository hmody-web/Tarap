#import <Foundation/Foundation.h>

static NSString * const kCover = @"https://scrptaty.com/apps/tarab/media/1.jpg";
static NSString * const kIcon  = @"https://scrptaty.com/apps/tarab/media/icon1.png";
static NSString * const kURL   = @"https://scrptaty.com/";

static BOOL LooksLikeTarabItems(NSData *data) {
    if (!data || data.length < 20) return NO;
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!s) return NO;
    return ([s rangeOfString:@"\"isBanner\""].location != NSNotFound &&
            [s rangeOfString:@"\"coverURL\""].location != NSNotFound &&
            ([s rangeOfString:@"tarab.app/uploads/media"].location != NSNotFound ||
             [s rangeOfString:@"panoramavideo.app/uploads/media"].location != NSNotFound));
}

static void PatchBannerDictionary(NSMutableDictionary *d) {
    if (![d isKindOfClass:[NSMutableDictionary class]]) return;
    if (![d[@"isBanner"] boolValue]) return;

    d[@"coverURL"] = kCover;
    d[@"iconURL"] = kIcon;
    d[@"type"] = @"internal_url";
    d[@"action"] = [@{ @"url": kURL } mutableCopy];
    d[@"name"] = [@{ @"ar": @"سكربتاتي", @"en": @"سكربتاتي" } mutableCopy];
    d[@"subtitle"] = [@{ @"ar": @"عالمك البرمجي في تطبيق واحد !", @"en": @"عالمك البرمجي في تطبيق واحد !" } mutableCopy];
    d[@"availability"] = [@{ @"countries": @[], @"showMode": @"all" } mutableCopy];
}

static void PatchTopLevelItems(id obj) {
    if ([obj isKindOfClass:[NSMutableArray class]]) {
        for (id item in (NSMutableArray *)obj) {
            if ([item isKindOfClass:[NSMutableDictionary class]]) PatchBannerDictionary(item);
        }
        return;
    }

    if ([obj isKindOfClass:[NSMutableDictionary class]]) {
        NSMutableDictionary *root = (NSMutableDictionary *)obj;
        for (NSString *key in @[@"iphone_items", @"ipad_items", @"items"]) {
            id arr = root[key];
            if ([arr isKindOfClass:[NSMutableArray class]]) {
                for (id item in (NSMutableArray *)arr) {
                    if ([item isKindOfClass:[NSMutableDictionary class]]) PatchBannerDictionary(item);
                }
            }
        }
    }
}

%hook NSJSONSerialization
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error {
    // Do not touch normal JSON used by YouTube/Firebase/etc.
    if (!LooksLikeTarabItems(data)) return %orig(data, opt, error);

    id obj = %orig(data, opt | NSJSONReadingMutableContainers, error);
    if (obj) PatchTopLevelItems(obj);
    return obj;
}
%end
