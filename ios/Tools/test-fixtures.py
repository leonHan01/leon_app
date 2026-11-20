import sys,json,zipfile
from pathlib import Path
out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
manifest={'format':'leon-chat','version':1,'conversation':{'name':'测试备份','kind':'direct'},'messages':[{},{}]}
for name,method in [('stored.zip',zipfile.ZIP_STORED),('deflated.zip',zipfile.ZIP_DEFLATED)]:
 with zipfile.ZipFile(out/name,'w',compression=method) as z: z.writestr('manifest.json',json.dumps(manifest,ensure_ascii=False).encode())
with zipfile.ZipFile(out/'oversize.zip','w',compression=zipfile.ZIP_DEFLATED) as z:z.writestr('manifest.json',b'x'*(16*1024*1024+1))
with zipfile.ZipFile(out/'invalid.zip','w') as z:z.writestr('manifest.json',b'{}')
data=bytearray((out/'stored.zip').read_bytes());data[45]^=1;(out/'corrupt.zip').write_bytes(data)
