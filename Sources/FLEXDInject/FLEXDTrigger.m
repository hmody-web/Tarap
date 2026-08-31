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
    if (FLEXDClassIsUpdateCoalescing(self)) {
        // Patch A:
        // The four nested views in the Sources app-list section all resolve
        // to the same runtime collection-view family around 358 x 257.
        // Force any matching 358-wide, ~257-high frame to 450.
        if (fabs(frame.size.width - 358.0) < 2.0 &&
            frame.size.height > 245.0 &&
            frame.size.height < 275.0) {
            frame.size.height = 450.0;
        }

        // Patch B:
        // The larger page collection previously discovered at 390 x 701
        // must remain 855 even after SwiftUI relayout/scroll.
        if (fabs(frame.size.width - 390.0) < 2.0 &&
            frame.size.height > 680.0 &&
            frame.size.height < 720.0) {
            frame.size.height = 855.0;
        }
    }

    ((void (*)(id, SEL, CGRect))FLEXDOriginalUIViewSetFrame)(self, _cmd, frame);
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

        NSLog(@"[FLEXDInject] Tarab patches installed: 358x~257 -> 450, 390x~701 -> 855");
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
