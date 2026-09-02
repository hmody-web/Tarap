#import <math.h>

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL TRBHNear(CGFloat a, CGFloat b) {
    return fabs(a - b) <= 1.5;
}

static BOOL TRBHTextContains(UIView *root, NSString *needle) {
    if (!root || needle.length == 0) return NO;

    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];

        NSString *text = nil;
        if ([v isKindOfClass:UILabel.class]) {
            text = ((UILabel *)v).text;
        } else if ([v isKindOfClass:UIButton.class]) {
            text = [((UIButton *)v) titleForState:UIControlStateNormal];
        }

        if (text.length && [text rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }

        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
    return NO;
}

static BOOL TRBHHasPageControlNearby(UIView *view) {
    UIView *p = view.superview;
    if (!p) return NO;

    for (UIView *s in p.subviews) {
        if ([s isKindOfClass:UIPageControl.class]) return YES;

        NSString *cn = NSStringFromClass(s.class);
        if ([cn containsString:@"PageControl"] || [cn containsString:@"PageIndicator"]) return YES;
    }
    return NO;
}

static BOOL TRBHLooksLikeOriginalBanner(UIView *view) {
    if (!view || view.window == nil) return NO;

    CGRect f = view.frame;
    CGRect b = view.bounds;

    BOOL exactSize =
        (TRBHNear(f.size.width, 358.0) && TRBHNear(f.size.height, 160.0)) ||
        (TRBHNear(b.size.width, 358.0) && TRBHNear(b.size.height, 160.0));

    if (!exactSize) return NO;

    // Strong markers from the original Tarab advertising banner.
    BOOL hasDownload = TRBHTextContains(view, @"تنزيل");
    BOOL hasPageControl = TRBHHasPageControlNearby(view);

    // Avoid touching unrelated 358x160 views: require banner-specific content.
    return hasDownload || hasPageControl;
}

static UIView *TRBHFindBannerAncestor(UIView *view) {
    UIView *v = view;
    for (NSInteger i = 0; v && i < 8; i++, v = v.superview) {
        if (TRBHLooksLikeOriginalBanner(v)) return v;
    }
    return nil;
}

static void TRBHForceHideView(UIView *view) {
    if (!view) return;
    view.hidden = YES;
    view.alpha = 0.0;
    view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

static void TRBHHideBannerAndAttachments(UIView *banner) {
    if (!banner) return;

    TRBHForceHideView(banner);

    UIView *parent = banner.superview;
    if (!parent) return;

    // Hide page dots / indicator directly associated with this banner.
    for (UIView *s in parent.subviews) {
        if (s == banner) continue;

        NSString *cn = NSStringFromClass(s.class);
        BOOL pageThing =
            [s isKindOfClass:UIPageControl.class] ||
            [cn containsString:@"PageControl"] ||
            [cn containsString:@"PageIndicator"];

        if (pageThing) {
            CGRect bf = [banner convertRect:banner.bounds toView:parent];
            CGRect sf = s.frame;
            CGFloat distance = CGRectGetMinY(sf) - CGRectGetMaxY(bf);
            if (distance > -20.0 && distance < 90.0) {
                TRBHForceHideView(s);
            }
        }
    }
}

static void TRBHScan(UIView *root) {
    if (!root) return;

    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];

        if (TRBHLooksLikeOriginalBanner(v)) {
            TRBHHideBannerAndAttachments(v);
            continue;
        }

        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
}

static void (*orig_setHidden)(UIView *, SEL, BOOL);
static void hook_setHidden(UIView *self, SEL _cmd, BOOL hidden) {
    UIView *banner = TRBHFindBannerAncestor(self);
    if (banner) {
        orig_setHidden(self, _cmd, YES);
        if (self == banner) {
            self.alpha = 0.0;
            self.userInteractionEnabled = NO;
        }
        return;
    }
    orig_setHidden(self, _cmd, hidden);
}

static void (*orig_setAlpha)(UIView *, SEL, CGFloat);
static void hook_setAlpha(UIView *self, SEL _cmd, CGFloat alpha) {
    UIView *banner = TRBHFindBannerAncestor(self);
    if (banner) {
        orig_setAlpha(self, _cmd, 0.0);
        return;
    }
    orig_setAlpha(self, _cmd, alpha);
}

static void (*orig_didMoveToWindow)(UIView *, SEL);
static void hook_didMoveToWindow(UIView *self, SEL _cmd) {
    orig_didMoveToWindow(self, _cmd);

    if (TRBHLooksLikeOriginalBanner(self)) {
        TRBHHideBannerAndAttachments(self);
    }
}

static void (*orig_layoutSubviews)(UIView *, SEL);
static void hook_layoutSubviews(UIView *self, SEL _cmd) {
    orig_layoutSubviews(self, _cmd);

    if (TRBHLooksLikeOriginalBanner(self)) {
        TRBHHideBannerAndAttachments(self);
    }
}

static void TRBHSwizzle(Class cls, SEL sel, IMP replacement, IMP *original) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    *original = method_getImplementation(m);
    method_setImplementation(m, replacement);
}

static void TRBHScanAllWindows(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!window.hidden) TRBHScan(window);
        }
    }
}

__attribute__((constructor))
static void TRBHInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        TRBHSwizzle(UIView.class, @selector(setHidden:), (IMP)hook_setHidden, (IMP *)&orig_setHidden);
        TRBHSwizzle(UIView.class, @selector(setAlpha:), (IMP)hook_setAlpha, (IMP *)&orig_setAlpha);
        TRBHSwizzle(UIView.class, @selector(didMoveToWindow), (IMP)hook_didMoveToWindow, (IMP *)&orig_didMoveToWindow);
        TRBHSwizzle(UIView.class, @selector(layoutSubviews), (IMP)hook_layoutSubviews, (IMP *)&orig_layoutSubviews);

        // Immediate scan + permanent watchdog. If the app recreates/re-shows it,
        // the banner is forced hidden again.
        TRBHScanAllWindows();

        [NSTimer scheduledTimerWithTimeInterval:0.15
                                         repeats:YES
                                           block:^(__unused NSTimer *timer) {
            TRBHScanAllWindows();
        }];
    });
}


#pragma mark - v1.3 SwiftUI original banner paging hider

static BOOL TRBIsOriginalBannerSize(CGRect r) {
    return fabs(r.size.width - 358.0) < 1.0 && fabs(r.size.height - 160.0) < 1.0;
}

static BOOL TRBIsSwiftUIPagingCell(UIView *view) {
    if (![view isKindOfClass:[UICollectionViewCell class]]) return NO;
    NSString *name = NSStringFromClass(view.class);
    return ([name containsString:@"UIKitPagingCell"] &&
            ([name containsString:@"SwiftUI"] || [name hasPrefix:@"_TtC7SwiftUI"]));
}

static UICollectionView *TRBOwningCollectionView(UIView *view) {
    UIView *p = view.superview;
    while (p) {
        if ([p isKindOfClass:[UICollectionView class]]) {
            return (UICollectionView *)p;
        }
        p = p.superview;
    }
    return nil;
}

static BOOL TRBCollectionContainsOriginalBannerPagingCell(UICollectionView *cv) {
    if (!cv) return NO;

    for (UIView *v in cv.subviews) {
        if (TRBIsSwiftUIPagingCell(v) && TRBIsOriginalBannerSize(v.bounds)) {
            return YES;
        }
    }

    for (UICollectionViewCell *cell in cv.visibleCells) {
        if (TRBIsSwiftUIPagingCell(cell) && TRBIsOriginalBannerSize(cell.bounds)) {
            return YES;
        }
    }
    return NO;
}

static void TRBForceHideOriginalBannerFromView(UIView *view) {
    if (!view) return;

    if (TRBIsSwiftUIPagingCell(view) && TRBIsOriginalBannerSize(view.bounds)) {
        UICollectionView *cv = TRBOwningCollectionView(view);
        if (cv) {
            cv.hidden = YES;
            cv.alpha = 0.0;
            cv.userInteractionEnabled = NO;

            UIView *p = cv.superview;
            if (p && TRBIsOriginalBannerSize(p.bounds)) {
                p.hidden = YES;
                p.alpha = 0.0;
                p.userInteractionEnabled = NO;
            }
        }

        view.hidden = YES;
        view.alpha = 0.0;
        view.userInteractionEnabled = NO;
        return;
    }

    if ([view isKindOfClass:[UICollectionView class]]) {
        UICollectionView *cv = (UICollectionView *)view;
        if (TRBCollectionContainsOriginalBannerPagingCell(cv)) {
            cv.hidden = YES;
            cv.alpha = 0.0;
            cv.userInteractionEnabled = NO;

            UIView *p = cv.superview;
            if (p && TRBIsOriginalBannerSize(p.bounds)) {
                p.hidden = YES;
                p.alpha = 0.0;
                p.userInteractionEnabled = NO;
            }
            return;
        }
    }
}

static IMP TRBOrigUIViewDidMoveToWindow_v13 = NULL;
static void TRBUIViewDidMoveToWindow_v13(UIView *self, SEL _cmd) {
    ((void(*)(id,SEL))TRBOrigUIViewDidMoveToWindow_v13)(self, _cmd);
    TRBForceHideOriginalBannerFromView(self);
}

static IMP TRBOrigUIViewLayoutSubviews_v13 = NULL;
static void TRBUIViewLayoutSubviews_v13(UIView *self, SEL _cmd) {
    ((void(*)(id,SEL))TRBOrigUIViewLayoutSubviews_v13)(self, _cmd);
    TRBForceHideOriginalBannerFromView(self);
}

