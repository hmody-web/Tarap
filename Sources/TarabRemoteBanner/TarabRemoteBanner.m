#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString * const TRBAPIURL = @"https://scrptaty.com/apps/tarab/api.php";
static const CGFloat TRBContainerHeight = 206.0;
static const CGFloat TRBContentHeight = 178.0;
static const CGFloat TRBGap = 12.0;

#pragma mark - Model

@interface TRBBannerItem : NSObject
@property(nonatomic, copy) NSString *itemID;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *descText;
@property(nonatomic, copy) NSString *coverURL;
@property(nonatomic, copy) NSString *iconURL;
@property(nonatomic, copy) NSString *downloadURL;
@property(nonatomic) NSInteger sortOrder;
@end

@implementation TRBBannerItem
@end

#pragma mark - Image loader/cache

@interface TRBImageLoader : NSObject
@property(nonatomic, strong) NSCache<NSString *, UIImage *> *cache;
+ (instancetype)shared;
- (void)load:(NSString *)urlString completion:(void(^)(UIImage *image))completion;
@end

@implementation TRBImageLoader

+ (instancetype)shared {
    static TRBImageLoader *loader;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        loader = [TRBImageLoader new];
        loader.cache = [NSCache new];
        loader.cache.countLimit = 80;
    });
    return loader;
}

- (void)load:(NSString *)urlString completion:(void(^)(UIImage *image))completion {
    if (urlString.length == 0) {
        if (completion) completion(nil);
        return;
    }

    UIImage *cached = [self.cache objectForKey:urlString];
    if (cached) {
        if (completion) completion(cached);
        return;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (completion) completion(nil);
        return;
    }

    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithURL:url
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            UIImage *image = data.length ? [UIImage imageWithData:data] : nil;
            if (image) {
                [[TRBImageLoader shared].cache setObject:image forKey:urlString];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(image);
            });
        }];
    [task resume];
}

@end

#pragma mark - Banner page

@interface TRBBannerPage : UIView
@property(nonatomic, strong) UIImageView *coverView;
@property(nonatomic, strong) UIView *shadeView;
@property(nonatomic, strong) UIImageView *iconView;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *descLabel;
@property(nonatomic, strong) UIButton *downloadButton;
@property(nonatomic, copy) NSString *downloadURL;
- (void)configure:(TRBBannerItem *)item;
@end

