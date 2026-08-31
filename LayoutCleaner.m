#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static IMP orig_tab_layout = NULL;
static IMP inherited_tabvc_layout = NULL;

/* ---------- Utilities ---------- */

static BOOL NameHas(id obj, NSString *needle) {
    if (!obj) return NO;
    NSString *n = NSStringFromClass(object_getClass(obj));
    return [n rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static void ClearViewVisuals(UIView *v) {
    if (!v) return;
    v.backgroundColor = UIColor.clearColor;
    v.opaque = NO;
}

/* ---------- Remove tab bar backdrop/background layers ---------- */

static void ClearTabBarBackdropTree(UIView *root) {
    if (!root) return;

    for (UIView *v in [root.subviews copy]) {
        BOOL isBackdrop =
            NameHas(v, @"BarBackground") ||
            NameHas(v, @"Backdrop") ||
            NameHas(v, @"VisualEffect") ||
            NameHas(v, @"BackgroundExtension") ||
            NameHas(v, @"BackgroundView");

        if (isBackdrop) {
            ClearViewVisuals(v);

            /*
             Don't hide everything blindly because some iOS 26 glass
             internals may be needed for the actual glass appearance.
             Instead clear the backing color and opacity.
            */
            if ([v isKindOfClass:UIVisualEffectView.class]) {
                UIVisualEffectView *ev = (UIVisualEffectView *)v;
                ev.backgroundColor = UIColor.clearColor;
                ev.contentView.backgroundColor = UIColor.clearColor;
            }
        }

        ClearTabBarBackdropTree(v);
    }
}

static void ConfigureFloatingGlass(UITabBar *tab) {
    if (!tab) return;

    ClearViewVisuals(tab);
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

    ClearTabBarBackdropTree(tab);
}

static void TabLayout(UITabBar *self, SEL _cmd) {
    if (orig_tab_layout) {
        ((void(*)(id,SEL))orig_tab_layout)(self,_cmd);
    }
    ConfigureFloatingGlass(self);
}

/* ---------- Extend selected controller to full tab controller bounds ---------- */

static UIViewController *RealContentController(UIViewController *vc) {
    if (!vc) return nil;

    if ([vc isKindOfClass:UINavigationController.class]) {
        UINavigationController *nav = (UINavigationController *)vc;
        if (nav.topViewController) return nav.topViewController;
    }

    if ([vc isKindOfClass:UISplitViewController.class]) {
        UISplitViewController *split = (UISplitViewController *)vc;
        if (split.viewControllers.count) return split.viewControllers.lastObject;
    }

    return vc;
}

static UIScrollView *FindLargestScrollView(UIView *root) {
    if (!root) return nil;

    __block UIScrollView *best = nil;
    __block CGFloat bestArea = 0;

    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];

    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];

        if ([v isKindOfClass:UIScrollView.class]) {
            CGFloat area = v.bounds.size.width * v.bounds.size.height;
            if (area > bestArea) {
                best = (UIScrollView *)v;
                bestArea = area;
            }
        }

        for (UIView *sv in v.subviews) {
            [stack addObject:sv];
        }
    }

    return best;
}

static void ExtendChildToBottom(UIView *child, UIView *parent) {
    if (!child || !parent) return;

    CGRect f = child.frame;
    CGFloat parentBottom = parent.bounds.origin.y + parent.bounds.size.height;
    CGFloat childTop = f.origin.y;

    CGFloat wantedHeight = parentBottom - childTop;

    if (wantedHeight > 0 && f.size.height < wantedHeight) {
        f.size.height = wantedHeight;
        child.frame = f;
    }

    child.autoresizingMask |= UIViewAutoresizingFlexibleHeight |
                              UIViewAutoresizingFlexibleWidth;
}

