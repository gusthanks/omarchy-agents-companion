# omarchy-agents-companion

**Kian** — a small animated blob that lives in your [Omarchy](https://omarchy.org) bar panel.
He watches your AI-agent usage (Claude, Codex, Antigravity, …), warns you before you hit a
limit, and answers questions about your laptop through a headless `agy` agent. Click him,
ask him, swap his brain.

> Built on top of Omarchy's stock **Agents** panel (MIT). Everything the stock panel does —
> limits, pace, balances, multi-account — is still here. The companion sits on top.

## What you get

- **A living avatar** — a soft blob with blinking eyes, idle breathing, and moods
  (idle, thinking, speaking, happy, alert). It follows your Omarchy theme colors.
- **One calm tip banner** — usage insights (tokens today/this week, top model, burn rate,
  limit warnings). One line of advice at a time, slow enough to actually read.
- **Chat with Kian** — type in the panel and he answers via a headless
  [`agy`](https://antigravity.google) run. He gets a short snapshot of your machine
  (OS, battery, token totals, quota alerts), so "why is my battery draining?" or "how much
  quota do I have left?" gets a real answer. Conversation continues across turns.
- **Swappable brain** — the model name sits next to his name. Click it to switch between
  every model `agy models` reports on your machine, on demand. The choice is remembered.
- **Customizable** — rename him, set the default model and reasoning effort.

Kian is meant for *general, whole-machine* questions. Keep using your terminals for
project-specific work.

## Requirements

| Requirement | Why |
|---|---|
| Omarchy with the shell plugin system | hosts the panel |
| [`agy`](https://antigravity.google) (Antigravity CLI), signed in | powers the chat |
| `rsync` (installer only) | copies the plugin |

## Install

```bash
git clone https://github.com/gusthanks/omarchy-agents-companion.git
cd omarchy-agents-companion
./scripts/install.sh
omarchy restart shell
```

The installer copies `plugin/` to `~/.config/omarchy/plugins/gusthx.agents/`. If you already
have a plugin there, it is backed up first (`gusthx.agents.bak.<timestamp>`).

Then add the **My Agents** widget to your bar (or keep it if it is already there).

> [!WARNING]
> Do **not** run `omarchy refresh shell` to reload — that resets your bar layout.
> Use `omarchy restart shell`.

## Configuration

Open the widget settings from the bar, or edit the widget's entry in
`~/.config/omarchy/shell.json`:

| Key | Default | Description |
|---|---|---|
| `companionName` | `Kian` | Your companion's name. |
| `companionModel` | `gemini-3.8-flash-medium` | `agy` model id used for chat. |
| `companionEffort` | `medium` | Reasoning effort: `low`, `medium`, `high`. |

Available models come from `agy models`; pick one live from the model button in the panel.

You can also drive the model from the shell IPC target `omarchy.agents`
(`getModel` / `setModel`).

## How chat works

Each question runs:

```bash
agy -p "<prompt>" --model <model> --effort <effort> \
    --dangerously-skip-permissions --output-format text
```

The first turn includes Kian's persona plus a one-paragraph machine snapshot; later turns
resume the same conversation with a refreshed snapshot.

> [!IMPORTANT]
> `--dangerously-skip-permissions` lets the headless agent run tools without asking.
> Kian is told to answer, not to change things — but you are trusting the model. If that is
> not acceptable for you, don't use the chat box (the avatar and tips work without it).

## Repository layout

```
plugin/          the Omarchy plugin (what gets installed)
  Panel.qml        bar button + panel, insights, model discovery
  CompanionView.qml  speech card, chat input, agy runner
  BlobAvatar.qml     animated blob
  BrainSelector.qml  model picker
  Main.qml, Agent.qml, collectors.py, assets/   stock Agents plugin pieces
scripts/
  install.sh       install into ~/.config/omarchy/plugins
  sync.sh          copy your live plugin back into the repo and push (dev)
```

## Development

The live plugin directory is the source of truth while hacking. `scripts/sync.sh` mirrors it
into `plugin/`, commits, and pushes. An optional systemd user service
(`scripts/omarchy-agents-companion-sync.service`) runs it automatically a few seconds after
you stop editing.

## Credits

- Stock Agents panel: the Omarchy project (MIT).
- Blob avatar style inspired by
  [smontlouis/bible-strong-avatar-lab](https://github.com/smontlouis/bible-strong-avatar-lab).

## License

MIT — see [LICENSE](LICENSE).

---

*Português: em breve. / Portuguese docs coming soon.*
