#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static IMP orig_tab_layout = NULL;
static IMP inherited_tabvc_layout = NULL;
static IMP orig_ads_update = NULL;

/* ---------------- Helpers ---------------- */

static id SafeGet(id obj, NSString *key) {
    @try { return [obj valueForKey:key]; }
    @catch (__unused NSException *e) { return nil; }
}
static void SafeSet(id obj, NSString *key, id value) {
    @try { [obj setValue:value forKey:key]; }
    @catch (__unused NSException *e) {}
}
static void ZeroConstraint(id obj) {
    if ([obj isKindOfClass:NSLayoutConstraint.class]) {
        NSLayoutConstraint *c = (NSLayoutConstraint *)obj;
        c.constant = 0.0;
    }
}
static void HideAdView(id obj) {
    if (![obj isKindOfClass:UIView.class]) return;
    UIView *v = obj;
    v.hidden = YES;
    v.alpha = 0.0;
    v.userInteractionEnabled = NO;
    for (NSLayoutConstraint *c in v.constraints) {
        if (c.firstAttribute == NSLayoutAttributeHeight) c.constant = 0.0;
    }
}

/* ---------------- Tarab ad reservation ---------------- */

static void CollapseKnownAdReservations(id obj) {
    if (!obj) return;

    SafeSet(obj, @"bannerHeight", @0.0);
    SafeSet(obj, @"inlineBannerHeight", @0.0);
    SafeSet(obj, @"bannerBottomPadding", @0.0);
    SafeSet(obj, @"adHeight", @0.0);
    SafeSet(obj, @"shouldShowBanner", @NO);

    ZeroConstraint(SafeGet(obj, @"bannerBottomConstraint"));
    ZeroConstraint(SafeGet(obj, @"webViewBottomConstraint"));

    HideAdView(SafeGet(obj, @"bannerView"));
    HideAdView(SafeGet(obj, @"inlineBannerView"));
}

static double ZeroDouble(id self, SEL _cmd) { return 0.0; }
static void IgnoreDouble(id self, SEL _cmd, double v) {}
static BOOL FalseBool(id self, SEL _cmd) { return NO; }
static void IgnoreBool(id self, SEL _cmd, BOOL v) {}

static void ReplaceIfPresent(Class c, const char *name, IMP imp) {
    if (!c) return;
    Method m = class_getInstanceMethod(c, sel_registerName(name));
    if (m) method_setImplementation(m, imp);
}

static void AdsUpdate(id self, SEL _cmd) {
    if (orig_ads_update) ((void(*)(id,SEL))orig_ads_update)(self,_cmd);
    CollapseKnownAdReservations(self);
}

/* ---------------- iOS 26 floating tab bar ---------------- */

static void ConfigureGlassTabBar(UITabBar *tab) {
    if (!tab) return;

    tab.backgroundColor = UIColor.clearColor;
    tab.opaque = NO;
    tab.translucent = YES;

    if (@available(iOS 15.0, *)) {
        UITabBarAppearance *a = [UITabBarAppearance new];
        [a configureWithTransparentBackground];
        a.backgroundColor = UIColor.clearColor;
        a.backgroundEffect = nil;
        a.shadowColor = UIColor.clearColor;
        tab.standardAppearance = a;
        tab.scrollEdgeAppearance = a;
    }
}

static void TabLayout(UITabBar *self, SEL _cmd) {
    if (orig_tab_layout) ((void(*)(id,SEL))orig_tab_layout)(self,_cmd);
    ConfigureGlassTabBar(self);
}

/* ---------------- Deep content extension ---------------- */

static UIScrollView *FirstScroll(UIView *root) {
    if (!root) return nil;
    if ([root isKindOfClass:UIScrollView.class]) return (UIScrollView *)root;
    for (UIView *v in root.subviews) {
        UIScrollView *s = FirstScroll(v);
        if (s) return s;
    }
    return nil;
}

static void ExtendAncestorChain(UIView *leaf, UIView *root) {
    if (!leaf || !root) return;

    UIView *v = leaf;
    while (v && v != root) {
        UIView *p = v.superview;
        if (!p) break;

        CGRect pf = p.bounds;
        CGRect f = v.frame;

        /*
         Preserve the existing top edge, but force the bottom edge to reach
         the parent bottom. This is the key fix for old pre-iOS-26 tab layouts.
        */
        CGFloat newHeight = pf.size.height - f.origin.y;
        if (newHeight > f.size.height) {
            f.size.height = newHeight;
            v.frame = f;
        }

        v.autoresizingMask |= UIViewAutoresizingFlexibleHeight |
                              UIViewAutoresizingFlexibleWidth;
        v = p;
    }
}

