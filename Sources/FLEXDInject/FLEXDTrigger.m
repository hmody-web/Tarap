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

    // Patch B: preserve previous V5/V6 modification.
    // UpdateCoalescingCollectionView 390 x ~701 -> 855.
    if (FLEXDClassIsUpdateCoalescing(self) &&
        fabs(frame.size.width - 390.0) < 2.0 &&
        frame.size.height > 680.0 &&
        frame.size.height < 720.0) {
        frame.size.height = 855.0;
    }

    // Patch C: Files page table discovered in FLEX.
    // UITableView frame {{0,205},{390,556}} -> force height 700.
    // Reapplied on every setFrame so UIKit cannot restore 556.
    if ([self isKindOfClass:UITableView.class] &&
        fabs(frame.origin.x - 0.0) < 2.0 &&
        fabs(frame.origin.y - 205.0) < 4.0 &&
        fabs(frame.size.width - 390.0) < 2.0 &&
        frame.size.height > 545.0 &&
        frame.size.height < 570.0) {
        frame.size.height = 700.0;
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

        NSLog(@"[FLEXDInject] Tarab patches installed: Sources -> 450, UpdateCoalescing 701 -> 855, Files UITableView 556 -> 700");
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