static void ClearPossibleBackdropSiblings(UITabBarController *tc) {
    if (!tc || !tc.view) return;

    UITabBar *tab = tc.tabBar;
    UIWindow *w = tc.view.window;
    if (!w) return;

    CGRect tabFrame = [tab convertRect:tab.bounds toView:w];
    CGFloat tabTop = tabFrame.origin.y;

    /*
     Clear only non-interactive wide views occupying the lower region.
     This targets the opaque/backdrop container behind the floating tab bar
     while leaving controls and scroll views alone.
    */
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:w];

    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];

        if (v == tab || v == tc.view) {
            for (UIView *sv in v.subviews) [stack addObject:sv];
            continue;
        }

        if ([v isKindOfClass:UIControl.class] ||
            [v isKindOfClass:UIScrollView.class]) {
            for (UIView *sv in v.subviews) [stack addObject:sv];
            continue;
        }

        CGRect r = [v convertRect:v.bounds toView:w];
        CGFloat maxY = r.origin.y + r.size.height;
        CGFloat screenBottom = w.bounds.origin.y + w.bounds.size.height;

        BOOL wide = r.size.width >= w.bounds.size.width * 0.92;
        BOOL lowerRegion = r.origin.y <= tabTop + 20.0 &&
                           maxY >= tabTop - 120.0;
        BOOL reachesBottom = maxY >= screenBottom - 4.0;
        BOOL looksBackdrop =
            NameHas(v, @"Backdrop") ||
            NameHas(v, @"Background") ||
            NameHas(v, @"Container") ||
            NameHas(v, @"Extension");

        if (wide && lowerRegion && reachesBottom &&
            (looksBackdrop || !v.userInteractionEnabled)) {
            ClearViewVisuals(v);
        }

        for (UIView *sv in v.subviews) {
            [stack addObject:sv];
        }
    }
}

static void ExtendPageBehindTab(UITabBarController *tc) {
    if (!tc) return;

    UIViewController *selected = tc.selectedViewController;
    UIViewController *content = RealContentController(selected);
    if (!selected || !content) return;

    /*
     Remove extra bottom safe area reservation on both container and page.
    */
    selected.additionalSafeAreaInsets = UIEdgeInsetsZero;
    content.additionalSafeAreaInsets = UIEdgeInsetsZero;

    selected.edgesForExtendedLayout = UIRectEdgeAll;
    selected.extendedLayoutIncludesOpaqueBars = YES;
    content.edgesForExtendedLayout = UIRectEdgeAll;
    content.extendedLayoutIncludesOpaqueBars = YES;

    ClearViewVisuals(tc.view);
    if (selected.view) {
        ExtendChildToBottom(selected.view, tc.view);
    }

    if (content.view) {
        ClearViewVisuals(content.view);

        if (content.view.superview) {
            ExtendChildToBottom(content.view, content.view.superview);
        }

        UIScrollView *scroll = FindLargestScrollView(content.view);

        if (scroll && scroll.superview) {
            ExtendChildToBottom(scroll, scroll.superview);

            /*
             Keep the content itself under the bar.
             The extra contentInset prevents the last item from being
             impossible to reach, but the background still continues behind.
            */
            UIEdgeInsets inset = scroll.contentInset;
            CGFloat barH = tc.tabBar.bounds.size.height;
            CGFloat safeB = tc.view.safeAreaInsets.bottom;

            if (inset.bottom < barH + safeB) {
                inset.bottom = barH + safeB;
                scroll.contentInset = inset;
            }

            if (@available(iOS 13.0, *)) {
                UIEdgeInsets vi = scroll.verticalScrollIndicatorInsets;
                vi.bottom = barH + safeB;
                scroll.verticalScrollIndicatorInsets = vi;
            }
        }
    }

    ConfigureFloatingGlass(tc.tabBar);
    ClearPossibleBackdropSiblings(tc);

    [tc.view bringSubviewToFront:tc.tabBar];
}

static void TabVCLayout(UITabBarController *self, SEL _cmd) {
    if (inherited_tabvc_layout) {
        ((void(*)(id,SEL))inherited_tabvc_layout)(self,_cmd);
    }

    ExtendPageBehindTab(self);

    dispatch_async(dispatch_get_main_queue(), ^{
        ExtendPageBehindTab(self);
    });
}

/* ---------- Safe per-class override ---------- */

__attribute__((constructor))
static void InitV7(void) {
    @autoreleasepool {
        Method tm = class_getInstanceMethod(UITabBar.class,
                                            @selector(layoutSubviews));
        if (tm) {
            orig_tab_layout = method_getImplementation(tm);
            method_setImplementation(tm, (IMP)TabLayout);
        }

        Class tc = UITabBarController.class;
        SEL sel = @selector(viewDidLayoutSubviews);
        Method inherited = class_getInstanceMethod(tc, sel);

        if (inherited) {
            inherited_tabvc_layout = method_getImplementation(inherited);
            const char *types = method_getTypeEncoding(inherited);

            if (!class_addMethod(tc, sel, (IMP)TabVCLayout, types)) {
                unsigned int count = 0;
                Method *methods = class_copyMethodList(tc, &count);

                for (unsigned int i=0; i<count; i++) {
                    if (method_getName(methods[i]) == sel) {
                        inherited_tabvc_layout =
                            method_getImplementation(methods[i]);
                        method_setImplementation(methods[i],
                                                 (IMP)TabVCLayout);
                        break;
                    }
                }

                free(methods);
            }
        }
    }
}
