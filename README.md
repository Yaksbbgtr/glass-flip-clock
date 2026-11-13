# glass-flip-clock

A single-file flip clock with a frosted-glass look. Open `index.html` in any modern browser — no build step or dependencies.

- Hours, minutes and seconds on animated split-flap cards
- Toggle between 24-hour and 12-hour (AM/PM) time; the choice is remembered
- Scales to fit phones, tablets and desktops
- Respects the system "reduce motion" setting

## Mac app and desktop widget

The `mac/` folder builds a native macOS app that contains two things:

- **Flip Clock.app** — a black, borderless window around the same `index.html`, with the full flip animation, bundled font (works offline), **Float on Top** (⌘T), **Reload** (⌘R), **Enter Full Screen** (⌃⌘F) and **Launch at Login**.
- **A real desktop widget** — a SwiftUI widget for the macOS widget gallery, in small, medium, large and extra-large sizes. Its look is set in the app: **Flip Clock → Widget Settings…** (⌘,) has a **Clear ↔ Solid** slider, **24-hour time** and **Seconds**. Apple widgets can't run web content, so this is a native re-creation of the cards with colons between them. Widgets can't run a real flip, so the digits roll into each new number instead; with seconds on, macOS refreshes the widget only about every 2 seconds, so the seconds step by two. The settings are stored in `~/Library/Application Support/FlipClock/widget-settings.json`, which the sandboxed widget is allowed to read. `fonts/FlipDigits-SemiBold.ttf` is Oswald SemiBold with equal-width digits.

```sh
brew install xcodegen   # once
./mac/build.sh
```

That produces `mac/build/Flip Clock.app`. Drag it into **Applications** and open it once. Then right-click the desktop → **Edit Widgets…**, search for *Flip Clock*, and drag the widget onto the desktop or Notification Center.

Needs Xcode. The app is signed for your own Mac only (ad-hoc); to share it with other people you'd need an Apple Developer account for proper signing and notarization.
