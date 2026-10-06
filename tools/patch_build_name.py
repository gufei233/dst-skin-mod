"""Patch the internal build name of a dynamic animation zip's `build.bin`.

The `.zip` files copied out of the official databundles declare the official build name
inside `build.bin`. The mod references those builds with a `custom_` prefix, and a `.zip`
whose internal name does not match the runtime build name can fail to render. `.dyn` files
store no build name and need no patching.

`build.bin` layout: magic `BILD`, then at offset 0x10 a 4-byte little-endian name length,
then the ASCII build name at 0x14.

Usage (on Windows use `python`, not `python3` -- `python3` often maps to the Microsoft Store
stub and exits 49):

    python tools/patch_build_name.py <source.zip> <output.zip> <new_build_name>

Example:

    python tools/patch_build_name.py \
        _tmp/wagdrone_rolling_fire.zip \
        anim/dynamic/custom_wagdrone_rolling_fire.zip \
        custom_wagdrone_rolling_fire
"""

import os
import struct
import sys
import zipfile


def main(argv):
    if len(argv) != 4:
        print(__doc__)
        return 2

    src_zip, out_zip, new_name_text = argv[1], argv[2], argv[3]
    new_name = new_name_text.encode("ascii")

    with zipfile.ZipFile(src_zip, "r") as zin:
        if "build.bin" not in zin.namelist():
            raise SystemExit("build.bin not found in %s: %s" % (src_zip, zin.namelist()))

        data = bytearray(zin.read("build.bin"))
        if bytes(data[:4]) != b"BILD":
            raise SystemExit("invalid BILD magic in %s: %r" % (src_zip, bytes(data[:4])))

        old_len = struct.unpack_from("<I", data, 0x10)[0]
        old_name = bytes(data[0x14:0x14 + old_len])
        print("old internal name: %s" % old_name.decode("ascii", "replace"))

        if len(data) < 0x14 + old_len:
            raise SystemExit("build name length exceeds file size in %s" % src_zip)

        patched = (
            bytes(data[:0x10])
            + struct.pack("<I", len(new_name))
            + new_name
            + bytes(data[0x14 + old_len:])
        )

        with zipfile.ZipFile(out_zip, "w", zipfile.ZIP_DEFLATED) as zout:
            for item in zin.infolist():
                if item.filename == "build.bin":
                    zout.writestr(item, patched)
                else:
                    zout.writestr(item, zin.read(item.filename))

    print("new internal name: %s" % new_name_text)
    print("wrote %s (%d bytes)" % (out_zip, os.path.getsize(out_zip)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