@implementation TRBBannerPage

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.clipsToBounds = YES;
    self.layer.cornerRadius = 16.0;
    if (@available(iOS 13.0, *)) {
        self.backgroundColor = UIColor.secondarySystemBackgroundColor;
    } else {
        self.backgroundColor = UIColor.darkGrayColor;
    }

    _coverView = [[UIImageView alloc] initWithFrame:self.bounds];
    _coverView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _coverView.contentMode = UIViewContentModeScaleAspectFill;
    _coverView.clipsToBounds = YES;
    [self addSubview:_coverView];

    _shadeView = [[UIView alloc] initWithFrame:self.bounds];
    _shadeView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.colors = @[
        (id)[UIColor colorWithWhite:0 alpha:0.05].CGColor,
        (id)[UIColor colorWithWhite:0 alpha:0.15].CGColor,
        (id)[UIColor colorWithWhite:0 alpha:0.72].CGColor
    ];
    gradient.locations = @[@0.0, @0.46, @1.0];
    gradient.startPoint = CGPointMake(0.5, 0.0);
    gradient.endPoint = CGPointMake(0.5, 1.0);
    gradient.frame = _shadeView.bounds;
    [_shadeView.layer addSublayer:gradient];
    [self addSubview:_shadeView];

    _iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.contentMode = UIViewContentModeScaleAspectFill;
    _iconView.clipsToBounds = YES;
    _iconView.layer.cornerRadius = 17.0;
    _iconView.backgroundColor = [UIColor colorWithWhite:1 alpha:0.18];
    [self addSubview:_iconView];

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.textColor = UIColor.whiteColor;
    _titleLabel.font = [UIFont systemFontOfSize:19 weight:UIFontWeightBold];
    _titleLabel.textAlignment = NSTextAlignmentRight;
    _titleLabel.numberOfLines = 1;
    _titleLabel.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    [self addSubview:_titleLabel];

    _descLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _descLabel.textColor = [UIColor colorWithWhite:1 alpha:0.82];
    _descLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    _descLabel.textAlignment = NSTextAlignmentRight;
    _descLabel.numberOfLines = 2;
    _descLabel.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    [self addSubview:_descLabel];

    _downloadButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _downloadButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_downloadButton setTitle:@"تنزيل" forState:UIControlStateNormal];
    [_downloadButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _downloadButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    _downloadButton.backgroundColor = [UIColor colorWithWhite:1 alpha:0.26];
    _downloadButton.layer.cornerRadius = 23.0;
    _downloadButton.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
    _downloadButton.layer.borderWidth = 1.0;
    [_downloadButton addTarget:self action:@selector(openDownload) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_downloadButton];

    [NSLayoutConstraint activateConstraints:@[
        [_iconView.topAnchor constraintEqualToAnchor:self.topAnchor constant:16],
        [_iconView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_iconView.widthAnchor constraintEqualToConstant:66],
        [_iconView.heightAnchor constraintEqualToConstant:66],

        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-18],
        [_titleLabel.bottomAnchor constraintEqualToAnchor:_descLabel.topAnchor constant:-2],
        [_titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_downloadButton.trailingAnchor constant:12],

        [_descLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-18],
        [_descLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-17],
        [_descLabel.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor multiplier:0.62],

        [_downloadButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:18],
        [_downloadButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-18],
        [_downloadButton.widthAnchor constraintEqualToConstant:116],
        [_downloadButton.heightAnchor constraintEqualToConstant:46],
    ]];

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    for (CALayer *layer in self.shadeView.layer.sublayers) {
        if ([layer isKindOfClass:CAGradientLayer.class]) {
            layer.frame = self.shadeView.bounds;
        }
    }
}

- (void)configure:(TRBBannerItem *)item {
    self.titleLabel.text = item.title ?: @"";
    self.descLabel.text = item.descText ?: @"";
    self.downloadURL = item.downloadURL ?: @"";

    self.coverView.image = nil;
    self.iconView.image = nil;

    __weak typeof(self) weakSelf = self;
    [[TRBImageLoader shared] load:item.coverURL completion:^(UIImage *image) {
        weakSelf.coverView.image = image;
    }];
    [[TRBImageLoader shared] load:item.iconURL completion:^(UIImage *image) {
        weakSelf.iconView.image = image;
    }];
}

- (void)openDownload {
    if (self.downloadURL.length == 0) return;
    NSURL *url = [NSURL URLWithString:self.downloadURL];
    if (!url) return;
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

@end

#pragma mark - Carousel

@interface TRBBannerCarousel : UIView <UIScrollViewDelegate>
@property(nonatomic, strong) UIScrollView *scroll;
@property(nonatomic, strong) UIPageControl *dots;
@property(nonatomic, strong) NSArray<TRBBannerItem *> *items;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic) BOOL didLoad;
- (void)loadRemoteData;
@end

@implementation TRBBannerCarousel

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.backgroundColor = UIColor.clearColor;

    _scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    _scroll.pagingEnabled = YES;
    _scroll.showsHorizontalScrollIndicator = NO;
    _scroll.delegate = self;
    _scroll.clipsToBounds = YES;
    [self addSubview:_scroll];

    _dots = [[UIPageControl alloc] initWithFrame:CGRectZero];
    _dots.translatesAutoresizingMaskIntoConstraints = NO;
    _dots.hidesForSinglePage = YES;
    _dots.userInteractionEnabled = NO;
    if (@available(iOS 14.0, *)) {
        _dots.backgroundStyle = UIPageControlBackgroundStyleMinimal;
    }
    [self addSubview:_dots];

    [NSLayoutConstraint activateConstraints:@[
        [_scroll.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_scroll.heightAnchor constraintEqualToConstant:TRBContentHeight],

        [_dots.topAnchor constraintEqualToAnchor:_scroll.bottomAnchor constant:1],
        [_dots.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_dots.heightAnchor constraintEqualToConstant:24],
    ]];

    return self;
}