static void TRBInstallPagingBannerHider_v13(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = UIView.class;

        Method m1 = class_getInstanceMethod(cls, @selector(didMoveToWindow));
        TRBOrigUIViewDidMoveToWindow_v13 = method_getImplementation(m1);
        method_setImplementation(m1, (IMP)TRBUIViewDidMoveToWindow_v13);

        Method m2 = class_getInstanceMethod(cls, @selector(layoutSubviews));
        TRBOrigUIViewLayoutSubviews_v13 = method_getImplementation(m2);
        method_setImplementation(m2, (IMP)TRBUIViewLayoutSubviews_v13);
    });
}

__attribute__((constructor))
static void TRBPagingBannerHiderEntry_v13(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        TRBInstallPagingBannerHider_v13();

        UIWindow *window = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) { window = w; break; }
            }
            if (window) break;
        }

        if (window) {
            NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:window];
            while (stack.count) {
                UIView *v = stack.lastObject;
                [stack removeLastObject];
                TRBForceHideOriginalBannerFromView(v);
                [stack addObjectsFromArray:v.subviews];
            }
        }
    });
}


#pragma mark - v1.4 Hide residual SwiftUI page dots

static char kTRBDotsCoverKey;

static UIColor *TRBDotsBackgroundColor(void) {
    if (@available(iOS 13.0, *)) {
        return UIColor.systemBackgroundColor;
    }
    return UIColor.blackColor;
}

static UIView *TRBEnsureDotsCover(UICollectionView *cv) {
    if (!cv || !cv.superview) return nil;

    UIView *host = cv.superview;
    UIView *cover = objc_getAssociatedObject(cv, &kTRBDotsCoverKey);

    if (!cover || cover.superview != host) {
        if (cover) [cover removeFromSuperview];

        cover = [[UIView alloc] initWithFrame:CGRectZero];
        cover.accessibilityIdentifier = @"TRBOriginalBannerDotsCover";
        cover.userInteractionEnabled = NO;
        cover.backgroundColor = TRBDotsBackgroundColor();
        cover.layer.zPosition = 100000.0;

        [host addSubview:cover];

        objc_setAssociatedObject(
            cv,
            &kTRBDotsCoverKey,
            cover,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }

    cover.backgroundColor = TRBDotsBackgroundColor();

    // The four SwiftUI indicators are drawn immediately below the
    // detected 358x160 paging collection. They do not expose a
    // selectable UIView in FLEX, so cover only their small strip.
    CGRect c = cv.frame;
    CGFloat y = CGRectGetMaxY(c) - 4.0;

    cover.frame = CGRectMake(
        0.0,
        y,
        host.bounds.size.width,
        46.0
    );

    cover.hidden = NO;
    cover.alpha = 1.0;

    [host bringSubviewToFront:cover];
    return cover;
}

static void TRBHidePagingCollectionAndDots_v14(UICollectionView *cv) {
    if (!cv) return;

    cv.hidden = YES;
    cv.alpha = 0.0;
    cv.userInteractionEnabled = NO;

    UIView *parent = cv.superview;
    if (parent && TRBIsOriginalBannerSize(parent.bounds)) {
        parent.hidden = YES;
        parent.alpha = 0.0;
        parent.userInteractionEnabled = NO;
    }

    TRBEnsureDotsCover(cv);
}

static void TRBRefreshDotsCoverFromView_v14(UIView *view) {
    if (!view) return;

    if (TRBIsSwiftUIPagingCell(view) &&
        TRBIsOriginalBannerSize(view.bounds)) {

        UICollectionView *cv = TRBOwningCollectionView(view);
        if (cv) {
            TRBHidePagingCollectionAndDots_v14(cv);
        }
        return;
    }

    if ([view isKindOfClass:UICollectionView.class]) {
        UICollectionView *cv = (UICollectionView *)view;

        if (TRBCollectionContainsOriginalBannerPagingCell(cv)) {
            TRBHidePagingCollectionAndDots_v14(cv);
        }
    }
}

__attribute__((constructor))
static void TRBDotsCoverEntry_v14(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // SwiftUI may redraw the indicators without creating a
        // separately selectable UIKit view, so keep the exact strip
        // covered while the target paging collection exists.
        [NSTimer scheduledTimerWithTimeInterval:0.10
                                         repeats:YES
                                           block:^(__unused NSTimer *timer) {

            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if (![scene isKindOfClass:UIWindowScene.class]) continue;

                for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                    if (window.hidden) continue;

                    NSMutableArray<UIView *> *stack =
                        [NSMutableArray arrayWithObject:window];

                    while (stack.count) {
                        UIView *v = stack.lastObject;
                        [stack removeLastObject];

                        TRBRefreshDotsCoverFromView_v14(v);

                        for (UIView *sub in v.subviews) {
                            [stack addObject:sub];
                        }
                    }
                }
            }
        }];
    });
}




static BOOL TRBTarabPlusSheetOpen_v22 = NO;
static __weak UIView *TRBPinnedHeader_v23 = nil;
static __weak UIView *TRBPinnedHeaderOriginalSuperview_v23 = nil;
static CGRect TRBPinnedHeaderOriginalFrame_v23;
static NSInteger TRBPinnedHeaderOriginalIndex_v23 = NSNotFound;

static void TRBPinHeaderBehindSheet_v23(UIView *header) {
    if (!header || TRBPinnedHeader_v23) return;

    UIWindow *window = header.window;
    UIView *superview = header.superview;
    if (!window || !superview) return;

    TRBPinnedHeader_v23 = header;
    TRBPinnedHeaderOriginalSuperview_v23 = superview;
    TRBPinnedHeaderOriginalFrame_v23 = header.frame;
    TRBPinnedHeaderOriginalIndex_v23 = [superview.subviews indexOfObject:header];

    CGRect windowFrame = [superview convertRect:header.frame toView:window];

    [header removeFromSuperview];
    [window addSubview:header];
    header.frame = windowFrame;

    header.hidden = NO;
    header.alpha = 1.0;
    header.layer.opacity = 1.0f;
    header.userInteractionEnabled = NO;

    // Keep it fixed at the top of the source screen.
    // The presented sheet is added above it by UIKit, so it won't travel inside the sheet.
}

static void TRBRestorePinnedHeader_v23(void) {
    UIView *header = TRBPinnedHeader_v23;
    UIView *superview = TRBPinnedHeaderOriginalSuperview_v23;
    if (!header || !superview) {
        TRBPinnedHeader_v23 = nil;
        TRBPinnedHeaderOriginalSuperview_v23 = nil;
        TRBPinnedHeaderOriginalIndex_v23 = NSNotFound;
        return;
    }

    [header removeFromSuperview];

    NSUInteger count = superview.subviews.count;
    if (TRBPinnedHeaderOriginalIndex_v23 != NSNotFound &&
        TRBPinnedHeaderOriginalIndex_v23 <= (NSInteger)count) {
        [superview insertSubview:header atIndex:(NSUInteger)MIN(TRBPinnedHeaderOriginalIndex_v23, (NSInteger)count)];
    } else {
        [superview addSubview:header];
    }

    header.frame = TRBPinnedHeaderOriginalFrame_v23;
    header.hidden = NO;
    header.alpha = 1.0;
    header.layer.opacity = 1.0f;
    header.userInteractionEnabled = YES;

    TRBPinnedHeader_v23 = nil;
    TRBPinnedHeaderOriginalSuperview_v23 = nil;
    TRBPinnedHeaderOriginalIndex_v23 = NSNotFound;
}


__attribute__((objc_runtime_name("TRBSourcesTopHeaderView")))
@interface TRBSourcesTopHeaderView : UIVisualEffectView
@property(nonatomic, weak) UIViewController *trbPresentingController;
@end

@interface TRBPlusSheetViewController : UIViewController
@property(nonatomic, strong) NSArray<UIView *> *trbAnimatedRows;
@end

static UIImage *TRBSourcesHeaderImage(void);

