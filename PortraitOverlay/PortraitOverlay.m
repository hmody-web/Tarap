
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static const NSInteger kPortraitTag = 0x53415241; // "SARA"

static BOOL IsSettingsController(UIViewController *vc) {
    NSString *n = NSStringFromClass([vc class]);
    return [n containsString:@"SettingsViewController"];
}

static UIImage *PortraitImage(void) {
    NSBundle *b = [NSBundle bundleForClass:NSClassFromString(@"PortraitOverlayMarker")];
    NSString *p = [b pathForResource:@"portrait" ofType:@"jpeg"];
    UIImage *im = p ? [UIImage imageWithContentsOfFile:p] : nil;
    if (!im) {
        NSString *main = [[NSBundle mainBundle] pathForResource:@"portrait" ofType:@"jpeg"];
        im = main ? [UIImage imageWithContentsOfFile:main] : nil;
    }
    return im;
}

static void AddPortrait(UIViewController *vc) {
    if (!IsSettingsController(vc) || !vc.view || [vc.view viewWithTag:kPortraitTag]) return;
    UIImage *im = PortraitImage();
    if (!im) return;

    UIImageView *iv = [[UIImageView alloc] initWithImage:im];
    iv.tag = kPortraitTag;
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    iv.contentMode = UIViewContentModeScaleAspectFill;
    iv.clipsToBounds = YES;
    iv.userInteractionEnabled = NO;
    iv.layer.cornerRadius = 18.0;
    iv.layer.borderWidth = 0.0;

    // Add above the hosting view, but do not intercept touches.
    [vc.view addSubview:iv];

    // RTL Settings row: icon is on the physical right.
    // The vertical position is intentionally isolated in one constant so it can
    // be adjusted from one screenshot without touching the hook/ABI.
    CGFloat topOffset = 122.0;
    UILayoutGuide *safe = vc.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [iv.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20.0],
        [iv.topAnchor constraintEqualToAnchor:safe.topAnchor constant:topOffset],
        [iv.widthAnchor constraintEqualToConstant:36.0],
        [iv.heightAnchor constraintEqualToConstant:36.0],
    ]];
}

@interface PortraitOverlayMarker : NSObject @end
@implementation PortraitOverlayMarker @end

@implementation UIViewController (TarabPortraitOverlay)
+ (void)load {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Method a = class_getInstanceMethod(self, @selector(viewDidAppear:));
        Method b = class_getInstanceMethod(self, @selector(ts_viewDidAppear:));
        method_exchangeImplementations(a, b);
    });
}
- (void)ts_viewDidAppear:(BOOL)animated {
    [self ts_viewDidAppear:animated];
    if (IsSettingsController(self)) {
        dispatch_async(dispatch_get_main_queue(), ^{ AddPortrait(self); });
    }
}
@end
