"""Bounded, source-pinned native recording metadata inspection; no scoring."""
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import io
import json
import math
import os
from pathlib import Path
import re
import struct
import sys
import warnings
import zlib

MAX_SOURCE = 512 * 1024**2
MAX_CHANNELS = 512
MAX_ANNOTATIONS = 100_000
MAX_OUTPUT = 2 * 1024**2


class InputError(ValueError):
    pass


def require(value, message):
    if not value:
        raise InputError(message)


def digest(path):
    with open(path, "rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()


def finite(value, name, minimum=None, maximum=None):
    require(not isinstance(value, bool), f"{name} must be numeric.")
    try:
        result = float(value)
    except (TypeError, ValueError) as error:
        raise InputError(f"{name} must be numeric.") from error
    require(math.isfinite(result) and (minimum is None or result >= minimum) and (maximum is None or result <= maximum), f"{name} is outside its supported range.")
    return result


def text(value, name, maximum=1024, empty=False):
    require(isinstance(value, str) and len(value) <= maximum and (empty or value.strip()) and "\x00" not in value, f"Invalid or overlong {name}.")
    return value


def optional_number(value):
    try:
        result = float(value)
        return result if math.isfinite(result) else None
    except (TypeError, ValueError):
        return None


def annotation(onset, duration, description, index):
    return {"index": index, "onset_s": finite(onset, "annotation onset"),
            "duration_s": finite(duration, "annotation duration", 0),
            "description": text(str(description), "annotation label", 4096, empty=True)}


def edf_header(path, fmt):
    width = 2 if fmt == "edf" else 3
    with path.open("rb") as file:
        fixed = file.read(256)
        require(len(fixed) == 256 and (fixed[:8] == b"0       " if fmt == "edf" else fixed[:8] == b"\xffBIOSEMI"), "The file signature does not match the declared EDF/BDF format.")
        try:
            header_bytes, declared_records, channel_count = int(fixed[184:192]), int(fixed[236:244]), int(fixed[252:256])
            duration = finite(fixed[244:252], "record duration", 1e-9, 86400)
            require(1 <= channel_count <= MAX_CHANNELS and header_bytes == 256*(channel_count+1), "EDF/BDF has an invalid or oversized signal header.")
            header = file.read(channel_count*256)
            require(len(header) == channel_count*256, "The signal header is truncated.")
            arrays, position = {}, 0
            for key, size in (("label",16),("transducer",80),("unit",8),("physical_min",8),("physical_max",8),("digital_min",8),("digital_max",8),("prefilter",80),("samples_per_record",8),("reserved",32)):
                arrays[key] = [header[position+i*size:position+(i+1)*size].decode("ascii").strip() for i in range(channel_count)]
                position += channel_count*size
            samples = [int(x) for x in arrays["samples_per_record"]]
            require(all(1 <= x <= 10_000_000 for x in samples), "An EDF/BDF per-record sample count is invalid.")
        except (UnicodeError, ValueError) as error:
            if isinstance(error, InputError):
                raise
            raise InputError("EDF/BDF technical header fields are malformed.") from error
        record_bytes = sum(samples)*width
        payload = path.stat().st_size-header_bytes
        require(payload >= 0 and payload % record_bytes == 0, "EDF/BDF has a truncated data record.")
        records = payload//record_bytes
        require(records <= 2_000_000 and (declared_records == -1 or declared_records == records), "EDF/BDF byte count disagrees with its declared record count.")
        annotations_index = [i for i, label in enumerate(arrays["label"]) if label in ("EDF Annotations", "BDF Annotations")]
        require(sum(samples[i] for i in annotations_index)*width*records <= 16*1024**2, "EDF/BDF annotation payload exceeds the 16 MiB inspection bound.")
        annotation_rows, annotation_count, starts = [], 0, []
        offsets = [sum(samples[:i])*width for i in range(channel_count)]
        for record in range(records) if annotations_index else ():
            start = None
            for index in annotations_index:
                file.seek(header_bytes + record*record_bytes + offsets[index])
                block = file.read(samples[index]*width)
                for tal in block.split(b"\x00"):
                    if not tal:
                        continue
                    parts = tal.split(b"\x14")
                    onset_duration = parts[0].split(b"\x15")
                    require(len(onset_duration) in (1,2), "An EDF/BDF annotation timestamp is malformed.")
                    onset = finite(onset_duration[0], "annotation onset")
                    length = finite(onset_duration[1], "annotation duration", 0) if len(onset_duration) == 2 else 0
                    if index == annotations_index[0] and start is None:
                        start = onset
                    for label in parts[1:]:
                        if not label:
                            continue
                        annotation_count += 1
                        require(annotation_count <= MAX_ANNOTATIONS, "Too many annotations for bounded header inspection.")
                        parsed = annotation(onset, length, label.decode("utf-8"), annotation_count)
                        if len(annotation_rows) < 100:
                            annotation_rows.append(parsed)
            if start is not None:
                starts.append(start)
        channels, notes = [], []
        names = [label for i, label in enumerate(arrays["label"]) if i not in annotations_index]
        duplicate = len(names) != len(set(names))
        for i in range(channel_count):
            if i in annotations_index:
                continue
            label = text(arrays["label"][i], "source channel label", 200)
            unit = arrays["unit"][i] or None
            calibration = {key: optional_number(arrays[key][i]) for key in ("physical_min", "physical_max", "digital_min", "digital_max")}
            valid_calibration = all(v is not None for v in calibration.values()) and calibration["physical_max"] != calibration["physical_min"] and calibration["digital_max"] > calibration["digital_min"] and \
                calibration["digital_min"].is_integer() and calibration["digital_max"].is_integer() and \
                -(2**(8*width-1)) <= calibration["digital_min"] < calibration["digital_max"] < 2**(8*width-1)
            channels.append({"index": i, "name": label, "type": "unknown", "type_basis": "EDF/BDF does not declare a sensor modality",
                "source_unit": unit, "analysis_unit": "V" if unit in ("V", "mV", "uV") else None,
                "sampling_rate_hz": samples[i]/duration, "sample_count": samples[i]*records,
                "calibration_evidence": {**calibration, "declared_unit": unit, "valid_linear_range": valid_calibration,
                    "prefilter": arrays["prefilter"][i], "transducer": arrays["transducer"][i]}})
        rates = {c["sampling_rate_hz"] for c in channels}
        reserved = fixed[192:236].decode("ascii").strip()
        if len(rates) > 1:
            notes.append("Channels have different native rates. MNE upsamples selected mixed-rate channels; select channels sharing a rate or review that conversion explicitly.")
        if duplicate:
            notes.append("Duplicate source channel names require an explicit reader-name mapping before analysis.")
        if not all(c["source_unit"] and c["calibration_evidence"]["valid_linear_range"] for c in channels):
            notes.append("At least one channel lacks a declared unit or valid calibration range.")
        discontinuous = reserved.startswith(("EDF+D", "BDF+D"))
        timing_contiguous = len(starts)==records and all(math.isclose(b-a,duration,rel_tol=1e-9,abs_tol=1e-9) for a,b in zip(starts,starts[1:])) if annotations_index else None
        if discontinuous:
            notes.append("This file declares discontinuous records. Recorded duration is summed support, not elapsed uninterrupted time.")
        elif timing_contiguous is False:
            notes.append("Recorded timekeeping annotations do not form the declared contiguous record sequence. Review source timing before continuous analysis.")
        return {"channels": channels, "recording": {"sampling_rate_hz": next(iter(rates)) if len(rates)==1 else None,
            "duration_s": records*duration, "duration_definition": "sum of declared record durations",
            "elapsed_span_s": starts[-1]+duration-starts[0] if starts and len(starts)==records else None,
            "data_record_count": records, "declared_data_record_count": None if declared_records==-1 else declared_records,
            "record_duration_s": duration, "discontinuous": discontinuous, "record_onset_preview_s": starts[:20],
            "record_onset_count":len(starts),"record_timing_contiguous":timing_contiguous},
            "annotations": {"count": annotation_count, "preview": annotation_rows, "preview_truncated": annotation_count>len(annotation_rows)},
            "quality": {"source_channel_names_unique": not duplicate, "mixed_sampling_rates": len(rates)>1,
                "signal_samples_read": False, "annotation_payload_read": bool(annotations_index), "needs_attention": bool(notes)},
            "warnings": notes, "packages": {}}


def mne_annotations(raw):
    count = len(raw.annotations)
    require(count <= MAX_ANNOTATIONS, "Too many annotations for bounded header inspection.")
    rows = [annotation(a,b,c,i+1) for i,(a,b,c) in enumerate(zip(raw.annotations.onset[:100],raw.annotations.duration[:100],raw.annotations.description[:100]))]
    return {"count":count,"preview":rows,"preview_truncated":count>len(rows)}


def bounded_set(path):
    """Bound the expanded MATLAB v5 container before SciPy materializes it."""
    from scipy.io import loadmat
    data = path.read_bytes()
    require(len(data)>=128 and data[126:128] in (b"IM",b"MI"), "SET inspection supports MATLAB v5/v7 containers; v7.3 HDF5 needs another adapter.")
    endian = "<" if data[126:128] == b"IM" else ">"
    pieces, total, offset = [data[:128]],128,128
    while offset<len(data):
        require(offset+8<=len(data), "Truncated MATLAB data element.")
        kind,length = struct.unpack(endian+"II",data[offset:offset+8]); offset+=8
        require(length<=64*1024**2 and offset+length<=len(data), "SET metadata exceeds the 64 MiB expanded-container bound or is truncated.")
        block=data[offset:offset+length]; offset+=length
        if kind==15:
            decoder=zlib.decompressobj(); block=decoder.decompress(block,64*1024**2-total+1)
            require(decoder.eof and not decoder.unconsumed_tail and not decoder.unused_data, "SET compressed data exceeds the 64 MiB expansion bound or is invalid.")
        else:
            block=struct.pack(endian+"II",kind,length)+block
            padding=(-length)%8; require(offset+padding<=len(data),"Truncated MATLAB element padding."); offset+=padding
        total+=len(block); require(total<=64*1024**2,"SET expanded data exceeds 64 MiB; create a bounded standalone export.")
        pieces.append(block)
    eeg=loadmat(io.BytesIO(b"".join(pieces)),variable_names=["EEG"],simplify_cells=True).get("EEG")
    require(isinstance(eeg,dict),"SET is missing its EEG structure.")
    if isinstance(eeg.get("data"),str):
        raise InputError("This SET references an external FDT file. Import a standalone SET containing its data, or use an explicit companion-file bundle; external paths are never followed.")
    return eeg


def mne_header(path,fmt):
    import mne
    from mne._fiff.constants import FIFF
    from mne._fiff.open import fiff_open
    from mne._fiff.tree import dir_tree_find
    if fmt=="fif":
        fid,tree,directory=fiff_open(path,preload=False,verbose=False)
        try:
            require(len(directory)<=200_000,"FIF directory exceeds the inspection bound.")
            require(not dir_tree_find(tree,FIFF.FIFFB_REF),"FIF references another file. Export a standalone recording or import a pinned companion-file bundle; references are never followed.")
        finally:
            fid.close()
        raw=mne.io.read_raw_fif(path,preload=False,on_split_missing="raise",verbose=False)
    else:
        eeg=bounded_set(path)
        require(int(eeg.get("trials",1))==1,"This SET contains epochs; the native continuous-recording adapter requires a continuous export.")
        raw=mne.io.read_raw_eeglab(path,preload=False,verbose=False)
    try:
        require(1<=len(raw.ch_names)<=MAX_CHANNELS,"Native channel count exceeds the inspection bound.")
        fs=finite(raw.info["sfreq"],"native sampling rate",1e-9,1e7)
        units={0:"1",1:"m",3:"s",4:"A",5:"K",6:"mol",101:"Hz",106:"C",107:"V",109:"Ohm",110:"S",112:"T",114:"degC",201:"T/m"}
        channels=[]
        for i,ch in enumerate(raw.info["chs"]):
            unit=units.get(int(ch["unit"]))
            channels.append({"index":i,"name":text(ch["ch_name"],"native channel name",200),"type":raw.get_channel_types(picks=[i])[0],
                "type_basis":"native MNE reader metadata" if fmt=="fif" else "EEGLAB reader channel mapping",
                "source_unit":unit if fmt=="fif" else None,"analysis_unit":unit,"sampling_rate_hz":fs,"sample_count":int(raw.n_times),
                "calibration_evidence":{"native_unit_code":int(ch["unit"]),"native_unit_multiplier":int(ch["unit_mul"]),
                    "range":optional_number(ch["range"]),"cal":optional_number(ch["cal"]),
                    "reader_convention":"MNE reads EEG in volts; EEGLAB stored EEG convention is microvolts" if fmt=="set" else "native FIFF calibration retained"},
                "marked_bad":ch["ch_name"] in raw.info["bads"]})
        return {"channels":channels,"recording":{"sampling_rate_hz":fs,"sample_count":int(raw.n_times),"duration_s":raw.n_times/fs,
            "sample_span_s":max(0,raw.n_times-1)/fs,"duration_definition":"sample count divided by header rate","first_sample":int(raw.first_samp),"first_time_s":float(raw.first_time)},
            "annotations":mne_annotations(raw),"quality":{"source_channel_names_unique":len(set(raw.ch_names))==len(raw.ch_names),
                "mixed_sampling_rates":False,"signal_samples_read":fmt=="set","needs_attention":fmt=="set"},
            "warnings":["SET stores embedded signal data inside its MATLAB structure, so bounded inspection must decode that structure. No samples appear in this result.",
                "EEGLAB's microvolt convention is a reader convention; confirm it against the exporter before analysis."] if fmt=="set" else [],
            "packages":{"mne":mne.__version__}}
    finally:
        raw.close()


def snirf_header(path):
    import h5py
    import numpy as np
    import mne
    with h5py.File(path,"r") as file:
        visited=set(); nodes=[0]
        def inspect(group):
            address=h5py.h5o.get_info(group.id).addr
            require(address not in visited,"Cyclic or shared HDF5 groups need an explicit adapter."); visited.add(address)
            for key in group:
                nodes[0]+=1; require(nodes[0]<=10000,"SNIRF metadata exceeds the 10,000-node inspection bound.")
                require(isinstance(group.get(key,getlink=True),h5py.HardLink),"SNIRF external or soft links are not followed; use a standalone file.")
                item=group[key]
                if isinstance(item,h5py.Group): inspect(item)
                else:
                    require(not item.is_virtual and not item.external,"SNIRF externally stored datasets are not followed.")
                    require(item.size<=20_000_000 and item.ndim<=3,"SNIRF dataset dimensions exceed the inspection bound.")
        inspect(file)
        groups=[k for k in file if re.fullmatch(r"nirs\d*",k)]
        require(len(groups)==1,"This file has multiple NIRS groups. Export one explicit recording group for the current analysis adapter.")
        nirs=file[groups[0]]; data_groups=[k for k in nirs if re.fullmatch(r"data\d+",k)]
        require(len(data_groups)==1,"This SNIRF contains multiple data blocks. Select one explicit block in a standalone export.")
        data=nirs[data_groups[0]]; shape=data["dataTimeSeries"].shape
        require(len(shape)==2 and 1<=shape[1]<=MAX_CHANNELS and 1<=shape[0]<=2_000_000,"SNIRF signal dimensions exceed the bounded native adapter.")
        require(data["time"].ndim==1 and data["time"].size in (2,shape[0]),"SNIRF time must contain sample timestamps or the start/spacing pair.")
        times=np.asarray(data["time"],float)
        require(np.isfinite(times).all(),"SNIRF time contains missing or nonfinite values.")
        tag=nirs["metaDataTags"]["TimeUnit"][()]
        time_unit=tag.decode("utf-8") if isinstance(tag,bytes) else str(tag)
        require(time_unit=="s","SNIRF native analysis currently needs an explicitly declared seconds time unit; no unit guessing is applied.")
        if len(times)==2 and shape[0]!=2:
            require(times[1]>0,"SNIRF sample spacing must be positive."); rate=1/float(times[1]); regular=True
        else:
            intervals=np.diff(times); require((intervals>0).all(),"SNIRF timestamps are duplicate or reversed; preserve boundaries in a multistream import.")
            regular=bool(np.allclose(intervals,intervals[0],rtol=1e-6,atol=1e-10)); rate=1/float(intervals[0]) if regular else None
        require(regular,"SNIRF has variable sampling intervals. The current native analysis requires an explicit regular-rate export; original timestamps are not resampled.")
        lists=sorted([k for k in data if re.fullmatch(r"measurementList\d+",k)],key=lambda x:int(re.search(r"\d+$",x)[0]))
        require(len(lists)==shape[1],"SNIRF measurementList groups must match signal columns; plural measurementLists needs an explicit adapter.")
        units=[]; measurement=[]
        for name in lists:
            item=data[name]
            unit=item["dataUnit"][()] if "dataUnit" in item else None
            unit=unit.decode("utf-8") if isinstance(unit,bytes) else None if unit is None else str(unit)
            units.append(unit)
            measurement.append({key:int(item[key][()]) for key in ("sourceIndex","detectorIndex","wavelengthIndex","dataType","dataTypeIndex") if key in item})
    raw=mne.io.read_raw_snirf(path,preload=False,verbose=False)
    try:
        require(len(raw.ch_names)==shape[1] and raw.n_times==shape[0],"SNIRF reader changed the declared recording dimensions.")
        channels=[{"index":i,"name":text(name,"SNIRF channel name",200),"type":raw.get_channel_types(picks=[i])[0],
            "type_basis":"SNIRF measurement list and MNE reader","source_unit":units[i],"analysis_unit":None,
            "sampling_rate_hz":rate,"sample_count":shape[0],"calibration_evidence":measurement[i]} for i,name in enumerate(raw.ch_names)]
        return {"channels":channels,"recording":{"sampling_rate_hz":rate,"sample_count":shape[0],"duration_s":shape[0]/rate,
            "sample_span_s":max(0,shape[0]-1)/rate,"duration_definition":"sample count divided by checked native interval","time_unit":time_unit},
            "annotations":mne_annotations(raw),"quality":{"source_channel_names_unique":len(set(raw.ch_names))==len(raw.ch_names),
                "mixed_sampling_rates":False,"signal_samples_read":False,"needs_attention":any(u is None for u in units)},
            "warnings":["Missing channel dataUnit remains undeclared. Continuous-wave intensity does not supply a calibrated haemoglobin unit; that requires the selected optical conversion and pathlength factors."],
            "packages":{"mne":mne.__version__,"h5py":h5py.__version__}}
    finally:
        raw.close()


def wav_header(path):
    import soundfile as sf
    info=sf.info(path)
    require(info.format in ("WAV","WAVEX","RF64"),"The source is not a supported WAV container.")
    require(1<=info.channels<=MAX_CHANNELS and info.frames>=0,"Invalid WAV channel/sample count.")
    fs=finite(info.samplerate,"WAV sampling rate",1,1e7)
    return {"channels":[{"index":i,"name":f"Audio channel {i+1}","type":"audio","type_basis":"container channel index; no speaker identity inferred",
        "source_unit":None,"analysis_unit":"FS","sampling_rate_hz":fs,"sample_count":int(info.frames),
        "calibration_evidence":{"subtype":info.subtype,"full_scale_is_not_sound_pressure":True}} for i in range(info.channels)],
        "recording":{"sampling_rate_hz":fs,"sample_count":int(info.frames),"duration_s":info.frames/fs,
            "duration_definition":"sample count divided by header rate","container":info.format,"sample_encoding":info.subtype},
        "annotations":{"count":None,"preview":[],"preview_truncated":False,"status":"WAV cue and broadcast metadata are not parsed by this header adapter"},
        "quality":{"source_channel_names_unique":True,"mixed_sampling_rates":False,"signal_samples_read":False,"needs_attention":False},
        "warnings":["Full-scale audio amplitude is not calibrated sound pressure and channels are not participant identities."],
        "packages":{"soundfile":sf.__version__,"libsndfile":sf.__libsndfile_version__}}


def run(request):
    require(isinstance(request,dict) and set(request)=={"schema","operation","source_path","source_hash","format"},"Header request fields are incomplete or unsupported.")
    require(request["schema"]=="brohn-header-request/1.0" and request["operation"]=="inspect_header","Unsupported header request.")
    fmt=request["format"]; require(fmt in ("edf","bdf","fif","set","snirf","wav"),"This native format has no header adapter.")
    path=Path(text(request["source_path"],"source path",4096)).resolve()
    require(path.is_file() and 0<path.stat().st_size<=MAX_SOURCE,"Native source must be a local file between 1 byte and 512 MiB.")
    sha=request["source_hash"]; require(isinstance(sha,str) and re.fullmatch(r"[a-f0-9]{64}",sha) and digest(path)==sha,"Native source failed its pinned SHA-256 check.")
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        header=edf_header(path,fmt) if fmt in ("edf","bdf") else mne_header(path,fmt) if fmt in ("fif","set") else snirf_header(path) if fmt=="snirf" else wav_header(path)
    require(1<=len(header["channels"])<=MAX_CHANNELS,"Native source has no supported signal channels.")
    require(digest(path)==sha,"Native source changed during inspection.")
    packages=header.pop("packages")
    header["quality"].update(signal_processing_applied=False,identities_inferred=False,source_hash_verified=True,
        parser_warning_count=len(caught),parser_warnings_preview=[str(w.message)[:1024] for w in caught[:20]])
    header["channel_count"]=len(header["channels"])
    result={"schema":"brohn-header-result/1.0","operation":"inspect_header","status":"needs_attention" if header["quality"]["needs_attention"] else "inspected",
        "source":{"sha256":sha,"bytes":path.stat().st_size,"format":fmt},
        "engine":{"name":"Brohn native header inspector","version":"1.0.0","script_sha256":digest(Path(__file__)),"packages":packages},
        "header":header,"parameters":{"source_limit_bytes":MAX_SOURCE,"channel_limit":MAX_CHANNELS,"annotation_preview_limit":100,"automatic_mapping":False},
        "limitations":["Header inspection identifies recorded channel metadata. It does not establish sensor calibration, participant identity or successful scientific analysis.",
            "Participant names, patient header text and recording dates are excluded from this preview; the immutable original retains its full header.",
            "Confirm selected channels and native unit policy before applying a recipe. A reader convention is distinct from a source-declared physical unit."]}
    require(len(json.dumps(result,ensure_ascii=True,allow_nan=False).encode())<=MAX_OUTPUT,"Native header exceeds the 2 MiB output bound.")
    return result


def main():
    parser=argparse.ArgumentParser(); parser.add_argument("--request",required=True); parser.add_argument("--output",required=True); args=parser.parse_args()
    output=Path(args.output).resolve(); request_path=Path(args.request).resolve(); code=0; source=None
    if output in (request_path,Path(__file__).resolve()):
        print("Output must not overwrite request or worker code.",file=sys.stderr); return 2
    try:
        require(request_path.stat().st_size<=64*1024,"Header request exceeds 64 KiB.")
        request=json.loads(request_path.read_text(encoding="utf-8-sig"))
        source=Path(request.get("source_path","")).resolve() if isinstance(request,dict) and isinstance(request.get("source_path"),str) else None
        require(output not in (source,request_path,Path(__file__).resolve()),"Output must not overwrite source, request or worker code.")
        result=run(request)
    except Exception as error:
        if output in (source,request_path,Path(__file__).resolve()):
            print("Output must not overwrite source, request or worker code.",file=sys.stderr); return 2
        result={"schema":"brohn-header-result/1.0","operation":"inspect_header","status":"error","error":{"type":type(error).__name__,"message":str(error)[:4000]}}; code=2
    output.parent.mkdir(parents=True,exist_ok=True); temporary=output.with_name(output.name+".tmp-"+str(os.getpid()))
    temporary.write_text(json.dumps(result,ensure_ascii=True,allow_nan=False),encoding="utf-8"); os.replace(temporary,output)
    return code


if __name__=="__main__":
    sys.exit(main())
