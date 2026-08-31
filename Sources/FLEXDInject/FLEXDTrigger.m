#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static char kFLEXDGestureKey;

static void FLEXDShowExplorer(void) {
    Class managerClass = NSClassFromString(@"FLEXManager");
    if (!managerClass) {
        NSLog(@"[FLEXDInject] FLEXManager class not found");
        return;
    }

    SEL sharedSel = sel_registerName("sharedManager");
    SEL showSel = sel_registerName("showExplorer");

    if (![managerClass respondsToSelector:sharedSel]) {
        NSLog(@"[FLEXDInject] sharedManager selector unavailable");
        return;
    }

    id manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, sharedSel);
    if (!manager) {
        NSLog(@"[FLEXDInject] FLEXManager sharedManager returned nil");
        return;
    }

    if (![manager respondsToSelector:showSel]) {
        NSLog(@"[FLEXDInject] showExplorer selector unavailable");
        return;
    }

    ((void (*)(id, SEL))objc_msgSend)(manager, showSel);
}

@interface FLEXDTrigger : NSObject
+ (instancetype)shared;
- (void)installOnAllWindows;
- (void)installOnWindow:(UIWindow *)window;
- (void)handleGesture:(UILongPressGestureRecognizer *)gesture;
@end

@implementation FLEXDTrigger

+ (instancetype)shared {
    static FLEXDTrigger *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [FLEXDTrigger new];
    });
    return instance;
}

- (void)installOnWindow:(UIWindow *)window {
    if (!window) return;
    if (objc_getAssociatedObject(window, &kFLEXDGestureKey)) return;

    UILongPressGestureRecognizer *gesture =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                     action:@selector(handleGesture:)];

    gesture.minimumPressDuration = 0.45;
    gesture.numberOfTouchesRequired = 3;
    gesture.cancelsTouchesInView = NO;
    gesture.delaysTouchesBegan = NO;
    gesture.delaysTouchesEnded = NO;

    [window addGestureRecognizer:gesture];
    objc_setAssociatedObject(
        window,
        &kFLEXDGestureKey,
        gesture,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}

- (void)installOnAllWindows {
    UIApplication *app = UIApplication.sharedApplication;

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;

            for (UIWindow *window in windowScene.windows) {
                [self installOnWindow:window];
            }
        }
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *window in app.windows) {
        [self installOnWindow:window];
    }
#pragma clang diagnostic pop
}

- (void)handleGesture:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    FLEXDShowExplorer();
}

@end



#pragma mark - Tarab permanent SwiftUI height patches

static IMP FLEXDOriginalUIViewSetFrame = NULL;

static BOOL FLEXDClassIsUpdateCoalescing(UIView *view) {
    NSString *className = NSStringFromClass(view.class);
    return [className containsString:@"UpdateCoalescingCollectionView"];
}

static void FLEXDPatchedUIViewSetFrame(UIView *self, SEL _cmd, CGRect frame) {
    NSString *className = NSStringFromClass(self.class);

    // Patch A:
    // FLEX shows FOUR nested objects for this Sources list, including
    // SwiftUI._UIInheritedView and SwiftUI.UpdateCoalescingCollectionView.
    // Force ALL of the matching 358 x ~257 wrappers to 450.
    BOOL isSourcesListWrapper =
        [className containsString:@"_UIInheritedView"] ||
        [className containsString:@"UpdateCoalescingCollectionView"];

    if (isSourcesListWrapper &&
        fabs(frame.size.width - 358.0) < 2.0 &&
        frame.size.height > 245.0 &&
        frame.size.height < 275.0) {
        frame.size.height = 450.0;
    }

    // Patch B: preserve previous V5 modification.
    // UpdateCoalescingCollectionView 390 x ~701 -> 855.
    if (FLEXDClassIsUpdateCoalescing(self) &&
        fabs(frame.size.width - 390.0) < 2.0 &&
        frame.size.height > 680.0 &&
        frame.size.height < 720.0) {
        frame.size.height = 855.0;
    }

    ((void (*)(id, SEL, CGRect))FLEXDOriginalUIViewSetFrame)(self, _cmd, frame);
}


#pragma mark - Direct SwiftUI class hooks (V7)

static IMP FLEXDOriginalInheritedSetFrame = NULL;
static IMP FLEXDOriginalInheritedSetBounds = NULL;
static IMP FLEXDOriginalUpdateSetFrame = NULL;
static IMP FLEXDOriginalUpdateSetBounds = NULL;

static BOOL FLEXDInheritedHooksInstalled = NO;
static BOOL FLEXDUpdateHooksInstalled = NO;

static BOOL FLEXDIs358x257(CGRect rect) {
    return fabs(rect.size.width - 358.0) < 2.0 &&
           rect.size.height > 245.0 &&
           rect.size.height < 275.0;
}

static BOOL FLEXDIs390x701(CGRect rect) {
    return fabs(rect.size.width - 390.0) < 2.0 &&
           rect.size.height > 680.0 &&
           rect.size.height < 720.0;
}

static void FLEXDInheritedSetFrame(id self, SEL _cmd, CGRect frame) {
    if (FLEXDIs358x257(frame)) {
        frame.size.height = 450.0;
    }

    if (FLEXDOriginalInheritedSetFrame) {
        ((void (*)(id, SEL, CGRect))FLEXDOriginalInheritedSetFrame)(self, _cmd, frame);
    }
}

