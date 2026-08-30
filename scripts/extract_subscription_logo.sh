#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CAR="$ROOT/Assets.car"
OUT="$ROOT/extracted_assets"
mkdir -p "$OUT"

echo "macOS: $(sw_vers -productVersion)"
echo "Xcode: $(xcodebuild -version | tr '\n' ' ')"
echo "Assets.car: $(stat -f%z "$CAR") bytes"

cat > "$ROOT/probe.m" <<'OBJC'
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static id Send0(id o, SEL s) { return ((id(*)(id,SEL))objc_msgSend)(o,s); }
static id Send1Obj(id o, SEL s, id a) { return ((id(*)(id,SEL,id))objc_msgSend)(o,s,a); }

static BOOL WriteImageObject(id value, NSString *path) {
    if (!value) return NO;
    NSImage *im=nil;
    if ([value isKindOfClass:[NSImage class]]) {
        im=value;
    } else {
        CFTypeRef cf=(__bridge CFTypeRef)value;
        if (cf && CFGetTypeID(cf)==CGImageGetTypeID()) {
            im=[[NSImage alloc] initWithCGImage:(__bridge CGImageRef)value size:NSZeroSize];
        }
    }
    if (!im) return NO;
    CGImageRef cg=[im CGImageForProposedRect:NULL context:nil hints:nil];
    if (!cg) return NO;
    NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithCGImage:cg];
    NSData *png=[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return png ? [png writeToFile:path atomically:YES] : NO;
}

int main(int argc,const char **argv) {
 @autoreleasepool {
   if(argc<3) return 2;
   NSString *car=@(argv[1]), *out=@(argv[2]);
   NSBundle *b=[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/CoreUI.framework"];
   NSError *le=nil; [b loadAndReturnError:&le];
   Class C=NSClassFromString(@"CUICatalog");
   if(!C){ fprintf(stderr,"No CUICatalog\n"); return 3; }

   id obj=((id(*)(id,SEL))objc_msgSend)((id)C,sel_registerName("alloc"));
   NSError *e=nil;
   id cat=((id(*)(id,SEL,NSURL*,NSError**))objc_msgSend)(
       obj,sel_registerName("initWithURL:error:"),[NSURL fileURLWithPath:car],&e);
   if(!cat){ fprintf(stderr,"Open failed: %s\n",e.localizedDescription.UTF8String); return 4; }

   NSString *target=@"subscriptionLogo";
   NSMutableString *report=[NSMutableString string];
   [report appendFormat:@"Catalog class: %@\nTarget: %@\n\n",NSStringFromClass([cat class]),target];

   // Record every image-related selector exposed by this exact macOS CoreUI.
   unsigned int count=0;
   Method *methods=class_copyMethodList([cat class],&count);
   [report appendString:@"=== CUICatalog image/name/rendition selectors ===\n"];
   for(unsigned int i=0;i<count;i++){
      NSString *n=NSStringFromSelector(method_getName(methods[i]));
      NSString *low=n.lowercaseString;
      if([low containsString:@"image"]||[low containsString:@"name"]||[low containsString:@"rendition"])
          [report appendFormat:@"%@\n",n];
   }
   free(methods);

   NSArray *names=nil;
   SEL all=sel_registerName("allImageNames");
   if([cat respondsToSelector:all]) names=Send0(cat,all);
   [report appendFormat:@"\nallImageNames count: %lu\nsubscriptionLogo present: %@\n",
       (unsigned long)names.count,[names containsObject:target]?@"YES":@"NO"];

   // Try known CUICatalog APIs with signatures appropriate to their names.
   NSArray *oneArg=@[@"imageWithName:", @"imageNamed:", @"imageForName:",
                     @"renditionWithName:", @"namedImageWithName:"];
   for(NSString *sn in oneArg){
      SEL s=NSSelectorFromString(sn);
      if(![cat respondsToSelector:s]) continue;
      id v=Send1Obj(cat,s,target);
      NSString *p=[out stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"subscriptionLogo_%@.png",
                     [sn stringByReplacingOccurrencesOfString:@":" withString:@"_"]]];
      BOOL ok=WriteImageObject(v,p);
      [report appendFormat:@"TRY %@ => %@ class=%@\n",sn,ok?@"PNG OK":@"no PNG",
          v?NSStringFromClass([v class]):@"nil"];
   }

   // Known scale APIs.
   for(NSString *sn in @[@"imageWithName:scaleFactor:", @"imageNamed:scaleFactor:"]){
      SEL s=NSSelectorFromString(sn);
      if(![cat respondsToSelector:s]) continue;
      for(NSNumber *num in @[@1.0,@2.0,@3.0]){
          CGFloat scale=num.doubleValue;
          id v=((id(*)(id,SEL,id,CGFloat))objc_msgSend)(cat,s,target,scale);
          NSString *p=[out stringByAppendingPathComponent:
             [NSString stringWithFormat:@"subscriptionLogo_%@%ldx.png",
              [sn stringByReplacingOccurrencesOfString:@":" withString:@"_"],(long)scale]];
          BOOL ok=WriteImageObject(v,p);
          [report appendFormat:@"TRY %@ scale %.0f => %@ class=%@\n",
             sn,scale,ok?@"PNG OK":@"no PNG",v?NSStringFromClass([v class]):@"nil"];
      }
   }

   [report writeToFile:[out stringByAppendingPathComponent:@"subscriptionLogo_probe.txt"]
             atomically:YES encoding:NSUTF8StringEncoding error:nil];

   // Also dump runtime method lists for useful related CoreUI classes.
   NSMutableString *runtime=[NSMutableString string];
   int ncls=objc_getClassList(NULL,0);
   Class *classes=malloc(sizeof(Class)*ncls);
   objc_getClassList(classes,ncls);
   for(int i=0;i<ncls;i++){
      NSString *cn=NSStringFromClass(classes[i]);
      NSString *lo=cn.lowercaseString;
      if(![lo containsString:@"cui"] && ![lo containsString:@"rendition"]) continue;
      unsigned int mc=0; Method *ms=class_copyMethodList(classes[i],&mc);
      BOOL header=NO;
      for(unsigned int j=0;j<mc;j++){
        NSString *mn=NSStringFromSelector(method_getName(ms[j]));
        NSString *ml=mn.lowercaseString;
        if([ml containsString:@"image"]||[ml containsString:@"rendition"]||
           [ml containsString:@"name"]||[ml containsString:@"asset"]){
          if(!header){ [runtime appendFormat:@"\n[%@]\n",cn]; header=YES; }
          [runtime appendFormat:@"%@\n",mn];
        }
      }
      free(ms);
   }
   free(classes);
   [runtime writeToFile:[out stringByAppendingPathComponent:@"coreui_runtime_methods.txt"]
              atomically:YES encoding:NSUTF8StringEncoding error:nil];

   NSLog(@"Probe complete");
   return 0;
 }
}
OBJC

xcrun clang -fobjc-arc "$ROOT/probe.m" -framework Foundation -framework AppKit -o "$ROOT/probe"

set +e
"$ROOT/probe" "$CAR" "$OUT"
RC=$?
set -e

strings "$CAR" | grep -i -C 3 'subscriptionLogo' > "$OUT/subscriptionLogo_strings_context.txt" || true
echo "$RC" > "$OUT/probe_exit_code.txt"

echo "=== RESULTS ==="
cat "$OUT/subscriptionLogo_probe.txt" 2>/dev/null || true
echo
find "$OUT" -maxdepth 1 -type f -print | sort

# Preserve diagnostics as artifacts even if a private API differs.
exit 0
