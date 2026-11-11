# Changelog

## 2.2.0 (2026-11-11)

Two upgrades in one release: the Pet Studio grows (new bodies, faces, extras, sizes and
recent colors), and the usage panel learns pacing, "Use first", desktop notifications and
clearer notices, ported from ai-usagebar (MIT).

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

- Clearer usage notices: a small icon for the kind of trouble (sign-in, network, rate
  limit), a readable message, and "Rate limited — trying again in 4m" when the wait is
  known. When a notice names the sign-in command of an installed agent CLI (`cursor-agent
  login`, `claude auth login`, `kimi login`...), a **Fix** button opens it in a floating
  terminal and fetches the limits again once it closes. Only each CLI's own sign-in
  argument lists are accepted (no flags, prompts or other subcommands, since provider error
  text reaches the notice), and they run as arguments, never as a shell string. The notice
  beside it wraps to two lines, with the whole text on hover. Only real throttling wording
  counts as a rate limit: "answered without its rate limits" or a gateway holding requests
  "until the account has credits again" is not. "Fixing…" shows only on the account being
  fixed, and the button frees up again if the terminal fails to start or is closed.
- The tip under the pet's name is shown whole, wrapped over up to four lines, instead of
  one line that only opened on hover. The pet and the name stay put as tips of different
  lengths rotate; the panel below eases to the new height. Hovering still pauses the
  rotation, and the › button now fades to the next tip like the timed rotation.
- **Pace on the limit meters**: an accent tick where usage would be at an even pace, an
  arrow beside the percentage (↑ ahead, → on track, ↓ under, turned around right-to-left;
  read as the share left, the arrow follows that number, so ahead points down) and a
  tooltip line with where that pace leads ("hits the limit in 1d 9h", "~92% left at
  reset"). Rows stay aligned with or without it.
- New widget settings: `showAs` (`Used` / `Left`; the alarm still follows the share used),
  `colorCodeUsage` (meters green → yellow → orange → red from the theme), `showPace`, and
  `moodWindow` (`Auto` / `Session` / `Weekly`: which limits make the pet worried or out of
  breath). Values are read in any case; configs without them keep today's look.
- Kian gets **out of breath** (open mouth with the tongue showing, flushed cheeks, quick
  breaths, a sweat drop and puffs) when a limit is burning at least 15 points ahead of an
  even pace with 20% or more used and no cap near yet; worried and tired win over it. A
  matching tip says when that limit would run out, and takes the place of "limits look
  healthy".
- **Use first**: when one of several subscriptions would reset with room left over, a
  section above the agents lists them in the order worth using, from the use-it-or-lose-it
  ranking: each with its state (urgent, spare, on pace, running out, spent) and why ("~60%
  of the weekly would go unused, resets in 20h", "At this pace it runs out in 2d 7h").
  "On pace" is kept for a quota that lands near the cap at its reset; one that would run
  out well before it says so and ranks below. Agents without current numbers are left to
  their own section. Each line is a keyboard stop; Enter or a click goes to its limits (to Use, for an
  account new sessions don't take yet), and hovering shows the numbers behind its place.
- Kian gets **hungry** (licking his lips with a drop of drool in the theme's cyan, eager
  eyes on a fork and knife; at bar size just the tongue) while a weekly quota is urgent: at least `alertUnusedPercent` projected unused and
  a reset within `alertHours`. Tired, worried and out of breath win over it. A tip says
  so, with the same projected unused share as its "Use first" line: "Codex would leave ~55%
  of its weekly quota unused by the reset in 20h".
- New widget settings: `showPriorities` (off, nothing is ranked or recorded),
  `recentHours`, `alertUnusedPercent`, `alertHours` and `priorityMood`. Configs without
  them get the defaults.

### Notifications

- **Desktop notifications** after fresh fetches, through `notify-send` (argv, never a
  shell) as "Agents Pet": normal when a limit reaches `notifyThreshold` (default 97%),
  critical (30 s) when that limit is then spent (or at once, if the first crossing is
  already at 100%), and one heads-up per Codex free reset expiring within 48 hours. Worded in Kian's calm voice in English and Brazilian Portuguese, with his face
  as the icon (`~/.cache/omarchy/agents-pet/kian-icon.png`, redrawn when the look or theme
  changes; no icon until it is). One notice per crossing, re-armed 7 points below the
  threshold or by a new window; the state is written atomically to
  `~/.local/state/omarchy/agents-pet/notify-state.json` before anything is shown, and any
  failure skips the notice. Readings already on disk when the plugin starts, from a source
  the state has never seen (first run, lost state), are recorded quietly. A provider
  gaining or losing an account hands its notified windows (and its recent-pace history) to
  the active account, so nothing repeats; a fetch stamped in the future (a clock running
  ahead) is ignored instead of silencing the ones after it.
- Kian jumps with a startled "!" (the new **alert** reaction, shown on the bar too) when a
  notice goes out, and lets out his "oof" for a cap, only once when the meters see it too.
- New widget settings: `notifications` (default on) and `notifyThreshold` (50–100).

### Usage math

- The limit-window rules (titles, lengths, expired resets) moved from the panel to
  `usage/Window.js`; the panel shows the same thing. A limit titled after a model alone
  (Antigravity's "Argon (7-day)") takes its length from the label, so it gets pace, counts
  as weekly for `moodWindow`, and, as a model's own allowance, never blocks its
  subscription in "Use first".
- New pure, tested libraries in `usage/`: pacing with a projection to the reset (now shown
  on the meters), a use-it-or-lose-it priority across subscriptions and accounts (now shown
  under "Use first"), limit and reset credit notification decisions (now sent as desktop
  notifications) and notice parsing (now behind the notices and the Fix button). Ported
  from ai-usagebar (MIT).
- The panel keeps the last 25 hours of fresh limit readings in
  `~/.local/state/omarchy/agents-pet/usage-history.json` (percentages and reset times
  only), for the priority's recent pace, while `showPriorities` is on.
- `usage/Display.js` (ported from ai-usagebar): used / left readings, color rungs, the pace
  arrow, the mood's windows and when the pet pants.
- `dev/run.sh test` runs the Node tests; `dev/run.sh check` also compiles `usage/`.

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
