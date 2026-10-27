import olefile, zlib, re, sys
p, out = sys.argv[1], sys.argv[2]
o = olefile.OleFileIO(p)
blob = b''
for s in o.listdir():
    name='/'.join(s); data=o.openstream(name).read()
    if name in ('BasicFileInfo','ProjectInformation','TransmissionData','Contents'):
        print('##', name, data.decode('utf-16-le','ignore').replace('\x00','')[:600].replace('\r',' '))
    for m in re.finditer(b'\x1f\x8b\x08', data):
        try:
            d = zlib.decompressobj(31)
            blob += d.decompress(data[m.start():]) + b'\n'
        except Exception: pass
open(out,'wb').write(blob)
print('decompressed bytes', len(blob))