static void ExtendSelectedPage(UITabBarController *tc) {
    if (!tc || !tc.selectedViewController) return;

    UIViewController *selected = tc.selectedViewController;
    UIViewController *content = selected;

    if ([selected isKindOfClass:UINavigationController.class]) {
        UINavigationController *nav = (UINavigationController *)selected;
        if (nav.topViewController) content = nav.topViewController;
    }

    /* Remove any ad/safe-area reserve from both container and real page. */
    selected.additionalSafeAreaInsets = UIEdgeInsetsZero;
    content.additionalSafeAreaInsets = UIEdgeInsetsZero;

    CollapseKnownAdReservations(selected);
    CollapseKnownAdReservations(content);

    /*
     Old Tarab layout can size the selected controller only to the old
     tab-bar-safe rectangle. Expand the actual UIKit container hierarchy
     after UIKit finishes layout.
    */
    if (selected.view) {
        ExtendAncestorChain(selected.view, tc.view);

        CGRect f = selected.view.frame;
        CGFloat targetBottom = tc.view.bounds.size.height;
        if ((f.origin.y + f.size.height) < targetBottom) {
            f.size.height = targetBottom - f.origin.y;
            selected.view.frame = f;
        }
    }

    if (content.view) {
        content.view.autoresizingMask |= UIViewAutoresizingFlexibleHeight |
                                         UIViewAutoresizingFlexibleWidth;

        UIScrollView *scroll = FirstScroll(content.view);
        if (scroll) {
            /*
             The scroll view itself fills the page behind glass.
             Keep a bottom content inset only so the LAST control remains
             reachable above the floating tab bar.
            */
            CGRect sf = scroll.frame;
            CGFloat desiredBottom = content.view.bounds.size.height;
            if ((sf.origin.y + sf.size.height) < desiredBottom) {
                sf.size.height = desiredBottom - sf.origin.y;
                scroll.frame = sf;
            }

            UIEdgeInsets inset = scroll.contentInset;
            CGFloat safe = tc.view.safeAreaInsets.bottom;
            CGFloat bar = tc.tabBar.bounds.size.height;
            inset.bottom = MAX(bar + safe, inset.bottom);
            scroll.contentInset = inset;
        }
    }

    /* Known Tarab support-page reservation; harmless on other pages. */
    ZeroConstraint(SafeGet(content, @"webViewBottomConstraint"));
    SafeSet(content, @"adHeight", @0.0);

    ConfigureGlassTabBar(tc.tabBar);

    [tc.view bringSubviewToFront:tc.tabBar];
}

static void SafeTabVCLayout(UITabBarController *self, SEL _cmd) {
    if (inherited_tabvc_layout) {
        ((void(*)(id,SEL))inherited_tabvc_layout)(self,_cmd);
    }
    ExtendSelectedPage(self);

    dispatch_async(dispatch_get_main_queue(), ^{
        ExtendSelectedPage(self);
    });
}

/* ---------------- Init ---------------- */

__attribute__((constructor))
static void InitDeepFix(void) {
    @autoreleasepool {
        /* Tarab AdsManager */
        Class ads = objc_getClass("_TtC5Tarab10AdsManager");
        if (!ads) ads = objc_getClass("AdsManager");

        if (ads) {
            ReplaceIfPresent(ads, "bannerHeight", (IMP)ZeroDouble);
            ReplaceIfPresent(ads, "setBannerHeight:", (IMP)IgnoreDouble);
            ReplaceIfPresent(ads, "inlineBannerHeight", (IMP)ZeroDouble);
            ReplaceIfPresent(ads, "setInlineBannerHeight:", (IMP)IgnoreDouble);
            ReplaceIfPresent(ads, "bannerBottomPadding", (IMP)ZeroDouble);
            ReplaceIfPresent(ads, "setBannerBottomPadding:", (IMP)IgnoreDouble);
            ReplaceIfPresent(ads, "shouldShowBanner", (IMP)FalseBool);
            ReplaceIfPresent(ads, "setShouldShowBanner:", (IMP)IgnoreBool);

            Method m = class_getInstanceMethod(
                ads, sel_registerName("updateBannerPosition")
            );
            if (m) {
                orig_ads_update = method_getImplementation(m);
                method_setImplementation(m, (IMP)AdsUpdate);
            }
        }

        /* Tarab BannerHeightManager */
        Class bhm = objc_getClass("_TtC5Tarab19BannerHeightManager");
        if (!bhm) bhm = objc_getClass("BannerHeightManager");
        if (bhm) {
            ReplaceIfPresent(bhm, "adHeight", (IMP)ZeroDouble);
            ReplaceIfPresent(bhm, "setAdHeight:", (IMP)IgnoreDouble);
            ReplaceIfPresent(bhm, "bannerHeight", (IMP)ZeroDouble);
            ReplaceIfPresent(bhm, "setBannerHeight:", (IMP)IgnoreDouble);
        }

        /* Keep working V2-style tab transparency */
        Method tm = class_getInstanceMethod(UITabBar.class, @selector(layoutSubviews));
        if (tm) {
            orig_tab_layout = method_getImplementation(tm);
            method_setImplementation(tm, (IMP)TabLayout);
        }

        /*
         IMPORTANT: create/replace method ONLY on UITabBarController itself.
         Never mutate UIViewController's inherited implementation globally.
        */
        Class tc = UITabBarController.class;
        SEL sel = @selector(viewDidLayoutSubviews);
        Method inherited = class_getInstanceMethod(tc, sel);

        if (inherited) {
            inherited_tabvc_layout = method_getImplementation(inherited);
            const char *types = method_getTypeEncoding(inherited);

            if (!class_addMethod(tc, sel, (IMP)SafeTabVCLayout, types)) {
                unsigned int count = 0;
                Method *list = class_copyMethodList(tc, &count);
                for (unsigned int i=0; i<count; i++) {
                    if (method_getName(list[i]) == sel) {
                        inherited_tabvc_layout =
                            method_getImplementation(list[i]);
                        method_setImplementation(list[i],
                                                 (IMP)SafeTabVCLayout);
                        break;
                    }
                }
                free(list);
            }
        }
    }
}