@implementation TRBPlusSheetViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    [self.view addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.distribution = UIStackViewDistributionFill;
    stack.spacing = 14.0;
    [scroll addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:22.0],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-22.0],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:24.0],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-28.0],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-44.0],
    ]];

    UIImageView *logo = [[UIImageView alloc] initWithImage:TRBSourcesHeaderImage()];
    logo.translatesAutoresizingMaskIntoConstraints = NO;
    logo.contentMode = UIViewContentModeScaleAspectFit;
    [logo.heightAnchor constraintEqualToConstant:74.0].active = YES;
    [stack addArrangedSubview:logo];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.text = @"طرب +";
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont systemFontOfSize:28.0 weight:UIFontWeightBold];
    title.textColor = UIColor.labelColor;
    [stack addArrangedSubview:title];

    UIView *spacer = [[UIView alloc] initWithFrame:CGRectZero];
    [spacer.heightAnchor constraintEqualToConstant:2.0].active = YES;
    [stack addArrangedSubview:spacer];

    NSArray<NSString *> *items = @[
        @"تصفح الملفات بسهولة وبطريقة امنة",
        @"لا يحتوي على اعلانات داخلية او خارجية",
        @"امكانية التنزيل من اليوتيوب وجميع الروابط",
        @"تم التأكد من اخر اصدار لطرب 5.11",
        @"تواصل معنا ان واجهت مشاكل في التطبيق"
    ];

    NSMutableArray<UIView *> *animated = [NSMutableArray array];

    for (NSString *text in items) {
        UIView *row = [[UIView alloc] initWithFrame:CGRectZero];
        row.translatesAutoresizingMaskIntoConstraints = NO;
        row.alpha = 0.0;
        row.transform = CGAffineTransformMakeTranslation(0.0, 16.0);

        UIImageSymbolConfiguration *symbolConfig =
            [UIImageSymbolConfiguration configurationWithPointSize:20.0 weight:UIImageSymbolWeightSemibold];
        UIImage *checkImage = [UIImage systemImageNamed:@"checkmark.circle.fill" withConfiguration:symbolConfig];
        UIImageView *check = [[UIImageView alloc] initWithImage:checkImage];
        check.translatesAutoresizingMaskIntoConstraints = NO;
        check.contentMode = UIViewContentModeScaleAspectFit;
        check.tintColor = self.view.tintColor;

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.text = text;
        label.numberOfLines = 0;
        label.textAlignment = NSTextAlignmentNatural;
        label.font = [UIFont systemFontOfSize:16.5 weight:UIFontWeightMedium];
        label.textColor = UIColor.labelColor;
        label.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;

        [row addSubview:check];
        [row addSubview:label];

        [NSLayoutConstraint activateConstraints:@[
            [check.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [check.topAnchor constraintGreaterThanOrEqualToAnchor:row.topAnchor constant:2.0],
            [check.widthAnchor constraintEqualToConstant:24.0],
            [check.heightAnchor constraintEqualToConstant:24.0],

            [label.trailingAnchor constraintEqualToAnchor:check.leadingAnchor constant:-10.0],
            [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
            [label.topAnchor constraintEqualToAnchor:row.topAnchor],
            [label.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
            [row.heightAnchor constraintGreaterThanOrEqualToConstant:34.0],
        ]];

        [stack addArrangedSubview:row];
        [animated addObject:row];
    }

    UIButton *contact = [UIButton buttonWithType:UIButtonTypeSystem];
    contact.translatesAutoresizingMaskIntoConstraints = NO;
    contact.accessibilityIdentifier = @"TRBDirectContactButton";

    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *configuration = [UIButtonConfiguration filledButtonConfiguration];
        configuration.title = @"التواصل المباشر";
        configuration.image = [UIImage systemImageNamed:@"paperplane.fill"];
        configuration.imagePadding = 8.0;
        configuration.cornerStyle = UIButtonConfigurationCornerStyleLarge;
        contact.configuration = configuration;
    } else {
        [contact setTitle:@"التواصل المباشر" forState:UIControlStateNormal];
    }

    [contact.heightAnchor constraintEqualToConstant:52.0].active = YES;
    [contact addTarget:self action:@selector(trbOpenTelegram:) forControlEvents:UIControlEventTouchUpInside];
    contact.alpha = 0.0;
    contact.transform = CGAffineTransformMakeTranslation(0.0, 16.0);
    [stack addArrangedSubview:contact];
    [animated addObject:contact];

    self.trbAnimatedRows = animated;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.trbAnimatedRows enumerateObjectsUsingBlock:^(UIView *view, NSUInteger idx, BOOL *stop) {
        [UIView animateWithDuration:0.42
                              delay:0.07 * idx
             usingSpringWithDamping:0.86
              initialSpringVelocity:0.25
                            options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            view.alpha = 1.0;
            view.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];
}


- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    TRBTarabPlusSheetOpen_v22 = NO;
}

- (void)trbOpenTelegram:(UIButton *)sender {
    NSURL *url = [NSURL URLWithString:@"https://t.me/Mooo5"];
    if (!url) return;
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

@end


static BOOL TRBHeaderInsidePlusSheet_v24(UIView *view) {
    UIResponder *r = view;
    while (r) {
        if ([NSStringFromClass(r.class) isEqualToString:@"TRBPlusSheetViewController"]) return YES;
        r = r.nextResponder;
    }
    return NO;
}

@implementation TRBSourcesTopHeaderView

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (TRBHeaderInsidePlusSheet_v24(self)) {
        [super setHidden:YES];
        [super setAlpha:0.0];
        self.userInteractionEnabled = NO;
        self.layer.opacity = 0.0f;
    }
}
- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    if (TRBHeaderInsidePlusSheet_v24(self)) {
        [super setHidden:YES];
        [super setAlpha:0.0];
        self.userInteractionEnabled = NO;
        self.layer.opacity = 0.0f;
    }
}
- (void)setHidden:(BOOL)hidden {
    [super setHidden:TRBHeaderInsidePlusSheet_v24(self) ? YES : hidden];
}
- (void)setAlpha:(CGFloat)alpha {
    [super setAlpha:TRBHeaderInsidePlusSheet_v24(self) ? 0.0 : alpha];
}


- (void)trbHandleTap:(UITapGestureRecognizer *)tap {
    if (tap.state != UIGestureRecognizerStateEnded) return;

    UIViewController *presenter = self.trbPresentingController;
    if (!presenter || presenter.presentedViewController) return;

    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];

    TRBPlusSheetViewController *sheetVC = [[TRBPlusSheetViewController alloc] init];
    sheetVC.modalPresentationStyle = UIModalPresentationPageSheet;

    if (@available(iOS 16.0, *)) {
        UISheetPresentationController *sheet = sheetVC.sheetPresentationController;
        UISheetPresentationControllerDetentIdentifier initialID = @"TRBPlusInitialPlus20";
        UISheetPresentationControllerDetent *initialDetent =
            [UISheetPresentationControllerDetent customDetentWithIdentifier:initialID
                                                                   resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
                CGFloat target = (context.maximumDetentValue * 0.5) + 20.0;
                return MIN(target, context.maximumDetentValue - 40.0);
            }];
        sheet.detents = @[
            initialDetent,
            [UISheetPresentationControllerDetent largeDetent]
        ];
        sheet.selectedDetentIdentifier = initialID;
        sheet.prefersGrabberVisible = YES;
        sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
    } else if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = sheetVC.sheetPresentationController;
        sheet.detents = @[
            [UISheetPresentationControllerDetent mediumDetent],
            [UISheetPresentationControllerDetent largeDetent]
        ];
        sheet.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
        sheet.prefersGrabberVisible = YES;
        sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
    }

    // Keep the Sources header in its original page hierarchy.
    // At the initial detent it remains visible in the uncovered area.
    // When the sheet expands to Large, UIKit naturally covers it.
    TRBTarabPlusSheetOpen_v22 = YES;

    [presenter presentViewController:sheetVC animated:YES completion:nil];
}

@end

__attribute__((objc_runtime_name("TRBSourcesTopHeaderImageView")))
@interface TRBSourcesTopHeaderImageView : UIImageView
@end
@implementation TRBSourcesTopHeaderImageView
@end

#pragma mark - Sources-only top header

static char kTRBSourcesHeaderKey;
static char kTRBSourcesHeaderImageKey;
static char kTRBPageHeaderKey;
static char kTRBPageHeaderImageKey;
static char kTRBGlobalGlassHeaderKey;
static char kTRBGlobalGlassImageKey;
static char kTRBPageBoundHeaderKey;
static char kTRBPageBoundHeaderImageKey;

static BOOL TRBTextLooksLikeSourcesRoot(UIView *root) {
    if (!root) return NO;
    __block BOOL foundGoogle = NO;
    __block BOOL foundInstagram = NO;
    __block BOOL foundTikTok = NO;

    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];

        NSString *text = nil;
        if ([v isKindOfClass:UILabel.class]) {
            text = ((UILabel *)v).text;
        } else if ([v isKindOfClass:UIButton.class]) {
            text = [((UIButton *)v) titleForState:UIControlStateNormal];
        }

        if (text.length) {
            if ([text containsString:@"جوجل"] || [text localizedCaseInsensitiveContainsString:@"Google"]) foundGoogle = YES;
            if ([text containsString:@"انستجرام"] || [text containsString:@"انستغرام"] || [text localizedCaseInsensitiveContainsString:@"Instagram"]) foundInstagram = YES;
            if ([text containsString:@"تيك توك"] || [text localizedCaseInsensitiveContainsString:@"TikTok"]) foundTikTok = YES;
        }

        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
    return foundGoogle && foundInstagram && foundTikTok;
}

static UIImage *TRBSourcesHeaderImage(void) {
    static UIImage *image = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        NSString *path = nil;

        // The build script copies the original JPEG directly into
        // TarabBannerHider.framework.
        for (NSBundle *bundle in NSBundle.allFrameworks) {
            NSString *bundlePath = bundle.bundlePath ?: @"";
            if ([bundlePath containsString:@"TarabBannerHider.framework"]) {
                path = [bundle pathForResource:@"TarabSourcesHeader" ofType:@"png"];
                if (!path) {
                    path = [bundle.bundlePath stringByAppendingPathComponent:@"TarabSourcesHeader.png"];
                }
                if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                    break;
                }
                path = nil;
            }
        }

        if (path.length) {
            image = [UIImage imageWithContentsOfFile:path];
        }
    });

    return image;
}


