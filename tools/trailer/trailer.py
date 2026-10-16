#!/usr/bin/env python3
"""Manifest-driven native 2160p60 recording, localized editing and validation.

Uses only Python's standard library and Pillow. FFmpeg/FFprobe and the patched
game runtime are supplied explicitly in a local config, never downloaded.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import wave

HERE = Path(__file__).resolve().parent
LANGUAGES = ("en", "ru", "de")


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def write(path, value):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def validate(m):
    assert m["schema"] == 1
    assert (m["width"], m["height"], m["fps"]) == (3840, 2160, 60), "Master must be native 2160p60"
    ids = []
    for s in m["shots"]:
        excluded = m.get("excluded_locations", {}).get(s.get("campaign", "cursed_lands"), [])
        assert s.get("zone") not in excluded, f"Rejected story/location choice: {s['id']} / {s.get('zone')}"
        assert re.fullmatch(r"[a-z0-9][a-z0-9-]*", s["id"]), "Unsafe shot id"
        assert isinstance(s["frames"], int) and s["frames"] > 0
        assert s["title"] in m["text"]
        if s.get("wardrobe"):
            kit = m["wardrobes"][s["wardrobe"]]
            assert len(kit["armors"]) == 7 and kit["weapons"], "Every wardrobe needs the complete regional kit"
        if s.get("kind") == "combat":
            assert s.get("enemies") and s.get("wardrobe"), "Combat needs an authored cast and regional equipment"
            assert all(isinstance(e.get("nid"), int) and e["nid"] > 0 and not e.get("offset")
                       for e in s["enemies"]), "Use original encounter actor IDs; enemy relocation is forbidden"
        for lang in LANGUAGES:
            lines = m["text"][s["title"]][lang]
            assert lines and all(isinstance(x, str) and x.strip() for x in lines)
            assert len(lines) == len(m["text"][s["title"]]["en"])
        ids.append(s["id"])
    assert len(set(ids)) == len(ids), "Duplicate shot ids"
    total = sum(s["frames"] for s in m["shots"])
    assert 55 * 60 <= total <= 65 * 60, "Keep the main cut about one minute"
    return total


class Project:
    def __init__(self, config, manifest):
        self.c = read(config)
        self.m = read(manifest)
        self.manifest = Path(manifest).resolve()
        validate(self.m)
        self.out = Path(self.c["output"]).resolve()
        self.out.mkdir(parents=True, exist_ok=True)
        self.env = os.environ.copy()
        self.env.update(self.c.get("environment", {}))
        self.ffmpeg = self.c["ffmpeg"]
        self.ffprobe = self.c["ffprobe"]

    def command(self, args, log, env=None, timeout=1800):
        with Path(log).open("w") as f:
            subprocess.run([str(x) for x in args], env=env or self.env,
                           stdout=f, stderr=subprocess.STDOUT, check=True, timeout=timeout)

    def probe_media(self, path, count=False):
        args = [self.ffprobe, "-v", "error", "-show_streams", "-show_format", "-of", "json"]
        if count:
            args += ["-threads", "4", "-count_frames"]
        return json.loads(subprocess.check_output(args + [str(path)], env=self.env))

    def encoder(self):
        if self.c.get("encoder", "libx264") == "h264_nvenc":
            return ["-c:v", "h264_nvenc", "-preset", "p6", "-rc", "vbr", "-cq", "17",
                    "-b:v", "60M", "-maxrate", "68M", "-bufsize", "136M"]
        return ["-c:v", "libx264", "-preset", "fast", "-crf", "16", "-threads", "8",
                "-maxrate", "68M", "-bufsize", "136M"]

    def video_args(self):
        return self.encoder() + ["-pix_fmt", "yuv420p", "-profile:v", "high", "-g", "30", "-bf", "2",
                                "-color_range", "tv", "-colorspace", "bt709", "-color_trc", "bt709",
                                "-color_primaries", "bt709", "-r", "60", "-movflags", "+faststart"]

    def selected(self, only):
        names = set(only.split(",")) if only else {s["id"] for s in self.m["shots"]}
        unknown = names - {s["id"] for s in self.m["shots"]}
        if unknown:
            raise ValueError(f"Unknown shots: {sorted(unknown)}")
        return [s for s in self.m["shots"] if s["id"] in names]

    def shot_spec(self, shot, probe=False):
        spec=dict(shot,width=1920 if probe else 3840,height=1080 if probe else 2160)
        if shot.get("wardrobe"):
            spec["equipment"]=dict(self.m["wardrobes"][shot["wardrobe"]],**shot.get("equipment",{}))
        return spec

    def runtime(self, name):
        source=Path(self.c["runtimes"][name])
        files=[source,source.with_suffix(".pck"),*sorted(source.parent.glob("*.so"))]
        key=hashlib.sha256("".join(digest(p) for p in files).encode()).hexdigest()[:20]
        target=self.out/"pinned-runtime"/key
        target.mkdir(parents=True,exist_ok=True)
        for p in files:
            dest=target/p.name
            if not dest.exists():shutil.copy2(p,dest)
        # MovieWriter fixes its output size before the capture Node is ready.
        # --resolution alone does not override the project's 1600×900 canvas.
        (target/"override.cfg").write_text('[display]\nwindow/size/viewport_width=3840\nwindow/size/viewport_height=2160\n[editor]\nmovie_writer/mix_rate=48000\nmovie_writer/fps=60\nmovie_writer/mjpeg_quality=0.95\n')
        return target/source.name

    def capture(self, shot, probe=False, language="en", force=False):
        mode = "probes" if probe else "takes"
        root = self.out / mode / shot["id"]
        root.mkdir(parents=True, exist_ok=True)
        runtime = self.runtime(shot.get("runtime", "stable"))
        script = HERE / ("arena.gd" if shot.get("kind") == "arena" else "capture.gd")
        spec = self.shot_spec(shot,probe)
        fingerprint = hashlib.sha256(json.dumps({"shot":spec,"language":language,"script":digest(script),"base_script":digest(HERE/"capture.gd"),"coop_client":digest(HERE/"coop_client.gd") if shot.get("kind")=="coop" else None,
            "engine":digest(runtime),"pck":digest(runtime.with_suffix(".pck"))},sort_keys=True).encode()).hexdigest()
        cache = root / "receipt.json"
        if cache.exists() and not force and read(cache).get("fingerprint") == fingerprint and (Path(read(cache)["take"])/("capture-start.png" if probe else "clean.mp4")).is_file():
            print(f"Cached {mode}: {shot['id']}", flush=True)
            return
        # Numbered takes are immutable. A new version never replaces old media.
        take = root / f"{time.time_ns()}"
        take.mkdir()
        driver = take / "driver"
        driver.mkdir()
        for name in ("capture.gd","arena.gd","coop_client.gd","preflight.gd"):
            shutil.copy2(HERE/name,driver/name)
        script = driver/script.name
        spec_path = take / "shot.json"
        write(spec_path, spec)
        profile = take / "profile"
        userdata = profile / "data/godot/app_userdata/Cursed Lands"
        userdata.mkdir(parents=True)
        shared = self.out / "shader-cache"
        shared.mkdir(exist_ok=True)
        (userdata / "shader_cache").symlink_to(shared, target_is_directory=True)
        if shot.get("hd"):
            package = Path(self.c["hd_lands"])
            if not (package / "mod.json").exists():
                raise FileNotFoundError("HD Lands 1.5.0 package is required for this shot")
            (userdata / "mods").mkdir()
            (userdata / "mods/community.hd-lands-textures@1.5.0").symlink_to(package, target_is_directory=True)
        env = dict(self.env, DISPLAY=self.c.get("display", ":19"),
                   XDG_DATA_HOME=str(profile / "data"), XDG_CONFIG_HOME=str(profile / "config"),
                   XDG_CACHE_HOME=str(profile / "cache"))
        campaign = self.c["game_data"][shot.get("campaign", "cursed_lands")]
        self.command([runtime,"--headless","--render-thread","safe","--",
                      f"--ei-path={campaign}","--no-movies",f"--tool={driver/'preflight.gd'}",
                      f"--trailer-driver={script}"],take/"preflight.log",env,timeout=60)
        output = take / "capture"
        args = [runtime, "--render-thread", "safe", "--rendering-method", "forward_plus", "--gpu-index", str(self.c.get("gpu",0)),
                "--resolution", f"{spec['width']}x{spec['height']}", "--fixed-fps", "60", "--disable-vsync"]
        if not probe:
            args += ["--write-movie", take / "capture.avi"]
        args += ["--", f"--ei-path={campaign}", "--ei-inline-host", "--ei-fixed-step", "--no-movies",
                 f"--tool={script}", f"--shot-spec={spec_path}", f"--shot-output={output}", f"--trailer-language={language}"]
        if probe:
            args += ["--trailer-probe"]
        print(f"Recording {shot['id']} ({spec['width']}×{spec['height']}, {shot['frames']/60:g}s)", flush=True)
        write(take / "command.json", {"args":[str(x) for x in args],"environment":{k:env[k] for k in ("DISPLAY","XDG_DATA_HOME","XDG_CONFIG_HOME","XDG_CACHE_HOME")}})
        client = None
        client_log = None
        if shot.get("kind") == "coop":
            coord = take / "coordination"
            coord.mkdir()
            args += [f"--coordination={coord}"]
            client_profile = take / "client-profile"
            client_env = dict(env, XDG_DATA_HOME=str(client_profile/"data"), XDG_CONFIG_HOME=str(client_profile/"config"), XDG_CACHE_HOME=str(client_profile/"cache"))
            client_args = [str(runtime),"--headless","--render-thread","safe","--max-fps","60","--",
                           f"--ei-path={campaign}","--ei-inline-host","--no-movies",f"--tool={driver/'coop_client.gd'}",f"--coordination={coord}"]
            client_log = (take/"client.log").open("w")
            client = subprocess.Popen(client_args,env=client_env,stdout=client_log,stderr=subprocess.STDOUT)
        try:
            self.command(args, take / "engine.log", env)
        finally:
            if client is not None:
                if client.poll() is None:
                    client.terminate()
                    try:client.wait(timeout=10)
                    except subprocess.TimeoutExpired:client.kill();client.wait()
                client_log.close()
        text = (take / "engine.log").read_text(errors="replace")
        errors = [line for line in text.splitlines() if "SCRIPT ERROR" in line or "SHADER ERROR" in line or "TRAILER_ERROR" in line]
        if errors:
            raise RuntimeError("\n".join(errors[:10]))
        if not Path(str(output)+"-start.png").exists():
            raise RuntimeError(f"Missing rendered frame: {take}")
        receipt = {"fingerprint":fingerprint,"take":str(take),"spec":spec,"language":language}
        if not probe:
            report = read(str(output)+".json")
            assert (report["width"], report["height"]) == (3840,2160)
            assert report["graphics"]["graphics_preset"] == 8 and report["graphics"]["auto_graphics"] == 0
            assert report["graphics"]["q_shadows"] == 3 and report["graphics"]["render_scale"] == 4
            if shot.get("kind") == "combat":
                assert [e["nid"] for e in report["authored_encounter"]] == [e["nid"] for e in shot["enemies"]]
            if shot.get("kind")=="coop":
                proof=report["coop"]
                assert proof["players_at_end"]==2 and proof["guest_start"]!=proof["guest_end"],"Guest must move in the real co-op take"
                assert proof["client_command"]["index"]==1
            src = self.probe_media(take / "capture.avi")
            v = next(s for s in src["streams"] if s["codec_type"] == "video")
            assert (v["width"], v["height"],v["r_frame_rate"]) == (3840,2160,"60/1"), v
            start = report["start_frame"]
            count = shot["frames"]
            graph = (f"[0:v]trim=start_frame={start}:end_frame={start+count},setpts=PTS-STARTPTS,"
                     "scale=in_range=full:out_range=limited:out_color_matrix=bt709[v];"
                     f"[0:a]atrim=start={start/60:.9f}:end={(start+count)/60:.9f},asetpts=PTS-STARTPTS,aresample=48000[a]")
            args = [self.ffmpeg,"-hide_banner","-y","-i",take / "capture.avi","-filter_complex_threads","2",
                    "-filter_complex",graph,"-map","[v]","-map","[a]"] + self.video_args() + [
                    "-c:a","aac","-b:a","384k","-ar","48000","-ac","2","-frames:v",str(count),take / "clean.mp4"]
            self.command(args,take / "encode.log")
            self.command([self.ffmpeg,"-hide_banner","-y","-i",take/"capture.avi","-map","0:a",
                          "-af",f"atrim=start={start/60:.9f}:end={(start+count)/60:.9f},asetpts=PTS-STARTPTS,aresample=48000,apad,atrim=duration={count/60:.9f}",
                          "-ac","2","-ar","48000","-c:a","pcm_s16le",take/"clean.wav"],take/"audio.log")
            receipt["capture"] = report
            receipt["media"] = self.probe_media(take / "clean.mp4")
            clean_v = next(s for s in receipt["media"]["streams"] if s["codec_type"] == "video")
            assert int(clean_v["nb_frames"]) == count, "Clean take has the wrong frame count"
        write(cache, receipt)

    def title_image(self, shot, language, path):
        from PIL import Image, ImageDraw, ImageFont
        w,h = self.m["width"],self.m["height"]
        im=Image.new("RGBA",(w,h))
        draw=ImageDraw.Draw(im)
        fonts=HERE.parent.parent / "game/fonts"
        serif=fonts / "LiberationSerif-Regular.ttf"
        sans=fonts / "LiberationSans-Regular.ttf"
        lines=self.m["text"][shot["title"]][language]
        gold=(225,192,129,255)
        ivory=(249,244,231,255)
        def fit(text, font, size, maxwidth):
            while size>=30:
                f=ImageFont.truetype(str(font),size)
                if draw.textlength(text,font=f)<=maxwidth:return f
                size-=1
            raise ValueError(f"Title cannot fit: {text}")
        if shot.get("card"):
            draw.rectangle((0,0,w,h),fill=(9,14,16,150))
            y=700
            for line,size,font,col in zip(lines,[184,86,58,44],[serif,sans,sans,sans],[ivory,gold,ivory,ivory]):
                f=fit(line,font,size,w-420)
                draw.text((w//2,y),line,font=f,fill=col,anchor="mt",stroke_width=1)
                y+=[230,190,125,90][lines.index(line)]
            draw.line((w//2-180,610,w//2+180,610),fill=gold,width=3)
            draw.line((w//2-180,1440,w//2+180,1440),fill=gold,width=3)
        else:
            # A quiet gradient leaves the scene readable, with phone-safe text.
            field_ui=shot.get("kind")=="coop" or shot.get("input")=="touch"
            top=shot.get("kind") in ("combat","coop","arena") or bool(shot.get("input"))
            # Keep ivory/gold readable over snow and the wiki's pale paper.
            # The soft edge still leaves the central action unobscured.
            band=800
            for offset in range(band):
                t=offset/(band-1)
                alpha=round(210*(t*t*(3-2*t))**0.65)
                y=band-1-offset if top else h-band+offset
                draw.line((0,y,w,y),fill=(5,10,12,alpha))
            x=700 if field_ui else 180
            y=480 if field_ui else (180 if top else h-365)
            draw.line((x,y-36,x+100,y-36),fill=gold,width=4)
            draw.text((x,y),lines[0],font=fit(lines[0],serif,92,w-x-360),fill=ivory,stroke_width=1,stroke_fill=(10,10,10,180))
            draw.text((x,y+128),lines[1],font=fit(lines[1],sans,52,w-x-360),fill=gold,stroke_width=1,stroke_fill=(10,10,10,180))
        im.save(path)

    def compose(self, language):
        folder=self.out / "edits" / language
        folder.mkdir(parents=True,exist_ok=True)
        parts=[]
        cursor=0
        srt=[]
        for n,shot in enumerate(self.m["shots"],1):
            receipt=read(self.out / "takes" / shot["id"] / "receipt.json")
            if receipt["spec"] != self.shot_spec(shot):
                raise RuntimeError(f"Stale shot {shot['id']}; record it again")
            if receipt.get("capture",{}).get("graphics",{}).get("graphics_preset") != 8:
                raise RuntimeError(f"Re-record {shot['id']} with Ultra graphics")
            take=Path(receipt["take"])
            overlay=folder / f"{shot['id']}.png"
            self.title_image(shot,language,overlay)
            seconds=shot["frames"]/60
            part=folder / f"{shot['id']}.mp4"
            fade=min(.35,seconds/5)
            graph=f"[1:v]format=rgba,fade=t=in:st=0:d={fade}:alpha=1,fade=t=out:st={seconds-fade}:d={fade}:alpha=1[title];[0:v][title]overlay=shortest=1:format=auto,format=yuv420p[v]"
            args=[self.ffmpeg,"-hide_banner","-y","-i",take/"clean.mp4","-loop","1","-framerate","60","-i",overlay,
                  "-filter_complex_threads","2","-filter_complex",graph,"-map","[v]","-an"]+self.video_args()+[
                  "-frames:v",str(shot["frames"]),part]
            signature=hashlib.sha256(json.dumps({"take":receipt["fingerprint"],"title":digest(overlay),
                "encoding":self.video_args(),"filter":graph},sort_keys=True).encode()).hexdigest()
            edit_receipt=folder/f"{shot['id']}.edit.json"
            if part.exists() and edit_receipt.exists() and read(edit_receipt).get("signature")==signature:
                print(f"Cached titles {language}: {shot['id']}",flush=True)
            else:
                print(f"Titles {language}: {shot['id']}",flush=True)
                self.command(args,folder/f"{shot['id']}.log")
                write(edit_receipt,{"signature":signature,"take":str(take),"frames":shot["frames"]})
            parts.append(part)
            def stamp(frame):
                ms=round(frame*1000/60);return f"{ms//3600000:02}:{ms//60000%60:02}:{ms//1000%60:02},{ms%1000:03}"
            srt.append(f"{n}\n{stamp(cursor)} --> {stamp(cursor+shot['frames'])}\n"+"\n".join(self.m["text"][shot["title"]][language])+"\n")
            cursor+=shot["frames"]
        (folder/"titles.srt").write_text("\n".join(srt),encoding="utf-8")
        concat=folder/"concat.txt"
        concat.write_text("".join("file '"+str(p).replace("'","'\\''")+"'\n" for p in parts))
        assembly=folder/"assembly.mp4"
        self.command([self.ffmpeg,"-hide_banner","-y","-f","concat","-safe","0","-i",concat,"-c","copy",assembly],folder/"assemble.log")
        master=self.out/f"Cursed-Lands-Trailer-{language}-2160p60.mp4"
        duration=cursor/60
        music=self.c.get("music") or str(Path(self.c["game_data"]["cursed_lands"])/"stream"/self.m["audio"]["track"])
        sfx=folder/"game-sounds.wav"
        with wave.open(str(sfx),"wb") as target:
            target.setparams((2,2,48000,0,"NONE","not compressed"))
            for shot in self.m["shots"]:
                take=Path(read(self.out/"takes"/shot["id"]/"receipt.json")["take"])
                with wave.open(str(take/"clean.wav"),"rb") as source:
                    assert (source.getnchannels(),source.getsampwidth(),source.getframerate())==(2,2,48000)
                    expected=shot["frames"]*800
                    assert source.getnframes()==expected,(shot["id"],source.getnframes(),expected)
                    target.writeframes(source.readframes(expected))
        graph=(f"[1:a]volume={self.m['audio']['sfx_gain']},afade=t=in:d=0.25,afade=t=out:st={duration-1}:d=1[sfx];"
               f"[2:a]atrim=duration={duration},asetpts=PTS-STARTPTS,"
               f"loudnorm=I={self.m['audio'].get('music_lufs',-20)}:TP=-2:LRA=11,volume={self.m['audio']['music_gain']},"
               f"afade=t=in:d=1.2,afade=t=out:st={duration-2.5}:d=2.5[music];"
               "[sfx][music]amix=inputs=2:normalize=0:duration=first,alimiter=limit=0.89:level=0:latency=1[a]")
        self.command([self.ffmpeg,"-hide_banner","-y","-i",assembly,"-i",sfx,"-stream_loop","-1","-i",music,
                      "-filter_complex",graph,"-map","0:v","-map","[a]","-c:v","copy","-c:a","aac","-b:a","384k",
                      "-ar","48000","-ac","2","-t",str(duration),"-movflags","+faststart",master],folder/"mix.log")
        self.verify(master,cursor)
        # The delivered master keeps its own immutable source selection even
        # after another recording updates a shot's current receipt.
        write(str(master)+".project.json", {
            "manifest":self.m,"language":language,"master_sha256":digest(master),
            "takes":[read(self.out/"takes"/s["id"]/"receipt.json") for s in self.m["shots"]],
            "audio":{"music":str(music),"music_sha256":digest(music),"game_sounds":str(sfx)},
        })
        print(master,flush=True)

    def verify(self,path,frames):
        media=self.probe_media(path,True)
        v=next(s for s in media["streams"] if s["codec_type"]=="video")
        a=next(s for s in media["streams"] if s["codec_type"]=="audio")
        assert (v["width"],v["height"],v["avg_frame_rate"],int(v["nb_read_frames"]))==(3840,2160,"60/1",frames),v
        assert v["pix_fmt"]=="yuv420p" and v["codec_name"]=="h264"
        assert int(a["sample_rate"])==48000 and a["channels"]==2
        assert abs(float(media["format"]["duration"])-frames/60)<.1
        write(str(path)+".validation.json",{"media":media,"sha256":digest(path),"expected_frames":frames,"checks":"Native dimensions, 60 fps, exact frame count, H.264, 4:2:0, 48 kHz stereo, duration"})


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command",choices=["validate","probe","record","compose","titles","verify"])
    parser.add_argument("--config",type=Path,required=True)
    parser.add_argument("--manifest",type=Path,default=HERE/"trailer.json")
    parser.add_argument("--only",default="")
    parser.add_argument("--language",choices=LANGUAGES,default="en")
    parser.add_argument("--force",action="store_true")
    args=parser.parse_args()
    p=Project(args.config,args.manifest)
    if args.command=="validate":
        print(f"{len(p.m['shots'])} shots; {validate(p.m)} frames; all EN/RU/DE title keys present")
    elif args.command in ("probe","record"):
        for shot in p.selected(args.only):p.capture(shot,args.command=="probe",args.language,args.force)
    elif args.command=="compose":p.compose(args.language)
    elif args.command=="titles":
        for lang in LANGUAGES:
            folder=p.out/"title-proofs"/lang;folder.mkdir(parents=True,exist_ok=True)
            for shot in p.m["shots"]:p.title_image(shot,lang,folder/f"{shot['id']}.png")
    else:
        p.verify(p.out/f"Cursed-Lands-Trailer-{args.language}-2160p60.mp4",validate(p.m))


if __name__=="__main__":
    main()
