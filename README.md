# Tarab PortraitOverlay

Run Codemagic workflow: **Build Tarab Portrait Dylib**

Artifact:
`build/PortraitOverlay.framework`

This framework contains the real uploaded portrait and a UIKit hook that runs
after `viewDidAppear:` only for `SettingsViewController`.

Important: building the framework alone does not make Tarab load it. The next
step is to inject the framework into the IPA and add its LC_LOAD_DYLIB load
command, then re-sign the app/framework.