static void TRBCreateSourcesHeaderImmediatelyForWindow(UIWindow *window) {
    if (!window) return;

    UIView *header = objc_getAssociatedObject(window, &kTRBSourcesHeaderKey);
    if (!header) {
        header = [[TRBSourcesTopHeaderView alloc] initWithFrame:CGRectZero];
        header.accessibilityIdentifier = @"TRBSourcesTopHeader";
        header.userInteractionEnabled = NO;
        header.clipsToBounds = YES;
        header.hidden = YES;
        header.alpha = 0.0;
        header.backgroundColor = UIColor.systemBackgroundColor;
        header.layer.zPosition = 999999.0;

        TRBSourcesTopHeaderImageView *iv =
            [[TRBSourcesTopHeaderImageView alloc] initWithFrame:CGRectZero];

        iv.accessibilityIdentifier = @"TRBSourcesTopHeaderImage";
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.clipsToBounds = YES;
        iv.userInteractionEnabled = NO;
        iv.image = TRBSourcesHeaderImage();

        [header addSubview:iv];
        [window addSubview:header];

        objc_setAssociatedObject(
            window,
            &kTRBSourcesHeaderKey,
            header,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );

        objc_setAssociatedObject(
            window,
            &kTRBSourcesHeaderImageKey,
            iv,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );

        NSLog(@"[TarabBannerHider] CREATED TRBSourcesTopHeaderView immediately");
    }

    UIImageView *iv = objc_getAssociatedObject(window, &kTRBSourcesHeaderImageKey);

    CGFloat top = window.safeAreaInsets.top;
    CGFloat height = MAX(104.0, top + 76.0);

    header.frame = CGRectMake(
        0.0,
        0.0,
        window.bounds.size.width,
        height
    );

    if (iv) {
        CGFloat imageTop = top + 5.0;
        CGFloat imageHeight = MAX(58.0, height - imageTop - 5.0);
        CGFloat imageWidth = MIN(window.bounds.size.width - 32.0, 300.0);

        iv.frame = CGRectMake(
            (window.bounds.size.width - imageWidth) / 2.0,
            imageTop,
            imageWidth,
            imageHeight
        );

        if (!iv.image) {
            iv.image = TRBSourcesHeaderImage();
        }
    }
}

static void TRBCreateSourcesHeaderImmediately(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;

        UIWindowScene *ws = (UIWindowScene *)scene;
        for (UIWindow *window in ws.windows) {
            TRBCreateSourcesHeaderImmediatelyForWindow(window);
        }
    }
}

static UIView *TRBEnsureSourcesHeader(UIWindow *window) {
    if (!window) return nil;

    TRBCreateSourcesHeaderImmediatelyForWindow(window);

    UIView *header = objc_getAssociatedObject(window, &kTRBSourcesHeaderKey);
    UIImageView *iv = objc_getAssociatedObject(window, &kTRBSourcesHeaderImageKey);

    if (!header) return nil;

    header.backgroundColor = UIColor.systemBackgroundColor;

    CGFloat top = window.safeAreaInsets.top;
    CGFloat height = MAX(104.0, top + 76.0);

    header.frame = CGRectMake(
        0.0,
        0.0,
        window.bounds.size.width,
        height
    );

    if (iv) {
        CGFloat imageTop = top + 5.0;
        CGFloat imageHeight = MAX(58.0, height - imageTop - 5.0);
        CGFloat imageWidth = MIN(window.bounds.size.width - 32.0, 300.0);

        iv.frame = CGRectMake(
            (window.bounds.size.width - imageWidth) / 2.0,
            imageTop,
            imageWidth,
            imageHeight
        );

        if (!iv.image) {
            iv.image = TRBSourcesHeaderImage();
        }
    }

    return header;
}


static UIViewController *TRBVisibleControllerFrom(UIViewController *vc) {
    if (!vc) return nil;

    if (vc.presentedViewController) {
        return TRBVisibleControllerFrom(vc.presentedViewController);
    }

    if ([vc isKindOfClass:UITabBarController.class]) {
        return TRBVisibleControllerFrom(((UITabBarController *)vc).selectedViewController);
    }

    if ([vc isKindOfClass:UINavigationController.class]) {
        return TRBVisibleControllerFrom(((UINavigationController *)vc).visibleViewController);
    }

    for (UIViewController *child in vc.childViewControllers.reverseObjectEnumerator) {
        if (child.isViewLoaded && child.view.window && !child.view.hidden && child.view.alpha > 0.05) {
            UIViewController *visible = TRBVisibleControllerFrom(child);
            if (visible) return visible;
        }
    }

    return vc;
}

static BOOL TRBViewContainsSourcesMarkers(UIView *root) {
    if (!root) return NO;

    BOOL youtube = NO;
    BOOL google = NO;
    BOOL instagram = NO;
    BOOL tiktok = NO;

    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];

    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];

        if (v.hidden || v.alpha < 0.05) continue;

        NSString *text = nil;
        if ([v isKindOfClass:UILabel.class]) {
            text = ((UILabel *)v).text;
        } else if ([v isKindOfClass:UIButton.class]) {
            text = [((UIButton *)v) titleForState:UIControlStateNormal];
        }

        if (text.length) {
            if ([text containsString:@"يوتيوب"] || [text localizedCaseInsensitiveContainsString:@"YouTube"]) youtube = YES;
            if ([text containsString:@"جوجل"] || [text localizedCaseInsensitiveContainsString:@"Google"]) google = YES;
            if ([text containsString:@"انستجرام"] || [text containsString:@"انستغرام"] || [text localizedCaseInsensitiveContainsString:@"Instagram"]) instagram = YES;
            if ([text containsString:@"تيك توك"] || [text localizedCaseInsensitiveContainsString:@"TikTok"]) tiktok = YES;
        }

        for (UIView *sub in v.subviews) {
            [stack addObject:sub];
        }
    }

    // Main Sources page should expose at least two source buttons simultaneously.
    NSInteger count = (youtube ? 1 : 0) + (google ? 1 : 0) + (instagram ? 1 : 0) + (tiktok ? 1 : 0);
    return count >= 2;
}


static BOOL TRBIsFrontmostVisibleView(UIView *view) {
    if (!view || !view.window || view.hidden || view.alpha < 0.05) return NO;

    CGRect r = [view convertRect:view.bounds toView:view.window];
    if (!CGRectIntersectsRect(r, view.window.bounds)) return NO;

    CGPoint p = CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r));
    UIView *hit = [view.window hitTest:p withEvent:nil];

    if (!hit) return NO;
    if (hit == view || [hit isDescendantOfView:view]) return YES;

    // Labels themselves may be non-interactive; accept a short visible ancestor chain.
    UIView *a = view.superview;
    for (NSUInteger i = 0; a && i < 4; i++, a = a.superview) {
        if (hit == a || [hit isDescendantOfView:a]) return YES;
    }

    return NO;
}

static UIViewController *TRBTopVisibleController(UIViewController *vc) {
    if (!vc) return nil;

    if (vc.presentedViewController) {
        return TRBTopVisibleController(vc.presentedViewController);
    }

    if ([vc isKindOfClass:UITabBarController.class]) {
        UITabBarController *tab = (UITabBarController *)vc;
        return TRBTopVisibleController(tab.selectedViewController);
    }

    if ([vc isKindOfClass:UINavigationController.class]) {
        UINavigationController *nav = (UINavigationController *)vc;
        return TRBTopVisibleController(nav.visibleViewController);
    }

    return vc;
}

static UITabBarController *TRBFindTabController(UIViewController *vc) {
    if (!vc) return nil;

    if ([vc isKindOfClass:UITabBarController.class]) {
        return (UITabBarController *)vc;
    }

    for (UIViewController *child in vc.childViewControllers) {
        UITabBarController *found = TRBFindTabController(child);
        if (found) return found;
    }

    return nil;
}

static BOOL TRBTitleMeansSources(NSString *title) {
    if (title.length == 0) return NO;

    return [title containsString:@"المصادر"] ||
           [title localizedCaseInsensitiveContainsString:@"Sources"];
}

static BOOL TRBWindowShowsSourcesHomeFrontmost(UIWindow *window) {
    if (!window || window.hidden || window.alpha < 0.05) return NO;
    if (!window.rootViewController) return NO;

    UITabBarController *tab = TRBFindTabController(window.rootViewController);

    if (tab) {
        UIViewController *selected = tab.selectedViewController;
        if (!selected) return NO;

        NSString *selectedTitle = selected.tabBarItem.title ?: selected.title ?: @"";
        BOOL sourcesTab = TRBTitleMeansSources(selectedTitle);

        // Some apps keep the visible page wrapped in UINavigationController.
        if ([selected isKindOfClass:UINavigationController.class]) {
            UINavigationController *nav = (UINavigationController *)selected;

            NSString *navTitle = nav.tabBarItem.title ?: nav.title ?: @"";
            if (TRBTitleMeansSources(navTitle)) {
                sourcesTab = YES;
            }

            // The header is ONLY for the Sources root.
            // Any pushed page such as YouTube/Google/etc. must hide it.
            if (sourcesTab) {
                if (nav.viewControllers.count != 1) return NO;
                if (nav.topViewController != nav.viewControllers.firstObject) return NO;
            }
        }

        if (sourcesTab) {
            UIViewController *top = TRBTopVisibleController(selected);
            if (!top || top.presentedViewController) return NO;
            return YES;
        }
    }

    // Fallback for a custom tab system:
    // only trust the actually visible controller's OWN title, not a parent's title.
    UIViewController *top = TRBTopVisibleController(window.rootViewController);
    if (!top) return NO;

    NSString *title = top.title ?: @"";
    NSString *tabTitle = top.tabBarItem.title ?: @"";

    if (!TRBTitleMeansSources(title) && !TRBTitleMeansSources(tabTitle)) {
        return NO;
    }

    if (top.navigationController) {
        UINavigationController *nav = top.navigationController;
        if (nav.viewControllers.count != 1) return NO;
        if (nav.topViewController != top) return NO;
    }

    return YES;
}

