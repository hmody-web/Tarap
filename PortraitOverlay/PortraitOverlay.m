
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static const NSInteger kPortraitTag = 0x53415241;

static BOOL IsSettingsController(UIViewController *vc) {
    return [NSStringFromClass([vc class]) containsString:@"SettingsViewController"];
}

static UIScrollView *FindScrollView(UIView *v) {
    if ([v isKindOfClass:[UIScrollView class]]) return (UIScrollView *)v;
    for (UIView *s in v.subviews) {
        UIScrollView *r = FindScrollView(s);
        if (r) return r;
    }
    return nil;
}

static UIImage *PortraitImage(void) {
    NSBundle *b=[NSBundle bundleForClass:NSClassFromString(@"PortraitOverlayMarker")];
    NSString *p=[b pathForResource:@"portrait" ofType:@"jpeg"];
    return p ? [UIImage imageWithContentsOfFile:p] : nil;
}

static void AddPortrait(UIViewController *vc) {
    if (!IsSettingsController(vc) || !vc.view) return;
    if ([vc.view viewWithTag:kPortraitTag]) return;

    UIScrollView *scroll=FindScrollView(vc.view);
    if (!scroll) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.15*NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ AddPortrait(vc); });
        return;
    }

    UIImage *im=PortraitImage();
    if (!im) return;

    UIImageView *iv=[[UIImageView alloc] initWithImage:im];
    iv.tag=kPortraitTag;
    iv.translatesAutoresizingMaskIntoConstraints=NO;
    iv.contentMode=UIViewContentModeScaleAspectFill;
    iv.clipsToBounds=YES;
    iv.userInteractionEnabled=NO;
    iv.layer.cornerRadius=18.0;

    // Put it INSIDE the actual scroll view so it moves with the Settings content.
    [scroll addSubview:iv];

    // Use physical RIGHT, not trailing: trailing flips to the left in Arabic RTL.
    [NSLayoutConstraint activateConstraints:@[
        [iv.rightAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.rightAnchor constant:-20.0],
        [iv.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:169.0],
        [iv.widthAnchor constraintEqualToConstant:36.0],
        [iv.heightAnchor constraintEqualToConstant:36.0]
    ]];
}

@interface PortraitOverlayMarker : NSObject @end
@implementation PortraitOverlayMarker @end

@implementation UIViewController (TarabPortraitOverlay)
+ (void)load {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        Method a=class_getInstanceMethod(self,@selector(viewDidAppear:));
        Method b=class_getInstanceMethod(self,@selector(ts_viewDidAppear:));
        method_exchangeImplementations(a,b);
    });
}
- (void)ts_viewDidAppear:(BOOL)animated {
    [self ts_viewDidAppear:animated];
    if (IsSettingsController(self)) {
        dispatch_async(dispatch_get_main_queue(),^{ AddPortrait(self); });
    }
}
@end
