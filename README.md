Run **Build Portrait Dylib Early**.

This build:
- hooks `viewWillAppear:` instead of `viewDidAppear:`
- attempts to add the portrait immediately, then once again on the next main-loop turn
- keeps the current visual orientation
- target position: X 28, Y 56
- target size: 32x32
- portrait remains inside the Settings scroll view