static TRBSourcesTopHeaderView *TRBCreateGlobalGlassHeader(UIWindow *window) {
    if (!window) return nil;

    TRBSourcesTopHeaderView *header =
        objc_getAssociatedObject(window, &kTRBGlobalGlassHeaderKey);

    TRBSourcesTopHeaderImageView *iv =
        objc_getAssociatedObject(window, &kTRBGlobalGlassImageKey);

    if (!header) {
        UIBlurEffect *blur =
            [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];

        header =
            [[TRBSourcesTopHeaderView alloc] initWithEffect:blur];

        header.accessibilityIdentifier = @"TRBSourcesTopHeaderView";
        header.userInteractionEnabled = NO;
        header.clipsToBounds = YES;
        header.layer.cornerRadius = 26.0;
        header.layer.cornerCurve = kCACornerCurveContinuous;
        header.layer.borderWidth = 0.5;
        header.layer.borderColor =
            [UIColor.separatorColor colorWithAlphaComponent:0.25].CGColor;
        header.layer.zPosition = 99999999.0;

        iv = [[TRBSourcesTopHeaderImageView alloc] initWithFrame:CGRectZero];
        iv.accessibilityIdentifier = @"TRBSourcesTopHeaderImageView";
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.userInteractionEnabled = NO;
        iv.image = TRBSourcesHeaderImage();

        [header.contentView addSubview:iv];
        [window addSubview:header];

        objc_setAssociatedObject(
            window,
            &kTRBGlobalGlassHeaderKey,
            header,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );

        objc_setAssociatedObject(
            window,
            &kTRBGlobalGlassImageKey,
            iv,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );

        NSLog(@"[TarabBannerHider] TRBSourcesTopHeaderView CREATED");
    }

    CGFloat side = 12.0;
    CGFloat safeTop = window.safeAreaInsets.top;
    CGFloat y = MAX(4.0, safeTop + 4.0);
    CGFloat width = MAX(0.0, window.bounds.size.width - 24.0);
    CGFloat height = 82.0;

    header.frame = CGRectMake(side, y, width, height);
    header.layer.cornerRadius = 26.0;
    header.layer.cornerCurve = kCACornerCurveContinuous;
    header.layer.zPosition = 99999999.0;

    if (iv) {
        CGFloat iw = MIN(width - 48.0, 242.0);
        CGFloat ih = 58.0;
        iv.frame = CGRectMake(
            (width - iw) / 2.0,
            (height - ih) / 2.0,
            iw,
            ih
        );

        if (!iv.image) {
            iv.image = TRBSourcesHeaderImage();
        }
    }

    return header;
}


static UIViewController *TRBVisiblePageController(UIViewController *vc) {
    if (!vc) return nil;

    if (vc.presentedViewController) {
        return TRBVisiblePageController(vc.presentedViewController);
    }

    if ([vc isKindOfClass:UITabBarController.class]) {
        return TRBVisiblePageController(((UITabBarController *)vc).selectedViewController);
    }

    if ([vc isKindOfClass:UINavigationController.class]) {
        return TRBVisiblePageController(((UINavigationController *)vc).visibleViewController);
    }

    for (UIViewController *child in vc.childViewControllers.reverseObjectEnumerator) {
        if (child.isViewLoaded &&
            child.view.window &&
            !child.view.hidden &&
            child.view.alpha > 0.05) {
            UIViewController *visible = TRBVisiblePageController(child);
            if (visible) return visible;
        }
    }

    return vc;
}

static TRBSourcesTopHeaderView *TRBEnsurePageBoundHeader(UIViewController *vc) {
    if (!vc || !vc.isViewLoaded) return nil;

    TRBSourcesTopHeaderView *header =
        objc_getAssociatedObject(vc, &kTRBPageBoundHeaderKey);

    TRBSourcesTopHeaderImageView *iv =
        objc_getAssociatedObject(vc, &kTRBPageBoundHeaderImageKey);

    if (!header) {
        UIVisualEffect *nativeEffect = nil;

        if (@available(iOS 26.0, *)) {
            UIGlassEffect *glass = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
            glass.interactive = YES;
            nativeEffect = glass;
        } else {
            nativeEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
        }

        header = [[TRBSourcesTopHeaderView alloc] initWithEffect:nativeEffect];
        header.accessibilityIdentifier = @"TRBSourcesTopHeaderView";
        header.userInteractionEnabled = YES;
        header.clipsToBounds = YES;
        header.layer.cornerRadius = 26.0;
        header.layer.cornerCurve = kCACornerCurveContinuous;
        header.layer.zPosition = 99999999.0;

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:header action:@selector(trbHandleTap:)];
        tap.cancelsTouchesInView = YES;
        [header addGestureRecognizer:tap];

        iv = [[TRBSourcesTopHeaderImageView alloc] initWithFrame:CGRectZero];
        iv.accessibilityIdentifier = @"TRBSourcesTopHeaderImageView";
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.userInteractionEnabled = NO;
        iv.image = TRBSourcesHeaderImage();

        [header.contentView addSubview:iv];
        [vc.view addSubview:header];

        objc_setAssociatedObject(
            vc,
            &kTRBPageBoundHeaderKey,
            header,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );

        objc_setAssociatedObject(
            vc,
            &kTRBPageBoundHeaderImageKey,
            iv,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }

    CGFloat side = 12.0;
    CGFloat y = 192.0;
    CGFloat width = MAX(0.0, vc.view.bounds.size.width - 24.0);
    CGFloat height = 70.0;

    header.frame = CGRectMake(side, y, width, height);
    header.layer.cornerRadius = 26.0;
    header.layer.cornerCurve = kCACornerCurveContinuous;
    header.layer.zPosition = 99999999.0;

    if (iv) {
        CGFloat iw = MIN(width - 48.0, 242.0);
        CGFloat ih = 58.0;

        iv.frame = CGRectMake(
            (width - iw) / 2.0,
            (height - ih) / 2.0,
            iw,
            ih
        );

        if (!iv.image) iv.image = TRBSourcesHeaderImage();
    }

    header.trbPresentingController = vc;

    if (TRBTarabPlusSheetOpen_v22) {
        // The real header is temporarily pinned to UIWindow.
        // Do not hide, recreate, or move it while the sheet is active.
        if (TRBPinnedHeader_v23) {
            TRBPinnedHeader_v23.hidden = NO;
            TRBPinnedHeader_v23.alpha = 1.0;
            TRBPinnedHeader_v23.layer.opacity = 1.0f;
        }
    } else {
        header.transform = CGAffineTransformIdentity;
        header.layer.opacity = 1.0f;
        header.hidden = NO;
        header.alpha = 1.0;
        header.userInteractionEnabled = YES;
        [vc.view bringSubviewToFront:header];
    }

    return header;
}

static void TRBRefreshGlobalGlassHeader(UIWindow *window) {
    if (!window || !window.rootViewController) return;

    // Never create/move a Sources header into TRBPlusSheetViewController.
    // The original Sources header stays underneath the native sheet.
    if (TRBTarabPlusSheetOpen_v22) return;

    // Keep the old window-level header disabled permanently.
    TRBSourcesTopHeaderView *globalHeader =
        objc_getAssociatedObject(window, &kTRBGlobalGlassHeaderKey);

    if (globalHeader) {
        globalHeader.hidden = YES;
        globalHeader.alpha = 0.0;
    }

    UIViewController *visible =
        TRBVisiblePageController(window.rootViewController);

    if (!visible) return;

    BOOL sourcesRoot = TRBWindowShowsSourcesHomeFrontmost(window);

    if (sourcesRoot) {
        // Attach to the actual Sources page view.
        // Therefore it participates in the exact same push/pop/tab transition
        // and never disappears independently before the page itself.
        TRBSourcesTopHeaderView *header =
            TRBEnsurePageBoundHeader(visible);

        if (header) {
            header.layer.zPosition = 99999999.0;

            if (TRBTarabPlusSheetOpen_v22) {
                // Header is pinned behind the sheet; leave its hierarchy and position untouched.
                if (TRBPinnedHeader_v23) {
                    TRBPinnedHeader_v23.hidden = NO;
                    TRBPinnedHeader_v23.alpha = 1.0;
                    TRBPinnedHeader_v23.layer.opacity = 1.0f;
                }
            } else {
                header.layer.opacity = 1.0f;
                header.hidden = NO;
                header.alpha = 1.0;
                header.userInteractionEnabled = YES;
                [visible.view bringSubviewToFront:header];
            }
        }
    }

    // IMPORTANT:
    // Do not hide the page-bound Sources header when another page becomes visible.
    // It remains attached to the Sources view underneath the pushed/tabbed page,
    // so the transition itself naturally carries/covers it.
}

static BOOL TRBControllerIsSourcesPage(UIViewController *vc) {
    if (!vc || !vc.isViewLoaded || !vc.view.window) return NO;

    // IMPORTANT:
    // Do not inherit "Sources" from a parent/tab controller.
    // Child pages like YouTube/Google/Instagram must fail this test.
    if (vc.presentedViewController) return NO;

    if (vc.navigationController &&
        vc.navigationController.visibleViewController != vc) {
        return NO;
    }

    // The Sources HOME page visibly contains several source choices together.
    // Child pages do not contain this group.
    BOOL youtube = NO;
    BOOL google = NO;
    BOOL instagram = NO;
    BOOL tiktok = NO;
    BOOL trends = NO;

    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:vc.view];

    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];

        if (v.hidden || v.alpha < 0.05) continue;

        NSString *text = nil;
        if ([v isKindOfClass:UILabel.class]) {
            text = ((UILabel *)v).text;
        } else if ([v isKindOfClass:UIButton.class]) {
            text = [((UIButton *)v) titleForState:UIControlStateNormal];
        }

        if (text.length) {
            if ([text containsString:@"يوتيوب"] ||
                [text localizedCaseInsensitiveContainsString:@"YouTube"]) youtube = YES;

            if ([text containsString:@"جوجل"] ||
                [text localizedCaseInsensitiveContainsString:@"Google"]) google = YES;

            if ([text containsString:@"انستجرام"] ||
                [text containsString:@"انستغرام"] ||
                [text localizedCaseInsensitiveContainsString:@"Instagram"]) instagram = YES;

            if ([text containsString:@"تيك توك"] ||
                [text localizedCaseInsensitiveContainsString:@"TikTok"]) tiktok = YES;

            if ([text containsString:@"ترندات"] ||
                [text localizedCaseInsensitiveContainsString:@"Trending"]) trends = YES;
        }

        for (UIView *sub in v.subviews) {
            [stack addObject:sub];
        }
    }

    NSInteger markers =
        (youtube ? 1 : 0) +
        (google ? 1 : 0) +
        (instagram ? 1 : 0) +
        (tiktok ? 1 : 0) +
        (trends ? 1 : 0);

    return markers >= 3;
}

