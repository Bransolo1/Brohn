"""Supervised complete-export display adapter; authorization belongs to R guards."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

import clock_plot as plot

MAX_REQUEST=3*1024**2
MAX_RESULT=256*1024
SUMMARY_KEYS=('schema','status','window_ref','map_ref','binding','artifact_hashes','implementation','coverage','axis',
              'scope','physical_synchronization','uncertainty','scientific_scoring')
SCOPE='schema_binding_and_plot_bytes_not_original_source_reinspection'


def read_json(path,maximum):
    path=Path(path)
    plot.require(not path.is_symlink(),'Use an owned regular JSON file.')
    raw=plot.bounded_bytes(path,maximum)
    return plot.decode(raw.decode('utf-8')),hashlib.sha256(raw).hexdigest()


def summary(value):
    return {key:value[key] for key in SUMMARY_KEYS}


def json_equivalent(left,right):
    """Allow exact finite JSON number equality across R/Python, never coercion."""
    if type(left) in (int,float) and type(right) in (int,float):
        return (type(left) is int or math.isfinite(left)) and (type(right) is int or math.isfinite(right)) and left==right
    if type(left) is not type(right):return False
    if type(left) is dict:return left.keys()==right.keys() and all(json_equivalent(left[k],right[k]) for k in left)
    if type(left) is list:return len(left)==len(right) and all(json_equivalent(a,b) for a,b in zip(left,right))
    return left==right


def check_shape(value,saved):
    """Validate display structure/counts, without re-reading any original CSV."""
    start=plot.decimal(saved['selection']['start_s']);end=plot.decimal(saved['selection']['end_s'])
    expected={(t['recording_side'],t['track_id']):t for t in saved['tracks']}
    kinds={(side,t['id']):t['kind'] for side in ('source','reference') for t in [saved['source_request'][side]['marker'],*saved['source_request'][side]['tracks']]}
    axis=value['axis']
    plot.require(axis['start_relative_seconds']==plot.pair(start) and axis['end_relative_seconds']==plot.pair(end)
                 and axis['end_exclusive'] is True and axis['display_base_relative_seconds']==plot.pair(start)
                 and axis['display_base_exact_decimal']==saved['selection']['start_s']
                 and axis['reference_anchor_seconds']==saved['preview']['mapping']['anchors'][0]['reference_seconds'],
                 'Display axis support or original reference base changed.')
    expected_ticks=[{'position':i/4,'relative_seconds':plot.pair(start+(end-start)*i/4),'offset_seconds':plot.pair((end-start)*i/4),
                     'display_offset_label':plot.display_label((end-start)*i/4)} for i in range(5)]
    plot.require(axis['ticks']==expected_ticks,'Display axis tick coordinates or labels changed.')
    found=set();numeric=0;vertices=0;continuity=0
    def point(item,track,bin_id=None,signal=False):
        ref=item['original_row_reference'];time=plot.saved_fraction(item['relative_fraction'])
        plot.require(type(ref) is dict and set(ref)=={'recording_side','track_id','source_sequence','samples_sha256'}
                     and (ref['recording_side'],ref['track_id'])==(track['recording_side'],track['track_id'])
                     and ref['samples_sha256']==track['samples']['hash']
                     and plot.integer(ref['source_sequence'],1,track['source_rows']),'Invalid display original row reference.')
        plot.require(start<=time<end and type(item['display_x']) in (int,float)
                     and item['display_x']==float((time-start)/(end-start)),'Invalid display horizontal projection.')
        if bin_id is not None:plot.require((time-start)*512//(end-start)==bin_id,'Display point escaped its exact bin.')
        if signal:
            y=plot.saved_fraction(item['display_y_fraction'])
            plot.require(item['source_sequence']==ref['source_sequence'] and 0<=y<=1
                         and type(item['display_y']) in (int,float) and item['display_y']==float(y),'Invalid display vertical projection.')
            plot.decimal(item['value_json'],True)
        return ref['source_sequence']
    plot.require(type(value['lanes']) is list and type(value['events']) is list and len(value['lanes'])+len(value['events'])==len(expected),
                 'Complete plot lane inventory changed.')
    for signal,lanes in ((True,value['lanes']),(False,value['events'])):
        for lane in lanes:
            key=(lane['recording_side'],lane['track_id'])
            plot.require(key in expected and key not in found,'Duplicate or foreign display lane.');found.add(key);track=expected[key]
            plot.require(lane['saved_counts']=={k:track[k] for k in plot.COUNTS}
                         and lane['channel']==track['channel'] and lane['clock']==track['clock']
                         and lane['source_stream_id']==track['source_stream_id'] and lane['origin']==track['origin']
                         and lane['unit']==track['channel'].get('unit') and kinds[key]==('signal' if signal else 'markers'),
                         'Display lane source metadata changed.')
            if signal:
                counts=lane['display_counts'];runs=lane['runs'];breaks=lane['breaks']
                plot.require(type(runs) is list and type(breaks) is list
                             and all(plot.integer(counts[k],0,plot.MAX_ROWS) for k in ('numeric_observed','saved_missing','exact_export_only','selected_rows','representatives','continuity_runs'))
                             and counts['selected_rows']==track['selected_rows']
                             and counts['saved_missing']==track['missing_selected_values']
                             and counts['numeric_observed']+counts['saved_missing']+counts['exact_export_only']==track['selected_rows']
                             and counts['continuity_runs']==len(runs),'Signal display counts changed.')
                lane_rows=0;lane_vertices=0;last_sequence=0
                for index,run in enumerate(runs):
                    plot.require(run['run_id']==index+1 and type(run['groups']) is list and run['groups'],'Invalid continuity run.')
                    first=None;run_rows=0;last_bin=-1
                    for group in run['groups']:
                        plot.require(plot.integer(group['bin'],0,511) and group['bin']>last_bin
                                     and plot.integer(group['observation_count'],1,plot.MAX_ROWS)
                                     and type(group['points']) is list and 1<=len(group['points'])<=4
                                     and len(group['points'])<=group['observation_count'],'Invalid original-observation envelope group.')
                        last_bin=group['bin'];run_rows+=group['observation_count']
                        for item in group['points']:
                            sequence=point(item,track,group['bin'],True)
                            plot.require(sequence>last_sequence and item['bin']==group['bin'],'Display original sequences changed.')
                            if first is None:first=sequence
                            last_sequence=sequence;lane_vertices+=1
                    plot.require(run['first_sequence']==first and run['last_sequence']==last_sequence and run['represented_rows']==run_rows,
                                 'Continuity run boundaries or counts changed.')
                    lane_rows+=run_rows
                plot.require(lane_rows==counts['numeric_observed'] and lane_vertices==counts['representatives'],'Complete signal coverage changed.')
                numeric+=lane_rows;vertices+=lane_vertices;continuity+=len(runs)+len(breaks)
            else:
                count=lane['selected_rows']
                plot.require(count==track['selected_rows'] and lane['missing_selected_values']==track['missing_selected_values'],'Event display counts changed.')
                if count<=plot.INDIVIDUAL_EVENTS:
                    plot.require(lane['mode']=='individual' and type(lane['events']) is list and len(lane['events'])==count and lane['bins']==[],
                                 'Individual event inventory changed.')
                    sequences=[point(item,track) for item in lane['events']]
                    plot.require(all(b>a for a,b in zip(sequences,sequences[1:])),'Original event ordering changed.')
                else:
                    plot.require(lane['mode']=='counted_bins' and lane['events']==[] and type(lane['bins']) is list and 1<=len(lane['bins'])<=512,
                                 'Counted event inventory changed.')
                    total=0;last_bin=-1;missing=0;exact_only=0
                    for group in lane['bins']:
                        plot.require(plot.integer(group['bin'],0,511) and group['bin']>last_bin and plot.integer(group['count'],1,plot.MAX_ROWS)
                                     and plot.integer(group['missing_values'],0,group['count'])
                                     and plot.integer(group['exact_export_only_values'],0,group['count']),'Invalid counted event bin.')
                        plot.require(point(group['first'],track,group['bin'])<=point(group['last'],track,group['bin']),'Counted event original ordering changed.')
                        total+=group['count'];missing+=group['missing_values'];exact_only+=group['exact_export_only_values'];last_bin=group['bin']
                    plot.require(total==count and missing==lane['missing_selected_values'] and exact_only==lane['exact_export_only_values'],
                                 'Complete counted event coverage changed.')
    coverage=value['coverage']
    plot.require(numeric==coverage['numeric_observations_represented'] and vertices==coverage['signal_representatives']
                 and vertices<=plot.MAX_VERTICES and continuity<=plot.MAX_RUNS_BREAKS,'Display resource or complete coverage bound changed.')
    status='empty_window' if not saved['counts']['selected_rows'] else 'available' if numeric else 'no_supported_numeric_signal'
    plot.require(value['status']==status,'Complete plot availability changed.')


def check(request,result):
    plot.require(type(request) is dict and request.get('schema')=='brohn-clock-plot-input/0.1','Unsupported original plot request.')
    plot.require(type(result) is dict and set(result)=={'schema','artifact','summary'}
                 and result['schema']=='brohn-clock-plot-worker-result/0.1','Unsupported plot worker result.')
    artifact=result['artifact']
    plot.require(type(artifact) is dict and set(artifact)=={'file','kind','sha256','bytes','media_type'}
                 and artifact['file']=='plot.json' and artifact['kind']=='clock_plot' and artifact['media_type']=='application/json'
                 and type(artifact['sha256']) is str and plot.HASH.fullmatch(artifact['sha256'])
                 and plot.integer(artifact['bytes'],1,plot.MAX_OUTPUT),'Invalid complete plot artifact descriptor.')
    path=Path(request['output_directory'])/artifact['file']
    raw_summary=result['summary']
    plot.require(type(raw_summary) is dict and set(raw_summary)==set(SUMMARY_KEYS),'Invalid complete plot summary fields.')
    value,digest=read_json(path,min(artifact['bytes'],plot.MAX_OUTPUT))
    plot.require(path.stat().st_size==artifact['bytes'] and digest==artifact['sha256'],'Complete plot bytes changed.')
    plot.require(type(value) is dict and value.get('schema')=='brohn-clock-plot/0.1'
                 and value.get('status') in ('available','empty_window','no_supported_numeric_signal'),'Unsupported complete plot schema.')
    plot.require(json_equivalent(summary(value),raw_summary),'Complete plot summary differs from its artifact.')
    expected_artifacts={a['kind']:{'hash':a['hash'],'bytes':a['bytes']} for a in request['artifacts']}
    saved=request['window_result']['result']
    for field,expected in [('window_ref',request['window_ref']),('map_ref',request['map_ref']),('binding',saved['binding']),
                           ('artifact_hashes',expected_artifacts),('implementation',{'clock_plot.py':plot.sha(Path(plot.__file__).read_bytes())})]:
        plot.require(plot.encoded(value[field])==plot.encoded(expected),'Complete plot '+field+' binding changed.')
    coverage=value['coverage']
    plot.require(type(coverage) is dict and coverage['bins']==512 and coverage['reduction_profile']==plot.PROFILE
                 and coverage['complete_selected_rows_read']==saved['counts']['selected_rows']
                 and coverage['complete_unplaced_rows_read']==saved['counts']['unplaced_rows']
                 and coverage['source_observation_count']==saved['counts']['source_rows']
                 and coverage['complete_segment_records_read']==next(a['rows'] for a in saved['artifacts'] if a['kind']=='complete_original_segments'),
                 'Complete plot coverage differs from its original saved exports.')
    plot.require(value['physical_synchronization']=='not_established' and value['uncertainty']=='unknown'
                 and value['scientific_scoring']=='not_performed' and value['scope']=='complete_saved_export_display_component_only',
                 'Complete plot interpretation changed.')
    check_shape(value,saved)
    plot.verify({'path':str(path),'bytes':artifact['bytes'],'hash':artifact['sha256']})
    return value


def execute(request):
    value=plot.prepare_plot(request)
    path=Path(request['output_directory'])/'plot.json'
    size=path.stat().st_size
    raw=plot.bounded_bytes(path,plot.MAX_OUTPUT)
    result={'schema':'brohn-clock-plot-worker-result/0.1',
            'artifact':{'file':'plot.json','kind':'clock_plot','sha256':plot.sha(raw),'bytes':size,'media_type':'application/json'},
            'summary':summary(value)}
    check(request,result)
    return result


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--request',required=True)
    parser.add_argument('--result')
    parser.add_argument('--output',required=True)
    args=parser.parse_args()
    destination=Path(args.output)
    plot.require(destination.parent.is_dir() and not destination.exists(),'Use a fresh owned result file.')
    request,request_hash=read_json(args.request,MAX_REQUEST)
    if args.result:
        result,result_hash=read_json(args.result,MAX_RESULT)
        check(request,result)
        output={'schema':'brohn-clock-plot-verification/0.1','passed':True,'request_sha256':request_hash,
                'result_sha256':result_hash,'scope':SCOPE}
    else:
        output=execute(request)
    raw=plot.bounded_encoded(output,MAX_RESULT-1)+b'\n'
    with destination.open('xb') as handle:handle.write(raw)


if __name__=='__main__':
    main()
