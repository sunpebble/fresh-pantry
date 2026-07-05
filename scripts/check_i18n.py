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
    # 行注释需感知字符串字面量，避免删除字符串内的 //（如 URL）
    LITERAL_OR_SLASH = re.compile(r'"(?:[^"\\\n]|\\.)*"|//')

    def strip_line_comment(line: str) -> str:
        for m in LITERAL_OR_SLASH.finditer(line):
            if m.group() == "//":
                return line[: m.start()]
        return line

    return "\n".join(strip_line_comment(line) for line in code.split("\n"))


def swift_offenders(dirs: list[Path]) -> list[str]:
    out = []
    for base in dirs:
        # ponytail: 支持单文件参数，不止目录
        files = [base] if base.is_file() else sorted(base.rglob("*.swift"))
        for f in files:
            if "build" in f.parts:
                continue
            raw_text = f.read_text()
            raw_lines = raw_text.splitlines()
            for i, line in enumerate(strip_comments(raw_text).splitlines(), 1):
                if i <= len(raw_lines) and "i18n:ignore" in raw_lines[i - 1]:
                    continue
                for m in STRING_LIT.finditer(line):
                    if CJK.search(m.group()):
                        try:
                            rel = f.relative_to(ROOT)
                        except ValueError:
                            rel = f
                        out.append(f"{rel}:{i}: {m.group()[:80]}")
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
                # ponytail: 只查语言键存在，不查 state=translated；xcstrings 由我们手写，出现 stub 再收紧
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