static UIView *TRBEnsurePageHeader(UIViewController *vc) {
    if (!vc || !vc.isViewLoaded) return nil;

    UIView *header = objc_getAssociatedObject(vc, &kTRBPageHeaderKey);
    UIImageView *iv = objc_getAssociatedObject(vc, &kTRBPageHeaderImageKey);

    if (!header) {
        // Real system material glass.
        UIBlurEffect *blur =
            [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];

        UIVisualEffectView *glass =
            [[UIVisualEffectView alloc] initWithEffect:blur];

        header = glass;
        header.accessibilityIdentifier = @"TRBSourcesTopHeaderView";
        header.userInteractionEnabled = NO;
        header.clipsToBounds = YES;
        header.layer.cornerRadius = 26.0;
        header.layer.cornerCurve = kCACornerCurveContinuous;
        header.layer.zPosition = 99999999.0;

        // Very subtle border, system-derived.
        header.layer.borderWidth = 0.5;
        header.layer.borderColor =
            [UIColor.separatorColor colorWithAlphaComponent:0.28].CGColor;

        iv = [[TRBSourcesTopHeaderImageView alloc] initWithFrame:CGRectZero];
        iv.accessibilityIdentifier = @"TRBSourcesTopHeaderImageView";
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.userInteractionEnabled = NO;
        iv.clipsToBounds = NO;
        iv.image = TRBSourcesHeaderImage();
        iv.layer.zPosition = 2.0;

        [glass.contentView addSubview:iv];
        [vc.view addSubview:header];

        objc_setAssociatedObject(
            vc,
            &kTRBPageHeaderKey,
            header,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );

        objc_setAssociatedObject(
            vc,
            &kTRBPageHeaderImageKey,
            iv,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }

    // Safe horizontal spacing; glass spans almost all screen width.
    CGFloat side = 12.0;
    CGFloat top = vc.view.safeAreaInsets.top + 4.0;
    CGFloat width = MAX(0.0, vc.view.bounds.size.width - (side * 2.0));
    CGFloat height = 82.0;

    header.frame = CGRectMake(
        side,
        top,
        width,
        height
    );

    header.layer.cornerRadius = 26.0;
    header.layer.cornerCurve = kCACornerCurveContinuous;
    header.layer.zPosition = 99999999.0;

    if (iv) {
        // Slightly smaller image, centered with transparent breathing room.
        CGFloat imageWidth = MIN(width - 44.0, 250.0);
        CGFloat imageHeight = 62.0;

        iv.frame = CGRectMake(
            (width - imageWidth) / 2.0,
            (height - imageHeight) / 2.0,
            imageWidth,
            imageHeight
        );

        if (!iv.image) {
            iv.image = TRBSourcesHeaderImage();
        }
    }

    header.hidden = NO;
    header.alpha = 1.0;
    [vc.view bringSubviewToFront:header];

    return header;
}

static void TRBRefreshPageHeader(UIWindow *window) {
    if (!window || !window.rootViewController) return;

    UIViewController *visible = TRBVisibleControllerFrom(window.rootViewController);
    if (!visible) return;

    BOOL isSources = TRBControllerIsSourcesPage(visible);

    // Hide any legacy window-level header; use only the page-local header now.
    UIView *legacy = objc_getAssociatedObject(window, &kTRBSourcesHeaderKey);
    if (legacy) {
        legacy.hidden = YES;
        legacy.alpha = 0.0;
    }

    if (isSources) {
        UIView *header = TRBEnsurePageHeader(visible);
        header.hidden = NO;
        header.alpha = 1.0;
        header.layer.zPosition = 99999999.0;
        [visible.view bringSubviewToFront:header];
    } else {
        UIView *header = objc_getAssociatedObject(visible, &kTRBPageHeaderKey);
        if (header) {
            header.hidden = YES;
            header.alpha = 0.0;
        }
    }
}

static BOOL TRBWindowIsShowingSourcesRoot(UIWindow *window) {
    if (!window || window.hidden || window.alpha <= 0.01) return NO;

    UIViewController *root = window.rootViewController;
    if (!root) return NO;

    // Require the actual Sources-root content to be visible. If a source detail
    // page is pushed/presented, its visible hierarchy will no longer match.
    UIViewController *vc = root;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if ([vc isKindOfClass:UITabBarController.class]) {
        UIViewController *sel = ((UITabBarController *)vc).selectedViewController;
        if (sel) vc = sel;
    }
    if ([vc isKindOfClass:UINavigationController.class]) {
        UIViewController *vis = ((UINavigationController *)vc).visibleViewController;
        if (vis) vc = vis;
    }

    return vc.view.window && TRBTextLooksLikeSourcesRoot(vc.view);
}

__attribute__((constructor))
static void TRBSourcesHeaderEntry(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        void (^refresh)(void) = ^{
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if (![scene isKindOfClass:UIWindowScene.class]) continue;

                for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                    if (window.hidden || window.alpha < 0.05) continue;
                    TRBRefreshGlobalGlassHeader(window);
                }
            }
        };

        // Immediate creation; FLEX can find the class even when it is hidden.
        refresh();

        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIWindowDidBecomeKeyNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification *note) {
            refresh();
        }];

        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification *note) {
            refresh();
        }];

        [NSTimer scheduledTimerWithTimeInterval:0.01
                                         repeats:YES
                                           block:^(__unused NSTimer *timer) {
            refresh();
        }];
    });
}



#pragma mark - Persistent Runtime Settings

@interface TRBRuntimeSettings : NSObject
@property(nonatomic) CGFloat targetX;
@property(nonatomic) CGFloat targetY;
@property(nonatomic) CGFloat targetWidth;
@property(nonatomic) CGFloat targetHeight;
+ (instancetype)shared;
@end

@implementation TRBRuntimeSettings

+ (instancetype)shared {
    static TRBRuntimeSettings *obj = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        obj = [TRBRuntimeSettings new];

        NSUserDefaults *d = NSUserDefaults.standardUserDefaults;

        if ([d objectForKey:@"TRB_targetX"] == nil) {
            [d setDouble:0.0 forKey:@"TRB_targetX"];
        }
        if ([d objectForKey:@"TRB_targetY"] == nil) {
            [d setDouble:-147.0 forKey:@"TRB_targetY"];
        }
        if ([d objectForKey:@"TRB_targetWidth"] == nil) {
            [d setDouble:390.0 forKey:@"TRB_targetWidth"];
        }
        if ([d objectForKey:@"TRB_targetHeight"] == nil) {
            [d setDouble:1200.0 forKey:@"TRB_targetHeight"];
        }

        obj->_targetX = [d doubleForKey:@"TRB_targetX"];
        obj->_targetY = [d doubleForKey:@"TRB_targetY"];
        obj->_targetWidth = [d doubleForKey:@"TRB_targetWidth"];
        obj->_targetHeight = [d doubleForKey:@"TRB_targetHeight"];
    });

    return obj;
}

- (void)setTargetX:(CGFloat)value {
    _targetX = value;
    [NSUserDefaults.standardUserDefaults setDouble:value forKey:@"TRB_targetX"];
}

- (void)setTargetY:(CGFloat)value {
    _targetY = value;
    [NSUserDefaults.standardUserDefaults setDouble:value forKey:@"TRB_targetY"];
}

- (void)setTargetWidth:(CGFloat)value {
    _targetWidth = value;
    [NSUserDefaults.standardUserDefaults setDouble:value forKey:@"TRB_targetWidth"];
}

- (void)setTargetHeight:(CGFloat)value {
    _targetHeight = value;
    [NSUserDefaults.standardUserDefaults setDouble:value forKey:@"TRB_targetHeight"];
}

@end

#pragma mark - v1.9 Force SwiftUI AnyView hosting frame

static UIViewController *TRBNearestViewControllerForView(UIView *view) {
    UIResponder *r = view;
    while (r) {
        r = r.nextResponder;
        if ([r isKindOfClass:UIViewController.class]) {
            return (UIViewController *)r;
        }
    }
    return nil;
}

static BOOL TRBControllerLooksLikeTarabAnyViewHost(UIViewController *vc) {
    if (!vc) return NO;

    NSString *name = NSStringFromClass(vc.class) ?: @"";
    NSString *desc = [vc description] ?: @"";

    BOOL tarab =
        [name containsString:@"Tarab"] ||
        [desc containsString:@"Tarab"];

    BOOL customHost =
        [name containsString:@"CustomUIHostingController"] ||
        [desc containsString:@"CustomUIHostingController"];

    BOOL anyView =
        [name containsString:@"AnyView"] ||
        [desc containsString:@"AnyView"];

    // FLEX previously showed:
    // Tarab.CustomUIHostingController<SwiftUI.AnyView>
    return tarab && customHost && anyView;
}

