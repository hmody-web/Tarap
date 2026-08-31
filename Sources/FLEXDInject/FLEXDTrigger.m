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
}


#pragma mark - Robust Files UITableView 700 patch

static IMP FLEXDOriginalTableSetFrame = NULL;
static IMP FLEXDOriginalTableSetBounds = NULL;
static IMP FLEXDOriginalTableLayoutSubviews = NULL;

static BOOL FLEXDIsFilesTable(UITableView *table, CGRect frame) {
    // Runtime target discovered with FLEX:
    // UITableView {{0,205},{390,556}}
    // Be intentionally tolerant because UIKit may briefly write intermediate
    // values while laying out the page.
    BOOL widthMatch = fabs(frame.size.width - 390.0) < 3.0;
    BOOL xMatch = fabs(frame.origin.x) < 3.0;
    BOOL yMatch = frame.origin.y > 195.0 && frame.origin.y < 215.0;
    BOOL heightMatch =
        (frame.size.height > 520.0 && frame.size.height < 590.0) ||
        (frame.size.height > 690.0 && frame.size.height < 710.0);

    return widthMatch && xMatch && yMatch && heightMatch;
}

static void FLEXDForceFilesTableHeight(UITableView *table) {
    CGRect frame = table.frame;
    if (!FLEXDIsFilesTable(table, frame)) return;

    if (fabs(frame.size.height - 700.0) > 0.5) {
        frame.size.height = 700.0;
        ((void (*)(id, SEL, CGRect))FLEXDOriginalTableSetFrame)(
            table, @selector(setFrame:), frame
        );
    }

    CGRect bounds = table.bounds;
    if (fabs(bounds.size.height - 700.0) > 0.5) {
        bounds.size.height = 700.0;
        ((void (*)(id, SEL, CGRect))FLEXDOriginalTableSetBounds)(
            table, @selector(setBounds:), bounds
        );
    }
}

static void FLEXDPatchedTableSetFrame(UITableView *self, SEL _cmd, CGRect frame) {
    if (FLEXDIsFilesTable(self, frame)) {
        frame.size.height = 700.0;
    }

    ((void (*)(id, SEL, CGRect))FLEXDOriginalTableSetFrame)(self, _cmd, frame);

    // Enforce again after UIKit accepts the frame.
    FLEXDForceFilesTableHeight(self);
}

static void FLEXDPatchedTableSetBounds(UITableView *self, SEL _cmd, CGRect bounds) {
    CGRect currentFrame = self.frame;

    if (FLEXDIsFilesTable(self, currentFrame) &&
        bounds.size.height > 520.0 &&
        bounds.size.height < 710.0) {
        bounds.size.height = 700.0;
    }

    ((void (*)(id, SEL, CGRect))FLEXDOriginalTableSetBounds)(self, _cmd, bounds);
}

static void FLEXDPatchedTableLayoutSubviews(UITableView *self, SEL _cmd) {
    ((void (*)(id, SEL))FLEXDOriginalTableLayoutSubviews)(self, _cmd);

    // UIKit/Auto Layout may rewrite the geometry during scrolling/layout.
    // Force the exact target back to 700 after EVERY layout pass.
    FLEXDForceFilesTableHeight(self);
}

static void FLEXDInstallFilesTablePatch(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method frameMethod = class_getInstanceMethod(UITableView.class, @selector(setFrame:));
        Method boundsMethod = class_getInstanceMethod(UITableView.class, @selector(setBounds:));
        Method layoutMethod = class_getInstanceMethod(UITableView.class, @selector(layoutSubviews));

        if (!frameMethod || !boundsMethod || !layoutMethod) {
            NSLog(@"[FLEXDInject] Files UITableView patch methods unavailable");
            return;
        }

        FLEXDOriginalTableSetFrame = method_getImplementation(frameMethod);
        FLEXDOriginalTableSetBounds = method_getImplementation(boundsMethod);
        FLEXDOriginalTableLayoutSubviews = method_getImplementation(layoutMethod);

        method_setImplementation(frameMethod, (IMP)FLEXDPatchedTableSetFrame);
        method_setImplementation(boundsMethod, (IMP)FLEXDPatchedTableSetBounds);
        method_setImplementation(layoutMethod, (IMP)FLEXDPatchedTableLayoutSubviews);

        NSLog(@"[FLEXDInject] STRONG Files UITableView patch installed: 556 -> 700");
    });
}

static void FLEXDInstall(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        FLEXDInstallFilesTablePatch();

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
