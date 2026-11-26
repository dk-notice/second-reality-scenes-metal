#!/usr/bin/env python3
"""Checks that a video made by tools/export_video.py has its sound and picture in step.

    python3 tools/check_video.py [--seconds N] [file.mov]

(`--seconds N`: the file is a trial made with the same option.) Needs the app built, ffmpeg and ffprobe.
It checks the FINISHED FILE, by measurement:

1. Shape: ProRes, 2880x2160, exactly 60 pictures a second, the expected number of pictures; 16-bit stereo
   sound at 44,100 a second with exactly 735 sample pairs per picture; both start at time 0.
2. The sound in the file is, byte for byte, the sound the app renders for the demo.
3. Song 2 (which the script starts with the Glenz part, at step 7,624) begins in the file at exactly
   sample pair 7,624 x 630: one second from there equals the song rendered on its own from its start.
4. Pictures: some forty pictures spread through the file, and the two either side of the Glenz part's
   start, are each taken out of the file and compared with the app's own picture of the same number and
   of the one before and after. Each must be the app's picture (colours kept), and where the
   neighbours differ, clearly nearer to its own number than to either neighbour.

Together with the self-test (picture k is drawn at k/60 s of the same script whose sound it is), a file
that passes has every picture on its own sound.
"""
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "build", "SRMetal.app", "Contents", "MacOS", "SRMetal")
DEFAULT_FILE = os.path.expanduser("~/Movies/SecondReality-Modern.mov")

GLENZ_STEP = 7624          # the step song 2 starts on (`DemoTimelineCommand.expected`, "Glenz vectors")
PAIRS_PER_STEP = 630       # sample pairs of sound in one 1/70 s step
SMALL = (288, 216)         # pictures are compared at this size
ACCURATE_COLOURS = ("scale=in_color_matrix=bt709:in_range=tv:out_range=pc:"
                    "flags=accurate_rnd+full_chroma_int+full_chroma_inp,format=rgb24")
SAME_PICTURE = 0.2         # a picture from the file is the app's if it differs by less (mean, of 255)
NEIGHBOURS_DIFFER = 0.05   # neighbours count as different pictures if they differ by more

failures = []


def check(name, passed, detail=""):
    print("%s  %s%s" % ("ok  " if passed else "FAIL", name, (": " + detail) if detail and not passed else ""))
    if not passed:
        failures.append(name)


def run(command, **options):
    return subprocess.run(command, check=True, capture_output=True, **options)


def plan():
    numbers = {}
    for line in run([APP, "--export-video", "plan"], text=True).stdout.splitlines():
        words = line.split()
        if len(words) == 2 and words[1].isdigit():
            numbers[words[0]] = int(words[1])
    return numbers


def wav_samples(path):
    """The sample bytes of a plain WAV file (its header is 44 bytes)."""
    with open(path, "rb") as file:
        data = file.read()
    assert data[:4] == b"RIFF" and data[36:40] == b"data", path
    return data[44:]


