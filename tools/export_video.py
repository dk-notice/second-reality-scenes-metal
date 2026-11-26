#!/usr/bin/env python3
"""Exports Play Demo (Modern look) to a video file for YouTube.

    python3 tools/export_video.py [--seconds N] [output.mov]

Makes ~/Movies/SecondReality-Modern.mov: 2880x2160, 60 pictures a second, ProRes 422, with the music as
uncompressed 16-bit stereo sound. Needs the app built (./build.sh) and ffmpeg (a development tool only:
the app and build.sh never use it). `--seconds N` stops after the first N seconds (a trial).

How: the app's own `--export-video` command writes the sound to a WAV file (a second's work) and then
every picture, raw, to a pipe that ffmpeg reads. Nothing follows a clock, so the speed of the Mac does
not matter. `tools/check_video.py` then proves the file's sound and picture are in step.
"""
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "build", "SRMetal.app", "Contents", "MacOS", "SRMetal")
DEFAULT_OUTPUT = os.path.expanduser("~/Movies/SecondReality-Modern.mov")


def plan():
    """The export's size, rate and length, as the app states them."""
    text = subprocess.run([APP, "--export-video", "plan"], check=True, capture_output=True, text=True).stdout
    numbers = {}
    for line in text.splitlines():
        words = line.split()
        if len(words) == 2 and words[1].isdigit():
            numbers[words[0]] = int(words[1])
    return numbers


def ffmpeg_command(size, sound, output):
    return [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        # The pictures: raw, from the pipe. (bgr0: blue, green, red and an unused byte.)
        "-f", "rawvideo", "-pix_fmt", "bgr0", "-video_size", "%dx%d" % (size["width"], size["height"]),
        "-framerate", str(size["rate"]), "-i", "pipe:0",
        "-i", sound,
        # To ProRes's colour form with the HD (BT.709) matrix, and labelled so, which is what YouTube expects.
        "-vf", "scale=out_color_matrix=bt709:out_range=tv,format=p210le,"
               "setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=tv",
        "-c:v", "prores_videotoolbox", "-profile:v", "standard",
        "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709", "-color_range", "tv",
        "-c:a", "pcm_s16le",
        output,
    ]


def main():
    arguments = sys.argv[1:]
    seconds = None
    if "--seconds" in arguments:
        at = arguments.index("--seconds")
        seconds = arguments[at + 1]
        del arguments[at:at + 2]
    if len(arguments) > 1 or (seconds is not None and not seconds.isdigit()):
        sys.exit(__doc__)
    output = os.path.abspath(arguments[0]) if arguments else DEFAULT_OUTPUT
    if not os.path.exists(APP):
        sys.exit("The app is not built: run ./build.sh first (looked for %s)" % APP)
    if shutil.which("ffmpeg") is None:
        sys.exit("ffmpeg is not installed (brew install ffmpeg)")
    limit = [seconds] if seconds else []
    size = plan()
    os.makedirs(os.path.dirname(output), exist_ok=True)
    with tempfile.TemporaryDirectory() as scratch:
        sound = os.path.join(scratch, "sound.wav")
        subprocess.run([APP, "--export-video", "sound", sound] + limit, check=True, stdout=subprocess.DEVNULL)
        pictures = subprocess.Popen([APP, "--export-video", "pictures"] + limit, stdout=subprocess.PIPE)
        encoder = subprocess.Popen(ffmpeg_command(size, sound, output), stdin=pictures.stdout)
        pictures.stdout.close()   # so the app notices if ffmpeg stops
        encoder_result = encoder.wait()
        pictures_result = pictures.wait()
    if encoder_result != 0 or pictures_result != 0:
        sys.exit("The export failed (the app: %d, ffmpeg: %d)" % (pictures_result, encoder_result))
    print("Wrote %s (%.2f GB)" % (output, os.path.getsize(output) / 1e9))


if __name__ == "__main__":
    main()
