---
name: capture-demo-video
description: Records a short demo video of a change in the Tree Yard Mac app by driving the debug build with a script and having the app write its own window as frames, speeding up slow waits like a stack booting, and gets it ready to attach to a pull request. Use when the user invokes /capture-demo-video, or asks for a demo video, screen recording or GIF of a change, including as part of opening a PR.
---

# Record a demo video

Tree Yard is a native SwiftUI app, so there is no browser to drive. Instead the debug build
records itself: with `TREEYARD_RECORD` set it writes its window as numbered frames while
`TREEYARD_SCRIPT` drives the store, and
[`scripts/record-demo.py`](scripts/record-demo.py) joins the frames into an H.264 mp4 that plays
inline on GitHub. Every `fast:<seconds>` step is shortened to at most `--max-wait` seconds of
video; everything else plays in real time.

The video is a demo for reviewers, not a substitute for testing the change.

## 1. Requirements

- **macOS with the Swift toolchain** this repo already builds with (`./scripts/build-app.sh debug`).
- **ffmpeg and ffprobe**: `brew install ffmpeg`.
- **python3**, which ships with the Command Line Tools.
- No screen-recording permission is needed: the app draws its own window into the frames.

## 2. What the recording can and can't show

The app captures its own view, not the screen. That shapes every scenario:

| Shows | Doesn't show |
|---|---|
| Tiles, dialogs, the app's dropdown menus, captions | The pointer, hover states and tooltips |
| State changes: Starting, Running, the rain orb, counts | System alerts (the window only dims) |
| Anything a script step can set off | VS Code, the terminal, Claude or a browser opening |

If the change is only visible on hover or in a system alert, say so and offer a still instead:
`TREEYARD_TIPS=1` with `TREEYARD_SNAPSHOT` shows every tooltip at once (see the README's
Development section). Don't fake it with a different change.

## 3. Use a throwaway pool

**Never record against the user's real worktree directory.** Script steps really run: `start`
boots a dev stack, `release` runs the pool's release command, `rebase` rewrites a branch.

```bash
.claude/skills/capture-demo-video/scripts/make-demo-pool.sh <scratchpad>/demo
```

It prints the pool path. The pool has four slots: 1 has a commit and uncommitted work, 2 and 3 are
behind main, 4 is free. Its `treeyard.json` starts two small local web servers per slot (ports
`41<slot>0` and `41<slot>1`) and has a four-second `install`, so Run, Stop, services and Install
all have something to show. Re-running the script rebuilds the pool from scratch, which is how to
reset between takes. Edit the pool's `treeyard.json` or its checkouts when the change needs a
different starting state.

A scripted run never changes which directory the real app opens next, and uses the same
preferences (terminal, rebase or merge) as the real app.

## 4. Write the scenario

Read the branch diff (`git diff origin/main...HEAD`) and decide the shortest path that shows the
change: usually 10 to 30 seconds of final video. Write the steps to a file in the scratchpad, not
the repo, starting from [`examples/run-and-stop.steps`](examples/run-and-stop.steps). One step per
line; `#` starts a comment.

| Step | |
|---|---|
| `caption:<text>` | Shows a caption pill at the bottom until the next caption. `caption` alone hides it. No commas |
| `sleep:<seconds>` | Waits in real time: a beat for the viewer to read the result |
| `fast:<seconds>` | Waits, and the video speeds through it. Use for anything slow |
| `start:<slot>`, `stop:<slot>` | Run or stop the dev stack (`stop` returns once it is down) |
| `rebase:<slot>` | Rebase or merge onto main, whichever Settings is set to |
| `install:<slot>` | Run the pool's `install` command |
| `switch:<slot>:<branch>`, `create:<slot>:<branch>` | Check out or create a branch |
| `release:<slot>` | Release the slot without the dialog |
| `refresh` | The manual refresh, with its orb |
| `dialog:branch:<slot>`, `dialog:new:<slot>`, `dialog:release:<slot>`, `dialog:settings`, `dialog:setup` | Open a dialog |
| `menu:header`, `menu:tile`, `menu:services` | Open a dropdown. These are stand-ins drawn at a fixed spot, not the real menus: check the picture before relying on one |
| `close` | Close any open dialog or menu |
| `quit` | End the take. Added for you if missing |

