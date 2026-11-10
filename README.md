# glass-flip-clock

A single-file flip clock with a frosted-glass look. Open `index.html` in any modern browser — no build step or dependencies.

- Hours, minutes and seconds on animated split-flap cards
- Toggle between 24-hour and 12-hour (AM/PM) time; the choice is remembered
- Scales to fit phones, tablets and desktops
- Respects the system "reduce motion" setting

## Mac app and desktop widget

The `mac/` folder builds a native macOS app that contains two things:

- **Flip Clock.app** — a black, borderless window around the same `index.html`, with the full flip animation, bundled font (works offline), **Float on Top** (⌘T), **Reload** (⌘R), **Enter Full Screen** (⌃⌘F) and **Launch at Login**.
- **A real desktop widget** — a SwiftUI widget for the macOS widget gallery, in small, medium and large sizes, with **24-hour time** and **Seconds** options (right-click the widget → *Edit "Flip Clock"*). Apple widgets can't run web content, so this is a native re-creation of the cards: hours and minutes change with a slide transition, and the seconds card is a live counter (no flip). `fonts/FlipDigits-SemiBold.ttf` is Oswald SemiBold with equal-width digits, which the seconds counter needs.

```sh
brew install xcodegen   # once
./mac/build.sh
```

That produces `mac/build/Flip Clock.app`. Drag it into **Applications** and open it once. Then right-click the desktop → **Edit Widgets…**, search for *Flip Clock*, and drag the widget onto the desktop or Notification Center.

Needs Xcode. The app is signed for your own Mac only (ad-hoc); to share it with other people you'd need an Apple Developer account for proper signing and notarization.
