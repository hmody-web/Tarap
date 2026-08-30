#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CAR="$ROOT/Assets.car"
OUT="$ROOT/extracted_assets"
mkdir -p "$OUT"

echo "macOS: $(sw_vers -productVersion)"
echo "Xcode: $(xcodebuild -version | tr '\n' ' ')"
echo "Assets.car: $(stat -f%z "$CAR") bytes"

# Build a small Swift extractor using Apple's private CoreUI framework available on macOS.
# It enumerates rendition names from CUICatalog and writes CGImage renditions as PNG.
cat > "$ROOT/extract.swift" <<'SWIFT'
import Foundation
import AppKit

let car = CommandLine.arguments[1]
let out = CommandLine.arguments[2]
let fm = FileManager.default
try? fm.createDirectory(atPath: out, withIntermediateDirectories: true)

guard let catalogClass = NSClassFromString("CUICatalog") as? NSObject.Type else {
    fputs("CUICatalog unavailable\n", stderr); exit(2)
}
let catalog = catalogClass.init()

let initSel = NSSelectorFromString("initWithURL:error:")
if catalog.responds(to: initSel) {
    // init cannot safely be invoked through perform; use KVC fallback below after loading framework.
}

let bundlePaths = [
    "/System/Library/PrivateFrameworks/CoreUI.framework",
    "/System/Library/PrivateFrameworks/CoreUI.framework/Versions/A"
]
for p in bundlePaths {
    if let b = Bundle(path: p) { try? b.loadAndReturnError() }
}

// Re-resolve after loading CoreUI
guard let C = NSClassFromString("CUICatalog") as? NSObject.Type else {
    fputs("Could not load CoreUI/CUICatalog\n", stderr); exit(3)
}

// Objective-C runtime invocation helpers
import ObjectiveC.runtime

typealias InitFn = @convention(c) (AnyObject, Selector, NSURL, AutoreleasingUnsafeMutablePointer<NSError?>?) -> AnyObject
let obj: AnyObject = C.alloc()
let sel = NSSelectorFromString("initWithURL:error:")
guard let method = class_getInstanceMethod(C, sel) else {
    fputs("initWithURL:error: unavailable\n", stderr); exit(4)
}
let imp = method_getImplementation(method)
let fn = unsafeBitCast(imp, to: InitFn.self)
var err: NSError?
let cat = fn(obj, sel, NSURL(fileURLWithPath: car), &err)

if let err = err {
    fputs("Catalog open error: \(err)\n", stderr); exit(5)
}

let namesSel = NSSelectorFromString("allImageNames")
guard cat.responds(to: namesSel),
      let unmanaged = cat.perform(namesSel),
      let names = unmanaged.takeUnretainedValue() as? [String] else {
    fputs("Could not enumerate allImageNames\n", stderr); exit(6)
}

print("Found \(names.count) image names")
try? names.sorted().joined(separator: "\n").write(toFile: out + "/asset_names.txt", atomically: true, encoding: .utf8)

func safe(_ s: String) -> String {
    return s.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
}

let imgSel = NSSelectorFromString("imageWithName:scaleFactor:")
if let m = class_getInstanceMethod(C, imgSel) {
    typealias ImgFn = @convention(c) (AnyObject, Selector, NSString, CGFloat) -> Unmanaged<AnyObject>?
    let imgFn = unsafeBitCast(method_getImplementation(m), to: ImgFn.self)

    for name in names {
        for scale: CGFloat in [1,2,3] {
            guard let u = imgFn(cat, imgSel, name as NSString, scale) else { continue }
            let v = u.takeUnretainedValue()
            var cg: CGImage?
            if let image = v as? NSImage {
                cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            } else if CFGetTypeID(v) == CGImage.typeID {
                cg = (v as! CGImage)
            }
            guard let cgi = cg else { continue }
            let rep = NSBitmapImageRep(cgImage: cgi)
            if let png = rep.representation(using: .png, properties: [:]) {
                let suffix = scale == 1 ? "" : "@\(Int(scale))x"
                let path = out + "/" + safe(name) + suffix + ".png"
                try? png.write(to: URL(fileURLWithPath: path))
            }
        }
    }
}

print("subscriptionLogo present:", names.contains("subscriptionLogo"))
SWIFT

# Compile with CoreUI linked dynamically at runtime.
xcrun swiftc "$ROOT/extract.swift" -o "$ROOT/extract_car" -framework AppKit

"$ROOT/extract_car" "$CAR" "$OUT" || {
  echo "Primary extractor failed. Saving diagnostic strings so we still get useful artifacts."
  strings "$CAR" > "$OUT/Assets_car_strings.txt" || true
}

# Always make a focused report.
{
  echo "=== subscriptionLogo search ==="
  grep -i "subscriptionLogo" "$OUT/asset_names.txt" 2>/dev/null || true
  grep -i "subscriptionLogo" "$OUT/Assets_car_strings.txt" 2>/dev/null || true
  echo
  echo "=== matching output files ==="
  find "$OUT" -maxdepth 1 -type f -iname '*subscription*' -print || true
} > "$OUT/subscriptionLogo_report.txt"

echo "Done. Output:"
find "$OUT" -maxdepth 1 -type f -print | sort
