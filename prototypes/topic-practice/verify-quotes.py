"""Check full article coverage, exact English preservation, and paragraph routing."""
from pathlib import Path
import json
from collections import Counter
base=Path(__file__).resolve().parent
data=json.loads((base/'article-data.json').read_text())
source=(base/'source-readback.txt').read_text()
body=source[source.index('Until recently,'):source.index('This article was originally published')]
paragraphs=[line for line in body.splitlines() if line and not line.startswith(('##','Image:'))]
nodes=[data['root']]+[node for group in data['groups'] for node in [group['main']]+group['evidence']]
counts=Counter(node['paragraph'] for node in nodes)
assert counts==Counter(range(1,len(paragraphs)+1)),f'Missing or duplicate paragraphs: {counts}'
assert len({node['id'] for node in nodes})==len(nodes),'Duplicate DOM IDs'
for node in nodes:
    assert node['en']==paragraphs[node['paragraph']-1],f'Changed or incomplete paragraph {node["paragraph"]}'
    assert node['zh'].strip(),f'Missing Chinese paragraph {node["paragraph"]}'
assert sorted(nodes,key=lambda n:n['paragraph'])==data['paragraphs'],'Coverage index differs from actual nodes'
assert data['coverage']['bodyWords']==sum(len(s.split()) for s in paragraphs)
report={'source':data['readback'],'totalBodyParagraphs':len(paragraphs),'coveredBodyParagraphs':len(nodes),'missingParagraphs':[],'duplicateParagraphs':[],'allEnglishParagraphsExact':True,'bodyWords':data['coverage']['bodyWords'],'scope':data['coverage']['scope']}
(base/'quote-verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(f'{len(nodes)}/{len(paragraphs)} whole body paragraphs exactly preserved; no omissions or duplicates; {report["bodyWords"]} words.')
