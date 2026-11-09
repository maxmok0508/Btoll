#!/usr/bin/env python3
"""Combine the authorized local animation clips into a single looping Lottie timeline."""
from pathlib import Path
import copy,hashlib,json
root=Path(__file__).resolve().parents[1]/'portable/Bridge/assets/animations'
catalog=json.loads((root/'catalog.json').read_text())
clips=[entry for entry in catalog if entry['id']!='sequence']
(root/'catalog.json').write_text(json.dumps(clips,ensure_ascii=False,indent=2)+'\n')

def combine(group):
    selected=[entry for entry in clips if entry['id'].startswith('grok-'+group+'_')]
    assets=[];layers=[];images={};offset=0
    transform={'o':{'a':0,'k':100},'r':{'a':0,'k':0},'p':{'a':0,'k':[0,0,0]},'a':{'a':0,'k':[0,0,0]},'s':{'a':0,'k':[100,100,100]}}
    for index,entry in enumerate(selected):
        clip=json.loads((root/Path(entry['file']).name).read_text());mapping={}
        for image in clip['assets']:
            digest=hashlib.sha256(image['p'].encode()).hexdigest()
            if digest not in images:
                identifier='image_'+str(len(images));images[digest]=identifier;assets.append({**image,'id':identifier})
            mapping[image['id']]=images[digest]
        children=copy.deepcopy([layer for layer in clip['layers'] if layer['ty']!=1])
        for layer in children:layer['refId']=mapping[layer['refId']]
        comp='clip_'+str(index);assets.append({'id':comp,'w':96,'h':96,'layers':children})
        duration=clip['op']-clip['ip']
        layers.append({'ddd':0,'ind':index+1,'ty':0,'nm':entry['name'],'refId':comp,'sr':1,'ks':copy.deepcopy(transform),'w':96,'h':96,'ip':offset,'op':offset+duration,'st':offset,'bm':0});offset+=duration
    layers.append({'ddd':0,'ind':len(layers)+1,'ty':1,'sw':96,'sh':96,'sc':'#000000','ks':transform,'ip':0,'op':offset,'st':0,'bm':0})
    value={'v':'5.7.4','fr':20,'ip':0,'op':offset,'w':96,'h':96,'nm':'Codex '+group,'ddd':0,'assets':assets,'layers':layers}
    (root/('state-'+group+'.json')).write_text(json.dumps(value,ensure_ascii=False,separators=(',',':')))
    print(group,len(selected),'clips',offset/20,'seconds')
for group in ['working','streaming','blocked','done','rotation','idle']:combine(group)
old=root/'all-sequence.json'
if old.exists():old.unlink()
