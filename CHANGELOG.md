# Changelog

## Unreleased

### Pet Studio

- A **Recent** row on the Color tab keeps your last 8 custom colors; click or press Enter to
  reuse one. Undo and Reset leave it alone, and backups carry it.
- Four new head extras: **Halo** (floats and bobs over the head), **Tuft**, **Bunny ears**
  and a **Unicorn horn**; "Ears" is now called **Cat ears**. Four new accessories:
  **Headphones**, **Crown**, **Scarf** and **Bow tie**. All of them fit every body, in
  solid and outline, in the bar and the panel, and follow the squash and breathing.
  The crown counts as a hat (the seasonal hat replaces it for the day), and any hat hides
  the extras that grow from the top of the head (antenna, leaf, tuft, horn, halo); ears
  and horns stay. Headphones go over the head and under a seasonal hat; scarf and bow tie
  sit low on the body with anything on top, and big mouths move up to stay clear of them.
  The Extras tab wraps both kinds of chips five to a row.
- Four new eyes: **Star**, **Sparkly** (big anime eyes with glints), **Cyclops** (one big
  eyeball whose pupil follows the cursor) and **Heart** (beats softly). Four new mouths:
  **Fang** (a light tooth under a small smile), **Tongue**, **Grin** and **Smirk** (a half
  smile with a dimple). Every reaction reads with them; the cyclops gets a single brow (it
  arches when worried, tilts when curious), one squeezed `><` eye, one spiral, a wink that
  shuts its eye, and glasses become one round lens, with the mouth kept clear of it at
  every eye size. At bar size the sparkly eyes get one big glint so they don't read as
  dots, and fine details (the fang's rim, the smirk's dimple) are left out.
- **Eye size** and **mouth size** (XS to XL) in the **Face** tab, saved with the look
  (saved pets, codes, backups, PNG, undo and reset; shuffle stays near the middle).
  Eyes and brows stay inside every body at the largest size, and a big mouth or a yawn
  shrinks or moves up instead of hanging off the bean's dent. Looks without them keep the
  usual size. The Face tab is now taller than the others, which stay compact.
- Four new bodies: **Cloud** (puffs that swell in turn), **Egg**, **Mochi** (a soft dome
  that jiggles) and **Bean** (a kidney bean resting on its ends). Each one squashes and
  breathes, comes in solid and outline, and wears every head extra, accessory and seasonal
  hat in the right place (smaller hats and closer ears on the egg's narrow top). The body
  chips wrap to a second row; shuffle picks the new bodies too.
- The pet's size in the bar and in the panel are now two settings (S / M / L each), in the
  **Shape** tab; the stage header keeps the pet and its name. Configs and backups with the
  old single `size` use it for both until one is changed, and the config still gets a
  `size` (the bar's) so an older copy of the plugin reading the same file keeps working.

### Panel

- The tip under the pet's name is shown whole, wrapped over up to four lines, instead of
  one line that only opened on hover. The pet and the name stay put as tips of different
  lengths rotate; the panel below eases to the new height. Hovering still pauses the
  rotation, and the › button now fades to the next tip like the timed rotation.

## 2.1.1 (2026-11-09)

### Panel

- Hero layout: the pet is centered against the name, token count and tip line, which now
  sit together as one block; the tip line spans to the panel's edge.

### Docs and license

- `LICENSE` is the plain MIT text again (GitHub detects it), with the upstream Omarchy
  copyright line kept; the manifest author is "Gustavo Costa (gusthx)".
- README reorganized (Install / update / uninstall, Use, Configuration, Privacy,
  Development, Changes, Credits, License) and translated to Brazilian Portuguese in
  `README.pt-BR.md`.
- `docs/demo.gif` is shorter (about 12 s): cursor, pats, party, startle, dizzy, dozing off
  and a few looks.

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