static void FLEXDInheritedSetBounds(id self, SEL _cmd, CGRect bounds) {
    if (FLEXDIs358x257(bounds)) {
        bounds.size.height = 450.0;
    }

    if (FLEXDOriginalInheritedSetBounds) {
        ((void (*)(id, SEL, CGRect))FLEXDOriginalInheritedSetBounds)(self, _cmd, bounds);
    }
}

static void FLEXDUpdateSetFrame(id self, SEL _cmd, CGRect frame) {
    if (FLEXDIs358x257(frame)) {
        frame.size.height = 450.0;
    } else if (FLEXDIs390x701(frame)) {
        frame.size.height = 855.0;
    }

    if (FLEXDOriginalUpdateSetFrame) {
        ((void (*)(id, SEL, CGRect))FLEXDOriginalUpdateSetFrame)(self, _cmd, frame);
    }
}

static void FLEXDUpdateSetBounds(id self, SEL _cmd, CGRect bounds) {
    if (FLEXDIs358x257(bounds)) {
        bounds.size.height = 450.0;
    } else if (FLEXDIs390x701(bounds)) {
        bounds.size.height = 855.0;
    }

    if (FLEXDOriginalUpdateSetBounds) {
        ((void (*)(id, SEL, CGRect))FLEXDOriginalUpdateSetBounds)(self, _cmd, bounds);
    }
}

static BOOL FLEXDInstallMethodHook(Class cls, SEL selector, IMP replacement, IMP *originalOut) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return NO;

    IMP original = class_getMethodImplementation(cls, selector);
    const char *types = method_getTypeEncoding(method);

    // If this class inherits the method, add an override only to this class.
    if (class_addMethod(cls, selector, replacement, types)) {
        *originalOut = original;
        return YES;
    }

    // If it already owns the method, replace only that class implementation.
    Method ownedMethod = class_getInstanceMethod(cls, selector);
    if (!ownedMethod) return NO;

    *originalOut = method_getImplementation(ownedMethod);
    method_setImplementation(ownedMethod, replacement);
    return YES;
}

static void FLEXDInstallDirectSwiftUIHooks(void) {
    if (!FLEXDInheritedHooksInstalled) {
        Class inheritedClass = NSClassFromString(@"SwiftUI._UIInheritedView");
        if (inheritedClass) {
            BOOL frameOK = FLEXDInstallMethodHook(
                inheritedClass,
                @selector(setFrame:),
                (IMP)FLEXDInheritedSetFrame,
                &FLEXDOriginalInheritedSetFrame
            );

            BOOL boundsOK = FLEXDInstallMethodHook(
                inheritedClass,
                @selector(setBounds:),
                (IMP)FLEXDInheritedSetBounds,
                &FLEXDOriginalInheritedSetBounds
            );

            if (frameOK && boundsOK) {
                FLEXDInheritedHooksInstalled = YES;
                NSLog(@"[FLEXDInject] DIRECT SwiftUI._UIInheritedView hook installed: 358x257 -> 450");
            }
        }
    }

    if (!FLEXDUpdateHooksInstalled) {
        Class updateClass = NSClassFromString(@"SwiftUI.UpdateCoalescingCollectionView");
        if (updateClass) {
            BOOL frameOK = FLEXDInstallMethodHook(
                updateClass,
                @selector(setFrame:),
                (IMP)FLEXDUpdateSetFrame,
                &FLEXDOriginalUpdateSetFrame
            );

            BOOL boundsOK = FLEXDInstallMethodHook(
                updateClass,
                @selector(setBounds:),
                (IMP)FLEXDUpdateSetBounds,
                &FLEXDOriginalUpdateSetBounds
            );

            if (frameOK && boundsOK) {
                FLEXDUpdateHooksInstalled = YES;
                NSLog(@"[FLEXDInject] DIRECT UpdateCoalescing hook installed: 358x257 -> 450; 390x701 -> 855");
            }
        }
    }
}


static void FLEXDInstallHeightPatch(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method method = class_getInstanceMethod(UIView.class, @selector(setFrame:));
        if (!method) {
            NSLog(@"[FLEXDInject] setFrame: not found");
            return;
        }

        FLEXDOriginalUIViewSetFrame = method_getImplementation(method);
        method_setImplementation(method, (IMP)FLEXDPatchedUIViewSetFrame);

        NSLog(@"[FLEXDInject] Tarab patches installed: all Sources 358x~257 wrappers -> 450, UpdateCoalescing 390x~701 -> 855");
    });

    // V7: Directly hook the private SwiftUI classes too, because
    // SwiftUI._UIInheritedView overrides its own geometry setters and can
    // bypass UIView's setFrame: implementation.
    FLEXDInstallDirectSwiftUIHooks();

    // Retry after SwiftUI finishes loading/constructing its internal classes.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        FLEXDInstallDirectSwiftUIHooks();
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        FLEXDInstallDirectSwiftUIHooks();
    });
}

static void FLEXDInstall(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        FLEXDInstallHeightPatch();

        FLEXDTrigger *trigger = [FLEXDTrigger shared];
        [trigger installOnAllWindows];

        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification *note) {
            [trigger installOnAllWindows];
        }];

        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIWindowDidBecomeKeyNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *note) {
            if ([note.object isKindOfClass:UIWindow.class]) {
                [trigger installOnWindow:(UIWindow *)note.object];
            }
        }];
    });
}

__attribute__((constructor))
static void FLEXDConstructor(void) {
    FLEXDInstall();
}
