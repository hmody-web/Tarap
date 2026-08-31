typedef void *id;
typedef void *Class;
typedef void *SEL;
typedef void *Method;
typedef void (*IMP)(void);
typedef unsigned long NSUInteger;
typedef long NSInteger;
typedef signed char BOOL;

typedef struct { double x; double y; } CGPoint;
typedef struct { double width; double height; } CGSize;
typedef struct { CGPoint origin; CGSize size; } CGRect;

extern Class objc_getClass(const char *name);
extern SEL sel_registerName(const char *str);
extern Method class_getInstanceMethod(Class cls, SEL name);
extern IMP method_getImplementation(Method m);
extern IMP method_setImplementation(Method m, IMP imp);
extern const char *object_getClassName(id obj);
extern void *objc_msgSend(void);

static IMP orig_vc_layout = 0;
static IMP orig_tab_layout = 0;

static int contains_ci(const char *s, const char *needle) {
    if (!s || !needle) return 0;
    for (; *s; s++) {
        const char *a=s,*b=needle;
        while (*a && *b) {
            char ca=*a, cb=*b;
            if (ca>='A'&&ca<='Z') ca += 32;
            if (cb>='A'&&cb<='Z') cb += 32;
            if (ca!=cb) break;
            a++; b++;
        }
        if (!*b) return 1;
    }
    return 0;
}

static id msg_id(id o, const char *s) {
    return ((id(*)(id,SEL))objc_msgSend)(o, sel_registerName(s));
}
static NSUInteger msg_u(id o, const char *s) {
    return ((NSUInteger(*)(id,SEL))objc_msgSend)(o, sel_registerName(s));
}
static id msg_idx(id o, const char *s, NSUInteger i) {
    return ((id(*)(id,SEL,NSUInteger))objc_msgSend)(o, sel_registerName(s), i);
}
static void msg_bool(id o, const char *s, BOOL b) {
    ((void(*)(id,SEL,BOOL))objc_msgSend)(o, sel_registerName(s), b);
}
static void msg_idarg(id o, const char *s, id a) {
    ((void(*)(id,SEL,id))objc_msgSend)(o, sel_registerName(s), a);
}
static void msg_double(id o, const char *s, double d) {
    ((void(*)(id,SEL,double))objc_msgSend)(o, sel_registerName(s), d);
}
static CGRect msg_rect(id o, const char *s) {
    return ((CGRect(*)(id,SEL))objc_msgSend)(o, sel_registerName(s));
}
static CGRect msg_rect_id(id o, const char *s, CGRect r, id v) {
    return ((CGRect(*)(id,SEL,CGRect,id))objc_msgSend)(o, sel_registerName(s), r, v);
}

static int is_meaningful_class(const char *n) {
    if (!n) return 0;
    return contains_ci(n,"label") || contains_ci(n,"button") ||
           contains_ci(n,"imageview") || contains_ci(n,"textfield") ||
           contains_ci(n,"textview") || contains_ci(n,"collection") ||
           contains_ci(n,"table") || contains_ci(n,"scroll") ||
           contains_ci(n,"switch") || contains_ci(n,"segmented") ||
           contains_ci(n,"progress");
}

static int has_meaningful_desc(id v, int depth) {
    if (!v || depth < 0) return 0;
    id subs = msg_id(v, "subviews");
    NSUInteger c = subs ? msg_u(subs, "count") : 0;

    for (NSUInteger i=0; i<c; i++) {
        id sv = msg_idx(subs, "objectAtIndex:", i);
        const char *n = object_getClassName(sv);
        if (is_meaningful_class(n)) return 1;
        if (depth > 0 && has_meaningful_desc(sv, depth-1)) return 1;
    }
    return 0;
}

static void collapse_height_constraints(id v) {
    if (!v) return;

    id cons = msg_id(v, "constraints");
    NSUInteger c = cons ? msg_u(cons, "count") : 0;

    for (NSUInteger i=0; i<c; i++) {
        id co = msg_idx(cons, "objectAtIndex:", i);
        NSInteger attr = ((NSInteger(*)(id,SEL))objc_msgSend)(
            co, sel_registerName("firstAttribute")
        );
        id first = msg_id(co, "firstItem");

        if (first == v && attr == 8) {
            msg_double(co, "setConstant:", 0.0);
        }
    }

    id sup = msg_id(v, "superview");
    if (sup) {
        cons = msg_id(sup, "constraints");
        c = cons ? msg_u(cons, "count") : 0;

        for (NSUInteger i=0; i<c; i++) {
            id co = msg_idx(cons, "objectAtIndex:", i);
            NSInteger attr = ((NSInteger(*)(id,SEL))objc_msgSend)(
                co, sel_registerName("firstAttribute")
            );
            id first = msg_id(co, "firstItem");

            if (first == v && attr == 8) {
                msg_double(co, "setConstant:", 0.0);
            }
        }
    }
}

