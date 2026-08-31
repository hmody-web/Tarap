#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static IMP orig_vc_appear = NULL;

static NSString *ColorDesc(UIColor *c) {
    if (!c) return @"nil";

    CGFloat r=0,g=0,b=0,a=0;
    if ([c getRed:&r green:&g blue:&b alpha:&a]) {
        return [NSString stringWithFormat:@"rgba(%.3f,%.3f,%.3f,%.3f)",r,g,b,a];
    }

    CGFloat w=0;
    if ([c getWhite:&w alpha:&a]) {
        return [NSString stringWithFormat:@"wa(%.3f,%.3f)",w,a];
    }

    return c.description ?: @"unknown";
}

static NSString *RectDesc(CGRect r) {
    return [NSString stringWithFormat:
        @"x=%.1f y=%.1f w=%.1f h=%.1f",
        r.origin.x, r.origin.y, r.size.width, r.size.height
    ];
}

static NSString *InsetsDesc(UIEdgeInsets i) {
    return [NSString stringWithFormat:
        @"t=%.1f l=%.1f b=%.1f r=%.1f",
        i.top, i.left, i.bottom, i.right
    ];
}

static BOOL InterestingClass(UIView *v) {
    if (!v) return NO;

    NSString *n = NSStringFromClass(v.class);

    NSArray *keys = @[
        @"Tab",
        @"Bar",
        @"Background",
        @"Backdrop",
        @"Container",
        @"VisualEffect",
        @"Scroll",
        @"Collection",
        @"Table",
        @"Transition",
        @"Wrapper",
        @"Content",
        @"Extension"
    ];

    for (NSString *k in keys) {
        if ([n rangeOfString:k options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }

    return NO;
}

static void DumpBottomViews(UIView *v,
                            UIWindow *window,
                            CGFloat focusTop,
                            NSInteger depth) {
    if (!v || !window || depth > 14) return;

    CGRect r = [v convertRect:v.bounds toView:window];
    CGFloat maxY = r.origin.y + r.size.height;

    BOOL intersectsBottom = maxY >= focusTop;
    BOOL wide = r.size.width >= window.bounds.size.width * 0.70;
    BOOL interesting = InterestingClass(v);

    if (intersectsBottom && (wide || interesting)) {
        NSString *cls = NSStringFromClass(v.class);
        NSString *sup = v.superview ? NSStringFromClass(v.superview.class) : @"nil";

        NSLog(
            @"[TarabBottom] depth=%ld class=%@ super=%@ frame=[%@] bounds=[%@] bg=%@ alpha=%.3f hidden=%d opaque=%d ui=%d safe=[%@] subviews=%lu",
            (long)depth,
            cls,
            sup,
            RectDesc(r),
            RectDesc(v.bounds),
            ColorDesc(v.backgroundColor),
            v.alpha,
            v.hidden,
            v.opaque,
            v.userInteractionEnabled,
            InsetsDesc(v.safeAreaInsets),
            (unsigned long)v.subviews.count
        );
    }

    for (UIView *sv in v.subviews) {
        DumpBottomViews(sv, window, focusTop, depth + 1);
    }
}

static void DumpControllerChain(UIViewController *vc) {
    if (!vc || !vc.view.window) return;

    UIWindow *w = vc.view.window;

    NSLog(
        @"[TarabBottom] ===== controller=%@ view=[%@] safe=[%@] additional=[%@] =====",
        NSStringFromClass(vc.class),
        RectDesc([vc.view convertRect:vc.view.bounds toView:w]),
        InsetsDesc(vc.view.safeAreaInsets),
        InsetsDesc(vc.additionalSafeAreaInsets)
    );

    UIViewController *p = vc.parentViewController;
    NSInteger level = 0;

    while (p && level < 8) {
        NSLog(
            @"[TarabBottom] parent[%ld]=%@ view=[%@] safe=[%@] additional=[%@]",
            (long)level,
            NSStringFromClass(p.class),
            p.view.window ? RectDesc([p.view convertRect:p.view.bounds toView:w]) : @"nil",
            InsetsDesc(p.view.safeAreaInsets),
            InsetsDesc(p.additionalSafeAreaInsets)
        );

        p = p.parentViewController;
        level++;
    }
}

static void DumpBottomDiagnostic(UIViewController *vc) {
    if (!vc || !vc.view.window) return;

    UIWindow *w = vc.view.window;
    CGFloat screenBottom = w.bounds.origin.y + w.bounds.size.height;
    CGFloat focusTop = screenBottom - 300.0;

    NSLog(@"[TarabBottom] >>> BEGIN PAGE %@", NSStringFromClass(vc.class));

    DumpControllerChain(vc);

    NSLog(
        @"[TarabBottom] window=[%@] focusTop=%.1f",
        RectDesc(w.bounds),
        focusTop
    );

    DumpBottomViews(w, w, focusTop, 0);

    NSLog(@"[TarabBottom] <<< END PAGE %@", NSStringFromClass(vc.class));
}

static void HookedAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    if (orig_vc_appear) {
        ((void(*)(id,SEL,BOOL))orig_vc_appear)(self, _cmd, animated);
    }

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{
            DumpBottomDiagnostic(self);
        }
    );
}

__attribute__((constructor))
static void InitRuntimeDiagV92(void) {
    @autoreleasepool {
        Method m = class_getInstanceMethod(
            UIViewController.class,
            @selector(viewDidAppear:)
        );

        if (m) {
            orig_vc_appear = method_getImplementation(m);
            method_setImplementation(m, (IMP)HookedAppear);
        }

        NSLog(@"[TarabBottom] RuntimeDiag V9.2 loaded");
    }
}