- (void)dealloc {
    [_timer invalidate];
}

- (void)loadRemoteData {
    if (self.didLoad) return;
    self.didLoad = YES;

    NSURL *url = [NSURL URLWithString:TRBAPIURL];
    if (!url) return;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.cachePolicy = NSURLRequestReloadRevalidatingCacheData;
    request.timeoutInterval = 12.0;
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    __weak typeof(self) weakSelf = self;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {

        if (!data.length || error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                weakSelf.didLoad = NO;
                weakSelf.hidden = YES;
            });
            return;
        }

        NSError *jsonError = nil;
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        NSArray *raw = [obj isKindOfClass:NSDictionary.class] ? ((NSDictionary *)obj)[@"banners"] : nil;

        if (![raw isKindOfClass:NSArray.class]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                weakSelf.didLoad = NO;
                weakSelf.hidden = YES;
            });
            return;
        }

        NSMutableArray *parsed = [NSMutableArray array];
        for (id rowObj in raw) {
            if (![rowObj isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *row = (NSDictionary *)rowObj;

            id enabled = row[@"enabled"];
            if ([enabled respondsToSelector:@selector(boolValue)] && ![enabled boolValue]) continue;

            TRBBannerItem *item = [TRBBannerItem new];
            item.itemID = [row[@"id"] description] ?: @"";
            item.title = [row[@"title"] isKindOfClass:NSString.class] ? row[@"title"] : @"";
            item.descText = [row[@"description"] isKindOfClass:NSString.class] ? row[@"description"] : @"";
            item.coverURL = [row[@"cover_url"] isKindOfClass:NSString.class] ? row[@"cover_url"] : @"";
            item.iconURL = [row[@"icon_url"] isKindOfClass:NSString.class] ? row[@"icon_url"] : @"";
            item.downloadURL = [row[@"download_url"] isKindOfClass:NSString.class] ? row[@"download_url"] : @"";
            item.sortOrder = [row[@"sort_order"] respondsToSelector:@selector(integerValue)] ? [row[@"sort_order"] integerValue] : 0;

            if (item.coverURL.length || item.title.length) {
                [parsed addObject:item];
            }
        }

        [parsed sortUsingComparator:^NSComparisonResult(TRBBannerItem *a, TRBBannerItem *b) {
            if (a.sortOrder < b.sortOrder) return NSOrderedAscending;
            if (a.sortOrder > b.sortOrder) return NSOrderedDescending;
            return NSOrderedSame;
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf applyItems:parsed];
        });
    }] resume];
}

