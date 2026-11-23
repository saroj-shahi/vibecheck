# VibeCheck for Raycast

See how your Mac is doing (vibing, mid or cooked) and what's behind it, without opening the deck.

This extension reads the status from VibeCheck's bundled `vibecheck` command (`vibecheck status --json`). It
looks for it at `/Applications/VibeCheck.app/Contents/Helpers/vibecheck`, then `~/Applications/...`, then
`vibecheck` on your PATH. If none is found, or VibeCheck hasn't run yet, the commands say so.

## Commands

- **Mac Vibe**: the verdict, every reading, culprits, agent limits (left, resets in) and dev servers when
  VibeCheck reports them. Actions: Open VibeCheck, Copy Status.
- **Vibe in Menu Bar**: the vibe word in the menu bar (refreshes every minute), with top readings and culprits.
- **Culprits**: the apps behind a mid or cooked Mac, by memory (or by CPU while the deck has it on).

## Develop

```bash
npm install
npm run build   # ray build
npm run dev     # ray develop
```

The icon is a copy of `branding/png/icon-512.png`. This extension isn't published to the Raycast Store.
