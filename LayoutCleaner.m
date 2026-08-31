#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static IMP orig_mk_layout = NULL;
static IMP orig_mk_safearea = NULL;
static IMP orig_tab_layout = NULL;

static BOOL NameHas(id obj, NSString *needle) {
    if (!obj) return NO;
    NSString *n = NSStringFromClass(object_getClass(obj));
    return [n rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static BOOL LooksLikeBar(UIView *v) {
    if (!v) return NO;

    if ([v isKindOfClass:UITabBar.class]) return YES;

    return NameHas(v, @"TabBar") ||
           NameHas(v, @"BarView") ||
           NameHas(v, @"LiquidGlass") ||
           NameHas(v, @"Glass");
}

static void MakeClear(UIView *v) {
    if (!v) return;
    v.backgroundColor = UIColor.clearColor;
    v.opaque = NO;
}

static void ConfigureGlass(UITabBar *tab) {
    if (!tab) return;

    MakeClear(tab);
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
    if (orig_tab_layout) {
        ((void(*)(id,SEL))orig_tab_layout)(self,_cmd);
    }
    ConfigureGlass(self);
}

static UIScrollView *LargestScrollView(UIView *root) {
    if (!root) return nil;

    UIScrollView *best = nil;
    CGFloat bestArea = 0;

    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];

    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];

        if ([v isKindOfClass:UIScrollView.class]) {
            CGFloat area = v.bounds.size.width * v.bounds.size.height;
            if (area > bestArea) {
                bestArea = area;
                best = (UIScrollView *)v;
            }
        }

        for (UIView *sv in v.subviews) {
            [stack addObject:sv];
        }
    }

    return best;
}

static void ExtendViewToParentBottom(UIView *v) {
    if (!v || !v.superview) return;

    UIView *p = v.superview;

    CGRect f = v.frame;
    CGFloat parentBottom = p.bounds.origin.y + p.bounds.size.height;
    CGFloat wantedHeight = parentBottom - f.origin.y;

    if (wantedHeight > 0 && f.size.height < wantedHeight) {
        f.size.height = wantedHeight;
        v.frame = f;
    }

    v.autoresizingMask |= UIViewAutoresizingFlexibleHeight |
                          UIViewAutoresizingFlexibleWidth;
}

/*
  Main MKTabBar fix:
  - clear only the controller/container backgrounds
  - extend content containers to the real bottom
  - do NOT resize/hide the actual tab bar
*/
static void FixMKHierarchy(UIViewController *vc) {
    if (!vc || !vc.view) return;

    UIView *root = vc.view;

    vc.additionalSafeAreaInsets = UIEdgeInsetsZero;
    vc.edgesForExtendedLayout = UIRectEdgeAll;
    vc.extendedLayoutIncludesOpaqueBars = YES;

    MakeClear(root);

    UIWindow *window = root.window;
    CGFloat screenBottom = root.bounds.origin.y + root.bounds.size.height;

    /*
      Direct children are especially important in MKTabBarViewController:
      one is usually the content/container, another is the bar.
    */
    for (UIView *child in [root.subviews copy]) {
        if (LooksLikeBar(child)) {
            if ([child isKindOfClass:UITabBar.class]) {
                ConfigureGlass((UITabBar *)child);
            }
            continue;
        }

        CGRect f = child.frame;

        BOOL wide = f.size.width >= root.bounds.size.width * 0.80;
        BOOL contentLike =
            [child isKindOfClass:UIScrollView.class] ||
            NameHas(child, @"Container") ||
            NameHas(child, @"Content") ||
            NameHas(child, @"Transition") ||
            NameHas(child, @"Wrapper") ||
            NameHas(child, @"View");

        if (wide && contentLike) {
            CGFloat wantedHeight = screenBottom - f.origin.y;

            if (wantedHeight > 0 && f.size.height < wantedHeight) {
                f.size.height = wantedHeight;
                child.frame = f;
            }

            child.autoresizingMask |= UIViewAutoresizingFlexibleHeight |
                                      UIViewAutoresizingFlexibleWidth;

            if (!LooksLikeBar(child)) {
                MakeClear(child);
            }
        }
    }

    /*
      Extend child controller views too. This is safer than touching all
      UIViewControllers globally because it is scoped to MKTabBarVC's children.
    */
    for (UIViewController *childVC in vc.childViewControllers) {
        childVC.additionalSafeAreaInsets = UIEdgeInsetsZero;
        childVC.edgesForExtendedLayout = UIRectEdgeAll;
        childVC.extendedLayoutIncludesOpaqueBars = YES;

        if (!childVC.view) continue;

        ExtendViewToParentBottom(childVC.view);

        UIScrollView *scroll = LargestScrollView(childVC.view);

        if (scroll && scroll.superview) {
            ExtendViewToParentBottom(scroll);

            /*
              Keep bottom items reachable while background/content extends
              under the floating bar.
            */
            CGFloat barHeight = 0;

            for (UIView *v in root.subviews) {
                if (LooksLikeBar(v)) {
                    if (v.bounds.size.height > barHeight) {
                        barHeight = v.bounds.size.height;
                    }
                }
            }

            if (barHeight < 44.0) barHeight = 88.0;

            UIEdgeInsets inset = scroll.contentInset;
            if (inset.bottom < barHeight) {
                inset.bottom = barHeight;
                scroll.contentInset = inset;
            }

            if (@available(iOS 13.0, *)) {
                UIEdgeInsets ind = scroll.verticalScrollIndicatorInsets;
                ind.bottom = barHeight;
                scroll.verticalScrollIndicatorInsets = ind;
            }
        }
    }

    /*
      Clear only background-ish lower siblings inside MKTabBar root.
      This specifically attacks the large opaque reserve behind the bar.
    */
    for (UIView *v in [root.subviews copy]) {
        if (LooksLikeBar(v)) continue;

        CGRect r = v.frame;
        CGFloat maxY = r.origin.y + r.size.height;

        BOOL lower = maxY >= screenBottom - 4.0;
        BOOL wide = r.size.width >= root.bounds.size.width * 0.90;
        BOOL bgLike =
            NameHas(v, @"Background") ||
            NameHas(v, @"Backdrop") ||
            NameHas(v, @"Extension");

        if (lower && wide && bgLike) {
            MakeClear(v);
        }
    }

    /*
      Keep all detected bars above content after resizing.
    */
    for (UIView *v in [root.subviews copy]) {
        if (LooksLikeBar(v)) {
            [root bringSubviewToFront:v];
        }
    }

    if (window) {
        [window setNeedsLayout];
    }
}

