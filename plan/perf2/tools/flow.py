# usage: python3 flow.py <time-profile.xml> [win START-END ...]
# Reads `xctrace export ... table[@schema="time-profile"]`, keeps the app's main-thread samples,
# prints busy ms per 5 s window with activity labels, then top app frames for any given windows.
import sys, re, xml.etree.ElementTree as ET
from collections import Counter
ids={}
def reg(e):
    if e.get('id') is not None: ids[e.get('id')]=e
    for c in e: reg(c)
def R(e):
    r=e.get('ref'); return ids[r] if r is not None else e
S=[]
for ev,el in ET.iterparse(sys.argv[1], events=('end',)):
    if el.tag!='row': continue
    reg(el); tm=th=bt=None
    for c in el:
        e=R(c)
        if e.tag=='sample-time': tm=int(e.text)/1e9
        elif e.tag=='thread': th=e.get('fmt','')
        elif e.tag in('backtrace','tagged-backtrace'): bt=e
    if tm is not None and th and 'Main Thread' in th and ('SkriftMobile' in th or 'Skrift Dev' in th) and bt is not None:
        S.append((tm,[R(f).get('name','?') for f in bt.iter('frame')]))
P={'search':r'NoteSearch|matchesSearch|NoteVisibility|PreparedNoteSearch','editor':r'NoteBody|QuickNote|commitDraft|CommitDebouncer|EditConflict|MemoEditHead',
   'record':r'Recording|MemoSaver|LiveRecording|Transcription','list':r'MemosListView','page':r'MemoPageView|MemoDetailView','books':r'Audiobook|ReadAlong','sweep':r'LaunchSweeps|AssetMaterializer|FadingSweep'}
P={k:re.compile(v) for k,v in P.items()}
print("main samples",len(S))
for a in range(0,int(max([t for t,_ in S]+[0]))+5,5):
    W=[f for t,f in S if a<=t<a+5]
    if len(W)<250: continue
    c={k:sum(1 for f in W if any(p.search(x) for x in f)) for k,p in P.items()}
    print(f"{a:3d}-{a+5:3d} busy {len(W):4d} "+" ".join(f"{k}:{v}" for k,v in c.items() if v>30))
KEY=re.compile(r'(Memo|Note|Repository|Sweep|Lifecycle|Search|Names|Asset|Index|Snippet|Cloud|Library|Book|Derived|Card|Skrift|Recording|Transcri|Body|Chip|Title|Backlink|Photo|Image|Player|Saver|Conflict|Row|List|UICollection|preferredLayout)')
SKIP=re.compile(r'^(closure #\d+ in SkriftApp|partial apply|protocol witness|thunk|reabstraction)|ViewGraphRootValueUpdater|DynamicBody|ViewBodyAccessor|applyNodes|DynamicViewList|ForEachList|ViewList')
for w in sys.argv[2:]:
    a,b=map(float,w.split('-')); W=[f for t,f in S if a<=t<b]; inc=Counter()
    for f in W:
        for x in set(f):
            if KEY.search(x) and not SKIP.search(x): inc[x]+=1
    print(f"== {a:.0f}-{b:.0f}s main busy {len(W)} ms")
    for x,c in inc.most_common(10): print(f"  {c:5d} {x[:130]}")
