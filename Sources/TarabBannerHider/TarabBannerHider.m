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




__attribute__((objc_runtime_name("TRBSourcesTopHeaderView")))
@interface TRBSourcesTopHeaderView : UIView
@end
@implementation TRBSourcesTopHeaderView
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
                path = [bundle pathForResource:@"TarabSourcesHeader" ofType:@"jpeg"];
                if (!path) {
                    path = [bundle.bundlePath stringByAppendingPathComponent:@"TarabSourcesHeader.jpeg"];
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

static BOOL TRBControllerIsSourcesPage(UIViewController *vc) {
    if (!vc || !vc.isViewLoaded || !vc.view.window) return NO;

    NSString *title = vc.title ?: @"";
    UITabBarItem *item = vc.tabBarItem;
    NSString *tabTitle = item.title ?: @"";

    if ([title containsString:@"المصادر"] ||
        [tabTitle containsString:@"المصادر"] ||
        [title localizedCaseInsensitiveContainsString:@"Sources"] ||
        [tabTitle localizedCaseInsensitiveContainsString:@"Sources"]) {
        return YES;
    }

    UIViewController *parent = vc.parentViewController;
    while (parent) {
        NSString *pt = parent.title ?: @"";
        NSString *pTab = parent.tabBarItem.title ?: @"";
        if ([pt containsString:@"المصادر"] ||
            [pTab containsString:@"المصادر"] ||
            [pt localizedCaseInsensitiveContainsString:@"Sources"] ||
            [pTab localizedCaseInsensitiveContainsString:@"Sources"]) {
            return YES;
        }
        parent = parent.parentViewController;
    }

    return TRBViewContainsSourcesMarkers(vc.view);
}

static UIView *TRBEnsurePageHeader(UIViewController *vc) {
    if (!vc || !vc.isViewLoaded) return nil;

    UIView *header = objc_getAssociatedObject(vc, &kTRBPageHeaderKey);
    UIImageView *iv = objc_getAssociatedObject(vc, &kTRBPageHeaderImageKey);

    if (!header) {
        header = [[TRBSourcesTopHeaderView alloc] initWithFrame:CGRectZero];
        header.accessibilityIdentifier = @"TRBSourcesTopHeaderView";
        header.userInteractionEnabled = NO;
        header.clipsToBounds = YES;
        header.backgroundColor = UIColor.systemBackgroundColor;
        header.layer.zPosition = 99999999.0;

        iv = [[TRBSourcesTopHeaderImageView alloc] initWithFrame:CGRectZero];
        iv.accessibilityIdentifier = @"TRBSourcesTopHeaderImageView";
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.userInteractionEnabled = NO;
        iv.clipsToBounds = YES;
        iv.image = TRBSourcesHeaderImage();
        iv.layer.zPosition = 2.0;

        [header addSubview:iv];
        [vc.view addSubview:header];

        objc_setAssociatedObject(vc, &kTRBPageHeaderKey, header, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(vc, &kTRBPageHeaderImageKey, iv, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    CGFloat top = vc.view.safeAreaInsets.top;
    CGFloat height = MAX(104.0, top + 76.0);

    header.frame = CGRectMake(
        0.0,
        0.0,
        vc.view.bounds.size.width,
        height
    );

    header.backgroundColor = UIColor.systemBackgroundColor;
    header.layer.zPosition = 99999999.0;

    if (iv) {
        CGFloat imageTop = MAX(4.0, top + 2.0);
        CGFloat imageHeight = MAX(58.0, height - imageTop - 4.0);
        CGFloat imageWidth = MIN(vc.view.bounds.size.width - 28.0, 300.0);

        iv.frame = CGRectMake(
            (vc.view.bounds.size.width - imageWidth) / 2.0,
            imageTop,
            imageWidth,
            imageHeight
        );

        if (!iv.image) iv.image = TRBSourcesHeaderImage();
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
                    TRBRefreshPageHeader(window);
                }
            }
        };

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

        [NSTimer scheduledTimerWithTimeInterval:0.03
                                         repeats:YES
                                           block:^(__unused NSTimer *timer) {
            refresh();
        }];
    });
}
