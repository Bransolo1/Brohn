"""Frozen public EDF/Welch reference; no production implementation is modified.

Independent reader: Python + NumPy only (Matplotlib for optional rendering).
The EDF reader and explicit DFT oracle do not import MNE, SciPy or Brohn helpers.
Actual production jobs run separately in the installed methods environment.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import urllib.request

import numpy as np

ROOT=Path(__file__).resolve().parents[2]
BASE='https://physionet.org/files/eegmmidb/1.0.0/'
RECORDS=[f'S{s:03d}R{r:02d}' for s in (1,50,109) for r in (1,2)]
SITES=['Cz','O1','O2']
CODE=['scripts/workers/physiology.py','scripts/workers/physiology_artifacts.py','scripts/workers/headers.py']
BANDS={'delta':[1,4],'theta':[4,8],'alpha':[8,13],'beta':[13,30],'gamma':[30,45]}

def digest(path):
    with Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()

def read(path):return json.loads(Path(path).read_text(encoding='utf-8'))

def save(path,value):
    with Path(path).open('w',encoding='utf-8') as f:json.dump(value,f,indent=2,allow_nan=False);f.write('\n')

def outside(path):
    path=Path(path).resolve()
    if path==ROOT or ROOT in path.parents:raise ValueError('Keep reference data and results outside the repository.')
    path.mkdir(parents=True,exist_ok=True);return path

def download(url,maximum):
    with urllib.request.urlopen(url,timeout=45) as r:content=r.read(maximum+1)
    if not 0<len(content)<=maximum:raise ValueError('Public response exceeds the declared bound.')
    return content

def prepare(folder):
    if (folder/'plan.json').exists():raise ValueError('Keep the existing frozen protocol; use a new folder.')
    checksums=download(BASE+'SHA256SUMS.txt',1024**2)
    (folder/'SHA256SUMS.txt').write_bytes(checksums)
    sums={line.split()[1].lstrip('*'):line.split()[0] for line in checksums.decode().splitlines()}
    entries=[]
    for record in RECORDS:
        relative=f'{record[:4]}/{record}.edf'
        assert relative in sums
        entries.append({'record':record,'url':BASE+relative,'sha256':sums[relative],
                        'condition':'eyes_open_baseline' if record.endswith('01') else 'eyes_closed_baseline'})
    plan={'schema':'brohn-eeg-recorded-reference-plan/1.0','frozen_at':datetime.now(timezone.utc).isoformat(),
          'dataset':'https://physionet.org/content/eegmmidb/1.0.0/','dataset_doi':'https://doi.org/10.13026/C28G6P',
          'license':'Open Data Commons Attribution License v1.0; cite the dataset and originating BCI2000 publication',
          'selection':'Subjects 1,50,109 and baseline runs 1,2; fixed before inspecting headers, waveforms or computed outcomes.',
          'repetition_scope':'This rule was set before the original evaluation. Repeating these known files is technical replay, not new unseen or held-out evidence.',
          'records':entries,'electrode_sites':SITES,
          'channel_resolution':'Unique header label whose trailing periods removed equals the prespecified site, case-insensitively; retain exact original label in requests/results.',
          'sample_selection':'Every original sample of each complete EDF+ recording; no trimming, replacement or chosen clean interval.',
          'expected_rate_hz':160,'expected_format':'contiguous EDF+; reject BAD annotations or inconsistent timing rather than silently change the reference scope',
          'production_profile':'eeg-welch-channel/1.0','parameters':{'window_s':2.0,'overlap_fraction':0.5,'bands_hz':BANDS,'relative_denominator_hz':[1,45]},
          'oracle':'Independent EDF signed-int16/channel-block reader and linear physical calibration; NumPy complex DFT matrix; periodic Hann; per-window demeaning; density divided by fs*sum(w^2); double interior positive frequencies; mean complete windows; half-open band sums times df.',
          'tolerances':{'psd_uv2_hz_atol':1e-8,'power_uv2_atol':1e-7,'relative_atol':1e-10,'rtol':1e-9,'native_sample_v_atol':1e-15,'native_time_s_atol':1e-12},
          'source_freeze':'Execution source hashes are locked separately before actual workers; any change during the run aborts. Protocol choices remain unchanged.',
          'evaluation':'Check all selected calibrated samples/times against production native reader; complete PSD bins, band/total powers, relative powers, RMS and peak frequency against independent oracle. Include every selected record and failure.',
          'limits':['Numerical/header qualification only; no independent artifact/brain-state/clinical labels or physical acquisition evidence.',
                    'No spectral or preprocessing tuning; no guarantee that eyes-closed alpha increases.',
                    'No re-reference, ICA, notch, automatic artifact correction or healthy-reference interpretation.'],
          'checksums_sha256':digest(folder/'SHA256SUMS.txt')}
    save(folder/'plan.json',plan);(folder/'plan.sha256').write_text(digest(folder/'plan.json')+'\n',encoding='ascii')
    print(json.dumps({'plan_sha256':digest(folder/'plan.json'),'records':RECORDS,'sites':SITES}),flush=True)

def decode_edf(path,sites):
    raw=path.read_bytes();assert raw[:8]==b'0       '
    size=int(raw[184:192]);count=int(raw[236:244]);duration=float(raw[244:252]);channels=int(raw[252:256])
    reserved=raw[192:236].decode('ascii').strip()
    assert reserved.startswith('EDF+C') and count>0 and duration>0 and size==256*(channels+1)
    cursor=256;fields={}
    for name,width in [('label',16),('transducer',80),('unit',8),('physical_min',8),('physical_max',8),('digital_min',8),('digital_max',8),('prefilter',80),('samples_per_record',8),('reserved',32)]:
        fields[name]=[raw[cursor+i*width:cursor+(i+1)*width].decode('ascii').strip() for i in range(channels)];cursor+=width*channels
    assert cursor==size
    samples=[int(x) for x in fields['samples_per_record']];record_bytes=sum(samples)*2
    assert len(raw)==size+count*record_bytes and len(set(fields['label']))==channels
    indices=[]
    for site in sites:
        matches=[i for i,name in enumerate(fields['label']) if name.rstrip('.').lower()==site.lower()]
        assert len(matches)==1;indices.extend(matches)
    annotation_indices=[i for i,name in enumerate(fields['label']) if name=='EDF Annotations']
    assert len(annotation_indices)==1
    offset=np.cumsum([0]+samples[:-1])*2;out={i:[] for i in indices};annotations=[];timing=[]
    for r in range(count):
        for i in indices:
            start=size+r*record_bytes+int(offset[i]);out[i].append(np.frombuffer(raw,dtype='<i2',count=samples[i],offset=start).copy())
        a=annotation_indices[0];start=size+r*record_bytes+int(offset[a]);block=raw[start:start+2*samples[a]]
        tals=[tal for tal in block.split(b'\0') if tal]
        assert tals
        first=tals[0].split(b'\x14');assert len(first)>=3 and first[1]==b''
        onset=float(first[0].split(b'\x15')[0]);assert abs(onset-r*duration)<1e-12;timing.append(onset)
        for tal in tals:
            parts=tal.split(b'\x14');clock=parts[0].split(b'\x15');onset=float(clock[0]);span=float(clock[1]) if len(clock)>1 else None
            for label in parts[1:]:
                if label:
                    desc=label.decode('utf-8');assert not desc.lower().startswith('bad')
                    annotations.append({'onset_s':onset,'duration_s':span,'description':desc})
    values=[];descriptors=[]
    for i,site in zip(indices,sites):
        digital=np.concatenate(out[i]);unit=fields['unit'][i];assert unit in {'V','mV','uV'}
        pmin,pmax=[float(fields[k][i]) for k in ('physical_min','physical_max')]
        dmin,dmax=[int(fields[k][i]) for k in ('digital_min','digital_max')]
        assert pmin<pmax and dmin<dmax and digital.min()>=dmin and digital.max()<=dmax
        factor={'V':1,'mV':1e-3,'uV':1e-6}[unit]
        scale=(pmax-pmin)/(dmax-dmin)
        converted=(digital.astype(float)-dmin)*scale+pmin;converted*=factor
        fs=samples[i]/duration;assert fs==160
        values.append(converted)
        descriptors.append({'site':site,'label':fields['label'][i],'channel_index_zero_based':i,'unit':unit,'sampling_rate_hz':fs,
                            'samples':len(digital),'physical_min':pmin,'physical_max':pmax,'digital_min':dmin,'digital_max':dmax,
                            'physical_units_per_digital_step':scale,'volts_per_physical_unit':factor,'transducer':fields['transducer'][i],
                            'prefilter':fields['prefilter'][i],'observed_digital_min':int(digital.min()),'observed_digital_max':int(digital.max()),
                            'rail_sample_count':int(np.sum((digital==dmin)|(digital==dmax)))})
    data=np.stack(values);times=np.arange(data.shape[1],dtype=float)/160
    return data,times,{'format':reserved,'record_duration_s':duration,'records':count,'record_timing_onsets_s':timing,'channels_total':channels,
                       'header_bytes':size,'data_record_bytes':record_bytes,'selected_channels':descriptors,'annotations':annotations}

def dft_welch(values,fs,window_s=2,overlap=.5):
    n=int(round(fs*window_s));step=n-int(n*overlap);starts=np.arange(0,len(values)-n+1,step)
    assert len(values)>=2*n and len(starts)>0
    w=.5-.5*np.cos(2*np.pi*np.arange(n)/n)
    windows=np.stack([values[s:s+n] for s in starts]);windows-=windows.mean(axis=1,keepdims=True)
    frequencies=np.arange(n//2+1)*fs/n
    transform=np.exp(-2j*np.pi*np.outer(np.arange(n//2+1),np.arange(n))/n)
    spectrum=(windows*w)@transform.T
    psd=(spectrum.real**2+spectrum.imag**2)/(fs*np.sum(w*w))
    psd[:,1:(-1 if n%2==0 else None)]*=2
    expected_parseval=np.mean(np.sum((windows*w)**2,axis=1)/np.sum(w*w))
    mean=psd.mean(axis=0);assert np.isclose(mean.sum()*fs/n,expected_parseval,rtol=1e-12,atol=1e-24)
    return frequencies,mean*1e12,{'n_per_segment':n,'n_overlap':n-step,'windows':len(starts),'unused_tail_samples':len(values)-(int(starts[-1])+n),
                                'frequency_bin_width_hz':fs/n,'parseval_weighted_power_uv2':float(expected_parseval*1e12)}

def analytic_checks():
    fs=160;t=np.arange(1600)/fs
    _,dc,_=dft_welch(np.full(1600,7e-6),fs);assert np.max(dc)<1e-20
    f,p,_=dft_welch(20e-6*np.sin(2*np.pi*10*t),fs);assert np.isclose(p.sum()*(f[1]-f[0]),200,rtol=1e-12)
    _,nyquist,_=dft_welch(20e-6*(-1.)**np.arange(1600),fs);assert np.isclose(nyquist.sum()*.5,400,rtol=1e-12)
    return {'constant_after_demean':'zero','sine_20uv_peak_total_uv2':float(p.sum()*.5),'nyquist_20uv_total_uv2':float(nyquist.sum()*.5)}

def calibration_probe(args):
    # This is the implementation under test, executed only by methods Python.
    spec=importlib.util.spec_from_file_location('native_probe',ROOT/'scripts/workers/physiology.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    request=read(args.request);recordings,info=module.native_eeg(Path(request['source_path']),request['metadata'],'edf')
    assert len(recordings)==1
    np.savez(args.output,values=recordings[0]['values'],times=recordings[0]['times'])
    save(Path(args.output).with_suffix('.json'),info)

def full_events(manifest):
    path=Path(manifest['path']);assert digest(path)==manifest['sha256'] and path.stat().st_size==manifest['bytes']
    tables=[];active=None;total=0;complete=False
    with path.open(encoding='utf-8') as stream:
        header=json.loads(next(stream));assert header['kind']=='physiology-events'
        for line in stream:
            item=json.loads(line);assert not complete
            if item['type']=='table':assert active is None;active={'declaration':item,'rows':[]};offset=0
            elif item['type']=='rows':
                assert item['table_id']==active['declaration']['table_id'] and item['offset']==offset
                fields=[x['name'] for x in active['declaration']['columns']]
                assert all(len(row)==len(fields) for row in item['rows'])
                active['rows'].extend(dict(zip(fields,row)) for row in item['rows']);offset+=len(item['rows']);total+=len(item['rows'])
            elif item['type']=='table_end':assert item['rows']==offset==active['declaration']['expected_rows'];tables.append(active);active=None
            elif item['type']=='complete':
                assert active is None and item['rows']==total==manifest['rows'] and item['tables']==len(tables)==manifest['tables'];complete=True
            else:raise AssertionError(item['type'])
    assert complete and digest(path)==manifest['sha256']
    return header,tables

def code_hashes():return {name:digest(ROOT/name) for name in CODE}

def audit(folder):
    """Inspect saved units, header evidence and exact table associations; no jobs."""
    results=read(folder/'results.json');plan=read(folder/'plan.json');lock=read(folder/'execution-lock.json');checks=0
    assert digest(folder/'plan.json')==results['plan_sha256']==lock['plan_sha256']
    for row in results['records']:
        work=folder/row['record'];output=read(work/'worker-result.json');request=read(work/'request.json')
        assert digest(work/'worker-result.json')==row['worker_result_sha256'] and digest(work/'request.json')==row['request_sha256']
        source=folder/'source'/(row['record']+'.edf');assert digest(source)==row['source_sha256']
        _,_,header=decode_edf(source,plan['electrode_sites']);assert header==row['calibration']
        gate=output['source']['calibration_gate'];assert gate['inspector_sha256']==lock['source_code_sha256']['scripts/workers/headers.py']
        for independent,native in zip(header['selected_channels'],gate['selected_channels']):
            assert native['name']==independent['label'] and native['source_unit']==independent['unit'] and native['analysis_unit']=='V'
            assert native['sampling_rate_hz']==independent['sampling_rate_hz'] and native['sample_count']==independent['samples']
            for key in ('physical_min','physical_max','digital_min','digital_max','prefilter','transducer'):
                assert native['calibration_evidence'][key]==independent[key]
            checks+=1
        h,tables=full_events(row['artifact']);encoded=json.dumps(h['provenance'],sort_keys=True,separators=(',',':'),ensure_ascii=True).encode('ascii')+b'\n'
        assert hashlib.sha256(encoded).hexdigest()==h['provenance_sha256']==row['artifact']['provenance_sha256']
        assert h['provenance']['parameters']['source_mapping']==request['metadata'] and h['provenance']['parameters']['requested']==plan['parameters']
        for table in tables:
            t=table['declaration'];columns={c['name']:c for c in t['columns']};channel=t['identity']['channel']
            assert columns['frequency_hz']['unit']=='Hz' and columns['density_uv2_hz']['unit']=='uV^2/Hz'
            assert columns['frequency_hz']['role']=='coordinate' and t['coordinates']['axis']=='frequency'
            assert t['identity']['group']=={k:request['metadata'][k] for k in ('participant_id','session_id','condition_id')}
            s=t['support']['source'];n=next(c['samples'] for c in header['selected_channels'] if c['label']==channel)
            assert s['source_row_start']==0 and s['source_row_end_exclusive']==n and s['samples']==n and s['retained_samples']==n
            assert s['unit']=='V' and s['sampling_rate']==160 and s['channel_quality']['time_gap_count']==0
            method=t['support']['method'];assert all(method[k]==v for k,v in plan['parameters'].items())
            assert method['n_fft']==method['n_per_segment']==320 and method['n_overlap']==160 and method['remove_dc'] is True
            assert method['recipe']=='eeg-welch-channel/1.0' and method['average']=='mean' and method['window']=='hann'
            checks+=1
        for f in output['features']:
            unit='uV' if f['name']=='signal_rms' else 'Hz' if f['name']=='psd_peak_frequency' else 'proportion' if f['name'].endswith('_relative_power') else 'uV^2'
            assert f['unit']==unit
            if f['name'].endswith(('_absolute_power','_relative_power')):assert f['band_hz']==BANDS[f['name'].split('_')[0]]
            checks+=1
    receipt={'passed':True,'checks':checks,'scope':'Saved native calibration, complete artifact identity/units/support/method and feature units/bands; no worker rerun.',
             'results_sha256':digest(folder/'results.json'),'harness_sha256':digest(__file__)}
    save(folder/'saved-metadata-audit.json',receipt);print(json.dumps(receipt),flush=True)

def render(folder):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from matplotlib.lines import Line2D
    results=read(folder/'results.json');colors=['#1d6491','#b3471b','#288059']
    fig,axes=plt.subplots(3,2,figsize=(12,10),sharex=True,layout='constrained')
    for ax,record in zip(axes.flat,results['records']):
        for c,color in zip(record['channels'],colors):
            ax.semilogy(c['frequencies_hz'],c['worker_density_uv2_hz'],color=color,linewidth=1.8,alpha=.65)
            ax.semilogy(c['frequencies_hz'],c['reference_density_uv2_hz'],color=color,linewidth=.9,linestyle='--')
        condition='eyes open' if record['condition'].startswith('eyes_open') else 'eyes closed'
        ax.set_title(record['record']+' | '+condition,fontsize=11)
        ax.set_ylabel('PSD (µV²/Hz)');ax.set_xlim(0,80);ax.grid(alpha=.2)
    for ax in axes[-1]:ax.set_xlabel('Frequency (Hz)')
    handles=[Line2D([0],[0],color=c,label=site) for c,site in zip(colors,SITES)]
    handles += [Line2D([0],[0],color='black',lw=2,label='Production'),Line2D([0],[0],color='black',ls='--',label='Independent DFT')]
    fig.suptitle('Recorded EEG Welch spectra: production and independent DFT\nOriginal acquisition reference; complete saved frequency bins',fontsize=14)
    fig.legend(handles=handles,loc='outside lower center',ncol=5,frameon=False)
    fig.savefig(folder/'recorded-welch-spectra.png',dpi=170);plt.close(fig)
    fig,axes=plt.subplots(3,2,figsize=(12,8),sharex=True,layout='constrained')
    for ax,record in zip(axes.flat,results['records']):
        values,times,_=decode_edf(folder/'source'/(record['record']+'.edf'),SITES);keep=times<5
        ax.plot(times[keep],values[1,keep]*1e6,color=colors[1],lw=.9);ax.set_title(record['record']+' | O1 source samples',fontsize=11)
        ax.set_ylabel('Input (µV)');ax.grid(alpha=.2)
    for ax in axes[-1]:ax.set_xlabel('Seconds from file start')
    fig.suptitle('Original EDF samples after independent header calibration\nFirst five seconds illustrated; all samples contributed to the recorded comparison',fontsize=14)
    fig.savefig(folder/'recorded-input-waveforms.png',dpi=170);plt.close(fig)

def run(folder,methods_python):
    plan=read(folder/'plan.json');assert digest(folder/'plan.json')==(folder/'plan.sha256').read_text().strip()
    if (folder/'execution-lock.json').exists() or (folder/'results.json').exists():raise ValueError('Preserve completed/partial execution; use a fresh evidence folder with the same frozen plan.')
    lock={'locked_at':datetime.now(timezone.utc).isoformat(),'source_code_sha256':code_hashes(),'harness_sha256':digest(__file__),'plan_sha256':digest(folder/'plan.json')}
    save(folder/'execution-lock.json',lock);oracle_checks=analytic_checks();results=[]
    source=folder/'source';source.mkdir(exist_ok=True)
    flags=subprocess.CREATE_NO_WINDOW if sys.platform=='win32' else 0
    for entry in plan['records']:
        assert code_hashes()==lock['source_code_sha256']
        record=entry['record'];edf=source/(record+'.edf')
        if not edf.exists():edf.write_bytes(download(entry['url'],4*1024**2))
        assert digest(edf)==entry['sha256']
        values,times,header=decode_edf(edf,plan['electrode_sites'])
        work=folder/record;work.mkdir();(work/'complete').mkdir();save(work/'independent-header.json',header)
        exact_channels=[c['label'] for c in header['selected_channels']]
        request={'schema':'brohn-worker-request/1.0','operation':'physiology','modality':'eeg','format':'edf','source_path':str(edf),'artifact_directory':str(work/'complete'),
                 'metadata':{'value_columns':exact_channels,'unit':'native','sampling_rate':160,'origin':'public_reference','participant_id':record[:4],
                             'session_id':record,'condition_id':entry['condition']},'parameters':plan['parameters'],'origin':'public_reference'}
        save(work/'request.json',request)
        commands=[([str(methods_python),str(ROOT/'scripts/workers/physiology.py'),'--request',str(work/'request.json'),'--output',str(work/'worker-result.json')],'worker'),
                  ([str(methods_python),str(Path(__file__).resolve()),'probe','--request',str(work/'request.json'),'--output',str(work/'native-samples.npz')],'native-probe')]
        for command,name in commands:
            child=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=120,creationflags=flags)
            (work/(name+'.log')).write_text(child.stdout+child.stderr,encoding='utf-8')
            if child.returncode:raise RuntimeError(child.stdout+child.stderr)
            assert code_hashes()==lock['source_code_sha256']
        output=read(work/'worker-result.json');probe=np.load(work/'native-samples.npz')
        assert output['status']=='completed' and len(output['recordings'])==3
        assert output['source']['sha256']==entry['sha256'] and output['source']['rows']==len(times)
        assert output['source']['calibration_gate']['resampling_applied'] is False and not output['source']['bad_channels_excluded']
        assert output['engine']['worker_sha256']==lock['source_code_sha256']['scripts/workers/physiology.py']
        assert output['engine']['artifact_writer_sha256']==lock['source_code_sha256']['scripts/workers/physiology_artifacts.py']
        np.testing.assert_allclose(probe['values'],values,atol=plan['tolerances']['native_sample_v_atol'],rtol=1e-12)
        np.testing.assert_allclose(probe['times'],times,atol=plan['tolerances']['native_time_s_atol'],rtol=0)
        assert len(output['artifacts'])==1 and output['artifacts'][0]['kind']=='physiology-events'
        artifact_header,tables=full_events(output['artifacts'][0]);assert len(tables)==3
        assert artifact_header['provenance']['source_sha256']==entry['sha256'] and artifact_header['provenance']['engine']==output['engine']
        channels=[]
        for i,channel in enumerate(exact_channels):
            f,p,details=dft_welch(values[i],160)
            matches=[t for t in tables if t['declaration']['identity']['channel']==channel];assert len(matches)==1
            table=matches[0];rows=table['rows'];assert all(r['type']=='psd_bin' for r in rows)
            assert table['declaration']['identity']['group']['participant_id']==record[:4]
            np.testing.assert_array_equal([r['frequency_hz'] for r in rows],f)
            actual=np.array([r['density_uv2_hz'] for r in rows])
            np.testing.assert_allclose(actual,p,atol=plan['tolerances']['psd_uv2_hz_atol'],rtol=plan['tolerances']['rtol'])
            features={x['name']:x for x in output['features'] if x['channel']==channel};df=f[1]-f[0]
            denominator=float(p[(f>=1)&(f<45)].sum()*df)
            expected={'signal_rms':float(np.sqrt(np.mean(values[i]**2))*1e6),'psd_total_power':float(p.sum()*df),
                      'psd_peak_frequency':float(f[np.argmax(p)]),'relative_power_denominator':denominator}
            for band,(lo,hi) in BANDS.items():
                power=float(p[(f>=lo)&(f<hi)].sum()*df);expected[band+'_absolute_power']=power;expected[band+'_relative_power']=power/denominator
            errors={}
            for name,expected_value in expected.items():
                actual_value=features[name]['value'];atol=plan['tolerances']['relative_atol'] if name.endswith('_relative_power') else plan['tolerances']['power_uv2_atol']
                np.testing.assert_allclose(actual_value,expected_value,rtol=plan['tolerances']['rtol'],atol=atol);errors[name]=actual_value-expected_value
            channels.append({'channel':channel,'site':SITES[i],'sample_count':len(times),'psd_bins':len(f),'max_abs_native_sample_error_v':float(np.max(np.abs(probe['values'][i]-values[i]))),
                             'max_abs_psd_error_uv2_hz':float(np.max(np.abs(actual-p))),'max_relative_psd_error':float(np.max(np.abs(actual-p)/np.maximum(np.abs(p),1e-30))),
                             'oracle':details,'features':expected,'feature_signed_errors':errors,'frequencies_hz':f.tolist(),'reference_density_uv2_hz':p.tolist(),'worker_density_uv2_hz':actual.tolist()})
        agreement={'record':record,'condition':entry['condition'],'source_sha256':entry['sha256'],'worker_result_sha256':digest(work/'worker-result.json'),
                   'request_sha256':digest(work/'request.json'),'calibration':header,'channels':channels,'engine':output['engine'],'artifact':output['artifacts'][0]}
        save(work/'agreement.json',agreement);results.append(agreement)
        save(folder/'progress.json',{'completed':[r['record'] for r in results]});print(json.dumps({'completed':record,'channels':len(channels),'max_psd_error':max(c['max_abs_psd_error_uv2_hz'] for c in channels)}),flush=True)
    assert code_hashes()==lock['source_code_sha256']
    save(folder/'results.json',{'schema':'brohn-eeg-recorded-reference/1.0','completed_at':datetime.now(timezone.utc).isoformat(),'passed':True,
                               'plan_sha256':digest(folder/'plan.json'),'execution':lock,'oracle_analytic_checks':oracle_checks,'reader_numpy':importlib.metadata.version('numpy'),'records':results})

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('mode',choices=['prepare','run','probe','audit','render']);parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--methods-python',type=Path);parser.add_argument('--request',type=Path);args=parser.parse_args()
    if args.mode=='probe':calibration_probe(args)
    elif args.mode=='prepare':prepare(outside(args.output))
    elif args.mode=='audit':audit(outside(args.output))
    elif args.mode=='render':render(outside(args.output))
    else:
        if args.methods_python is None:parser.error('run requires --methods-python')
        run(outside(args.output),args.methods_python.resolve())
