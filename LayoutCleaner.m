#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static IMP orig_tab_layout = NULL;
static IMP inherited_tabvc_layout = NULL;

/* ---------- BannerHeightManager ---------- */

static double zeroDouble(id self, SEL _cmd) { return 0.0; }
static void ignoreDouble(id self, SEL _cmd, double value) {}
static BOOL falseBool(id self, SEL _cmd) { return NO; }
static void ignoreBool(id self, SEL _cmd, BOOL value) {}

static void replaceIfPresent(Class c, const char *name, IMP imp) {
    if (!c) return;
    Method m = class_getInstanceMethod(c, sel_registerName(name));
    if (m) method_setImplementation(m, imp);
}

/* ---------- Tab bar transparency ---------- */

static BOOL classNameContains(id obj, NSString *needle) {
    if (!obj) return NO;
    NSString *name = NSStringFromClass(object_getClass(obj));
    return [name rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static void cleanTabSubviews(UIView *root) {
    if (!root) return;

    for (UIView *v in [root.subviews copy]) {
        if (classNameContains(v, @"BarBackground") ||
            classNameContains(v, @"Backdrop") ||
            classNameContains(v, @"VisualEffect")) {
            v.backgroundColor = UIColor.clearColor;
            v.opaque = NO;
        }
        cleanTabSubviews(v);
    }
}

static void makeTabTransparent(UITabBar *tab) {
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

    cleanTabSubviews(tab);
}

static void tab_layout(UITabBar *self, SEL _cmd) {
    if (orig_tab_layout) {
        ((void(*)(id,SEL))orig_tab_layout)(self, _cmd);
    }
    makeTabTransparent(self);
}

/* ---------- Selected page extends under the tab bar ---------- */

static UIScrollView *firstScrollView(UIView *root) {
    if (!root) return nil;
    if ([root isKindOfClass:UIScrollView.class]) return (UIScrollView *)root;

    for (UIView *v in root.subviews) {
        UIScrollView *r = firstScrollView(v);
        if (r) return r;
    }
    return nil;
}

static void extendPage(UITabBarController *tc) {
    if (!tc) return;

    UIViewController *vc = tc.selectedViewController;
    if (!vc) return;

    UIViewController *target = vc;

    if ([vc isKindOfClass:UINavigationController.class]) {
        UIViewController *top = ((UINavigationController *)vc).topViewController;
        if (top) target = top;
    }

    target.edgesForExtendedLayout = UIRectEdgeAll;
    target.extendedLayoutIncludesOpaqueBars = YES;

    UIView *page = target.view;
    if (!page) return;

    page.backgroundColor = page.backgroundColor ?: UIColor.clearColor;

    UIScrollView *scroll = firstScrollView(page);
    if (scroll) {
        /*
         Keep the page under the tab bar while preserving its own content.
         We do NOT zero the whole safe-area and do NOT hide arbitrary views.
        */
        scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;

        UIEdgeInsets inset = scroll.contentInset;
        inset.bottom = 0;
        scroll.contentInset = inset;

        if (@available(iOS 13.0, *)) {
            UIEdgeInsets v = scroll.verticalScrollIndicatorInsets;
            v.bottom = 0;
            scroll.verticalScrollIndicatorInsets = v;

            UIEdgeInsets h = scroll.horizontalScrollIndicatorInsets;
            h.bottom = 0;
            scroll.horizontalScrollIndicatorInsets = h;
        }
    }

    makeTabTransparent(tc.tabBar);
}

/*
 Safe per-class override:
 Do NOT call method_setImplementation on an inherited UIViewController Method.
 Instead class_addMethod creates an override owned only by UITabBarController.
*/
static void safe_tabvc_layout(UITabBarController *self, SEL _cmd) {
    if (inherited_tabvc_layout) {
        ((void(*)(id,SEL))inherited_tabvc_layout)(self, _cmd);
    }
    extendPage(self);
}

__attribute__((constructor))
static void init_v4(void) {
    @autoreleasepool {
        /* Targeted banner manager only */
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

        /* V2-style UITabBar hook - already known to work */
        Class tb = UITabBar.class;
        Method tm = class_getInstanceMethod(tb, @selector(layoutSubviews));
        if (tm) {
            orig_tab_layout = method_getImplementation(tm);
            method_setImplementation(tm, (IMP)tab_layout);
        }

        /*
         Add an override ONLY on UITabBarController.
         This avoids modifying UIViewController globally.
        */
        Class tc = UITabBarController.class;
        SEL sel = @selector(viewDidLayoutSubviews);

        Method inherited = class_getInstanceMethod(tc, sel);
        if (inherited) {
            inherited_tabvc_layout = method_getImplementation(inherited);
            const char *types = method_getTypeEncoding(inherited);

            BOOL added = class_addMethod(tc, sel, (IMP)safe_tabvc_layout, types);

            if (!added) {
                /*
                 If UITabBarController already owns an override, replace only
                 its own method after confirming it is present directly.
                */
                unsigned int count = 0;
                Method *methods = class_copyMethodList(tc, &count);
                for (unsigned int i = 0; i < count; i++) {
                    if (method_getName(methods[i]) == sel) {
                        inherited_tabvc_layout = method_getImplementation(methods[i]);
                        method_setImplementation(methods[i], (IMP)safe_tabvc_layout);
                        break;
                    }
                }
                free(methods);
            }
        }
    }
}
