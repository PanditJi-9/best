#!/usr/bin/env python3
"""Compare the methods real extension APKs call with Best's runtime surface.

The class-level audit only proves a class is packaged. Mangalek showed the gap
that leaves: `SManga` existed, but `setMemo(JsonObject)` did not, so every
catalogue request died with NoSuchMethodError while the class audit stayed
green.

This reads each dex's method_ids/proto_ids, resolves every reference to a class
Best itself provides through the runtime's superclass/interface chain, and
prints the ones that cannot resolve.

Usage:
    python3 tool/source_method_audit.py --apks /path/to/apks \
        --runtime /path/to/compiled/runtime/classes

The runtime directory is what `tool/bootstrap_android.sh` compiles from
`tool/android/kotlin`; a local compile of that tree (see /tmp/kcheck.sh in the
release notes) is enough.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
import zipfile
from pathlib import Path

SURFACE = "eu.kanade.tachiyomi."

# java.lang.Object is not packaged with the runtime, so its members are listed
# explicitly instead of being treated as "some other jar will provide it".
OBJECT_METHODS = {
    ("toString", "()Ljava/lang/String;"),
    ("equals", "(Ljava/lang/Object;)Z"),
    ("hashCode", "()I"),
    ("getClass", "()Ljava/lang/Class;"),
    ("clone", "()Ljava/lang/Object;"),
    ("notify", "()V"),
    ("notifyAll", "()V"),
    ("wait", "()V"),
    ("wait", "(J)V"),
    ("wait", "(JI)V"),
    ("finalize", "()V"),
}


def u16(data: bytes, offset: int) -> int:
    return struct.unpack_from(">H", data, offset)[0]


def u32be(data: bytes, offset: int) -> int:
    return struct.unpack_from(">I", data, offset)[0]


def u32le(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


class ClassFile:
    """The parts of the class format the audit needs: names, parents, methods."""

    def __init__(self, data: bytes) -> None:
        if data[:4] != b"\xca\xfe\xba\xbe":
            raise ValueError("not a class file")
        count = u16(data, 8)
        pool: list[tuple[int, object]] = [(0, None)] * count
        cursor = 10
        index = 1
        while index < count:
            tag = data[cursor]
            cursor += 1
            if tag == 1:
                length = u16(data, cursor)
                cursor += 2
                pool[index] = (tag, data[cursor:cursor + length].decode("utf-8", "replace"))
                cursor += length
            elif tag in (7, 8, 16, 19, 20):
                pool[index] = (tag, u16(data, cursor))
                cursor += 2
            elif tag == 15:
                pool[index] = (tag, (data[cursor], u16(data, cursor + 1)))
                cursor += 3
            elif tag in (3, 4, 9, 10, 11, 12, 17, 18):
                pool[index] = (tag, None)
                cursor += 4
            elif tag in (5, 6):
                pool[index] = (tag, None)
                cursor += 8
                index += 1
            else:
                raise ValueError(f"constant pool tag {tag}")
            index += 1
        self.pool = pool
        self.access = u16(data, cursor)
        self.this = self.class_name(u16(data, cursor + 2))
        super_index = u16(data, cursor + 4)
        self.super = self.class_name(super_index) if super_index else None
        interfaces = u16(data, cursor + 6)
        cursor += 8
        self.interfaces = [self.class_name(u16(data, cursor + i * 2))
                           for i in range(interfaces)]
        cursor += interfaces * 2

        def skip(offset: int, want: bool) -> tuple[int, list[tuple[str, str]]]:
            total = u16(data, offset)
            offset += 2
            found: list[tuple[str, str]] = []
            for _ in range(total):
                name = self.utf(u16(data, offset + 2))
                descriptor = self.utf(u16(data, offset + 4))
                attributes = u16(data, offset + 6)
                offset += 8
                for _ in range(attributes):
                    offset += 6 + u32be(data, offset + 2)
                if want:
                    found.append((name, descriptor))
            return offset, found

        cursor, _fields = skip(cursor, False)
        _cursor, self.methods = skip(cursor, True)

    def utf(self, index: int) -> str:
        return str(self.pool[index][1])

    def class_name(self, index: int) -> str | None:
        if not index:
            return None
        tag, value = self.pool[index]
        return self.utf(int(value)).replace("/", ".") if tag == 7 else None


def runtime_surface(runtime: Path):
    classes: dict[str, ClassFile] = {}
    for path in runtime.rglob("*.class"):
        parsed = ClassFile(path.read_bytes())
        classes[parsed.this] = parsed
    methods = {name: set(item.methods) for name, item in classes.items()}
    return classes, methods


def resolves(classes, methods, owner: str, name: str, descriptor: str,
             seen: set[str] | None = None) -> bool:
    seen = seen if seen is not None else set()
    if owner in seen:
        return False
    seen.add(owner)
    if (name, descriptor) in methods.get(owner, set()):
        return True
    item = classes.get(owner)
    if item is None:
        return True
    # An interface's class-file super is java.lang.Object, which is not part of
    # interface method resolution and would mask every missing member.
    parents = (list(item.interfaces) if item.access & 0x0200
               else ([item.super] if item.super else []) + list(item.interfaces))
    for parent in parents:
        if not parent:
            continue
        if parent == "java.lang.Object":
            if (name, descriptor) in OBJECT_METHODS:
                return True
            continue
        if parent not in classes:
            # A platform or third-party parent: its jar is the contract.
            return True
        if resolves(classes, methods, parent, name, descriptor, seen):
            return True
    return False


def _uleb128(data: bytes, offset: int) -> tuple[int, int]:
    result = 0
    shift = 0
    while True:
        byte = data[offset]
        offset += 1
        result |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return result, offset
        shift += 7


def dex_method_refs(path: Path) -> list[tuple[str, str, str]]:
    data = path.read_bytes()
    if not data.startswith(b"dex\n"):
        return []
    string_ids_size, string_ids_off = u32le(data, 0x38), u32le(data, 0x3C)
    type_ids_size, type_ids_off = u32le(data, 0x40), u32le(data, 0x44)
    proto_ids_size, proto_ids_off = u32le(data, 0x48), u32le(data, 0x4C)
    method_ids_size, method_ids_off = u32le(data, 0x58), u32le(data, 0x5C)

    strings: list[str] = []
    for index in range(string_ids_size):
        offset = u32le(data, string_ids_off + index * 4)
        length, cursor = _uleb128(data, offset)
        strings.append(data[cursor:cursor + length].decode("utf-8", "replace"))

    types = [strings[u32le(data, type_ids_off + index * 4)]
             for index in range(type_ids_size)]

    protos: list[str] = []
    for index in range(proto_ids_size):
        entry = proto_ids_off + index * 12
        return_type = types[u32le(data, entry + 4)]
        parameters_off = u32le(data, entry + 8)
        params = ""
        if parameters_off:
            size = u32le(data, parameters_off)
            params = "".join(
                types[struct.unpack_from("<H", data,
                                         parameters_off + 4 + i * 2)[0]]
                for i in range(size))
        protos.append(f"({params}){return_type}")

    refs = []
    for index in range(method_ids_size):
        entry = method_ids_off + index * 8
        owner = types[struct.unpack_from("<H", data, entry)[0]]
        proto = protos[struct.unpack_from("<H", data, entry + 2)[0]]
        name = strings[u32le(data, entry + 4)]
        if owner.startswith("L") and owner.endswith(";"):
            owner = owner[1:-1].replace("/", ".")
        refs.append((owner, name, proto))
    return refs


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apks", required=True, type=Path)
    parser.add_argument("--runtime", required=True, type=Path)
    parser.add_argument("--json", type=Path, default=None)
    args = parser.parse_args()

    classes, methods = runtime_surface(args.runtime)
    print(f"runtime surface: {len(classes)} classes")

    report = []
    summary: dict[tuple[str, str, str], set[str]] = {}
    for apk in sorted(args.apks.glob("*.apk")):
        missing: set[tuple[str, str, str]] = set()
        checked = 0
        with zipfile.ZipFile(apk) as archive:
            for entry in archive.namelist():
                if not entry.endswith(".dex"):
                    continue
                target = args.apks / f"{apk.stem}-{entry}"
                target.write_bytes(archive.read(entry))
                try:
                    for owner, name, descriptor in dex_method_refs(target):
                        if not owner.startswith(SURFACE) or owner not in classes:
                            continue
                        checked += 1
                        if not resolves(classes, methods, owner, name, descriptor):
                            missing.add((owner, name, descriptor))
                finally:
                    target.unlink()
        for item in missing:
            summary.setdefault(item, set()).add(apk.stem)
        report.append({"apk": apk.stem, "checked": checked,
                       "missing": sorted(f"{o}.{n}{d}" for o, n, d in missing)})

    if args.json:
        args.json.write_text(json.dumps(report, ensure_ascii=False, indent=2))

    print("\n== missing methods ==")
    if not summary:
        print("none")
    for (owner, name, descriptor), apks in sorted(
            summary.items(), key=lambda item: (-len(item[1]), item[0])):
        print(f"{owner}.{name}{descriptor}  <- {len(apks)} apk(s): "
              f"{', '.join(sorted(apks)[:6])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
