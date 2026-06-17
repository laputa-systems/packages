These files are extracted from Alpine edge `libgcc-15.2.0-r6.apk` payloads.

The package source still pins the original APK checksums. These generated files
exist because XSH's safe tar extractor rejects the APK's absolute symlink:

```text
usr/lib/libgcc_s.so -> /usr/lib/libgcc_s.so.1
```

Only the real runtime file is needed by Alpine's LLVM binaries.

Source APK checksums:

```text
aarch64 libgcc-15.2.0-r6.apk e62f234bf2405dd2f968165e19e4a56a03430a0634bbd26848ae4d150505ee80
x86_64  libgcc-15.2.0-r6.apk d285c3e251486004567c47353be986145a58c1f6761c6fae829c1a7e0a6b068f
```

Extracted file checksums:

```text
aarch64 libgcc_s.so.1 b83bc14b3e1660d66b0387077aea7e104fce3ed93bb56d05e30e4e2cdb37b473
x86_64  libgcc_s.so.1 5ea51dd885b6fc691eccc569d0bda739204204f6161e97075b26dc9c050d1ca1
```
