# Tearsheet

A personal macOS menu-bar app for region screenshots and light annotation. Spec and issues: [Linear](https://linear.app/howells/project/tearsheet-20262a013424).

```sh
scripts/install.sh
```

Then turn off both "selected area" shortcuts in System Settings → Keyboard → Keyboard Shortcuts → Screenshots so ⇧⌘4 reaches Tearsheet, and grant Screen Recording when asked.

To publish a notarised release of the version in `project.yml`:

```sh
ASC_ISSUER_ID=<uuid> scripts/release.sh
```
