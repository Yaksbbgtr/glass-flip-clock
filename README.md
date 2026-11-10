# glass-flip-clock

A single-file flip clock with a frosted-glass look. Open `index.html` in any modern browser — no build step or dependencies.

- Hours, minutes and seconds on animated split-flap cards
- Toggle between 24-hour and 12-hour (AM/PM) time; the choice is remembered
- Scales to fit phones, tablets and desktops
- Respects the system "reduce motion" setting

## Mac app

The `mac/` folder turns the clock into a native macOS app (a thin native window around the same `index.html`, bundled with the font so it works offline).

```sh
./mac/build.sh
```

That produces `mac/build/Flip Clock.app`. Drag it into **Applications** and open it like any other app. The **View** menu has **Float on Top** (⌘T), **Reload** (⌘R) and **Enter Full Screen** (⌃⌘F); the app menu has **Launch at Login**. The window remembers its size and position.

Needs Xcode or the Command Line Tools. The app is signed for your own Mac only (ad-hoc); to share it with other people you'd need an Apple Developer account for proper signing and notarization.
