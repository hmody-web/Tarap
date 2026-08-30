V4: macOS 26 CUINamedImage support.

The previous artifact proved subscriptionLogo is returned as CUINamedImage and that CUINamedImage exposes the `image` and `croppedImage` selectors. V4 unwraps those objects and writes the underlying image as PNG.

Run workflow: Extract subscriptionLogo V4
Then download the complete extracted_assets artifact and send it back.
