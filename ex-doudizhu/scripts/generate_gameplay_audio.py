#!/usr/bin/env python3
"""Generate every persona's gameplay clips from the audio manifest.

Requires `gradio_client` and `ffmpeg`. Existing clips are retained unless
`--force` is passed, so interrupted runs can be resumed safely.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

from gradio_client import Client

PROJECT_ROOT = Path(__file__).resolve().parents[1]
AUDIO_ROOT = PROJECT_ROOT / "priv/static/audio/gameplay"
MANIFEST_PATH = AUDIO_ROOT / "manifest.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--persona",
        action="append",
        dest="personas",
        help="Generate only this manifest persona ID; may be repeated.",
    )
    parser.add_argument(
        "--cue",
        action="append",
        dest="cues",
        help="Generate only this cue filename; may be repeated.",
    )
    parser.add_argument(
        "--force", action="store_true", help="Replace clips that already exist."
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=1,
        help="Number of personas to generate concurrently (default: 1).",
    )
    return parser.parse_args()


def cue_entries(node: Any) -> list[tuple[str, str, dict[str, Any]]]:
    if not isinstance(node, dict):
        return []
    if "file" in node:
        return [(node["file"], node["text"], node.get("post_processing", {}))]
    return [
        cue
        for child in (node.get("variants") or node).values()
        for cue in cue_entries(child)
    ]


def provider_option(
    client: Client, api_name: str, parameter_name: str, simple_name: str
) -> str:
    endpoint = next(
        endpoint
        for endpoint in client.endpoints.values()
        if endpoint.api_name == api_name
    )
    parameter = next(
        parameter
        for parameter in endpoint.parameters_info
        if parameter["parameter_name"] == parameter_name
    )
    choices = parameter["type"].get("enum", [])

    for choice in choices:
        if choice == simple_name or choice.partition("/")[0].strip() == simple_name:
            return choice

    raise ValueError(
        f"Provider has no {parameter_name} option matching {simple_name!r}"
    )


def audio_filters(post_processing: dict[str, Any]) -> list[str]:
    silence = post_processing.get("compress_silence")
    if not silence:
        return []

    threshold = silence["threshold_db"]
    minimum = silence["minimum_duration_ms"] / 1000
    retained = silence["retained_duration_ms"] / 1000
    value = (
        "silenceremove="
        f"start_periods=1:start_duration=0.02:start_threshold={threshold}dB:"
        f"stop_periods=-1:stop_duration={minimum}:stop_threshold={threshold}dB:"
        f"stop_silence={retained}:detection=rms"
    )
    return ["-af", value]


def generate_persona(
    persona_id: str,
    persona: dict[str, Any],
    cues: list[tuple[str, str, dict[str, Any]]],
    generation: dict[str, str],
    force: bool,
) -> tuple[str, int]:
    client = Client(generation["space"], verbose=False)
    generated_count = 0
    base_path = AUDIO_ROOT / persona["base_path"]
    speaker = provider_option(
        client,
        generation["api_name"],
        "voice_display",
        persona["generation"]["speaker"],
    )
    language = provider_option(
        client,
        generation["api_name"],
        "language_display",
        persona["generation"]["language"],
    )

    for index, (filename, text, post_processing) in enumerate(cues, start=1):
        if Path(filename).name != filename:
            raise ValueError(f"Cue file must be a plain filename: {filename!r}")

        destination = base_path / filename
        if destination.exists() and not force:
            continue

        destination.parent.mkdir(parents=True, exist_ok=True)
        print(f"[{persona_id} {index:02}/{len(cues)}] {text}", flush=True)

        for attempt in range(1, 5):
            try:
                source = client.predict(
                    text=text,
                    voice_display=speaker,
                    language_display=language,
                    api_name=generation["api_name"],
                )
                break
            except Exception:
                if attempt == 4:
                    raise
                time.sleep(2**attempt)

        temporary = destination.with_suffix(".tmp.mp3")
        subprocess.run(
            [
                "ffmpeg",
                "-hide_banner",
                "-loglevel",
                "error",
                "-y",
                "-i",
                str(source),
                *audio_filters(post_processing),
                "-ac",
                "1",
                "-ar",
                "48000",
                "-codec:a",
                "libmp3lame",
                "-b:a",
                "160k",
                str(temporary),
            ],
            check=True,
        )
        temporary.replace(destination)
        generated_count += 1

    return persona_id, generated_count


def main() -> None:
    args = parse_args()
    if args.workers < 1:
        raise SystemExit("--workers must be at least 1")

    manifest = json.loads(MANIFEST_PATH.read_text())
    personas = manifest["personas"]
    selected_ids = args.personas or list(manifest["player_voice_assignment"]["personas"])

    unknown = set(selected_ids) - set(personas)
    if unknown:
        raise SystemExit(f"Unknown persona IDs: {', '.join(sorted(unknown))}")

    cues = cue_entries(manifest["events"])
    filenames = [filename for filename, _text, _processing in cues]
    if len(filenames) != len(set(filenames)):
        raise SystemExit("Manifest contains duplicate cue filenames")

    if args.cues:
        unknown_cues = set(args.cues) - set(filenames)
        if unknown_cues:
            raise SystemExit(f"Unknown cue filenames: {', '.join(sorted(unknown_cues))}")
        cues = [cue for cue in cues if cue[0] in args.cues]

    generation = manifest["pack"]["generation"]
    with ThreadPoolExecutor(max_workers=min(args.workers, len(selected_ids))) as executor:
        results = executor.map(
            lambda persona_id: generate_persona(
                persona_id,
                personas[persona_id],
                cues,
                generation,
                args.force,
            ),
            selected_ids,
        )

    for persona_id, generated_count in results:
        print(f"{persona_id}: generated {generated_count} clip(s)")


if __name__ == "__main__":
    main()