static void hide_ad_named_views(id v) {
    if (!v) return;

    const char *n = object_getClassName(v);

    if (n && (
        contains_ci(n,"gadbanner") ||
        contains_ci(n,"googlemobileads") ||
        contains_ci(n,"adbanner") ||
        contains_ci(n,"bannerad") ||
        contains_ci(n,"adcontainer") ||
        contains_ci(n,"advert") ||
        contains_ci(n,"adsview") ||
        contains_ci(n,"admob")
    )) {
        msg_bool(v, "setHidden:", 1);
        msg_bool(v, "setUserInteractionEnabled:", 0);
        collapse_height_constraints(v);

        CGRect f = msg_rect(v, "frame");
        f.size.height = 0;
        ((void(*)(id,SEL,CGRect))objc_msgSend)(
            v, sel_registerName("setFrame:"), f
        );
        return;
    }

    id subs = msg_id(v, "subviews");
    NSUInteger c = subs ? msg_u(subs, "count") : 0;

    for (NSUInteger i=0; i<c; i++) {
        hide_ad_named_views(msg_idx(subs, "objectAtIndex:", i));
    }
}

static id find_tabbar(id v) {
    if (!v) return 0;

    const char *n = object_getClassName(v);

    if (n && contains_ci(n,"uitabbar") && !contains_ci(n,"controller")) {
        return v;
    }

    id subs = msg_id(v, "subviews");
    NSUInteger c = subs ? msg_u(subs, "count") : 0;

    for (NSUInteger i=0; i<c; i++) {
        id r = find_tabbar(msg_idx(subs, "objectAtIndex:", i));
        if (r) return r;
    }

    return 0;
}

static void collapse_blank_slot(id root, id tab) {
    if (!root || !tab) return;

    id window = msg_id(tab, "window");
    if (!window) return;

    CGRect tf = msg_rect(tab, "bounds");
    tf = msg_rect_id(tab, "convertRect:toView:", tf, window);

    double tabY = tf.origin.y;
    if (tabY <= 0) return;

    id subs = msg_id(root, "subviews");
    NSUInteger c = subs ? msg_u(subs, "count") : 0;

    for (NSUInteger i=0; i<c; i++) {
        id v = msg_idx(subs, "objectAtIndex:", i);
        if (v == tab) continue;

        const char *n = object_getClassName(v);

        if (n && (
            contains_ci(n,"uitabbar") ||
            contains_ci(n,"barbackground")
        )) continue;

        CGRect b = msg_rect(v, "bounds");
        CGRect f = msg_rect_id(v, "convertRect:toView:", b, window);

        double h = f.size.height;
        double w = f.size.width;
        double maxY = f.origin.y + h;

        CGRect wb = msg_rect(window, "bounds");

        int near = (maxY > tabY - 14.0 && maxY < tabY + 14.0);
        int sizeok = (h >= 35.0 && h <= 180.0 && w >= wb.size.width * 0.78);

        if (near && sizeok && !has_meaningful_desc(v, 2)) {
            msg_bool(v, "setHidden:", 1);
            collapse_height_constraints(v);

            CGRect z = msg_rect(v, "frame");
            z.size.height = 0;

            ((void(*)(id,SEL,CGRect))objc_msgSend)(
                v, sel_registerName("setFrame:"), z
            );
        } else {
            collapse_blank_slot(v, tab);
        }
    }
}

static void transparent_tabbar(id tab) {
    if (!tab) return;

    Class UIColor = objc_getClass("UIColor");
    id clear = ((id(*)(id,SEL))objc_msgSend)(
        (id)UIColor, sel_registerName("clearColor")
    );

    msg_idarg(tab, "setBackgroundColor:", clear);
    msg_bool(tab, "setOpaque:", 0);
    msg_bool(tab, "setTranslucent:", 1);

    id subs = msg_id(tab, "subviews");
    NSUInteger c = subs ? msg_u(subs, "count") : 0;

    for (NSUInteger i=0; i<c; i++) {
        id sv = msg_idx(subs, "objectAtIndex:", i);
        const char *n = object_getClassName(sv);

        if (n && (
            contains_ci(n,"barbackground") ||
            contains_ci(n,"visualeffect")
        )) {
            msg_bool(sv, "setHidden:", 1);
            msg_idarg(sv, "setBackgroundColor:", clear);
        }
    }
}

static void vc_layout(id self, SEL _cmd) {
    ((void(*)(id,SEL))orig_vc_layout)(self, _cmd);

    id root = msg_id(self, "view");
    if (!root) return;

    hide_ad_named_views(root);

    id tab = find_tabbar(root);

    if (!tab) {
        id win = msg_id(root, "window");
        if (win) tab = find_tabbar(win);
    }

    if (tab) {
        transparent_tabbar(tab);

        id win = msg_id(tab, "window");
        if (win) collapse_blank_slot(win, tab);
    }
}

static void tab_layout(id self, SEL _cmd) {
    ((void(*)(id,SEL))orig_tab_layout)(self, _cmd);
    transparent_tabbar(self);
}

__attribute__((constructor))
static void init_layout_cleaner(void) {
    Class vc = objc_getClass("UIViewController");
    Method m = class_getInstanceMethod(
        vc,
        sel_registerName("viewDidLayoutSubviews")
    );

    if (m) {
        orig_vc_layout = method_getImplementation(m);
        method_setImplementation(m, (IMP)vc_layout);
    }

    Class tb = objc_getClass("UITabBar");
    Method t = class_getInstanceMethod(
        tb,
        sel_registerName("layoutSubviews")
    );

    if (t) {
        orig_tab_layout = method_getImplementation(t);
        method_setImplementation(t, (IMP)tab_layout);
    }
}
