#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString * const TRBAPIURL = @"https://scrptaty.com/apps/tarab/api.php";
static const CGFloat TRBContainerHeight = 180.0;
static const CGFloat TRBContentHeight = 180.0;
static const CGFloat TRBGap = 0.0;
static const CGFloat TRBPageGap = 12.0;

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
@property(nonatomic, strong) CALayer *iconShadowLayer;
@property(nonatomic, strong) CALayer *breezeLayer;
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
    self.accessibilityIdentifier = @"TRBBannerPage";
    self.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    self.layer.cornerRadius = 18.0;
    if (@available(iOS 13.0, *)) self.layer.cornerCurve = kCACornerCurveContinuous;
    if (@available(iOS 13.0, *)) {
        self.backgroundColor = UIColor.secondarySystemBackgroundColor;
    } else {
        self.backgroundColor = UIColor.darkGrayColor;
    }

    _coverView = [[UIImageView alloc] initWithFrame:self.bounds];
    _coverView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _coverView.contentMode = UIViewContentModeScaleAspectFill;
    _coverView.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    _coverView.transform = CGAffineTransformIdentity;
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

    // Subtle "breeze" / bubbles, similar to the native banner decoration.
    _breezeLayer = [CALayer layer];
    _breezeLayer.frame = self.bounds;
    _breezeLayer.masksToBounds = YES;
    [self.layer addSublayer:_breezeLayer];

    NSArray<NSValue *> *bubblePoints = @[
        [NSValue valueWithCGPoint:CGPointMake(28, 30)],
        [NSValue valueWithCGPoint:CGPointMake(72, 58)],
        [NSValue valueWithCGPoint:CGPointMake(302, 34)],
        [NSValue valueWithCGPoint:CGPointMake(330, 76)],
        [NSValue valueWithCGPoint:CGPointMake(245, 112)],
        [NSValue valueWithCGPoint:CGPointMake(116, 126)]
    ];
    NSArray<NSNumber *> *bubbleSizes = @[@7,@4,@6,@3,@5,@4];
    for (NSUInteger i = 0; i < bubblePoints.count; i++) {
        CGPoint p = bubblePoints[i].CGPointValue;
        CGFloat d = bubbleSizes[i].doubleValue;
        CAShapeLayer *bubble = [CAShapeLayer layer];
        bubble.frame = CGRectMake(p.x, p.y, d, d);
        bubble.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, d, d)].CGPath;
        bubble.fillColor = [UIColor colorWithWhite:1.0 alpha:0.16].CGColor;
        [_breezeLayer addSublayer:bubble];

        CABasicAnimation *floatAnim = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
        floatAnim.fromValue = @0;
        floatAnim.toValue = @(-10.0 - (CGFloat)i);
        floatAnim.duration = 2.8 + (CGFloat)i * 0.32;
        floatAnim.autoreverses = YES;
        floatAnim.repeatCount = HUGE_VALF;
        floatAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [bubble addAnimation:floatAnim forKey:@"trb.breeze"];

        CABasicAnimation *fadeAnim = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fadeAnim.fromValue = @0.35;
        fadeAnim.toValue = @0.9;
        fadeAnim.duration = 2.2 + (CGFloat)i * 0.25;
        fadeAnim.autoreverses = YES;
        fadeAnim.repeatCount = HUGE_VALF;
        [bubble addAnimation:fadeAnim forKey:@"trb.fade"];
    }

    _iconShadowLayer = [CALayer layer];
    _iconShadowLayer.backgroundColor = UIColor.clearColor.CGColor;
    _iconShadowLayer.shadowColor = UIColor.blackColor.CGColor;
    _iconShadowLayer.shadowOpacity = 0.28;
    _iconShadowLayer.shadowRadius = 7.0;
    _iconShadowLayer.shadowOffset = CGSizeMake(0, 3);
    [self.layer addSublayer:_iconShadowLayer];

    _iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.contentMode = UIViewContentModeScaleAspectFill;
    _iconView.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    _iconView.transform = CGAffineTransformIdentity;
    _iconView.clipsToBounds = YES;
    _iconView.layer.cornerRadius = 17.0;
    _iconView.backgroundColor = [UIColor colorWithWhite:1 alpha:0.18];
    [self addSubview:_iconView];
    [self bringSubviewToFront:_iconView];

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.textColor = UIColor.whiteColor;
    _titleLabel.font = [UIFont systemFontOfSize:19 weight:UIFontWeightBold];
    _titleLabel.textAlignment = NSTextAlignmentRight;
    _titleLabel.numberOfLines = 1;
    _titleLabel.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    _titleLabel.transform = CGAffineTransformIdentity;
    [self addSubview:_titleLabel];
    [self bringSubviewToFront:_titleLabel];

    _descLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _descLabel.textColor = [UIColor colorWithWhite:1 alpha:0.82];
    _descLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    _descLabel.textAlignment = NSTextAlignmentRight;
    _descLabel.numberOfLines = 2;
    _descLabel.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    _descLabel.transform = CGAffineTransformIdentity;
    [self addSubview:_descLabel];
    [self bringSubviewToFront:_descLabel];

    _downloadButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _downloadButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_downloadButton setTitle:@"تنزيل" forState:UIControlStateNormal];
    [_downloadButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _downloadButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    _downloadButton.backgroundColor = [UIColor colorWithWhite:1 alpha:0.26];
    _downloadButton.layer.cornerRadius = 21.0;
    if (@available(iOS 13.0, *)) _downloadButton.layer.cornerCurve = kCACornerCurveContinuous;
    _downloadButton.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
    _downloadButton.layer.borderWidth = 1.0;
    [_downloadButton addTarget:self action:@selector(openDownload) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_downloadButton];
    [self bringSubviewToFront:_downloadButton];

    [NSLayoutConstraint activateConstraints:@[
        [_iconView.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
        [_iconView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_iconView.widthAnchor constraintEqualToConstant:58],
        [_iconView.heightAnchor constraintEqualToConstant:58],

        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-18],
        [_titleLabel.bottomAnchor constraintEqualToAnchor:_descLabel.topAnchor constant:-2],
        [_titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_downloadButton.trailingAnchor constant:12],

        [_descLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-18],
        [_descLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12],
        [_descLabel.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor multiplier:0.62],

        [_downloadButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:18],
        [_downloadButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12],
        [_downloadButton.widthAnchor constraintEqualToConstant:96],
        [_downloadButton.heightAnchor constraintEqualToConstant:42],
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
    self.breezeLayer.frame = self.bounds;
    CGRect iconFrame = self.iconView.frame;
    self.iconShadowLayer.frame = iconFrame;
    self.iconShadowLayer.shadowPath =
        [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, iconFrame.size.width, iconFrame.size.height)
                                   cornerRadius:17.0].CGPath;
}

- (void)configure:(TRBBannerItem *)item {
    NSString *title = item.title ?: @"";
    NSString *desc = item.descText ?: @"";
    NSMutableParagraphStyle *titleStyle = [[NSMutableParagraphStyle alloc] init];
    titleStyle.alignment = NSTextAlignmentRight;
    titleStyle.baseWritingDirection = NSWritingDirectionRightToLeft;

    NSMutableParagraphStyle *descStyle = [[NSMutableParagraphStyle alloc] init];
    descStyle.alignment = NSTextAlignmentRight;
    descStyle.baseWritingDirection = NSWritingDirectionRightToLeft;

    self.titleLabel.attributedText =
        [[NSAttributedString alloc] initWithString:title attributes:@{
            NSParagraphStyleAttributeName: titleStyle
        }];

    self.descLabel.attributedText =
        [[NSAttributedString alloc] initWithString:desc attributes:@{
            NSParagraphStyleAttributeName: descStyle
        }];

    self.titleLabel.textAlignment = NSTextAlignmentRight;
    self.descLabel.textAlignment = NSTextAlignmentRight;
    self.titleLabel.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    self.descLabel.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    self.titleLabel.transform = CGAffineTransformIdentity;
    self.descLabel.transform = CGAffineTransformIdentity;
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
    self.accessibilityIdentifier = @"TRBBannerCarousel";
    self.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    self.transform = CGAffineTransformIdentity;

    _scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    _scroll.pagingEnabled = NO;
    _scroll.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    _scroll.transform = CGAffineTransformIdentity;
    _scroll.showsHorizontalScrollIndicator = NO;
    _scroll.delegate = self;
    _scroll.clipsToBounds = YES;
    _scroll.decelerationRate = UIScrollViewDecelerationRateFast;
    _scroll.directionalLockEnabled = YES;
    _scroll.alwaysBounceHorizontal = YES;
    [self addSubview:_scroll];

    _dots = [[UIPageControl alloc] initWithFrame:CGRectZero];
    _dots.hidden = YES;
    _dots.translatesAutoresizingMaskIntoConstraints = NO;
    _dots.hidesForSinglePage = YES;
    _dots.userInteractionEnabled = NO;
    _dots.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    if (@available(iOS 14.0, *)) {
        _dots.backgroundStyle = UIPageControlBackgroundStyleMinimal;
    }
    [self addSubview:_dots];

    [NSLayoutConstraint activateConstraints:@[
        [_scroll.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_scroll.heightAnchor constraintEqualToConstant:TRBContentHeight],

        [_dots.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_dots.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-2],
        [_dots.heightAnchor constraintEqualToConstant:18],
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

    for (UIView *v in [self.scroll.subviews copy]) {
        [v removeFromSuperview];
    }

    if (self.items.count == 0) {
        self.hidden = YES;
        return;
    }

    self.hidden = NO;
    CGFloat w = self.bounds.size.width > 100.0 ? self.bounds.size.width : 358.0;
    CGFloat step = w + TRBPageGap;

    self.scroll.contentSize = CGSizeMake(MAX(w, step * self.items.count - TRBPageGap), TRBContentHeight);
    self.dots.numberOfPages = self.items.count;
    self.dots.currentPage = 0;

    [self.items enumerateObjectsUsingBlock:^(TRBBannerItem *item, NSUInteger idx, BOOL *stop) {
        TRBBannerPage *page = [[TRBBannerPage alloc] initWithFrame:CGRectMake(step * idx, 0, w, TRBContentHeight)];
        page.tag = 0x54525000 + (NSInteger)idx;
        [page configure:item];
        [self.scroll addSubview:page];
    }];

    [self.timer invalidate];
    self.timer = nil;

    if (self.items.count > 1) {
        self.timer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(nextPage) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width > 100.0 ? self.bounds.size.width : 358.0;
    CGFloat step = w + TRBPageGap;
    self.scroll.frame = CGRectMake(0, 0, w, TRBContentHeight);

    for (NSUInteger idx = 0; idx < self.items.count; idx++) {
        UIView *page = [self.scroll viewWithTag:(0x54525000 + (NSInteger)idx)];
        if (page) page.frame = CGRectMake(step * idx, 0, w, TRBContentHeight);
    }

    self.scroll.contentSize = CGSizeMake(MAX(w, step * self.items.count - TRBPageGap), TRBContentHeight);
}

- (NSInteger)nearestPageForOffset:(CGFloat)x {
    if (self.items.count == 0) return 0;
    CGFloat w = MAX(self.bounds.size.width, 1.0);
    CGFloat step = w + TRBPageGap;
    NSInteger page = (NSInteger)llround(x / step);
    return MAX(0, MIN(page, (NSInteger)self.items.count - 1));
}

- (void)nextPage {
    if (self.items.count < 2 || self.scroll.isDragging || self.scroll.isDecelerating) return;
    CGFloat step = MAX(self.bounds.size.width, 1.0) + TRBPageGap;
    NSInteger next = (self.dots.currentPage + 1) % self.items.count;
    [self.scroll setContentOffset:CGPointMake(next * step, 0) animated:YES];
    self.dots.currentPage = next;
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView
                     withVelocity:(CGPoint)velocity
              targetContentOffset:(inout CGPoint *)targetContentOffset {
    NSInteger page = [self nearestPageForOffset:targetContentOffset->x];
    CGFloat step = MAX(self.bounds.size.width, 1.0) + TRBPageGap;
    targetContentOffset->x = page * step;
    self.dots.currentPage = page;
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    self.dots.currentPage = [self nearestPageForOffset:scrollView.contentOffset.x];
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    self.dots.currentPage = [self nearestPageForOffset:scrollView.contentOffset.x];
}

@end



// Forward declarations used by the strict Sources-only helpers below.
static BOOL TRBStringContains(NSString *haystack, NSString *needle);
static BOOL TRBIsSourcesPage(UIViewController *vc);
static char kTRBCarouselKey;
static char kTRBBackdropKey;

static BOOL TRBControllerIsActuallyVisible(UIViewController *vc) {
    if (!vc || !vc.isViewLoaded || !vc.view.window) return NO;
    if (vc.presentedViewController) return NO;

    if (vc.navigationController) {
        if (vc.navigationController.topViewController != vc) return NO;
        NSArray *navStack = vc.navigationController.viewControllers;
        if (navStack.count > 0 && navStack.firstObject != vc) return NO;
    }

    UITabBarController *tab = vc.tabBarController;
    if (tab) {
        UIViewController *selected = tab.selectedViewController;
        BOOL selectedContains = (selected == vc);
        if ([selected isKindOfClass:UINavigationController.class]) {
            UINavigationController *nav = (UINavigationController *)selected;
            selectedContains = (nav.topViewController == vc);
        }
        if (!selectedContains) return NO;
    }

    return YES;
}

static BOOL TRBIsStrictSourcesRoot(UIViewController *vc) {
    if (!vc || !vc.isViewLoaded || !vc.view.window) return NO;

    // Must still be the Sources tab/page according to the original proven detector.
    if (!TRBIsSourcesPage(vc)) return NO;

    // A presented controller means another page is visually on top.
    if (vc.presentedViewController) return NO;

    // If this controller is inside navigation, it must be the visible TOP controller
    // and also the ROOT controller. Any YouTube / Google / Instagram / Facebook /
    // TikTok page pushed on top will therefore hide the banner.
    if (vc.navigationController) {
        UINavigationController *nav = vc.navigationController;
        if (nav.topViewController != vc) return NO;

        if (nav.viewControllers.count > 0 &&
            nav.viewControllers.firstObject != vc) {
            return NO;
        }
    }

    // If standard UITabBarController is available, Sources must be selected.
    UITabBarController *tab = vc.tabBarController;
    if (tab) {
        UIViewController *selected = tab.selectedViewController;

        if ([selected isKindOfClass:UINavigationController.class]) {
            UINavigationController *nav = (UINavigationController *)selected;
            if (nav.topViewController != vc &&
                nav.viewControllers.firstObject != vc) {
                return NO;
            }
        } else if (selected != vc) {
            return NO;
        }
    }

    return YES;
}

static void TRBHideCarouselForController(UIViewController *vc) {
    TRBBannerCarousel *carousel = objc_getAssociatedObject(vc, &kTRBCarouselKey);
    UIView *backdrop = objc_getAssociatedObject(vc, &kTRBBackdropKey);

    if (carousel) {
        carousel.hidden = YES;
        [carousel.timer invalidate];
        carousel.timer = nil;
    }

    if (backdrop) {
        backdrop.hidden = YES;
    }
}

static void TRBRemoveDuplicateCarouselsInView(UIView *root, TRBBannerCarousel *keep) {
    if (!root) return;
    NSMutableArray<UIView *> *views = [NSMutableArray arrayWithObject:root];
    while (views.count) {
        UIView *v = views.lastObject;
        [views removeLastObject];
        for (UIView *sub in [v.subviews copy]) {
            if ([sub isKindOfClass:TRBBannerCarousel.class] && sub != keep) {
                TRBBannerCarousel *dup = (TRBBannerCarousel *)sub;
                [dup.timer invalidate];
                dup.timer = nil;
                [dup removeFromSuperview];
            } else {
                [views addObject:sub];
            }
        }
    }
}


static UIColor *TRBThemeBackgroundColor(void) {
    if (@available(iOS 13.0, *)) {
        return UIColor.systemBackgroundColor;
    }
    return UIColor.blackColor;
}

static UIView *TRBEnsureBackdrop(UIViewController *vc) {
    UIView *backdrop = objc_getAssociatedObject(vc, &kTRBBackdropKey);

    if (!backdrop || backdrop.superview != vc.view) {
        if (backdrop) [backdrop removeFromSuperview];

        backdrop = [[UIView alloc] initWithFrame:CGRectZero];
        backdrop.accessibilityIdentifier = @"TRBBannerBackdrop";
        backdrop.userInteractionEnabled = NO;
        backdrop.backgroundColor = TRBThemeBackgroundColor();
        backdrop.layer.zPosition = 9999998.0;

        [vc.view addSubview:backdrop];
        objc_setAssociatedObject(
            vc,
            &kTRBBackdropKey,
            backdrop,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }

    backdrop.backgroundColor = TRBThemeBackgroundColor();
    backdrop.frame = CGRectMake(0.0, 117.0, vc.view.bounds.size.width, 180.0);
    backdrop.layer.zPosition = 9999998.0;

    return backdrop;
}

static void TRBSetBannerVisibility(UIViewController *vc, BOOL visible) {
    TRBBannerCarousel *carousel = objc_getAssociatedObject(vc, &kTRBCarouselKey);
    UIView *backdrop = objc_getAssociatedObject(vc, &kTRBBackdropKey);

    if (carousel) carousel.hidden = !visible;
    if (backdrop) backdrop.hidden = !visible;
}

#pragma mark - Installation / page targeting


static char kTRBOriginalInsetKey;
static char kTRBTargetScrollKey;
static IMP TRBOriginalViewDidAppear = NULL;
static IMP TRBOriginalViewWillDisappear = NULL;
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
    if (!TRBIsStrictSourcesRoot(vc)) {
        TRBHideCarouselForController(vc);
        return;
    }

    UIView *backdrop = TRBEnsureBackdrop(vc);
    backdrop.hidden = NO;
    [vc.view bringSubviewToFront:backdrop];

    TRBBannerCarousel *existing = objc_getAssociatedObject(vc, &kTRBCarouselKey);
    TRBRemoveDuplicateCarouselsInView(vc.view, existing);

    if (existing && existing.superview == vc.view) {
        existing.frame = CGRectMake(16.0, 117.0, 358.0, 180.0);
        existing.layer.zPosition = 9999999.0;
        existing.hidden = NO;
        [vc.view bringSubviewToFront:backdrop];
        [vc.view bringSubviewToFront:existing];
        [existing loadRemoteData];
        return;
    }

    if (existing) {
        [existing.timer invalidate];
        existing.timer = nil;
        [existing removeFromSuperview];
        objc_setAssociatedObject(vc, &kTRBCarouselKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    TRBBannerCarousel *carousel = [[TRBBannerCarousel alloc] initWithFrame:CGRectMake(16.0, 117.0, 358.0, 180.0)];
    carousel.autoresizingMask = UIViewAutoresizingNone;
    carousel.hidden = YES;
    carousel.tag = 0x54524231;
    carousel.layer.zPosition = 9999999.0;

    [vc.view addSubview:carousel];
    [vc.view bringSubviewToFront:backdrop];
    [vc.view bringSubviewToFront:carousel];
    objc_setAssociatedObject(vc, &kTRBCarouselKey, carousel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    TRBRemoveDuplicateCarouselsInView(vc.view, carousel);
    [carousel loadRemoteData];
}

static void TRBPatchedViewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    ((void (*)(id, SEL, BOOL))TRBOriginalViewDidAppear)(self, _cmd, animated);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (TRBIsStrictSourcesRoot(self)) {
            TRBBannerCarousel *carousel = objc_getAssociatedObject(self, &kTRBCarouselKey);
            if (carousel) {
                carousel.hidden = NO;
            }
            TRBInstallBannerIntoController(self);
        } else {
            TRBHideCarouselForController(self);
        }
    });
}

static void TRBPatchedViewWillDisappear(UIViewController *self, SEL _cmd, BOOL animated) {
    TRBHideCarouselForController(self);
    if (TRBOriginalViewWillDisappear) {
        ((void (*)(id, SEL, BOOL))TRBOriginalViewWillDisappear)(self, _cmd, animated);
    }
}

static void TRBPatchedViewDidLayout(UIViewController *self, SEL _cmd) {
    if (TRBOriginalViewDidLayout) ((void (*)(id, SEL))TRBOriginalViewDidLayout)(self, _cmd);

    TRBBannerCarousel *carousel = objc_getAssociatedObject(self, &kTRBCarouselKey);
    UIView *backdrop = objc_getAssociatedObject(self, &kTRBBackdropKey);
    if (!TRBIsStrictSourcesRoot(self)) {
        if (carousel) carousel.hidden = YES;
        if (backdrop) backdrop.hidden = YES;
        return;
    }

    if (!carousel || carousel.superview != self.view) {
        TRBInstallBannerIntoController(self);
        return;
    }

    if (!backdrop || backdrop.superview != self.view) {
        backdrop = TRBEnsureBackdrop(self);
    }

    backdrop.frame = CGRectMake(0.0, 117.0, self.view.bounds.size.width, 180.0);
    backdrop.backgroundColor = TRBThemeBackgroundColor();
    backdrop.layer.zPosition = 9999998.0;
    backdrop.hidden = NO;

    carousel.frame = CGRectMake(16.0, 117.0, 358.0, 180.0);
    carousel.layer.zPosition = 9999999.0;
    carousel.hidden = NO;
    TRBRemoveDuplicateCarouselsInView(self.view, carousel);
    [self.view bringSubviewToFront:backdrop];
    [self.view bringSubviewToFront:carousel];
}

static void TRBInstallHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = UIViewController.class;
        Method appear = class_getInstanceMethod(cls, @selector(viewDidAppear:));
        Method disappear = class_getInstanceMethod(cls, @selector(viewWillDisappear:));
        Method layout = class_getInstanceMethod(cls, @selector(viewDidLayoutSubviews));
        if (!appear || !disappear || !layout) return;

        TRBOriginalViewDidAppear = method_getImplementation(appear);
        TRBOriginalViewWillDisappear = method_getImplementation(disappear);
        TRBOriginalViewDidLayout = method_getImplementation(layout);

        method_setImplementation(appear, (IMP)TRBPatchedViewDidAppear);
        method_setImplementation(disappear, (IMP)TRBPatchedViewWillDisappear);
        method_setImplementation(layout, (IMP)TRBPatchedViewDidLayout);
    });
}


static NSTimer *TRBVisibilityTimer = nil;

static UIViewController *TRBTopControllerFrom(UIViewController *vc) {
    if (!vc) return nil;

    if (vc.presentedViewController) {
        return TRBTopControllerFrom(vc.presentedViewController);
    }

    if ([vc isKindOfClass:UINavigationController.class]) {
        return TRBTopControllerFrom(((UINavigationController *)vc).topViewController);
    }

    if ([vc isKindOfClass:UITabBarController.class]) {
        return TRBTopControllerFrom(((UITabBarController *)vc).selectedViewController);
    }

    for (UIViewController *child in vc.childViewControllers.reverseObjectEnumerator) {
        if (child.isViewLoaded && child.view.window) {
            UIViewController *top = TRBTopControllerFrom(child);
            if (top) return top;
        }
    }

    return vc;
}

static void TRBReconcileVisibility(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;

        for (UIWindow *window in ws.windows) {
            if (!window.isKeyWindow || !window.rootViewController) continue;

            UIViewController *top = TRBTopControllerFrom(window.rootViewController);
            if (!top) continue;

            if (TRBIsStrictSourcesRoot(top)) {
                TRBInstallBannerIntoController(top);
            }
        }
    }
}

static void TRBStartVisibilityTimer(void) {
    if (TRBVisibilityTimer) return;

    TRBVisibilityTimer = [NSTimer scheduledTimerWithTimeInterval:0.6
                                                         repeats:YES
                                                           block:^(__unused NSTimer *timer) {
        TRBReconcileVisibility();
    }];
    [[NSRunLoop mainRunLoop] addTimer:TRBVisibilityTimer forMode:NSRunLoopCommonModes];
}

__attribute__((constructor))
static void TRBConstructor(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        TRBInstallHooks();
        TRBStartVisibilityTimer();
    });
}
