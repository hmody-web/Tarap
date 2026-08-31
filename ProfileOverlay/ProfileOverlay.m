
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL IsSettingsController(UIViewController *vc) {
    return [NSStringFromClass([vc class]) containsString:@"SettingsViewController"];
}

static UIImage *PortraitImage(void) {
    NSBundle *b=[NSBundle bundleForClass:NSClassFromString(@"ProfileOverlayMarker")];
    NSString *p=[b pathForResource:@"portrait" ofType:@"jpeg"];
    return p ? [UIImage imageWithContentsOfFile:p] : nil;
}

static UILabel *Label(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *l=[UILabel new];
    l.translatesAutoresizingMaskIntoConstraints=NO;
    l.text=text; l.textAlignment=NSTextAlignmentCenter; l.numberOfLines=0;
    l.font=[UIFont systemFontOfSize:size weight:weight];
    l.textColor=color;
    return l;
}

static UIButton *Button(NSString *title, NSString *symbol) {
    UIButtonConfiguration *c=[UIButtonConfiguration filledButtonConfiguration];
    c.title=title;
    c.cornerStyle=UIButtonConfigurationCornerStyleLarge;
    c.baseBackgroundColor=UIColor.systemBlueColor;
    c.baseForegroundColor=UIColor.whiteColor;
    c.image=[UIImage systemImageNamed:symbol];
    c.imagePadding=8;
    UIButton *b=[UIButton buttonWithConfiguration:c primaryAction:nil];
    b.translatesAutoresizingMaskIntoConstraints=NO;
    return b;
}

@interface AlsarayProfileViewController : UIViewController @end
@implementation AlsarayProfileViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=UIColor.systemBackgroundColor;

    UIButton *close=[UIButton buttonWithType:UIButtonTypeSystem];
    close.translatesAutoresizingMaskIntoConstraints=NO;
    [close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    close.tintColor=UIColor.labelColor;
    [close addTarget:self action:@selector(closeMe) forControlEvents:UIControlEventTouchUpInside];

    UIImageView *iv=[[UIImageView alloc] initWithImage:PortraitImage()];
    iv.translatesAutoresizingMaskIntoConstraints=NO;
    iv.contentMode=UIViewContentModeScaleAspectFill;
    iv.clipsToBounds=YES;
    iv.layer.cornerRadius=52;

    UILabel *name=Label(@"محمد السراي",28,UIFontWeightBold,UIColor.labelColor);
    UILabel *desc=Label(@"مطور ومصمم برامج وتطبيقات iOS ومواقع الويب",17,UIFontWeightRegular,UIColor.secondaryLabelColor);
    UILabel *contact=Label(@"تواصل معنا",20,UIFontWeightSemibold,UIColor.labelColor);

    UIButton *site=Button(@"موقعنا",@"globe");
    UIButton *tg=Button(@"تيليجرام",@"paperplane.fill");
    [site addTarget:self action:@selector(openSite) forControlEvents:UIControlEventTouchUpInside];
    [tg addTarget:self action:@selector(openTelegram) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *buttons=[[UIStackView alloc] initWithArrangedSubviews:@[site,tg]];
    buttons.translatesAutoresizingMaskIntoConstraints=NO;
    buttons.axis=UILayoutConstraintAxisHorizontal;
    buttons.spacing=12;
    buttons.distribution=UIStackViewDistributionFillEqually;

    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[iv,name,desc,contact,buttons]];
    stack.translatesAutoresizingMaskIntoConstraints=NO;
    stack.axis=UILayoutConstraintAxisVertical;
    stack.alignment=UIStackViewAlignmentCenter;
    stack.spacing=14;
    [stack setCustomSpacing:6 afterView:name];
    [stack setCustomSpacing:34 afterView:desc];
    [stack setCustomSpacing:16 afterView:contact];

    [self.view addSubview:close];
    [self.view addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
      [close.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
      [close.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
      [close.widthAnchor constraintEqualToConstant:44],
      [close.heightAnchor constraintEqualToConstant:44],

      [stack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
      [stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-30],
      [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:28],
      [stack.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-28],

      [iv.widthAnchor constraintEqualToConstant:104],
      [iv.heightAnchor constraintEqualToConstant:104],
      [desc.widthAnchor constraintLessThanOrEqualToConstant:330],
      [buttons.widthAnchor constraintEqualToConstant:320],
      [site.heightAnchor constraintEqualToConstant:54],
      [tg.heightAnchor constraintEqualToConstant:54],
    ]];
}
- (void)closeMe { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)openSite {
    NSURL *u=[NSURL URLWithString:@"https://scrptaty.com"];
    if (u) [[UIApplication sharedApplication] openURL:u options:@{} completionHandler:nil];
}
- (void)openTelegram {
    NSURL *u=[NSURL URLWithString:@"https://t.me/mooo5"];
    if (u) [[UIApplication sharedApplication] openURL:u options:@{} completionHandler:nil];
}
@end

@interface ProfileOverlayMarker : NSObject @end
@implementation ProfileOverlayMarker @end

// Intercept presentation of the existing subscription/paywall screen from Settings.
// The first modal presentation triggered while Settings is visible is replaced by our profile.
@implementation UIViewController (AlsarayProfileOverlay)
+ (void)load {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        Method a=class_getInstanceMethod(self,@selector(presentViewController:animated:completion:));
        Method b=class_getInstanceMethod(self,@selector(as_presentViewController:animated:completion:));
        method_exchangeImplementations(a,b);
    });
}
- (void)as_presentViewController:(UIViewController *)vc animated:(BOOL)animated completion:(void (^)(void))completion {
    UIViewController *presenter=self;
    UIViewController *p=presenter;
    BOOL fromSettings=NO;
    while (p) {
        if (IsSettingsController(p)) { fromSettings=YES; break; }
        p=p.parentViewController;
    }
    if (fromSettings) {
        AlsarayProfileViewController *profile=[AlsarayProfileViewController new];
        profile.modalPresentationStyle=UIModalPresentationFullScreen;
        [self as_presentViewController:profile animated:animated completion:completion];
        return;
    }
    [self as_presentViewController:vc animated:animated completion:completion];
}
@end
