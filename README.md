# Agents Pet

**Kian**: a small flat pet that lives in your [Omarchy](https://omarchy.org) Agents panel.
It keeps you company while you work, follows your cursor around the screen, and shows calm
tips about your AI-agent usage (Claude, Codex, Antigravity, …). You can reshape it however
you like.

> Built on top of Omarchy's stock **Agents** panel (MIT). Everything the stock panel does
> (limits, pace, balances, multi-account) is still here. The pet sits on top.

## What you get

- **A living pet**: a flat, theme-aware creature that breathes, blinks, and hops when
  clicked. While the panel is open, its eyes follow your cursor anywhere on the screen.
  It turns your theme's urgent color when a limit is close.
- **One calm tip banner**: usage insights (tokens today, top model, session pace, limit
  warnings). One line at a time, slow enough to read. Click the pet or the banner for the next one.
- **A pet editor**: click the pencil in the panel header to sculpt it.
  - Body: blob, orb, squircle, drop, ghost
  - Eyes: capsule, dot, googly, pixel, sleepy
  - Mouth: none, smile, o, cat, flat
  - Extra: antenna, leaf, ears, horns
  - Style: solid or outline, cheeks on or off
  - Color: follow the Omarchy theme, or pick a swatch
  - Name, 🎲 random, reset

  Changes apply live and are saved to `~/.config/omarchy/agents-pet.json`.

## Install

```bash
omarchy plugin add https://github.com/gusthanks/omarchy-agents-pet.git --enable
```

Update later with `omarchy plugin update gusthx.agents-pet`.

> [!NOTE]
> Agents Pet replaces the stock **Agents** bar widget. Keep only one of them in your bar.

## Configuration

| Where | What |
|---|---|
| Pencil button in the panel | Pet look and name (saved in `~/.config/omarchy/agents-pet.json`) |
| Widget settings / `shell.json` → `companionName` | Fallback name when the editor hasn't set one |
| Widget settings / `shell.json` → `refreshIntervalSec`, `sync*` | Same as the stock Agents panel |

IPC (`omarchy-shell gusthx.agents-pet <method>`): `open`, `close`, `toggle`, `refresh`,
`nextInsight`, `editPet`.

## Repository layout

The repository root is the plugin folder, the layout `omarchy plugin add` expects.

```
manifest.json    plugin manifest (id gusthx.agents-pet)
Panel.qml        bar button + panel, insights, pet wiring
BlobAvatar.qml   the pet (one Canvas, drawn from a "look" object)
PetEditor.qml    inline sculptor with live preview
i18n/            en + pt-BR strings
Main.qml, Agent.qml, collectors.py, assets/   stock Agents plugin pieces
```

## Development

Clone the repo straight into your plugin folder; the shell reloads on save:

```bash
git clone https://github.com/gusthanks/omarchy-agents-pet.git ~/.config/omarchy/plugins/gusthx.agents-pet
omarchy plugin validate ~/.config/omarchy/plugins/gusthx.agents-pet
```

If IPC changes don't show up after a hot reload, run `omarchy restart shell`
(never `omarchy refresh shell`, which resets your bar layout).

## Credits

- Stock Agents panel: the Omarchy project (MIT).
- Parametric pet idea inspired by the Hermes Agent mobile app's bot sculptor.

## License

MIT. See [LICENSE](LICENSE).
