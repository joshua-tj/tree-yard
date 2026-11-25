#!/usr/bin/env python3
"""Records a demo video of Tree Yard driven by a script, with slow waits sped up.

    record-demo.py <pool> --script "caption:Run a stack,start:1,fast:6,sleep:2,quit" --out demo.mp4

It builds the debug app, runs it with TREEYARD_RECORD so the app writes its own window as
frames, then joins the frames with ffmpeg. Every `fast:<seconds>` step in the script is shortened
to --max-wait seconds of video by dropping frames; everything else plays in real time.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
APP = REPO / "build" / "Tree Yard Debug.app" / "Contents" / "MacOS" / "TreeYard"
FPS = 12  # Matches DemoRecorder.fps in Sources/TreeYard/App.swift.


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("pool", help="worktree directory to open (use make-demo-pool.sh for a throwaway one)")
    parser.add_argument("--script", help="TREEYARD_SCRIPT steps, comma-separated")
    parser.add_argument("--script-file", help="file with one step per line (# starts a comment)")
    parser.add_argument("--out", default="demo.mp4", help="final H.264 mp4 (default demo.mp4)")
    parser.add_argument("--size", default="1160x780", help="window content size in points (default 1160x780)")
    parser.add_argument("--width", type=int, default=1600, help="video width in pixels (default 1600)")
    parser.add_argument("--max-wait", type=float, default=2.0, help="seconds each fast: step lasts in the video")
    parser.add_argument("--timeout", type=float, default=600, help="give up if the app runs longer than this")
    parser.add_argument("--gif", action="store_true", help="also write a 960px-wide GIF next to the mp4")
    parser.add_argument("--keep-frames", action="store_true", help="keep the raw frames and print where they are")
    parser.add_argument("--no-build", action="store_true", help="skip rebuilding the debug app")
    args = parser.parse_args()

    for tool in ("ffmpeg", "ffprobe"):
        if not shutil.which(tool):
            sys.exit(f"{tool} not found. Install it with: brew install ffmpeg")
    pool = Path(args.pool).resolve()
    if not pool.is_dir():
        sys.exit(f"{pool} is not a directory")

    steps = read_steps(args)
    if steps[-1] != "quit":
        steps.append("quit")

    if not args.no_build:
        print("Building the debug app…")
        build = subprocess.run([str(REPO / "scripts" / "build-app.sh"), "debug"], cwd=REPO, capture_output=True, text=True)
        if build.returncode != 0:
            sys.exit(build.stdout + build.stderr)

    frames = Path(tempfile.mkdtemp(prefix="treeyard-demo-"))
    env = dict(os.environ, TREEYARD_RECORD=str(frames), TREEYARD_SCRIPT=",".join(steps), TREEYARD_SIZE=args.size)
    print(f"Recording {len(steps)} steps…")
    try:
        subprocess.run([str(APP), str(pool)], env=env, timeout=args.timeout, capture_output=True)
    except subprocess.TimeoutExpired:
        print(f"The app was still running after {args.timeout:.0f}s and was stopped; using what was recorded.")

    # Frames are numbered by the clock; a slot the app was too busy to capture reuses the one before.
    captured = {int(p.stem.split("-")[1]): p.name for p in frames.glob("frame-*.jpg")}
    if not captured:
        sys.exit("No frames were recorded. Did the app open a window?")
    names, last = [], captured[min(captured)]
    for index in range(max(captured) + 1):
        last = captured.get(index, last)
        names.append(last)
    marks = read_marks(frames / "marks.tsv")
    keep, sped = choose_frames(len(names), marks, args.max_wait)

    sequence = frames / "sequence"
    sequence.mkdir()
    for i, index in enumerate(keep):
        os.symlink(frames / names[index], sequence / f"{i:06d}.jpg")

    out = Path(args.out).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    ffmpeg(
        "-framerate", str(FPS), "-i", str(sequence / "%06d.jpg"),
        "-vf", f"scale={args.width}:-2:flags=lanczos", "-c:v", "libx264", "-pix_fmt", "yuv420p",
        "-crf", "20", "-movflags", "+faststart", str(out),
    )
    if args.gif:
        gif = out.with_suffix(".gif")
        ffmpeg(
            "-i", str(out), "-vf",
            "fps=10,scale=960:-2:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse", str(gif),
        )
        print(f"Wrote {gif}")

    size = out.stat().st_size / 1e6
    print(f"Wrote {out}: {len(keep) / FPS:.1f}s ({size:.1f} MB), from {len(names) / FPS:.1f}s recorded")
    for label, raw, final in sped:
        print(f"  sped up {label}: {raw:.1f}s -> {final:.1f}s")
    if args.keep_frames:
        print(f"Frames kept in {frames}")
    else:
        shutil.rmtree(frames)


def read_steps(args):
    if args.script_file:
        lines = Path(args.script_file).read_text().splitlines()
        steps = [line.split("#", 1)[0].strip() for line in lines]
    elif args.script:
        steps = [step.strip() for step in args.script.split(",")]
    else:
        sys.exit("Pass --script or --script-file")
    steps = [step for step in steps if step]
    for step in steps:
        if "," in step:
            sys.exit(f"A step can't contain a comma: {step}")
    return steps


def read_marks(path):
    marks = []
    if path.exists():
        for line in path.read_text().splitlines():
            frame, _, step = line.partition("\t")
            marks.append((int(frame), step))
    return marks


def choose_frames(total, marks, max_wait):
    """Frame indexes to keep: all of them, thinned inside each fast: step."""
    budget = max(1, round(max_wait * FPS))
    keep, sped, cursor = [], [], 0
    for i, (start, step) in enumerate(marks):
        if not step.startswith("fast"):
            continue
        end = min(marks[i + 1][0] if i + 1 < len(marks) else total, total)
        if end - start <= budget:
            continue
        keep.extend(range(cursor, start))
        keep.extend(start + round(k * (end - start) / budget) for k in range(budget))
        sped.append((step, (end - start) / FPS, budget / FPS))
        cursor = end
    keep.extend(range(cursor, total))
    return keep, sped


def ffmpeg(*args):
    result = subprocess.run(["ffmpeg", "-loglevel", "error", "-y", *args], capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(result.stderr)


if __name__ == "__main__":
    main()
