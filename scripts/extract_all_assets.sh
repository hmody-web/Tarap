#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CAR="$ROOT/Assets.car"
OUT="$ROOT/extracted_assets"
IMG="$OUT/images"
mkdir -p "$IMG"

echo "macOS: $(sw_vers -productVersion)"
echo "Xcode: $(xcodebuild -version | tr '\n' ' ')"
echo "Assets.car: $(stat -f%z "$CAR") bytes"

cat > "$ROOT/extract_all.m" <<'OBJC'
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *Safe(NSString *s) {
    NSCharacterSet *bad=[[NSCharacterSet characterSetWithCharactersInString:
      @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"] invertedSet];
    return [[s componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@"_"];
}
static id Unwrap(id v) {
    if(!v) return nil;
    for(NSString *sn in @[@"image",@"croppedImage",@"unslicedImage",@"uncroppedImage"]) {
        SEL s=NSSelectorFromString(sn);
        if([v respondsToSelector:s]) {
            id n=((id(*)(id,SEL))objc_msgSend)(v,s);
            if(n && n!=v) v=n;
        }
    }
    return v;
}
static BOOL SavePNG(id v, NSString *path) {
    v=Unwrap(v); if(!v) return NO;
    NSImage *im=nil;
    if([v isKindOfClass:[NSImage class]]) im=v;
    else {
        CFTypeRef cf=(__bridge CFTypeRef)v;
        if(cf && CFGetTypeID(cf)==CGImageGetTypeID())
            im=[[NSImage alloc] initWithCGImage:(__bridge CGImageRef)v size:NSZeroSize];
    }
    if(!im) return NO;
    CGImageRef cg=[im CGImageForProposedRect:NULL context:nil hints:nil];
    if(!cg) return NO;
    NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithCGImage:cg];
    NSData *png=[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return png ? [png writeToFile:path atomically:YES] : NO;
}

int main(int argc,const char **argv) {
 @autoreleasepool {
   if(argc<3) return 2;
   NSString *car=@(argv[1]), *out=@(argv[2]);
   [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/CoreUI.framework"] load];
   Class C=NSClassFromString(@"CUICatalog"); if(!C) return 3;
   id obj=((id(*)(id,SEL))objc_msgSend)((id)C,sel_registerName("alloc"));
   NSError *e=nil;
   id cat=((id(*)(id,SEL,NSURL*,NSError**))objc_msgSend)(
       obj,sel_registerName("initWithURL:error:"),[NSURL fileURLWithPath:car],&e);
   if(!cat){ NSLog(@"%@",e); return 4; }

   NSArray *names=((id(*)(id,SEL))objc_msgSend)(cat,sel_registerName("allImageNames"));
   names=[names sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
   [names componentsJoinedByString:@"\n"];
   [[names componentsJoinedByString:@"\n"] writeToFile:
      [out stringByAppendingPathComponent:@"asset_names.txt"]
      atomically:YES encoding:NSUTF8StringEncoding error:nil];

   SEL imageSel=sel_registerName("imageWithName:scaleFactor:");
   NSMutableString *report=[NSMutableString string];
   NSUInteger ok=0,fail=0;
   for(NSString *name in names) {
      BOOL saved=NO;
      // Prefer @3x, then @2x, then 1x: one PNG per asset keeps review simple.
      for(NSNumber *num in @[@3.0,@2.0,@1.0]) {
        CGFloat scale=num.doubleValue;
        id v=((id(*)(id,SEL,id,CGFloat))objc_msgSend)(cat,imageSel,name,scale);
        if(!v) continue;
        NSString *file=[NSString stringWithFormat:@"%@.png",Safe(name)];
        NSString *path=[[out stringByAppendingPathComponent:@"images"] stringByAppendingPathComponent:file];
        if(SavePNG(v,path)) {
          [report appendFormat:@"OK\t%@\t%.0fx\t%@\n",name,scale,file];
          ok++; saved=YES; break;
        }
      }
      if(!saved){ [report appendFormat:@"FAIL\t%@\n",name]; fail++; }
   }
   [report appendFormat:@"\nTOTAL=%lu EXTRACTED=%lu FAILED=%lu\n",
      (unsigned long)names.count,(unsigned long)ok,(unsigned long)fail];
   [report writeToFile:[out stringByAppendingPathComponent:@"extraction_report.txt"]
      atomically:YES encoding:NSUTF8StringEncoding error:nil];
   NSLog(@"TOTAL=%lu EXTRACTED=%lu FAILED=%lu",
      (unsigned long)names.count,(unsigned long)ok,(unsigned long)fail);
   return 0;
 }
}
OBJC

xcrun clang -fobjc-arc "$ROOT/extract_all.m" -framework Foundation -framework AppKit -o "$ROOT/extract_all"
"$ROOT/extract_all" "$CAR" "$OUT"

# Contact sheet makes it fast to visually spot the crown.
cat > "$ROOT/contact_sheet.swift" <<'SWIFT'
import AppKit
import Foundation

let dir=URL(fileURLWithPath:CommandLine.arguments[1])
let out=URL(fileURLWithPath:CommandLine.arguments[2])
let fm=FileManager.default
let files=(try! fm.contentsOfDirectory(at:dir,includingPropertiesForKeys:nil))
  .filter{$0.pathExtension.lowercased()=="png"}.sorted{$0.lastPathComponent<$1.lastPathComponent}
let cellW=180, cellH=210, cols=6
let rows=max(1,Int(ceil(Double(files.count)/Double(cols))))
let canvas=NSImage(size:NSSize(width:cols*cellW,height:rows*cellH))
canvas.lockFocus()
NSColor.white.setFill()
NSRect(x:0,y:0,width:cols*cellW,height:rows*cellH).fill()
for (i,u) in files.enumerated() {
  guard let im=NSImage(contentsOf:u) else { continue }
  let c=i%cols, r=i/cols
  let x=c*cellW, y=(rows-1-r)*cellH
  let box=NSRect(x:x+15,y:y+42,width:150,height:150)
  im.draw(in:box,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
  let name=(u.deletingPathExtension().lastPathComponent as NSString)
  name.draw(in:NSRect(x:x+5,y:y+5,width:170,height:34),
    withAttributes:[.font:NSFont.systemFont(ofSize:9),.foregroundColor:NSColor.black])
}
canvas.unlockFocus()
guard let cg=canvas.cgImage(forProposedRect:nil,context:nil,hints:nil) else { exit(2) }
let rep=NSBitmapImageRep(cgImage:cg)
try! rep.representation(using:.png,properties:[:])!.write(to:out)
SWIFT

xcrun swift "$ROOT/contact_sheet.swift" "$IMG" "$OUT/contact_sheet.png" || true

echo "=== extraction report ==="
tail -n 5 "$OUT/extraction_report.txt" || true
find "$OUT" -maxdepth 2 -type f | sort
