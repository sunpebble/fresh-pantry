#!/usr/bin/env python3
"""i18n 闸门：
1) iOS 源码的字符串字面量里不允许出现中日文字符（注释除外；行尾 `// i18n:ignore` 豁免）；
2) 所有 .xcstrings 的每个 key 必须四语言（zh-Hans/en/ja/fr）齐全。
用法: check_i18n.py [swift源码路径...]   无参数 = 全量检查(源码+xcstrings)。
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IOS = ROOT / "apps" / "ios"
DEFAULT_DIRS = [IOS / "FreshPantry", IOS / "FreshPantryWidgets", IOS / "ShareExtension"]
LANGS = {"zh-Hans", "en", "ja", "fr"}
CJK = re.compile(r"[぀-ヿ一-鿿]")
STRING_LIT = re.compile(r'"(?:[^"\\\n]|\\.)*"')


def strip_comments(code: str) -> str:
    # 块注释换成等量换行，保住行号
    code = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group().count("\n"), code, flags=re.S)
    return re.sub(r"//[^\n]*", "", code)


def swift_offenders(dirs: list[Path]) -> list[str]:
    out = []
    for base in dirs:
        for f in sorted(base.rglob("*.swift")):
            if "build" in f.parts:
                continue
            raw_lines = f.read_text().splitlines()
            for i, line in enumerate(strip_comments(f.read_text()).splitlines(), 1):
                if i <= len(raw_lines) and "i18n:ignore" in raw_lines[i - 1]:
                    continue
                for m in STRING_LIT.finditer(line):
                    if CJK.search(m.group()):
                        out.append(f"{f.relative_to(ROOT)}:{i}: {m.group()[:80]}")
    return out


def xcstrings_offenders() -> list[str]:
    out = []
    for f in sorted(IOS.rglob("*.xcstrings")):
        if "build" in f.parts:
            continue
        catalog = json.loads(f.read_text())
        for key, entry in catalog.get("strings", {}).items():
            missing = LANGS - set(entry.get("localizations", {}))
            if missing:
                out.append(f"{f.relative_to(ROOT)}: '{key}' 缺 {sorted(missing)}")
    return out


def main() -> int:
    args = [Path(a).resolve() for a in sys.argv[1:]]
    offenders = swift_offenders(args or DEFAULT_DIRS)
    if not args:
        offenders += xcstrings_offenders()
    for line in offenders:
        print(line)
    print(f"\n{'FAIL' if offenders else 'OK'}: {len(offenders)} 处未本地化/缺翻译")
    return 1 if offenders else 0


if __name__ == "__main__":
    sys.exit(main())