static BOOL TRBIsTargetAnyViewHostingView(UIView *view) {
    if (!view || !view.window) return NO;

    CGRect f = view.frame;
    CGRect b = view.bounds;

    BOOL widthMatch =
        fabs(f.size.width - 390.0) < 12.0 ||
        fabs(b.size.width - 390.0) < 12.0;

    BOOL tallEnough =
        f.size.height >= 800.0 ||
        b.size.height >= 800.0;

    BOOL yLooksRight =
        f.origin.y < -120.0 ||
        fabs(f.origin.y + 158.0) < 25.0 ||
        fabs(f.origin.y + 160.0) < 25.0;

    UIViewController *nearest = TRBNearestViewControllerForView(view);
    BOOL controllerMatch = TRBControllerLooksLikeTarabAnyViewHost(nearest);

    if (controllerMatch && widthMatch && tallEnough) {
        return YES;
    }

    // Fallback to SwiftUI hosting runtime name if present.
    NSString *name = NSStringFromClass(view.class) ?: @"";
    NSString *desc = [view description] ?: @"";

    BOOL hostingName =
        ([name containsString:@"_UIHostingView"] ||
         [desc containsString:@"_UIHostingView"]) &&
        ([name containsString:@"AnyView"] ||
         [desc containsString:@"AnyView"]);

    return hostingName && widthMatch && tallEnough && yLooksRight;
}

static CGRect TRBForcedAnyViewFrameForView(UIView *view);

static BOOL TRBIsForcedHeightChild_v20(UIView *v, CGFloat *heightOut) {
    if (!v) return NO;

    NSString *cn = NSStringFromClass(v.class);
    CGRect f = v.frame;
    CGRect b = v.bounds;

    // FLEX #1: SwiftUI._UIInheritedView, 358x450 -> force height 600.
    BOOL inherited450 =
        ([cn containsString:@"_UIInheritedView"] &&
         ((fabs(f.size.width - 358.0) < 3.0 && fabs(f.size.height - 450.0) < 8.0) ||
          (fabs(b.size.width - 358.0) < 3.0 && fabs(b.size.height - 450.0) < 8.0) ||
          fabs(f.size.height - 600.0) < 8.0 || fabs(b.size.height - 600.0) < 8.0));

    // FLEX #2: UIKitPlatformViewHost / ListRepresentable, 358x340 -> force height 600.
    BOOL list340 =
        (([cn containsString:@"UIKitPlatformViewHost"] ||
          [cn containsString:@"ListRepresentable"] ||
          [cn containsString:@"CollectionViewListDataSource"]) &&
         ((fabs(f.size.width - 358.0) < 3.0 && fabs(f.size.height - 340.0) < 8.0) ||
          (fabs(b.size.width - 358.0) < 3.0 && fabs(b.size.height - 340.0) < 8.0) ||
          fabs(f.size.height - 600.0) < 8.0 || fabs(b.size.height - 600.0) < 8.0));

    // FLEX: SwiftUI.UpdateCoalescingCollectionView 358x450 -> permanently force 600.
    BOOL updateCoalescing450 =
        ([cn containsString:@"UpdateCoalescingCollectionView"] &&
         ((fabs(f.size.width - 358.0) < 3.0 &&
           (fabs(f.size.height - 450.0) < 8.0 || fabs(f.size.height - 600.0) < 8.0)) ||
          (fabs(b.size.width - 358.0) < 3.0 &&
           (fabs(b.size.height - 450.0) < 8.0 || fabs(b.size.height - 600.0) < 8.0))));

    if (inherited450 || list340 || updateCoalescing450) {
        if (heightOut) *heightOut = 600.0;
        return YES;
    }
    return NO;
}

static IMP TRBOrigSetFrame_v19 = NULL;

static void TRBMarkAndForceTargetHostingView(UIView *view) {
    if (!TRBIsTargetAnyViewHostingView(view)) return;

    view.accessibilityIdentifier = @"TRBSourcesMainHostingView";

    CGRect wanted = view.frame;
    wanted.origin.y = -147.0;
    wanted.size.height = 1000.0;

    if (fabs(view.frame.origin.y - (-147.0)) > 0.0001 ||
        fabs(view.frame.size.height - 1000.0) > 0.0001) {
        if (TRBOrigSetFrame_v19) {
            ((void(*)(id,SEL,CGRect))TRBOrigSetFrame_v19)(
                view,
                @selector(setFrame:),
                wanted
            );
        } else {
            view.frame = wanted;
        }
    }
}

static CGRect TRBForcedAnyViewFrameForView(UIView *view) {
    CGRect f = view.frame;
    f.origin.y = -147.0;
    return f;
}

static void TRBSetFrame_v19(UIView *self, SEL _cmd, CGRect frame) {
    if (TRBIsTargetAnyViewHostingView(self)) {
        frame.origin.y = -147.0;
        frame.size.height = 1000.0;
        self.accessibilityIdentifier = @"TRBSourcesMainHostingView";
    } else {
        CGFloat forcedHeight = 0.0;
        if (TRBIsForcedHeightChild_v20(self, &forcedHeight)) {
            frame.size.height = forcedHeight;
            self.accessibilityIdentifier = @"TRBForcedContentHeight";
        }
    }

    ((void(*)(id,SEL,CGRect))TRBOrigSetFrame_v19)(self, _cmd, frame);
}

static IMP TRBOrigSetBounds_v19 = NULL;
static void TRBSetBounds_v19(UIView *self, SEL _cmd, CGRect bounds) {
    ((void(*)(id,SEL,CGRect))TRBOrigSetBounds_v19)(self, _cmd, bounds);
}

static IMP TRBOrigLayout_v19 = NULL;
static void TRBLayout_v19(UIView *self, SEL _cmd) {
    ((void(*)(id,SEL))TRBOrigLayout_v19)(self, _cmd);

    if (TRBIsTargetAnyViewHostingView(self)) {
        self.accessibilityIdentifier = @"TRBSourcesMainHostingView";

        CGRect wanted = self.frame;
        wanted.origin.y = -147.0;
        wanted.size.height = 1000.0;

        if (fabs(self.frame.origin.y - (-147.0)) > 0.0001 ||
            fabs(self.frame.size.height - 1000.0) > 0.0001) {
            ((void(*)(id,SEL,CGRect))TRBOrigSetFrame_v19)(
                self,
                @selector(setFrame:),
                wanted
            );
        }
    } else {
        CGFloat forcedHeight = 0.0;
        if (TRBIsForcedHeightChild_v20(self, &forcedHeight)) {
            CGRect wanted = self.frame;
            wanted.size.height = forcedHeight;
            if (fabs(self.frame.size.height - forcedHeight) > 0.0001) {
                ((void(*)(id,SEL,CGRect))TRBOrigSetFrame_v19)(
                    self, @selector(setFrame:), wanted
                );
            }
        }
    }
}

static void TRBInstallAnyViewFrameForce_v19(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = UIView.class;

        Method setFrameM = class_getInstanceMethod(cls, @selector(setFrame:));
        Method setBoundsM = class_getInstanceMethod(cls, @selector(setBounds:));
        Method layoutM = class_getInstanceMethod(cls, @selector(layoutSubviews));

        if (setFrameM) {
            TRBOrigSetFrame_v19 = method_getImplementation(setFrameM);
            method_setImplementation(setFrameM, (IMP)TRBSetFrame_v19);
        }

        if (setBoundsM) {
            TRBOrigSetBounds_v19 = method_getImplementation(setBoundsM);
            method_setImplementation(setBoundsM, (IMP)TRBSetBounds_v19);
        }

        if (layoutM) {
            TRBOrigLayout_v19 = method_getImplementation(layoutM);
            method_setImplementation(layoutM, (IMP)TRBLayout_v19);
        }
    });
}


static void TRBScanAndForceHostingViews(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;

        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden) continue;

            NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:window];

            while (stack.count) {
                UIView *v = stack.lastObject;
                [stack removeLastObject];

                if (TRBIsTargetAnyViewHostingView(v)) {
                    v.accessibilityIdentifier = @"TRBSourcesMainHostingView";

                    CGRect wanted = v.frame;
                    wanted.origin.y = -147.0;
                    wanted.size.height = 1000.0;

                    if (TRBOrigSetFrame_v19 &&
                        (fabs(v.frame.origin.y - (-147.0)) > 0.0001 ||
                         fabs(v.frame.size.height - 1000.0) > 0.0001)) {
                        ((void(*)(id,SEL,CGRect))TRBOrigSetFrame_v19)(
                            v,
                            @selector(setFrame:),
                            wanted
                        );
                    }
                }

                CGFloat forcedChildHeight = 0.0;
                if (TRBIsForcedHeightChild_v20(v, &forcedChildHeight)) {
                    v.accessibilityIdentifier = @"TRBForcedContentHeight";
                    CGRect childWanted = v.frame;
                    childWanted.size.height = forcedChildHeight;
                    if (TRBOrigSetFrame_v19 &&
                        fabs(v.frame.size.height - forcedChildHeight) > 0.0001) {
                        ((void(*)(id,SEL,CGRect))TRBOrigSetFrame_v19)(
                            v, @selector(setFrame:), childWanted
                        );
                    }
                }

                for (UIView *sub in v.subviews) {
                    [stack addObject:sub];
                }
            }
        }
    }
}

