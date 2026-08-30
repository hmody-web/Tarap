#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CAR="$ROOT/Assets.car"
OUT="$ROOT/extracted_assets"
mkdir -p "$OUT"

echo "macOS: $(sw_vers -productVersion)"
echo "Xcode: $(xcodebuild -version | tr '\n' ' ')"
echo "Assets.car: $(stat -f%z "$CAR") bytes"

# Xcode 26 compatible Objective-C extractor.
# We use Objective-C here because Swift 6/Xcode 26 blocks direct +alloc calls.
cat > "$ROOT/extract.m" <<'OBJC'
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *SafeName(NSString *s) {
    return [[s stringByReplacingOccurrencesOfString:@"/" withString:@"_"]
            stringByReplacingOccurrencesOfString:@":" withString:@"_"];
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc < 3) return 2;
        NSString *car = [NSString stringWithUTF8String:argv[1]];
        NSString *out = [NSString stringWithUTF8String:argv[2]];

        NSBundle *coreUI = [NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/CoreUI.framework"];
        NSError *loadError = nil;
        [coreUI loadAndReturnError:&loadError];

        Class C = NSClassFromString(@"CUICatalog");
        if (!C) {
            fprintf(stderr, "CUICatalog unavailable: %s\n",
                    loadError.localizedDescription.UTF8String ?: "unknown");
            return 3;
        }

        id obj = ((id (*)(id, SEL))objc_msgSend)((id)C, sel_registerName("alloc"));
        NSError *err = nil;
        SEL initSel = sel_registerName("initWithURL:error:");
        id catalog = ((id (*)(id, SEL, NSURL *, NSError **))objc_msgSend)(
            obj, initSel, [NSURL fileURLWithPath:car], &err);

        if (!catalog) {
            fprintf(stderr, "Catalog open failed: %s\n",
                    err.localizedDescription.UTF8String ?: "unknown");
            return 4;
        }

        SEL namesSel = sel_registerName("allImageNames");
        if (![catalog respondsToSelector:namesSel]) {
            fprintf(stderr, "allImageNames unavailable\n");
            return 5;
        }

        NSArray *names = ((id (*)(id, SEL))objc_msgSend)(catalog, namesSel);
        NSLog(@"Found %lu image names", (unsigned long)names.count);

        NSString *nameList = [[names sortedArrayUsingSelector:@selector(compare:)]
                              componentsJoinedByString:@"\n"];
        [nameList writeToFile:[out stringByAppendingPathComponent:@"asset_names.txt"]
                   atomically:YES encoding:NSUTF8StringEncoding error:nil];

        SEL imageSel = sel_registerName("imageWithName:scaleFactor:");
        if (![catalog respondsToSelector:imageSel]) {
            fprintf(stderr, "imageWithName:scaleFactor: unavailable\n");
            return 6;
        }

        for (NSString *name in names) {
            for (NSNumber *scaleNum in @[@1.0, @2.0, @3.0]) {
                CGFloat scale = scaleNum.doubleValue;
                id value = ((id (*)(id, SEL, id, CGFloat))objc_msgSend)(
                    catalog, imageSel, name, scale);
                if (!value) continue;

                NSImage *image = nil;
                if ([value isKindOfClass:[NSImage class]]) {
                    image = value;
                } else if (CFGetTypeID((__bridge CFTypeRef)value) == CGImageGetTypeID()) {
                    CGImageRef cg = (__bridge CGImageRef)value;
                    image = [[NSImage alloc] initWithCGImage:cg size:NSZeroSize];
                }
                if (!image) continue;

                CGImageRef cg = [image CGImageForProposedRect:NULL context:nil hints:nil];
                if (!cg) continue;

                NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cg];
                NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                if (!png) continue;

                NSString *suffix = scale == 1.0 ? @"" :
                    [NSString stringWithFormat:@"@%ldx", (long)scale];
                NSString *file = [NSString stringWithFormat:@"%@%@.png", SafeName(name), suffix];
                [png writeToFile:[out stringByAppendingPathComponent:file] atomically:YES];
            }
        }

        BOOL found = [names containsObject:@"subscriptionLogo"];
        NSLog(@"subscriptionLogo present: %@", found ? @"YES" : @"NO");
        return 0;
    }
}
OBJC

xcrun clang -fobjc-arc "$ROOT/extract.m" \
  -framework Foundation -framework AppKit \
  -o "$ROOT/extract_car"

set +e
"$ROOT/extract_car" "$CAR" "$OUT"
RC=$?
set -e

# Diagnostics/fallback are always saved, even if CoreUI changes again.
strings "$CAR" > "$OUT/Assets_car_strings.txt" || true

{
  echo "Extractor exit code: $RC"
  echo "=== subscriptionLogo search ==="
  grep -i "subscriptionLogo" "$OUT/asset_names.txt" 2>/dev/null || true
  grep -i "subscriptionLogo" "$OUT/Assets_car_strings.txt" 2>/dev/null || true
  echo
  echo "=== matching output files ==="
  find "$OUT" -maxdepth 1 -type f -iname '*subscription*' -print || true
} > "$OUT/subscriptionLogo_report.txt"

echo "Done. Output:"
find "$OUT" -maxdepth 1 -type f -print | sort

# Do not fail the Codemagic build merely because a private CoreUI API changed;
# artifacts and diagnostics remain downloadable.
exit 0
