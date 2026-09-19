# VTG Page Mode demo

A small Mac app that runs `vpm-demo.sh` in SwiftTerm's
`LocalProcessVectorTerminalView` — the terminal view VGTerm uses — so every
page on screen arrives as escape sequences through a real pseudo-terminal.

| Scene | Shows |
|---|---|
| 1 | A card on a page placed with `pageViewport`, floating over terminal output that keeps scrolling underneath |
| 2 | A growable document built off screen in the other buffer, swapped in with one `pageShow`, scrolled by the program and then by your trackpad (`pageScrollMode,user=1`), with a HUD layer pinned to the viewport |
| 3 | A 220-frame animation: every frame is a new page in the other buffer; the night sky and clouds are borrowed from the previous page by reference, drawn once and rasterized once; the clouds drift by layer offset alone |
| 4 | A transparent page drawn into while visible, over live terminal output |
| 5 | `pageEnd`: the terminal underneath, untouched |

Build with Xcode, never `swift build`:

```sh
xcodegen generate
xcodebuild -scheme VPMDemo -configuration Release -derivedDataPath ~/tmp/VPMDemo/DerivedData build
```

When the script finishes the window becomes an interactive shell; run the
script again, or type page-mode sequences by hand. **App ▸ Dismiss Page** (⌘D)
is the host's escape hatch: it ends page mode without the program's help.

The script itself runs in any terminal that advertises `page=` in its VTG
capabilities — VGTerm, once its staged SwiftTerm includes page mode:

```sh
bash vpm-demo.sh
```

`VPMDemo --capture <dir>` runs the script unattended, writes an SVG snapshot
of the window every half second, and quits.
