"""Выводит причину ошибки сборки или тестов в аннотацию GitHub Actions.

Аннотации видны в API и в интерфейсе без скачивания полного журнала.
"""
import re
import sys

log_path, title = sys.argv[1], sys.argv[2]
log = open(log_path, encoding="utf-8", errors="replace").read()
lines = log.splitlines()
picked = []
# Flutter-тесты: сначала полный текст исключения.
for i, line in enumerate(lines):
    if "EXCEPTION CAUGHT" in line or "overflowed by" in line:
        picked.extend(lines[i: i + 30])
for i, line in enumerate(lines):
    if re.search(r"(Error:|error:|^e: |FAILED|Expected:|Actual:|Exception|What went wrong|\[E\]|Some tests failed)", line):
        picked.extend(lines[max(0, i - 2): i + 6])
text = "\n".join(dict.fromkeys(picked)) if picked else "\n".join(lines[-60:])
chunks = [text[i:i + 3500] for i in range(0, min(len(text), 3500 * 4), 3500)] or ["(пусто)"]
for n, chunk in enumerate(chunks, 1):
    print(f"::error title={title} {n}/{len(chunks)}::" + chunk.replace("%", "%25").replace("\r", "").replace("\n", "%0A"))