- (void)applyItems:(NSArray<TRBBannerItem *> *)items {
    self.items = items ?: @[];

    for (UIView *v in self.scroll.subviews) [v removeFromSuperview];

    if (self.items.count == 0) {
        self.hidden = YES;
        return;
    }

    self.hidden = NO;
    CGFloat w = self.bounds.size.width;
    if (w < 100) w = UIScreen.mainScreen.bounds.size.width - 32.0;

    self.scroll.contentSize = CGSizeMake(w * self.items.count, TRBContentHeight);
    self.dots.numberOfPages = self.items.count;
    self.dots.currentPage = 0;

    [self.items enumerateObjectsUsingBlock:^(TRBBannerItem *item, NSUInteger idx, BOOL *stop) {
        CGRect frame = CGRectMake(w * idx, 0, w, TRBContentHeight);
        TRBBannerPage *page = [[TRBBannerPage alloc] initWithFrame:CGRectInset(frame, 0, 0)];
        [page configure:item];
        [self.scroll addSubview:page];
    }];

    [self.timer invalidate];
    if (self.items.count > 1) {
        self.timer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                     target:self
                                                   selector:@selector(nextPage)
                                                   userInfo:nil
                                                    repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    self.scroll.frame = CGRectMake(0, 0, w, TRBContentHeight);

    [self.items enumerateObjectsUsingBlock:^(TRBBannerItem *item, NSUInteger idx, BOOL *stop) {
        if (idx < self.scroll.subviews.count) {
            UIView *page = self.scroll.subviews[idx];
            page.frame = CGRectMake(w * idx, 0, w, TRBContentHeight);
        }
    }];
    self.scroll.contentSize = CGSizeMake(w * self.items.count, TRBContentHeight);
}

- (void)nextPage {
    if (self.items.count < 2 || self.scroll.isDragging || self.scroll.isDecelerating) return;
    NSInteger next = (self.dots.currentPage + 1) % self.items.count;
    [self.scroll setContentOffset:CGPointMake(next * self.scroll.bounds.size.width, 0) animated:YES];
    self.dots.currentPage = next;
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    CGFloat w = MAX(scrollView.bounds.size.width, 1);
    NSInteger page = (NSInteger)llround(scrollView.contentOffset.x / w);
    self.dots.currentPage = MAX(0, MIN(page, (NSInteger)self.items.count - 1));
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    [self scrollViewDidEndDecelerating:scrollView];
}

@end

#pragma mark - Installation / page targeting

static char kTRBCarouselKey;
static char kTRBOriginalInsetKey;
static char kTRBTargetScrollKey;
static IMP TRBOriginalViewDidAppear = NULL;
static IMP TRBOriginalViewDidLayout = NULL;

static BOOL TRBStringContains(NSString *haystack, NSString *needle) {
    if (![haystack isKindOfClass:NSString.class] || ![needle isKindOfClass:NSString.class]) return NO;
    return [haystack rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static BOOL TRBIsSourcesPage(UIViewController *vc) {
    UITabBarItem *selected = vc.tabBarController.tabBar.selectedItem;
    NSString *tabTitle = selected.title ?: @"";

    if (TRBStringContains(tabTitle, @"المصادر") || TRBStringContains(tabTitle, @"source")) {
        return YES;
    }

    NSString *className = NSStringFromClass(vc.class);
    if (TRBStringContains(className, @"source")) return YES;

    // Fallback for custom/floating tab bars: look for source-page-specific texts.
    __block BOOL foundYouTube = NO;
    __block BOOL foundTrending = NO;

    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:vc.view];
    NSUInteger inspected = 0;
    while (stack.count && inspected < 1200) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        inspected++;

        NSString *text = nil;
        if ([v isKindOfClass:UILabel.class]) {
            text = ((UILabel *)v).text;
        } else if ([v isKindOfClass:UIButton.class]) {
            text = [((UIButton *)v) titleForState:UIControlStateNormal];
        }

        if (TRBStringContains(text, @"يوتيوب")) foundYouTube = YES;
        if (TRBStringContains(text, @"ترندات")) foundTrending = YES;
        if (foundYouTube && foundTrending) return YES;

        for (UIView *sub in v.subviews) {
            [stack addObject:sub];
        }
    }

    return NO;
}

static UIScrollView *TRBFindMainScrollView(UIView *root) {
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    UIScrollView *best = nil;
    CGFloat bestScore = 0;

    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];

        if ([v isKindOfClass:UIScrollView.class]) {
            UIScrollView *s = (UIScrollView *)v;
            CGRect f = [s convertRect:s.bounds toView:root];

            // We want the page's large vertical scroller, not the native ad carousel
            // or our own horizontal pager.
            if (f.size.width >= 350.0 && f.size.height >= 420.0 &&
                s != objc_getAssociatedObject(root, &kTRBTargetScrollKey)) {
                CGFloat score = f.size.width * f.size.height;
                if (score > bestScore) {
                    bestScore = score;
                    best = s;
                }
            }
        }

        for (UIView *sub in v.subviews) {
            [stack addObject:sub];
        }
    }
    return best;
}

