"""Two original loopback-only LSL sources; no physical device or real participant."""
import json, os, struct, sys, time
from pathlib import Path
config = json.loads(Path(sys.argv[1]).read_text())
os.environ['LSLAPICFG'] = config['lsl_config']
import pylsl

def outlet(name, role, source_id, value_format, unit):
    info = pylsl.StreamInfo(name, role, 1, 0, value_format, source_id)
    info.desc().append_child_value('origin', 'synthetic')
    channel = info.desc().append_child('channels').append_child('channel')
    channel.append_child_value('label', 'original_conductance' if role == 'EDA' else 'original_event')
    channel.append_child_value('type', role)
    channel.append_child_value('unit', unit)
    return pylsl.StreamOutlet(info, chunk_size=1, max_buffered=5)

signal = outlet('Original browser QA conductance', 'EDA', config['source_ids'][0], 'double64', 'uS')
markers = outlet('Original browser QA markers', 'Markers', config['source_ids'][1], 'string', 'marker')
Path(config['ready']).write_text('Original loopback outlets ready')
i = 0
with Path(config['sent']).open('w', encoding='utf-8') as evidence:
    while not Path(config['stop']).exists():
        if signal.have_consumers() and markers.have_consumers():
            cycle, slot = divmod(i, 6)
            timestamp = 100.125 + cycle*4 + [0, .25, .25, .125, 1.5, 2.0][slot]
            value = [0.0, -0.0, 1.25, 5.5, 8.0, 2.5][slot]
            marker = ['control', '', 'test', 'repeat', 'évent', 'complete'][slot]
            signal.push_sample([value], timestamp=timestamp)
            markers.push_sample([marker], timestamp=timestamp)
            evidence.write(json.dumps({'index': i, 'timestamp': repr(timestamp),
                'timestamp_ieee754_le_hex': struct.pack('<d', timestamp).hex(),
                'value': value, 'value_ieee754_le_hex': struct.pack('<d', value).hex(), 'marker': marker}, ensure_ascii=False)+'\n')
            evidence.flush()
            i += 1
        time.sleep(.05)