def small_picture(source, seek=None):
    """A picture file, or the file's picture at a time, as SMALL red-green-blue bytes."""
    command = ["ffmpeg", "-hide_banner", "-loglevel", "error"]
    if seek is not None:
        command += ["-ss", "%.6f" % seek]
    # From the video, the colours are first turned back with ffmpeg's ACCURATE conversion: its default,
    # fast one comes out 2 to 3 levels of 255 dark (measured on flat colours; the accurate one is exact).
    back = (ACCURATE_COLOURS + ",") if seek is not None else ""
    command += ["-i", source, "-frames:v", "1", "-vf", back + "scale=%d:%d:flags=area" % SMALL,
                "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
    return run(command).stdout


def difference(a, b):
    if len(a) != len(b) or not a:
        return 255.0
    return sum(abs(x - y) for x, y in zip(a, b)) / len(a)


def main():
    arguments = sys.argv[1:]
    seconds = None
    if "--seconds" in arguments:
        at = arguments.index("--seconds")
        seconds = arguments[at + 1]
        del arguments[at:at + 2]
    if len(arguments) > 1 or (seconds is not None and not seconds.isdigit()):
        sys.exit(__doc__)
    video = os.path.abspath(arguments[0]) if arguments else DEFAULT_FILE
    for tool in ("ffmpeg", "ffprobe"):
        if shutil.which(tool) is None:
            sys.exit("%s is not installed" % tool)
    if not os.path.exists(APP):
        sys.exit("The app is not built: run ./build.sh first")
    limit = [seconds] if seconds else []
    size = plan()
    rate = size["rate"]
    frames = min(size["frames"], int(seconds) * rate) if seconds else size["frames"]
    pairs_per_picture = 44100 // rate

    # 1. Shape.
    probe = json.loads(run(["ffprobe", "-v", "error", "-show_streams", "-of", "json", video], text=True).stdout)
    pictures = [s for s in probe["streams"] if s["codec_type"] == "video"]
    sounds = [s for s in probe["streams"] if s["codec_type"] == "audio"]
    check("one picture stream and one sound stream", len(pictures) == 1 and len(sounds) == 1,
          "%d and %d" % (len(pictures), len(sounds)))
    if len(pictures) != 1 or len(sounds) != 1:
        return
    p, s = pictures[0], sounds[0]
    check("pictures: ProRes, %dx%d, exactly %d a second" % (size["width"], size["height"], rate),
          p["codec_name"] == "prores" and p["width"] == size["width"] and p["height"] == size["height"]
          and p["r_frame_rate"] == "%d/1" % rate and p["avg_frame_rate"] == "%d/1" % rate,
          "%s %sx%s %s (average %s)" % (p["codec_name"], p["width"], p["height"], p["r_frame_rate"], p["avg_frame_rate"]))
    check("pictures: %d of them" % frames, int(p.get("nb_frames", -1)) == frames, str(p.get("nb_frames")))
    check("sound: 16-bit stereo at 44,100 a second",
          s["codec_name"] == "pcm_s16le" and s["sample_rate"] == "44100" and s["channels"] == 2,
          "%s %s %s" % (s["codec_name"], s["sample_rate"], s["channels"]))
    check("picture and sound both start at time 0",
          float(p["start_time"]) == 0 and float(s["start_time"]) == 0, "%s and %s" % (p["start_time"], s["start_time"]))

    with tempfile.TemporaryDirectory() as scratch:
        # 2. The sound, byte for byte.
        in_file = run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", video, "-map", "0:a",
                       "-f", "s16le", "-c:a", "pcm_s16le", "-"]).stdout
        check("sound: exactly %d sample pairs for each of the %d pictures" % (pairs_per_picture, frames),
              len(in_file) == frames * pairs_per_picture * 4, "%d pairs" % (len(in_file) // 4))
        own = os.path.join(scratch, "sound.wav")
        run([APP, "--export-video", "sound", own] + limit)
        check("sound: byte for byte what the app renders for the demo", in_file == wav_samples(own))

        # 3. Song 2 starts exactly where the script starts it.
        start = GLENZ_STEP * PAIRS_PER_STEP * 4
        name = "sound: song 2 begins at sample pair %d x %d (the Glenz part's step)" % (GLENZ_STEP, PAIRS_PER_STEP)
        if len(in_file) >= start + 44100 * 4 + 4:
            song = os.path.join(scratch, "song2.wav")
            run([APP, "--music-render", "2", "1", song])
            alone = wav_samples(song)
            # Rendered 630 pairs at a time (the demo) or in one go (the song alone), a sample here and
            # there rounds differently by 1 of 32,767: "equal" allows that 1. One pair early or late is
            # far from equal.
            def apart(offset):
                there = in_file[start + offset * 4:start + offset * 4 + len(alone)]
                a = struct.unpack("<%dh" % (len(alone) // 2), alone)
                b = struct.unpack("<%dh" % (len(there) // 2), there)
                return sum(1 for x, y in zip(a, b) if abs(x - y) > 1)
            here, early, late = apart(0), apart(-1), apart(1)
            check(name, len(alone) == 44100 * 4 and here == 0 and early > 10000 and late > 10000,
                  "%d samples differ there, %d one pair early, %d one pair late" % (here, early, late))
        else:
            print("--    %s: the file ends before it (a trial)" % name)

        # 4. Pictures against the app's own.
        chosen = {frames * (2 * i + 1) // 80 for i in range(40)}
        glenz = -(-GLENZ_STEP * 6 // 7)   # the first picture at or after the step
        chosen |= {glenz - 1, glenz}
        chosen = sorted(f for f in chosen if 1 <= f <= frames - 2)
        needed = sorted({g for f in chosen for g in (f - 1, f, f + 1)})
        stills = os.path.join(scratch, "stills")
        os.mkdir(stills)
        run([APP, "--export-video", "stills", stills] + [str(f) for f in needed])
        still = {f: small_picture(os.path.join(stills, "frame-%06d.png" % f)) for f in needed}
        wrong, not_same, told_apart, worst = [], [], 0, 0.0
        for f in chosen:
            # Half a picture early: the first picture at or after that moment is number f.
            from_file = small_picture(video, seek=(f - 0.5) / rate)
            here = difference(from_file, still[f])
            worst = max(worst, here)
            if here >= SAME_PICTURE:
                not_same.append("%d (%.2f)" % (f, here))
            for other in (f - 1, f + 1):
                if difference(still[f], still[other]) > NEIGHBOURS_DIFFER:
                    told_apart += 1
                    if here * 2 >= difference(from_file, still[other]):
                        wrong.append("%d looks like %d" % (f, other))
        check("pictures: all %d taken from the file are the app's own of that number (worst difference %.3f of 255)"
              % (len(chosen), worst), not not_same, ", ".join(not_same[:6]))
        enough = 20 if not seconds else 4
        check("pictures: each is nearer to its own number than to the one before or after (%d comparisons)" % told_apart,
              not wrong and told_apart >= enough,
              ", ".join(wrong[:6]) or "only %d neighbours differed enough to tell, %d needed" % (told_apart, enough))

    print("%d of the checks FAILED" % len(failures) if failures else "All checks passed: sound and picture are in step.")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