static void MKLayout(id self, SEL _cmd) {
    if (orig_mk_layout) {
        ((void(*)(id,SEL))orig_mk_layout)(self,_cmd);
    }

    FixMKHierarchy((UIViewController *)self);

    dispatch_async(dispatch_get_main_queue(), ^{
        FixMKHierarchy((UIViewController *)self);
    });
}

static void MKSafeAreaChanged(id self, SEL _cmd) {
    if (orig_mk_safearea) {
        ((void(*)(id,SEL))orig_mk_safearea)(self,_cmd);
    }

    UIViewController *vc = (UIViewController *)self;
    vc.additionalSafeAreaInsets = UIEdgeInsetsZero;

    FixMKHierarchy(vc);
}

static void InstallOverride(Class cls,
                            SEL sel,
                            IMP replacement,
                            IMP *originalOut) {
    if (!cls) return;

    Method inherited = class_getInstanceMethod(cls, sel);
    if (!inherited) return;

    IMP inheritedIMP = method_getImplementation(inherited);
    const char *types = method_getTypeEncoding(inherited);

    /*
      First try to add an override owned by MKTabBarViewController.
      This avoids mutating UIViewController globally if the method is inherited.
    */
    if (class_addMethod(cls, sel, replacement, types)) {
        if (originalOut) *originalOut = inheritedIMP;
        return;
    }

    /*
      If the class already owns the method, replace ONLY the method in the
      class's own method list.
    */
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);

    for (unsigned int i=0; i<count; i++) {
        if (method_getName(methods[i]) == sel) {
            if (originalOut) {
                *originalOut = method_getImplementation(methods[i]);
            }
            method_setImplementation(methods[i], replacement);
            break;
        }
    }

    free(methods);
}

__attribute__((constructor))
static void InitMKTabBarFixV8(void) {
    @autoreleasepool {
        /*
          Actual class found in Tarab:
          MKTabBarViewController
        */
        Class mk = objc_getClass("MKTabBarViewController");

        if (mk) {
            InstallOverride(
                mk,
                @selector(viewDidLayoutSubviews),
                (IMP)MKLayout,
                &orig_mk_layout
            );

            InstallOverride(
                mk,
                @selector(viewSafeAreaInsetsDidChange),
                (IMP)MKSafeAreaChanged,
                &orig_mk_safearea
            );
        }

        /*
          Preserve the glass appearance of the system UITabBar itself.
        */
        Method tabLayout = class_getInstanceMethod(
            UITabBar.class,
            @selector(layoutSubviews)
        );

        if (tabLayout) {
            orig_tab_layout = method_getImplementation(tabLayout);
            method_setImplementation(tabLayout, (IMP)TabLayout);
        }
    }
}
