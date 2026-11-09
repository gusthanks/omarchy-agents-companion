# Changelog

## 2.1.0 (2026-11-09)

### Reactions

- The pet's face is now driven by an expression model (`PetFace.js`) and reactions are data
  clips (`PetClips.js`) played one at a time by `FacePlayer.qml`, with priorities and
  cooldowns.
- New reactions: yawn and doze off, wake-up stretch, startle (cursor rushing at it), curious
  head tilt (cursor resting nearby), dizzy (too many pats), wink hello, sneeze, thinking
  (while usage refreshes), "oof" (a subscription hits its cap) and a sigh (a limit stops
  being close).
- IPC `react <name>` plays a reaction by name.
- The bar pet stays cheap: no blink timers, still poses only, except short celebrate / oof.

### Pet Studio (pet settings)

- The settings are rebuilt: a stage with the pet and a random (shuffle) button, the name
  and the size in the bar on top; **Shape**, **Face**, **Extras**, **Color** and **Saved** tabs below; Undo,
  Reset and Done at the bottom.
- Pointing at an option (mouse or keyboard) tries it on the stage; a click commits it.
  Undo puts back the last random roll, reset, worn, removed, pasted or restored pet.
- Keyboard shortcuts: arrows / hjkl, Enter, 1-5 or [ ] for tabs, r, u (or Ctrl+Z), s, c / v,
  e, x / Delete / Backspace, and Esc steps back one level.
- Eye and mouth chips show the whole pet; while the settings are open, only the pet being edited
  is shown.

### Personality

- Face tab: **Lively** (every reaction and little fidgets), **Calm** (reacts to you, no idle
  fidgets) or **Still** (poses only, no animated reactions), shown as three cards.
- A Try row previews Wink, Startle, Dizzy, Yawn and Party (celebrate) on the stage.

### Backup and PNG

- **Back up all** writes the current pet, saved pets, size and personality to
  `agents-pet-backup.json` in your Documents folder (XDG, or `~`); **Restore** reads it back
  with the same checks as pasted codes.
- **Save PNG** saves the pet as a transparent 1024 px image in your Pictures folder (XDG).
- Saved pets are capped at 24.

### Panel

- The tip box is now one line under the pet's name: hover it to read the whole tip, › for
  the next one. Limit alerts stay red.
- The hero pet is centered on the name, token count and tip line.

### Development

- `dev/run.sh`: an isolated Quickshell harness (never touches the running bar) with offscreen
  captures of the docs images, a demo GIF, a `png` mode that checks PNG export, backup /
  restore and editor keys in a temp folder, and a `check` mode that compiles every type,
  `Panel.qml` included.
- `dev/deploy.sh` fast-forwards the installed plugin to the committed HEAD, refuses broken
  QML, and restarts the shell once.
- `AGENTS.md` describes the workflow.

## 2.0.0 (2026-11-09)

The plugin becomes **Agents Pet** (`gusthx.agents-pet`), built on Omarchy's stock Agents panel.

- The headless chat, model picker and their settings are gone; the companion is now a
  flat, sculptable pet drawn in one Canvas from a "look" (body, eyes, mouth, head extra,
  accessory, style, cheeks, color).
- The bar icon is the pet itself, sized from the bar height.
- In the panel it breathes, blinks and follows the cursor across the screen; click it for a
  pat (squish, heart, a hop after a few).
- Moods from the limits: worried when one is close, tired when every subscription is maxed
  out, confetti when one comes back. Dozes off when the mouse is still.
- Seasonal hats: Santa hat on Dec 24–25, party hat on Dec 31 / Jan 1.
- Live tips (limits with reset times, a quieter subscription, tokens today and per session,
  a late-night nudge) plus general agent tips, with a › next-tip button.
- Pet settings with sizes (S / M / L), accessories, theme colors that follow theme switches,
  a color picker / hex code, saved pets and copy / paste as a short JSON code.
- Own IPC target and i18n catalog (stock panel strings in 50 languages, pet strings in
  English and Brazilian Portuguese). The repository root is the plugin folder.
