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

static void AppendLine(NSMutableString *out, NSString *line) {
    [out appendString:line ?: @""];
    [out appendString:@"\n"];
}

static void DumpViewTree(UIView *v,
                         UIWindow *window,
                         NSMutableString *out,
                         NSInteger depth,
                         CGFloat focusTop) {
    if (!v || !window || depth > 12) return;

    CGRect wr = [v convertRect:v.bounds toView:window];
    CGFloat maxY = wr.origin.y + wr.size.height;

    BOOL intersectsBottomZone = maxY >= focusTop;

    if (intersectsBottomZone) {
        NSString *indent = [@"" stringByPaddingToLength:(NSUInteger)(depth*2)
                                              withString:@" "
                                         startingAtIndex:0];

        NSString *cls = NSStringFromClass(v.class);
        NSString *sup = v.superview ? NSStringFromClass(v.superview.class) : @"nil";

        AppendLine(out, [NSString stringWithFormat:
            @"%@VIEW class=%@ super=%@ frameWin=[%@] bounds=[%@] bg=%@ alpha=%.3f hidden=%d opaque=%d ui=%d safe=[%@] subviews=%lu",
            indent,
            cls,
            sup,
            RectDesc(wr),
            RectDesc(v.bounds),
            ColorDesc(v.backgroundColor),
            v.alpha,
            v.hidden,
            v.opaque,
            v.userInteractionEnabled,
            InsetsDesc(v.safeAreaInsets),
            (unsigned long)v.subviews.count
        ]);
    }

    for (UIView *sv in v.subviews) {
        DumpViewTree(sv, window, out, depth+1, focusTop);
    }
}

static void WriteReportForController(UIViewController *vc) {
    if (!vc.view.window) return;

    UIWindow *w = vc.view.window;
    CGRect wb = w.bounds;

    CGFloat focusTop = wb.origin.y + wb.size.height - 320.0;

    NSMutableString *out = [NSMutableString string];

    AppendLine(out, @"===== TARAB RUNTIME DIAGNOSTIC V9 =====");
    AppendLine(out, [NSString stringWithFormat:@"controller=%@", NSStringFromClass(vc.class)]);
    AppendLine(out, [NSString stringWithFormat:@"window=%@", RectDesc(wb)]);
    AppendLine(out, [NSString stringWithFormat:@"controllerView=%@", RectDesc([vc.view convertRect:vc.view.bounds toView:w])]);
    AppendLine(out, [NSString stringWithFormat:@"controllerSafe=%@", InsetsDesc(vc.view.safeAreaInsets)]);
    AppendLine(out, [NSString stringWithFormat:@"additionalSafe=%@", InsetsDesc(vc.additionalSafeAreaInsets)]);
    AppendLine(out, [NSString stringWithFormat:@"focusTop=%.1f", focusTop]);
    AppendLine(out, @"");

    UIViewController *p = vc.parentViewController;
    NSInteger level = 0;
    while (p && level < 8) {
        AppendLine(out, [NSString stringWithFormat:
            @"PARENT[%ld]=%@ view=%@ safe=%@ additional=%@",
            (long)level,
            NSStringFromClass(p.class),
            p.view.window ? RectDesc([p.view convertRect:p.view.bounds toView:w]) : @"nil",
            InsetsDesc(p.view.safeAreaInsets),
            InsetsDesc(p.additionalSafeAreaInsets)
        ]);
        p = p.parentViewController;
        level++;
    }

    AppendLine(out, @"");
    AppendLine(out, @"----- WINDOW VIEW TREE (BOTTOM ZONE) -----");
    DumpViewTree(w, w, out, 0, focusTop);

    AppendLine(out, @"");
    AppendLine(out, @"----- CONTROLLER VIEW TREE (BOTTOM ZONE) -----");
    DumpViewTree(vc.view, w, out, 0, focusTop);

    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory,
        NSUserDomainMask,
        YES
    );

    NSString *docs = paths.firstObject;
    if (!docs) return;

    NSString *safeName = [NSStringFromClass(vc.class)
        stringByReplacingOccurrencesOfString:@"/" withString:@"_"];

    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.dateFormat = @"yyyyMMdd_HHmmss_SSS";

    NSString *name = [NSString stringWithFormat:
        @"TarabDiag_%@_%@.txt",
        safeName,
        [fmt stringFromDate:[NSDate date]]
    ];

    NSString *path = [docs stringByAppendingPathComponent:name];

    NSError *err = nil;
    [out writeToFile:path
          atomically:YES
            encoding:NSUTF8StringEncoding
               error:&err];

    NSLog(@"[TarabDiag] report=%@ error=%@", path, err);
}

static void HookedAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    if (orig_vc_appear) {
        ((void(*)(id,SEL,BOOL))orig_vc_appear)(self,_cmd,animated);
    }

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{
            WriteReportForController(self);
        }
    );
}

__attribute__((constructor))
static void InitRuntimeDiagV9(void) {
    @autoreleasepool {
        /*
          Diagnostic only:
          hook viewDidAppear globally because it does not alter layout.
          It only records runtime geometry after each page is already visible.
        */
        Method m = class_getInstanceMethod(
            UIViewController.class,
            @selector(viewDidAppear:)
        );

        if (m) {
            orig_vc_appear = method_getImplementation(m);
            method_setImplementation(m, (IMP)HookedAppear);
        }
    }
}
