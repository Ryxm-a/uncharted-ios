# PC-side preparation of a dump for iOS

Run **once** on any Windows/Mac/Linux machine with Python 3:

```
# You already have the PC port's upstream checkout (uncharted_pc):
python3 ios/tools/make_ios_load.py "C:\games\CUSA02343"
# Uncharted 2:  python3 ios/tools/make_ios_load.py <dump> --exe big2-ps4_Shipping.elf
# Uncharted 3:  python3 ios/tools/make_ios_load.py <dump> --exe big3-ps4_Shipping.elf
```

Produces `boot-linked.bin`, `patches.bin`, `content.bin`, `manifest.json` next to
`eboot.bin` in the dump itself; the iOS app picks them up. Turn off game-file
redistribution check: these are YOUR files and stay on your device.
