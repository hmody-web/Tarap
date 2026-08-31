#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <os/log.h>

static IMP orig_vc_appear = NULL;

static const char *SafeClassName(id obj) {
    if (!obj) return "nil";
    Class c = object_getClass(obj);
    const char *n = class_getName(c);
    return n ? n : "unknown";
}

static void PrintColor(UIColor *c, const char *prefix) {
    if (!c) {
        os_log(OS_LOG_DEFAULT, @"[TarabBottom] %s_color=nil", prefix);
        return;
    }

    CGFloat r=0,g=0,b=0,a=0,w=0;

    if ([c getRed:&r green:&g blue:&b alpha:&a]) {
        os_log(OS_LOG_DEFAULT, @"[TarabBottom] %s_rgba r=%.4f g=%.4f b=%.4f a=%.4f",
              prefix, r,g,b,a);
        return;
    }

    if ([c getWhite:&w alpha:&a]) {
        os_log(OS_LOG_DEFAULT, @"[TarabBottom] %s_wa w=%.4f a=%.4f",
              prefix, w,a);
        return;
    }

    os_log(OS_LOG_DEFAULT, @"[TarabBottom] %s_color=unresolved", prefix);
}

static BOOL InterestingClass(UIView *v) {
    if (!v) return NO;

    const char *cn = SafeClassName(v);
    if (!cn) return NO;

    NSString *n = [NSString stringWithUTF8String:cn];
    if (!n) return NO;

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
        @"Extension",
        @"Hosting",
        @"SafeArea"
    ];

    for (NSString *k in keys) {
        if ([n rangeOfString:k options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }

    return NO;
}

static void DumpOneView(UIView *v, UIWindow *w, NSInteger depth) {
    CGRect r = [v convertRect:v.bounds toView:w];
    CGRect b = v.bounds;
    UIEdgeInsets s = v.safeAreaInsets;

    const char *cls = SafeClassName(v);
    const char *sup = v.superview ? SafeClassName(v.superview) : "nil";

    os_log(OS_LOG_DEFAULT, @"[TarabBottom] VIEW_BEGIN");
    os_log(OS_LOG_DEFAULT, @"[TarabBottom] depth=%ld", (long)depth);
    os_log(OS_LOG_DEFAULT, @"[TarabBottom] class=%{public}s", cls);
    os_log(OS_LOG_DEFAULT, @"[TarabBottom] super=%{public}s", sup);

    os_log(OS_LOG_DEFAULT, @"[TarabBottom] frame x=%.2f y=%.2f w=%.2f h=%.2f",
          r.origin.x, r.origin.y, r.size.width, r.size.height);

    os_log(OS_LOG_DEFAULT, @"[TarabBottom] bounds x=%.2f y=%.2f w=%.2f h=%.2f",
          b.origin.x, b.origin.y, b.size.width, b.size.height);

    os_log(OS_LOG_DEFAULT, @"[TarabBottom] state alpha=%.3f hidden=%d opaque=%d ui=%d clips=%d",
          v.alpha,
          v.hidden,
          v.opaque,
          v.userInteractionEnabled,
          v.clipsToBounds);

    os_log(OS_LOG_DEFAULT, @"[TarabBottom] safe top=%.2f left=%.2f bottom=%.2f right=%.2f",
          s.top, s.left, s.bottom, s.right);

    os_log(OS_LOG_DEFAULT, @"[TarabBottom] subviews=%lu",
          (unsigned long)v.subviews.count);

    PrintColor(v.backgroundColor, "bg");

    if ([v isKindOfClass:[UIVisualEffectView class]]) {
        UIVisualEffectView *ev = (UIVisualEffectView *)v;
        os_log(OS_LOG_DEFAULT, @"[TarabBottom] visual_effect=1");
        os_log(OS_LOG_DEFAULT, @"[TarabBottom] effect_class=%{public}s",
              ev.effect ? SafeClassName(ev.effect) : "nil");
    } else {
        os_log(OS_LOG_DEFAULT, @"[TarabBottom] visual_effect=0");
    }

    if ([v isKindOfClass:[UIScrollView class]]) {
        UIScrollView *sv = (UIScrollView *)v;
        UIEdgeInsets ci = sv.contentInset;
        UIEdgeInsets ai = sv.adjustedContentInset;
        CGSize cs = sv.contentSize;

        os_log(OS_LOG_DEFAULT, @"[TarabBottom] scroll contentSize w=%.2f h=%.2f",
              cs.width, cs.height);

        os_log(OS_LOG_DEFAULT, @"[TarabBottom] scroll contentInset t=%.2f l=%.2f b=%.2f r=%.2f",
              ci.top, ci.left, ci.bottom, ci.right);

        os_log(OS_LOG_DEFAULT, @"[TarabBottom] scroll adjustedInset t=%.2f l=%.2f b=%.2f r=%.2f",
              ai.top, ai.left, ai.bottom, ai.right);
    }

    os_log(OS_LOG_DEFAULT, @"[TarabBottom] VIEW_END");
}

static void DumpBottomViews(UIView *v,
                            UIWindow *window,
                            CGFloat focusTop,
                            NSInteger depth) {
    if (!v || !window || depth > 16) return;

    CGRect r = [v convertRect:v.bounds toView:window];
    CGFloat maxY = r.origin.y + r.size.height;

    BOOL intersectsBottom = maxY >= focusTop;
    BOOL wide = r.size.width >= window.bounds.size.width * 0.60;
    BOOL interesting = InterestingClass(v);

    if (intersectsBottom && (wide || interesting)) {
        DumpOneView(v, window, depth);
    }

    for (UIView *sv in v.subviews) {
        DumpBottomViews(sv, window, focusTop, depth + 1);
    }
}

static void DumpController(UIViewController *vc) {
    if (!vc || !vc.view.window) return;

    UIWindow *w = vc.view.window;
    CGRect r = [vc.view convertRect:vc.view.bounds toView:w];
    UIEdgeInsets s = vc.view.safeAreaInsets;
    UIEdgeInsets a = vc.additionalSafeAreaInsets;

    os_log(OS_LOG_DEFAULT, @"[TarabBottom] PAGE_BEGIN");
    os_log(OS_LOG_DEFAULT, @"[TarabBottom] controller=%{public}s", SafeClassName(vc));
    os_log(OS_LOG_DEFAULT, @"[TarabBottom] controller_frame x=%.2f y=%.2f w=%.2f h=%.2f",
          r.origin.x, r.origin.y, r.size.width, r.size.height);

    os_log(OS_LOG_DEFAULT, @"[TarabBottom] controller_safe t=%.2f l=%.2f b=%.2f r=%.2f",
          s.top,s.left,s.bottom,s.right);

    os_log(OS_LOG_DEFAULT, @"[TarabBottom] controller_additional t=%.2f l=%.2f b=%.2f r=%.2f",
          a.top,a.left,a.bottom,a.right);

    UIViewController *p = vc.parentViewController;
    NSInteger level = 0;

    while (p && level < 8) {
        CGRect pr = p.view.window ? [p.view convertRect:p.view.bounds toView:w] : (CGRect){{0.0,0.0},{0.0,0.0}};
        UIEdgeInsets ps = p.view.safeAreaInsets;
        UIEdgeInsets pa = p.additionalSafeAreaInsets;

        os_log(OS_LOG_DEFAULT, @"[TarabBottom] parent_level=%ld", (long)level);
        os_log(OS_LOG_DEFAULT, @"[TarabBottom] parent_class=%{public}s", SafeClassName(p));
        os_log(OS_LOG_DEFAULT, @"[TarabBottom] parent_frame x=%.2f y=%.2f w=%.2f h=%.2f",
              pr.origin.x,pr.origin.y,pr.size.width,pr.size.height);
        os_log(OS_LOG_DEFAULT, @"[TarabBottom] parent_safe t=%.2f l=%.2f b=%.2f r=%.2f",
              ps.top,ps.left,ps.bottom,ps.right);
        os_log(OS_LOG_DEFAULT, @"[TarabBottom] parent_additional t=%.2f l=%.2f b=%.2f r=%.2f",
              pa.top,pa.left,pa.bottom,pa.right);

        p = p.parentViewController;
        level++;
    }

    CGFloat focusTop = w.bounds.size.height - 320.0;

    os_log(OS_LOG_DEFAULT, @"[TarabBottom] window w=%.2f h=%.2f focusTop=%.2f",
          w.bounds.size.width, w.bounds.size.height, focusTop);

    DumpBottomViews(w, w, focusTop, 0);

    os_log(OS_LOG_DEFAULT, @"[TarabBottom] PAGE_END");
}

static void HookedAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    if (orig_vc_appear) {
        ((void(*)(id,SEL,BOOL))orig_vc_appear)(self, _cmd, animated);
    }

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{
            DumpController(self);
        }
    );
}

__attribute__((constructor))
static void InitRuntimeDiagV93(void) {
    @autoreleasepool {
        Method m = class_getInstanceMethod(
            UIViewController.class,
            @selector(viewDidAppear:)
        );

        if (m) {
            orig_vc_appear = method_getImplementation(m);
            method_setImplementation(m, (IMP)HookedAppear);
        }

        os_log(OS_LOG_DEFAULT, @"[TarabBottom] RuntimeDiag_V9_3_LOADED");
    }
}