The steps live in `Store.run(script:)` in `Sources/TreeYard/Store.swift`, inside `#if DEBUG`. If
the change needs an interaction no step covers, add a step there: it is the intended place, and
it keeps the next demo easy.

Rules for a good demo:

- **Use `fast:` for every slow wait** (a stack booting, an install, a fetch) and `sleep:` only for
  reading beats. Steps other than `stop`, `switch`, `create` and `release` return at once, so
  follow them with a wait long enough for the result to show.
- **Size waits generously.** A `fast:` that is longer than needed costs nothing in the final
  video; one that is too short cuts the result off.
- **Caption each beat** in a few words, so the video makes sense with no narration.
- **End on the result** with a `sleep:2`, so the last frame is the thing being shown.

## 5. Record

```bash
.claude/skills/capture-demo-video/scripts/record-demo.py <pool> \
  --script-file <scratchpad>/scenario.steps --out <scratchpad>/demo.mp4
```

| Flag | Default | |
|---|---|---|
| `--script-file` / `--script` | | Steps from a file, or comma-separated on the command line |
| `--out` | `demo.mp4` | Final H.264 mp4 |
| `--size` | `1160x780` | Window content size in points |
| `--width` | `1600` | Video width in pixels |
| `--max-wait` | `2` | Seconds each `fast:` step lasts in the final video |
| `--gif` | off | Also write a 960px-wide GIF |
| `--keep-frames` | off | Keep the raw frames and print where they are |
| `--no-build` | off | Skip rebuilding the debug app |
| `--timeout` | `600` | Stop the app if a take runs longer than this many seconds |

The script rebuilds the debug app, so the video always shows the current working tree. It prints
the final length, the recorded length and each sped-up range. The app window opens on the user's
screen while it records and closes itself at the end; tell the user before a long take.

Afterwards, check nothing was left running: `lsof -nP -iTCP -sTCP:LISTEN | grep 41` should be
empty. If a take was interrupted mid-stack, stop the leftover servers by their process id, not by
name.

## 6. Check the video before sharing

Look at it rather than trusting the exit code: extract a contact sheet and read it.

```bash
ffmpeg -loglevel error -y -i demo.mp4 -vf "fps=1,scale=640:-1,tile=4x4" -frames:v 1 sheet.png
```

Confirm the change is actually visible, each caption matches what is on screen, and no dimmed
window (a system alert the recording can't show) covers the result. Re-record if not. Keep the
file under 10 MB, GitHub's limit for free accounts; these videos are usually well under 1 MB.

## 7. Attach it to the pull request

**Never commit the video to the repo.** Before pushing anything, review the diff for unwanted
content as usual. Then pick the route by what this session can use:

**`gh` 2.99.0 or newer** (check `gh --version`; that release added `--attach`). It uploads the
file and embeds it inline:

```bash
gh pr create --title "..." --body-file body.md --attach demo.mp4
```

For an existing PR, use `gh pr edit <number> --attach demo.mp4` or
`gh pr comment <number> --body "Demo: <what it shows>" --attach demo.mp4`. Then run
`gh pr view <number>` and confirm a `https://github.com/user-attachments/assets/...` link is in
the body or comment.

**Otherwise:**

1. Add a `## Demo` section to the PR body with a placeholder line,
   `_Demo video: drag demo.mp4 here_`, plus one sentence on what the video shows.
2. Give the user the absolute path of the file.
3. Tell the user to edit the PR description and drag the file onto the placeholder; GitHub
   uploads it and renders an inline player.
