# audio-probe

Generates a 6-second 440 Hz tone through WebAudio and reports what happened, so
the audio **output** path can be verified end to end on a device:

    JS -> engine mixer -> cpal/oboe -> AudioFlinger -> speaker

Run it like any other bundle:

    adb shell am start -n com.migo.bench.migo/.BenchGameActivity \
      --es migo_game_id bench --es migo_entry_point game.js \
      --es game_asset game-audio-probe --es migo_log_level info

It carries no audio file on purpose. An asset would drag the decoder into the
measurement; the question this answers is whether frames reach the device.

## Reading the result

`[audio-probe]` lines say what JS saw. The device-side evidence is the gap
between `AudioThread (lazy) started` and `AudioThread entered idle sleep`:
it should be the tone's 6 seconds plus the ~3 second idle timeout, ~9 s. A gap
of ~3 s means the thread started and never received a frame. `AudioFlinger:
ReportBDForPlayback` should also appear.

## Why it exists

`AudioThread (lazy) started` and `Audio output device: Ok("default")` look like
proof that audio works. They are not: they only say a stream was opened.
endless-runner opens an audio context and **ships no audio files at all**, so it
produces those exact lines and stays silent — which is correct for that game and
useless as verification. This probe was written after that gap let a packaging
change look verified when nothing had ever played.
