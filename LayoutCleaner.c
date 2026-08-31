typedef void *id;
typedef void *Class;
typedef void *SEL;
typedef void *Method;
typedef void (*IMP)(void);
typedef signed char BOOL;

extern Class objc_getClass(const char *name);
extern SEL sel_registerName(const char *str);
extern Method class_getInstanceMethod(Class cls, SEL name);
extern IMP method_getImplementation(Method m);
extern IMP method_setImplementation(Method m, IMP imp);
extern void *objc_msgSend(void);

static IMP orig_tab_layout = 0;

/* ---- BannerHeightManager: targeted hooks only ---- */

static double zero_double(id self, SEL _cmd) {
    return 0.0;
}

static void ignore_double_setter(id self, SEL _cmd, double value) {
    /* Deliberately force banner-related dimensions to stay zero. */
}

static BOOL always_false(id self, SEL _cmd) {
    return 0;
}

static void ignore_bool_setter(id self, SEL _cmd, BOOL value) {
}

/* ---- UITabBar: transparency only ---- */

static id msg_id(id o, const char *s) {
    return ((id(*)(id,SEL))objc_msgSend)(o, sel_registerName(s));
}
static void msg_idarg(id o, const char *s, id a) {
    ((void(*)(id,SEL,id))objc_msgSend)(o, sel_registerName(s), a);
}
static void msg_bool(id o, const char *s, BOOL b) {
    ((void(*)(id,SEL,BOOL))objc_msgSend)(o, sel_registerName(s), b);
}

static void make_tabbar_transparent(id tab) {
    if (!tab) return;

    Class UIColor = objc_getClass("UIColor");
    if (!UIColor) return;

    id clear = ((id(*)(id,SEL))objc_msgSend)(
        (id)UIColor, sel_registerName("clearColor")
    );

    msg_idarg(tab, "setBackgroundColor:", clear);
    msg_bool(tab, "setOpaque:", 0);

    /* setTranslucent exists on UITabBar/UINavigationBar lineage */
    SEL translucent = sel_registerName("setTranslucent:");
    ((void(*)(id,SEL,BOOL))objc_msgSend)(tab, translucent, 1);

    /*
     * iOS 15+: configure standardAppearance/scrollEdgeAppearance
     * using a UITabBarAppearance with transparent background.
     */
    Class Appearance = objc_getClass("UITabBarAppearance");
    if (Appearance) {
        id ap = ((id(*)(id,SEL))objc_msgSend)(
            (id)Appearance, sel_registerName("alloc")
        );
        ap = ((id(*)(id,SEL))objc_msgSend)(
            ap, sel_registerName("init")
        );

        if (ap) {
            ((void(*)(id,SEL))objc_msgSend)(
                ap, sel_registerName("configureWithTransparentBackground")
            );

            msg_idarg(tab, "setStandardAppearance:", ap);
            msg_idarg(tab, "setScrollEdgeAppearance:", ap);

            ((void(*)(id,SEL))objc_msgSend)(ap, sel_registerName("release"));
        }
    }
}

static void tab_layout(id self, SEL _cmd) {
    if (orig_tab_layout) {
        ((void(*)(id,SEL))orig_tab_layout)(self, _cmd);
    }
    make_tabbar_transparent(self);
}

static void replace_if_present(Class cls, const char *selName, IMP replacement) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, sel_registerName(selName));
    if (m) method_setImplementation(m, replacement);
}

__attribute__((constructor))
static void init_layout_cleaner(void) {
    /*
     * Swift runtime name observed in Tarab:
     * _TtC5Tarab19BannerHeightManager
     */
    Class bhm = objc_getClass("_TtC5Tarab19BannerHeightManager");

    if (!bhm) {
        /* Fallback for possible @objc exposure. */
        bhm = objc_getClass("BannerHeightManager");
    }

    if (bhm) {
        replace_if_present(bhm, "bannerHeight", (IMP)zero_double);
        replace_if_present(bhm, "setBannerHeight:", (IMP)ignore_double_setter);

        replace_if_present(bhm, "inlineBannerHeight", (IMP)zero_double);
        replace_if_present(bhm, "setInlineBannerHeight:", (IMP)ignore_double_setter);

        replace_if_present(bhm, "bannerBottomPadding", (IMP)zero_double);
        replace_if_present(bhm, "setBannerBottomPadding:", (IMP)ignore_double_setter);

        replace_if_present(bhm, "shouldShowBanner", (IMP)always_false);
        replace_if_present(bhm, "setShouldShowBanner:", (IMP)ignore_bool_setter);
    }

    Class tb = objc_getClass("UITabBar");
    if (tb) {
        Method t = class_getInstanceMethod(
            tb, sel_registerName("layoutSubviews")
        );

        if (t) {
            orig_tab_layout = method_getImplementation(t);
            method_setImplementation(t, (IMP)tab_layout);
        }
    }
}
