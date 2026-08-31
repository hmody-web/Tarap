#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static IMP orig_updateBannerPosition = NULL;
static IMP orig_tab_layout = NULL;

/* ---------- Utilities ---------- */

static id safeValue(id obj, NSString *key) {
    @try {
        return [obj valueForKey:key];
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static void safeSetValue(id obj, NSString *key, id value) {
    @try {
        [obj setValue:value forKey:key];
    } @catch (__unused NSException *e) {}
}

static void zeroConstraint(id c) {
    if ([c isKindOfClass:[NSLayoutConstraint class]]) {
        NSLayoutConstraint *constraint = (NSLayoutConstraint *)c;
        constraint.constant = 0.0;
        constraint.active = NO;
    }
}

static void hideAdView(id obj) {
    if ([obj isKindOfClass:[UIView class]]) {
        UIView *v = (UIView *)obj;
        v.hidden = YES;
        v.alpha = 0.0;
        v.userInteractionEnabled = NO;

        for (NSLayoutConstraint *c in v.constraints) {
            if (c.firstAttribute == NSLayoutAttributeHeight) {
                c.constant = 0.0;
            }
        }

        UIView *superview = v.superview;
        if (superview) {
            for (NSLayoutConstraint *c in superview.constraints) {
                if ((c.firstItem == v || c.secondItem == v) &&
                    (c.firstAttribute == NSLayoutAttributeHeight ||
                     c.secondAttribute == NSLayoutAttributeHeight)) {
                    c.constant = 0.0;
                }
            }
        }
    }
}

/* ---------- Actual source: Tarab AdsManager ---------- */

static void collapseAdsManager(id manager) {
    if (!manager) return;

    /* These ivars/properties are present in Tarab's AdsManager binary. */
    safeSetValue(manager, @"bannerBottomPadding", @0.0);
    safeSetValue(manager, @"bannerHeight", @0.0);
    safeSetValue(manager, @"inlineBannerHeight", @0.0);
    safeSetValue(manager, @"shouldShowBanner", @NO);

    id bottomConstraint = safeValue(manager, @"bannerBottomConstraint");
    zeroConstraint(bottomConstraint);

    hideAdView(safeValue(manager, @"bannerView"));
    hideAdView(safeValue(manager, @"inlineBannerView"));

    /*
     Some builds keep NSLayoutConstraint references only as ivars.
     Access them directly if KVC/property resolution did not expose them.
    */
    Ivar iv = class_getInstanceVariable(object_getClass(manager), "bannerBottomConstraint");
    if (!iv) iv = class_getInstanceVariable(object_getClass(manager), "_bannerBottomConstraint");
    if (iv) {
        id c = object_getIvar(manager, iv);
        zeroConstraint(c);
    }

    Ivar bv = class_getInstanceVariable(object_getClass(manager), "bannerView");
    if (!bv) bv = class_getInstanceVariable(object_getClass(manager), "_bannerView");
    if (bv) hideAdView(object_getIvar(manager, bv));

    Ivar ibv = class_getInstanceVariable(object_getClass(manager), "inlineBannerView");
    if (!ibv) ibv = class_getInstanceVariable(object_getClass(manager), "_inlineBannerView");
    if (ibv) hideAdView(object_getIvar(manager, ibv));
}

static void hooked_updateBannerPosition(id self, SEL _cmd) {
    /*
     Let Tarab finish its normal layout first, then remove only the ad reserve.
     This means the app can relayout normally, and we collapse the ad slot last.
    */
    if (orig_updateBannerPosition) {
        ((void(*)(id,SEL))orig_updateBannerPosition)(self, _cmd);
    }

    collapseAdsManager(self);

    dispatch_async(dispatch_get_main_queue(), ^{
        collapseAdsManager(self);

        UIWindow *w = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
                    if (candidate.isKeyWindow) {
                        w = candidate;
                        break;
                    }
                }
            }
            if (w) break;
        }

        [w layoutIfNeeded];
    });
}

/* ---------- Getter/setter hooks on AdsManager only ---------- */

static double zeroDouble(id self, SEL _cmd) {
    return 0.0;
}

static void ignoreDouble(id self, SEL _cmd, double value) {
}

static BOOL falseBool(id self, SEL _cmd) {
    return NO;
}

static void ignoreBool(id self, SEL _cmd, BOOL value) {
}

static void replaceIfPresent(Class c, const char *name, IMP imp) {
    if (!c) return;
    Method m = class_getInstanceMethod(c, sel_registerName(name));
    if (!m) return;

    /*
      AdsManager is an app-specific class, so replacing its own methods does
      not affect UIViewController/UIKit globally.
    */
    method_setImplementation(m, imp);
}

/* ---------- Keep the V2 tab transparency that already worked ---------- */

static void makeTabTransparent(UITabBar *tab) {
    if (!tab) return;

    tab.backgroundColor = UIColor.clearColor;
    tab.opaque = NO;
    tab.translucent = YES;

    if (@available(iOS 15.0, *)) {
        UITabBarAppearance *appearance = [UITabBarAppearance new];
        [appearance configureWithTransparentBackground];
        appearance.backgroundColor = UIColor.clearColor;
        appearance.backgroundEffect = nil;
        appearance.shadowColor = UIColor.clearColor;

        tab.standardAppearance = appearance;
        tab.scrollEdgeAppearance = appearance;
    }
}

static void hooked_tab_layout(UITabBar *self, SEL _cmd) {
    if (orig_tab_layout) {
        ((void(*)(id,SEL))orig_tab_layout)(self, _cmd);
    }

    makeTabTransparent(self);
}

/* ---------- Init ---------- */

__attribute__((constructor))
static void init_v5(void) {
    @autoreleasepool {
        Class ads = objc_getClass("_TtC5Tarab10AdsManager");
        if (!ads) ads = objc_getClass("AdsManager");

        if (ads) {
            replaceIfPresent(ads, "bannerHeight", (IMP)zeroDouble);
            replaceIfPresent(ads, "setBannerHeight:", (IMP)ignoreDouble);

            replaceIfPresent(ads, "inlineBannerHeight", (IMP)zeroDouble);
            replaceIfPresent(ads, "setInlineBannerHeight:", (IMP)ignoreDouble);

            replaceIfPresent(ads, "bannerBottomPadding", (IMP)zeroDouble);
            replaceIfPresent(ads, "setBannerBottomPadding:", (IMP)ignoreDouble);

            replaceIfPresent(ads, "shouldShowBanner", (IMP)falseBool);
            replaceIfPresent(ads, "setShouldShowBanner:", (IMP)ignoreBool);

            Method update = class_getInstanceMethod(
                ads,
                sel_registerName("updateBannerPosition")
            );

            if (update) {
                orig_updateBannerPosition = method_getImplementation(update);
                method_setImplementation(
                    update,
                    (IMP)hooked_updateBannerPosition
                );
            }
        }

        Class tb = UITabBar.class;
        Method layout = class_getInstanceMethod(tb, @selector(layoutSubviews));
        if (layout) {
            orig_tab_layout = method_getImplementation(layout);
            method_setImplementation(layout, (IMP)hooked_tab_layout);
        }
    }
}
