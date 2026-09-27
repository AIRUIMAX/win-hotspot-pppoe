# -*- coding: utf-8 -*-
"""打包 GitHub Release 附件。

用法:
    python tools/pack_release.py 1.0.0

产物: dist/win-hotspot-pppoe-v<版本>.zip，内含 start-hotspot.ps1 与 开启热点.cmd。
两个文件必须待在同一个文件夹里才能运行，所以打包时不加子目录层级。
中文文件名显式置 UTF-8 标志位，避免在非中文系统下解压乱码。
"""
import os
import sys
import zipfile

PACKAGE = "win-hotspot-pppoe"
FILES = ["start-hotspot.ps1", "开启热点.cmd"]

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def build(version, root=ROOT):
    out_dir = os.path.join(root, "dist")
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "%s-v%s.zip" % (PACKAGE, version))

    missing = [n for n in FILES if not os.path.exists(os.path.join(root, n))]
    if missing:
        raise SystemExit("缺少文件: " + ", ".join(missing))

    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for name in FILES:
            src = os.path.join(root, name)
            info = zipfile.ZipInfo(name, date_time=(2026, 9, 27, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.flag_bits |= 0x800  # UTF-8 文件名
            info.external_attr = 0o644 << 16
            with open(src, "rb") as f:
                z.writestr(info, f.read())
            print("packed: %s (%d bytes)" % (name, os.path.getsize(src)))

    print("output: %s (%d bytes)" % (out, os.path.getsize(out)))
    with zipfile.ZipFile(out) as z:
        assert z.testzip() is None, "压缩包校验失败"
        assert z.namelist() == FILES, "压缩包内容与预期不符: %s" % z.namelist()
    print("verify: OK")
    return out


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    build(sys.argv[1])