static void TRBInstallBannerIntoController(UIViewController *vc) {
    if (!vc.isViewLoaded || !vc.view.window) return;
    if (!TRBIsSourcesPage(vc)) return;

    TRBBannerCarousel *existing = objc_getAssociatedObject(vc, &kTRBCarouselKey);
    if (existing && existing.superview) {
        [existing loadRemoteData];
        return;
    }

    UIScrollView *scroll = TRBFindMainScrollView(vc.view);
    if (!scroll) return;

    // Preserve the exact original inset once.
    NSValue *savedValue = objc_getAssociatedObject(scroll, &kTRBOriginalInsetKey);
    UIEdgeInsets originalInset = savedValue ? savedValue.UIEdgeInsetsValue : scroll.contentInset;

    if (!savedValue) {
        objc_setAssociatedObject(
            scroll,
            &kTRBOriginalInsetKey,
            [NSValue valueWithUIEdgeInsets:originalInset],
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }

    CGFloat extra = TRBContainerHeight + TRBGap;
    UIEdgeInsets newInset = originalInset;
    newInset.top += extra;
    scroll.contentInset = newInset;

    if (@available(iOS 11.0, *)) {
        // Do not modify automatic behavior; only contentInset is changed.
    }

    CGFloat width = MIN(358.0, MAX(280.0, scroll.bounds.size.width - 32.0));
    CGFloat x = (scroll.bounds.size.width - width) / 2.0;
    CGFloat y = -newInset.top + originalInset.top + 4.0;

    TRBBannerCarousel *carousel = [[TRBBannerCarousel alloc]
        initWithFrame:CGRectMake(x, y, width, TRBContainerHeight)];
    carousel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    carousel.hidden = YES;
    carousel.tag = 0x54524231; // TRB1

    [scroll addSubview:carousel];
    [scroll sendSubviewToBack:carousel];

    objc_setAssociatedObject(vc, &kTRBCarouselKey, carousel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(vc.view, &kTRBTargetScrollKey, scroll, OBJC_ASSOCIATION_ASSIGN);

    [carousel loadRemoteData];
}

static void TRBPatchedViewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    ((void (*)(id, SEL, BOOL))TRBOriginalViewDidAppear)(self, _cmd, animated);

    dispatch_async(dispatch_get_main_queue(), ^{
        TRBInstallBannerIntoController(self);
    });
}

static void TRBPatchedViewDidLayout(UIViewController *self, SEL _cmd) {
    ((void (*)(id, SEL))TRBOriginalViewDidLayout)(self, _cmd);

    TRBBannerCarousel *carousel = objc_getAssociatedObject(self, &kTRBCarouselKey);
    if (carousel && carousel.superview) {
        UIScrollView *scroll = (UIScrollView *)carousel.superview;
        CGFloat width = MIN(358.0, MAX(280.0, scroll.bounds.size.width - 32.0));
        CGFloat x = (scroll.bounds.size.width - width) / 2.0;
        CGRect f = carousel.frame;
        f.origin.x = x;
        f.size.width = width;
        f.size.height = TRBContainerHeight;
        carousel.frame = f;
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            TRBInstallBannerIntoController(self);
        });
    }
}

static void TRBInstallHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = UIViewController.class;

        Method appear = class_getInstanceMethod(cls, @selector(viewDidAppear:));
        Method layout = class_getInstanceMethod(cls, @selector(viewDidLayoutSubviews));

        TRBOriginalViewDidAppear = method_getImplementation(appear);
        TRBOriginalViewDidLayout = method_getImplementation(layout);

        method_setImplementation(appear, (IMP)TRBPatchedViewDidAppear);
        method_setImplementation(layout, (IMP)TRBPatchedViewDidLayout);

        NSLog(@"[TarabRemoteBanner] hooks installed");
    });
}

__attribute__((constructor))
static void TRBConstructor(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        TRBInstallHooks();
    });
}
