# Tearsheet

A macOS menu-bar app for region screenshots, light annotation and copying original images from Safari and Chrome. Download it from [tearsheet.danielhowells.com](https://tearsheet.danielhowells.com). Spec and issues: [Linear](https://linear.app/howells/project/tearsheet-20262a013424).

```sh
scripts/install.sh
```

Then turn off both "selected area" shortcuts in System Settings → Keyboard → Keyboard Shortcuts → Screenshots so ⇧⌘4 reaches Tearsheet, and grant Screen Recording when asked.

To publish a notarised release of the version in `project.yml` (needs the Developer ID Application certificate in the keychain):

```sh
scripts/release.sh
```

The website is in `site/`: plain HTML and Tailwind v4, built locally and deployed to Vercel with `vercel build --prod && vercel deploy --prebuilt --prod`.