static void TRBSetCustomTopHeaderHidden_v20(BOOL hidden) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:w];
            while (stack.count) {
                UIView *v = stack.lastObject;
                [stack removeLastObject];

                NSString *aid = v.accessibilityIdentifier ?: @"";
                BOOL isOurExactHeader =
                    [aid isEqualToString:@"TRBTopHeader"] ||
                    [aid isEqualToString:@"TRBSourcesTopHeader"] ||
                    [aid isEqualToString:@"TRBSourcesTopHeaderView"] ||
                    [aid isEqualToString:@"TRBNativeGlassHeader"] ||
                    [aid isEqualToString:@"TRBOriginalTopHeader"];

                CGRect hf = v.frame;
                BOOL isOurHeaderByGeometry =
                    (fabs(hf.origin.y - 192.0) < 4.0 &&
                     fabs(hf.size.height - 70.0) < 5.0 &&
                     hf.size.width > 250.0 &&
                     [aid containsString:@"TRB"]);

                if (isOurExactHeader || isOurHeaderByGeometry) {
                    v.hidden = hidden;
                    v.alpha = hidden ? 0.0 : 1.0;
                    v.userInteractionEnabled = !hidden;
                    continue;
                }

                for (UIView *sub in v.subviews) [stack addObject:sub];
            }
        }
    }
}

static BOOL TRBIsTarabPlusSheetPresented_v20(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            UIViewController *vc = w.rootViewController;
            while (vc.presentedViewController) {
                vc = vc.presentedViewController;
                if (vc.sheetPresentationController != nil) {
                    return YES;
                }
            }
        }
    }
    return NO;
}

static void TRBApplySavedRuntimeFrame(void) {
    static BOOL trbHadSheet_v21 = NO;
    BOOL sheetVisible = TRBIsTarabPlusSheetPresented_v20();
    if (sheetVisible != trbHadSheet_v21) {
        /* v23: real header is pinned instead of hidden */
        trbHadSheet_v21 = sheetVisible;
    }
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;

        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden) continue;

            NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:window];

            while (stack.count) {
                UIView *v = stack.lastObject;
                [stack removeLastObject];

                if (TRBIsTargetAnyViewHostingView(v)) {
                    v.accessibilityIdentifier = @"TRBSourcesMainHostingView";

                    CGRect wanted = v.frame;
                    wanted.origin.y = -147.0;
                    wanted.size.height = 1000.0;

                    if (TRBOrigSetFrame_v19 &&
                        (fabs(v.frame.origin.y - (-147.0)) > 0.0001 ||
                         fabs(v.frame.size.height - 1000.0) > 0.0001)) {
                        ((void(*)(id,SEL,CGRect))TRBOrigSetFrame_v19)(
                            v,
                            @selector(setFrame:),
                            wanted
                        );
                    }
                }

                CGFloat forcedChildHeight = 0.0;
                if (TRBIsForcedHeightChild_v20(v, &forcedChildHeight)) {
                    v.accessibilityIdentifier = @"TRBForcedContentHeight";
                    CGRect childWanted = v.frame;
                    childWanted.size.height = forcedChildHeight;
                    if (TRBOrigSetFrame_v19 &&
                        fabs(v.frame.size.height - forcedChildHeight) > 0.0001) {
                        ((void(*)(id,SEL,CGRect))TRBOrigSetFrame_v19)(
                            v, @selector(setFrame:), childWanted
                        );
                    }
                }

                for (UIView *sub in v.subviews) {
                    [stack addObject:sub];
                }
            }
        }
    }
}

__attribute__((constructor))
static void TRBAnyViewFrameEntry_v19(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Create settings object immediately so FLEX can find it.
        (void)[TRBRuntimeSettings shared];

        TRBInstallAnyViewFrameForce_v19();

        // Apply persisted values immediately.
        TRBScanAndForceHostingViews();
        TRBApplySavedRuntimeFrame();

        [NSTimer scheduledTimerWithTimeInterval:0.02
                                         repeats:YES
                                           block:^(__unused NSTimer *timer) {
            TRBApplySavedRuntimeFrame();
        }];
    });
}



static BOOL TRBIsMKSongsTable_v24(UIView *view) {
    if (![view isKindOfClass:UITableView.class]) return NO;
    UIResponder *r = view;
    while (r) {
        if ([NSStringFromClass(r.class) isEqualToString:@"MKSongsViewController"]) return YES;
        r = r.nextResponder;
    }
    return NO;
}

static IMP TRBOrigUIViewSetFrame_v24 = NULL;
static void TRBUIViewSetFrame_v24(UIView *self, SEL _cmd, CGRect frame) {
    if (TRBIsMKSongsTable_v24(self)) frame.origin.y = 200.0;
    ((void(*)(id,SEL,CGRect))TRBOrigUIViewSetFrame_v24)(self,_cmd,frame);
}

static void TRBInstallSongsTableYForce_v24(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method m = class_getInstanceMethod(UIView.class, @selector(setFrame:));
        if (!m) return;
        TRBOrigUIViewSetFrame_v24 = method_getImplementation(m);
        method_setImplementation(m, (IMP)TRBUIViewSetFrame_v24);
    });
}

__attribute__((constructor))
static void TRBSongsTableYEntry_v24(void) {
    TRBInstallSongsTableYForce_v24();
}




#pragma mark - v25 Native Mohammed Alsaray profile sheet

@interface UINavigationController (TRBProfileSheetClose_v25)
- (void)trbDismissProfileSheet_v25;
@end

@implementation UINavigationController (TRBProfileSheetClose_v25)
- (void)trbDismissProfileSheet_v25 {
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end

static BOOL TRBViewContainsText_v25(UIView *root, NSString *needle) {
    if (!root || needle.length == 0) return NO;

    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];

        NSString *text = nil;
        if ([v isKindOfClass:UILabel.class]) {
            text = ((UILabel *)v).text;
        } else if ([v isKindOfClass:UIButton.class]) {
            text = [((UIButton *)v) titleForState:UIControlStateNormal];
        } else if ([v isKindOfClass:UITextView.class]) {
            text = ((UITextView *)v).text;
        }

        if (text.length && [text containsString:needle]) return YES;
        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
    return NO;
}

static BOOL TRBLooksLikeMohammedProfile_v25(UIViewController *vc) {
    if (!vc) return NO;

    NSString *className = NSStringFromClass(vc.class) ?: @"";
    NSString *title = vc.title ?: @"";

    if ([title containsString:@"محمد السراي"]) return YES;

    BOOL classHint =
        [className localizedCaseInsensitiveContainsString:@"profile"] ||
        [className localizedCaseInsensitiveContainsString:@"developer"] ||
        [className localizedCaseInsensitiveContainsString:@"about"];

    [vc loadViewIfNeeded];

    BOOL nameFound = TRBViewContainsText_v25(vc.view, @"محمد السراي");
    return nameFound && (classHint || vc.view != nil);
}

static BOOL TRBCurrentPageLooksLikeMore_v25(UIViewController *vc) {
    if (!vc) return NO;
    [vc loadViewIfNeeded];

    // The More page contains the Mohammed Alsaray row/card that launches profile.
    return TRBViewContainsText_v25(vc.view, @"محمد السراي");
}

static IMP TRBOrigPushVC_v25 = NULL;

static void TRBPushVC_v25(UINavigationController *nav,
                          SEL _cmd,
                          UIViewController *vc,
                          BOOL animated) {
    UIViewController *source = nav.visibleViewController;

    if (vc &&
        source &&
        TRBCurrentPageLooksLikeMore_v25(source) &&
        TRBLooksLikeMohammedProfile_v25(vc)) {

        // Use the ORIGINAL profile VC/content, only replace navigation style.
        UINavigationController *sheetNav =
            [[UINavigationController alloc] initWithRootViewController:vc];
        sheetNav.modalPresentationStyle = UIModalPresentationPageSheet;

        if (@available(iOS 16.0, *)) {
            UISheetPresentationController *sheet = sheetNav.sheetPresentationController;

            UISheetPresentationControllerDetentIdentifier profileID =
                @"TRBMohammedProfileFixed";

            UISheetPresentationControllerDetent *profileDetent =
                [UISheetPresentationControllerDetent customDetentWithIdentifier:profileID
                                                                       resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
                    CGFloat target = (context.maximumDetentValue * 0.5) + 20.0;
                    return MIN(target, context.maximumDetentValue - 40.0);
                }];

            // ONE detent only: user cannot drag this profile sheet to Full Screen.
            sheet.detents = @[profileDetent];
            sheet.selectedDetentIdentifier = profileID;
            sheet.prefersGrabberVisible = YES;
            sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
            sheet.prefersEdgeAttachedInCompactHeight = YES;
        } else if (@available(iOS 15.0, *)) {
            UISheetPresentationController *sheet = sheetNav.sheetPresentationController;
            sheet.detents = @[[UISheetPresentationControllerDetent mediumDetent]];
            sheet.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
            sheet.prefersGrabberVisible = YES;
            sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
        }

        // Add a native close button only if the original page does not already have one.
        if (!vc.navigationItem.leftBarButtonItem) {
            vc.navigationItem.leftBarButtonItem =
                [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                             target:sheetNav
                                                             action:@selector(trbDismissProfileSheet_v25)];
        }

        [source presentViewController:sheetNav animated:YES completion:nil];
        return;
    }

    ((void(*)(id,SEL,id,BOOL))TRBOrigPushVC_v25)(nav, _cmd, vc, animated);
}

static void TRBInstallProfileSheetHook_v25(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method m = class_getInstanceMethod(UINavigationController.class,
                                           @selector(pushViewController:animated:));
        if (!m) return;

        TRBOrigPushVC_v25 = method_getImplementation(m);
        method_setImplementation(m, (IMP)TRBPushVC_v25);
    });
}

__attribute__((constructor))
static void TRBProfileSheetEntry_v25(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        TRBInstallProfileSheetHook_v25();
    });
}

