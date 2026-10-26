# Native recording cadence audit

The first user recording has irregular presentation timestamps despite its
nominal 60 FPS rate. Decoding 195 seconds to the end with `fps=60` omitted 389
native frame occurrences and added 390 repeats, compared by frame-hash
multiset. Native passthrough yielded 2,214 frames. These are occurrence counts,
not a claim that 389 distinct images were lost.

`summary.json` records the result; compressed hashes and the full candidate
scan preserve the underlying observations. All 30 selected triplets were
visually reviewed. No candidate conclusively isolates the reported mountain
flash. Reduced resolution, masking, thresholds and the three-frame comparison
limit the scan; negative results are not proof that the issue is absent.
Contact-sheet times are rounded to the hash output's 1/60 time base, so adjacent
native frames can have the same label. The native frame index is unambiguous.

To reproduce, create a documented disposable directory under
`local/scratchpad/`, copy `../../probes/followup/native_flash_scan.py` there,
and decompress `native.md5.gz` and `sampled.md5.gz` beside the script. The script
uses the unchanged first user recording at its original absolute path and the
registered local FFmpeg executable. Run it with the bundled Python runtime
that supplies NumPy and Pillow. It writes its scan and contact sheets beside
itself. The output can be compared with `native-scan.json.gz` here.

The hash decodes used these options after `ffmpeg`:

```
-ss 195 -i <first-user-recording> -t 37 -map 0:v:0 -vf scale=640:360 -fps_mode passthrough -f framemd5 native.md5
-ss 195 -i <first-user-recording> -t 37 -map 0:v:0 -vf fps=60,scale=640:360 -f framemd5 sampled.md5
```

The actual native visual scan does not use the `fps` filter. Its FFmpeg warnings
about rounded non-monotonic DTS are retained in `scan.log.gz`; the raw-video
pipe still returned all 2,214 frames, asserted against the native hash rows.
Two representative contact sheets are retained under
`Evidence/e2/fixes-20261026/followup/native-frame-candidates-{0,2}.jpg` in the
workspace. The original video is retained and all derived sheets are reproducible.
