#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static IMP orig_tab_layout = NULL;
static IMP orig_tab_vc_layout = NULL;

static BOOL nameHas(Class c, NSString *s) {
    if (!c) return NO;
    NSString *n = NSStringFromClass(c);
    return [n rangeOfString:s options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static BOOL isTabBackgroundView(UIView *v) {
    if (!v) return NO;
    Class c = object_getClass(v);
    return nameHas(c, @"BarBackground") ||
           nameHas(c, @"VisualEffect") ||
           nameHas(c, @"Backdrop") ||
           nameHas(c, @"BackgroundView");
}

static void clearTabBackgroundTree(UIView *v) {
    if (!v) return;
    for (UIView *sv in [v.subviews copy]) {
        if (isTabBackgroundView(sv)) {
            sv.backgroundColor = UIColor.clearColor;
            sv.opaque = NO;
            sv.hidden = YES;
        }
        clearTabBackgroundTree(sv);
    }
}

static void configureTransparentTabBar(UITabBar *tab) {
    if (!tab) return;

    tab.backgroundColor = UIColor.clearColor;
    tab.opaque = NO;
    tab.translucent = YES;
    tab.backgroundImage = [UIImage new];
    tab.shadowImage = [UIImage new];

    if (@available(iOS 15.0, *)) {
        UITabBarAppearance *a = [UITabBarAppearance new];
        [a configureWithTransparentBackground];
        a.backgroundColor = UIColor.clearColor;
        a.backgroundEffect = nil;
        a.shadowColor = UIColor.clearColor;
        tab.standardAppearance = a;
        tab.scrollEdgeAppearance = a;
    }

    clearTabBackgroundTree(tab);
}

/*
 The important part:
 Let the selected page extend underneath the floating/glass tab bar.
 This removes the large opaque/black safe-area/container behind it.
 */
static void extendSelectedPageUnderTabBar(UITabBarController *tc) {
    if (!tc) return;

    UIViewController *vc = tc.selectedViewController;
    if (!vc) return;

    UIViewController *target = vc;
    if ([vc isKindOfClass:[UINavigationController class]]) {
        UIViewController *top = ((UINavigationController *)vc).topViewController;
        if (top) target = top;
    }

    target.edgesForExtendedLayout = UIRectEdgeAll;
    target.extendedLayoutIncludesOpaqueBars = YES;

    UIScrollView *scroll = nil;
    if ([target.view isKindOfClass:[UIScrollView class]]) {
        scroll = (UIScrollView *)target.view;
    } else {
        for (UIView *v in target.view.subviews) {
            if ([v isKindOfClass:[UIScrollView class]]) {
                scroll = (UIScrollView *)v;
                break;
            }
        }
    }

    if (scroll) {
        scroll.contentInsetAdjustmentBehavior =
            UIScrollViewContentInsetAdjustmentNever;

        UIEdgeInsets inset = scroll.contentInset;
        inset.bottom = 0;
        scroll.contentInset = inset;

        UIEdgeInsets indicator = scroll.scrollIndicatorInsets;
        indicator.bottom = 0;
        scroll.scrollIndicatorInsets = indicator;
    }

    /*
     Remove only large empty sibling views that sit immediately behind/
     below the tab bar. Never hide controls, scroll views, labels, etc.
    */
    UIWindow *w = tc.view.window;
    if (!w) return;

    CGRect tabRect = [tc.tabBar convertRect:tc.tabBar.bounds toView:w];

    for (UIView *v in [w.subviews copy]) {
        if (v == tc.view || v == tc.tabBar) continue;
        if ([v isKindOfClass:UIControl.class] ||
            [v isKindOfClass:UIScrollView.class]) continue;

        CGRect r = [v convertRect:v.bounds toView:w];

        BOOL wide = r.size.width >= w.bounds.size.width * 0.90;
        BOOL lower = CGRectGetMinY(r) >= tabRect.origin.y - 220.0;
        BOOL reachesBottom = CGRectGetMaxY(r) >=
                             CGRectGetMaxY(w.bounds) - 8.0;
        BOOL mostlyEmpty = v.subviews.count == 0;

        if (wide && lower && reachesBottom && mostlyEmpty) {
            v.backgroundColor = UIColor.clearColor;
            v.opaque = NO;
            v.userInteractionEnabled = NO;
        }
    }
}

static void tab_layout(UITabBar *self, SEL _cmd) {
    if (orig_tab_layout) {
        ((void(*)(id,SEL))orig_tab_layout)(self, _cmd);
    }
    configureTransparentTabBar(self);
}

static void tabvc_layout(UITabBarController *self, SEL _cmd) {
    if (orig_tab_vc_layout) {
        ((void(*)(id,SEL))orig_tab_vc_layout)(self, _cmd);
    }
    configureTransparentTabBar(self.tabBar);
    extendSelectedPageUnderTabBar(self);
}

/* BannerHeightManager remains targeted and safe. */
static double zeroDouble(id self, SEL _cmd) { return 0.0; }
static void ignoreDouble(id self, SEL _cmd, double x) {}
static BOOL falseBool(id self, SEL _cmd) { return NO; }
static void ignoreBool(id self, SEL _cmd, BOOL x) {}

static void replaceIfPresent(Class c, const char *name, IMP imp) {
    if (!c) return;
    Method m = class_getInstanceMethod(c, sel_registerName(name));
    if (m) method_setImplementation(m, imp);
}

__attribute__((constructor))
static void init_v3(void) {
    @autoreleasepool {
        Class bhm = objc_getClass("_TtC5Tarab19BannerHeightManager");
        if (!bhm) bhm = objc_getClass("BannerHeightManager");

        replaceIfPresent(bhm, "bannerHeight", (IMP)zeroDouble);
        replaceIfPresent(bhm, "setBannerHeight:", (IMP)ignoreDouble);
        replaceIfPresent(bhm, "inlineBannerHeight", (IMP)zeroDouble);
        replaceIfPresent(bhm, "setInlineBannerHeight:", (IMP)ignoreDouble);
        replaceIfPresent(bhm, "bannerBottomPadding", (IMP)zeroDouble);
        replaceIfPresent(bhm, "setBannerBottomPadding:", (IMP)ignoreDouble);
        replaceIfPresent(bhm, "shouldShowBanner", (IMP)falseBool);
        replaceIfPresent(bhm, "setShouldShowBanner:", (IMP)ignoreBool);

        Class tb = UITabBar.class;
        Method tm = class_getInstanceMethod(tb, @selector(layoutSubviews));
        if (tm) {
            orig_tab_layout = method_getImplementation(tm);
            method_setImplementation(tm, (IMP)tab_layout);
        }

        Class tc = UITabBarController.class;
        Method cm = class_getInstanceMethod(tc, @selector(viewDidLayoutSubviews));
        if (cm) {
            orig_tab_vc_layout = method_getImplementation(cm);
            method_setImplementation(cm, (IMP)tabvc_layout);
        }
    }
}
