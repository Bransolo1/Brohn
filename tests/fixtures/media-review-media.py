"""Original lossless RGB and PCM containers; no people, copied media or timestamps."""
import json, math, struct, subprocess, sys, wave
from pathlib import Path
folder=Path(sys.argv[1]).resolve();folder.mkdir(parents=True,exist_ok=True)
assert not any(folder.iterdir()),"Use a fresh empty media directory."
raw=folder/'original.rgb';raw.write_bytes(b''.join(bytes((n,255-n,n*3%256))*(64*48) for n in range(160)))
audio=folder/'original.wav'
with wave.open(str(audio),'wb') as f:
    f.setparams((1,2,8000,0,'NONE','not compressed'))
    f.writeframes(b''.join(struct.pack('<h',round(9000*math.sin(2*math.pi*250*n/8000))) for n in range(32000)))
inputs=['-f','rawvideo','-pixel_format','rgb24','-video_size','64x48','-framerate','40','-i',str(raw),'-i',str(audio),'-map','0:v:0','-map','1:a:0']
for name,extra in [('regular',[]),('gap',['-vf',r'setpts=PTS+if(gte(N\,80)\,0.5/TB\,0)','-fps_mode','passthrough'])]:
    subprocess.run(['ffmpeg','-v','error','-nostdin','-n',*inputs,*extra,'-c:v','ffv1','-c:a','copy',str(folder/f'{name}.mkv')],check=True,timeout=60,capture_output=True)
(folder/'original-specification.json').write_text(json.dumps({'frames':160,'width':64,'height':48,'rate':40,'audio_rate':8000,'audio_samples':32000,'gap':{'first_shifted_frame':80,'shift_s':.5},'origin':'Original generated software fixture; no human observations.'},indent=2))
