#!/usr/bin/env python3
"""prompt-report.py OLD.json NEW.json OUT.html [--judge MODEL] [--url URL]

Puts two runs of PromptEvaluationTests side by side (Roadmap v19 Sprint 1):
per module the automatic checks (language, format, cut off, preamble) and,
with --judge, a model's verdict on whether each answer fits the sense the
item is about (its "watch" note). Both runs are judged the same way, so the
comparison is fair; the verdicts are a guide for the person reading the
report, not a score to trust blindly.

The judge talks to an OpenAI-compatible server (default: Ollama on this Mac).
Standard library only.
"""
import argparse
import html
import json
import sys
import time
import urllib.request

JUDGED_MODULES = {"definitionEN", "meaningTR", "collocations", "examplesEN", "etymologyEN",
                  "mnemonicEN", "synonymsEN", "wordFamilyEN", "usageNotesEN"}


def judge(record, model, url):
    if record["module"] not in JUDGED_MODULES or not record["output"]:
        return None
    if record["mode"] == "Sentence":
        task = (f'A language learner selected this sentence: "{record["term"]}".\n'
                f'The key point a good answer must get right: {record["watch"]}.')
        question = "Does this answer explain the sentence correctly and get the key point right?"
    else:
        where = f' in the sentence "{record["context"]}"' if record.get("context") else " (no sentence given)"
        task = (f'A language learner selected the word "{record["term"]}"{where}.\n'
                f'The sense that matters: {record["watch"]}.')
        question = ("Does this answer fit that sense? For examples, collocations, word family, origin and "
                    "memory hooks: are they about that sense? For definitions and meanings: is that sense "
                    "explained first and correctly?")
    prompt = (f'{task}\n\nAnswer of the "{record["module"]}" module:\n<<<\n{record["output"]}\n>>>\n\n'
              f'{question}\nReply with PASS or FAIL, then a reason of at most 12 words.')
    body = json.dumps({"model": model, "messages": [{"role": "user", "content": prompt}],
                       "temperature": 0, "max_tokens": 60}).encode()
    for attempt in range(3):
        try:
            request = urllib.request.Request(url.rstrip("/") + "/v1/chat/completions", data=body,
                                             headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(request, timeout=90) as response:
                text = json.load(response)["choices"][0]["message"]["content"].strip()
            verdict = "PASS" if text.upper().startswith("PASS") else "FAIL" if text.upper().startswith("FAIL") else "?"
            return {"verdict": verdict, "reason": text.split(None, 1)[1] if " " in text else ""}
        except Exception as error:  # a transient server error: try again
            time.sleep(2 * (attempt + 1))
            last = str(error)
    return {"verdict": "?", "reason": f"judge failed: {last}"}


def key(record):
    return (record["item"], record["module"])


def badge(record):
    marks = []
    if record.get("languageOK") is False:
        marks.append(("bad", f'language {record.get("detectedLanguage")}'))
    if record.get("formatOK") is False:
        marks.append(("bad", "format"))
    if record.get("truncated"):
        marks.append(("bad", "cut off"))
    if record.get("preamble"):
        marks.append(("bad", "preamble"))
    if record.get("error"):
        marks.append(("bad", "error"))
    verdict = record.get("judge")
    if verdict:
        marks.append(("ok" if verdict["verdict"] == "PASS" else "bad", verdict["verdict"]))
    return "".join(f'<span class="m {kind}" title="{html.escape(verdict["reason"]) if verdict and text in ("PASS", "FAIL", "?") else ""}">{html.escape(text)}</span>'
                   for kind, text in marks)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("old")
    parser.add_argument("new")
    parser.add_argument("out")
    parser.add_argument("--judge", help="model name for the sense verdicts")
    parser.add_argument("--url", default="http://127.0.0.1:11434")
    args = parser.parse_args()

    old, new = json.load(open(args.old)), json.load(open(args.new))
    runs = [("old", old), ("new", new)]
    if args.judge:
        total = sum(len(run["records"]) for _, run in runs)
        done = 0
        for _, run in runs:
            for record in run["records"]:
                record["judge"] = judge(record, args.judge, args.url)
                done += 1
                if done % 25 == 0:
                    print(f"judged {done}/{total}", file=sys.stderr)

    old_by, new_by = {key(r): r for r in old["records"]}, {key(r): r for r in new["records"]}
    modules = list(dict.fromkeys(r["module"] for r in new["records"]))
    items = list(dict.fromkeys(r["item"] for r in new["records"]))

    def rate(records, module):
        judged = [r for r in records if r["module"] == module and r.get("judge") and r["judge"]["verdict"] != "?"]
        if not judged:
            return "—"
        passed = sum(r["judge"]["verdict"] == "PASS" for r in judged)
        return f"{passed}/{len(judged)}"

    def checks(records, module):
        rs = [r for r in records if r["module"] == module]
        bad = sum(1 for r in rs if r.get("languageOK") is False or r.get("formatOK") is False
                  or r.get("truncated") or r.get("preamble") or r.get("error"))
        return f"{bad}"

    def chars(records, module):
        rs = [r for r in records if r["module"] == module]
        return f"{sum(len(r['output']) for r in rs) / max(1, len(rs)):.0f}"

    summary = "".join(
        f"<tr><td>{m}</td><td>{rate(old['records'], m)}</td><td><b>{rate(new['records'], m)}</b></td>"
        f"<td>{checks(old['records'], m)}</td><td>{checks(new['records'], m)}</td>"
        f"<td>{chars(old['records'], m)}</td><td>{chars(new['records'], m)}</td></tr>" for m in modules)

    blocks = []
    for item in items:
        first = next(r for r in new["records"] if r["item"] == item)
        head = (f'<b>{html.escape(first["term"])}</b>'
                + (f' — <i>{html.escape(first["context"])}</i>' if first.get("context") else "")
                + f' <span class="watch">{html.escape(first["watch"])} · {first["target"]}</span>')
        rows = []
        for module in modules:
            o, n = old_by.get((item, module)), new_by.get((item, module))
            if not n:
                continue
            def cell(r):
                if not r:
                    return '<td class="empty">—</td>'
                reason = f'<div class="reason">{html.escape(r["judge"]["reason"])}</div>' if r.get("judge") else ""
                return f'<td><div class="marks">{badge(r)}</div><pre>{html.escape(r["output"])}</pre>{reason}</td>'
            rows.append(f'<tr><th>{module}</th>{cell(o)}{cell(n)}</tr>')
        blocks.append(f'<details><summary>{head}</summary><table class="side">'
                      f'<tr><th></th><th>old (rev {old["revision"]})</th><th>new (rev {new["revision"]})</th></tr>'
                      f'{"".join(rows)}</table></details>')

    page = f"""<title>RELL Prompt Report</title>
<meta name="claude:viewport-fit-sides" content="cover">
<style>
:root {{ --bg:#f5f5f2; --ink:#1c1d1f; --ink2:#5a5c62; --line:#dcdcd6; --panel:#fff; --ok:#23803e; --bad:#b23a32; --accent:#2f6bd8;
  --font:-apple-system,BlinkMacSystemFont,"SF Pro Text",Arial,sans-serif; --mono:ui-monospace,"SF Mono",Menlo,monospace; }}
@media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) {{ --bg:#1a1b1c; --ink:#f0f0ee; --ink2:#b4b5b9; --line:#36373a; --panel:#242527; --ok:#55c278; --bad:#ec7268; --accent:#6d9cf2; color-scheme:dark; }} }}
:root[data-theme="dark"] {{ --bg:#1a1b1c; --ink:#f0f0ee; --ink2:#b4b5b9; --line:#36373a; --panel:#242527; --ok:#55c278; --bad:#ec7268; --accent:#6d9cf2; color-scheme:dark; }}
* {{ box-sizing:border-box; }}
body {{ background:var(--bg); color:var(--ink); font-family:var(--font); font-size:14px; line-height:1.5; padding-block:28px 60px;
  padding-left:max(16px, env(safe-area-inset-left,0px)); padding-right:max(16px, env(safe-area-inset-right,0px)); }}
.wrap {{ max-width:1200px; margin:0 auto; display:grid; gap:22px; }}
h1 {{ font-size:24px; margin:0; }} p {{ margin:0; color:var(--ink2); max-width:80ch; }}
.scroll {{ overflow-x:auto; }}
table {{ border-collapse:collapse; width:100%; background:var(--panel); border:1px solid var(--line); }}
th, td {{ text-align:left; vertical-align:top; padding:7px 10px; border-top:1px solid var(--line); }}
.sum td, .sum th {{ font-variant-numeric:tabular-nums; }}
.side {{ min-width:760px; table-layout:fixed; }} .side th:first-child {{ width:120px; }}
details {{ background:var(--panel); border:1px solid var(--line); border-radius:10px; padding:8px 12px; }}
summary {{ cursor:pointer; }}
.watch {{ color:var(--ink2); font-size:12.5px; }}
pre {{ white-space:pre-wrap; margin:4px 0 0; font-family:var(--font); font-size:13px; }}
.marks {{ display:flex; gap:4px; flex-wrap:wrap; }}
.m {{ font-size:11px; font-weight:700; border-radius:999px; padding:0 7px; border:1px solid var(--line); }}
.m.ok {{ color:var(--ok); }} .m.bad {{ color:var(--bad); }}
.reason {{ color:var(--ink2); font-size:12px; margin-top:4px; }}
.empty {{ color:var(--ink2); }}
</style>
<div class="wrap">
<h1>Prompt report: revision {old["revision"]} → {new["revision"]}</h1>
<p>{len(items)} items · model {html.escape(new["model"])}. Verdicts: the same model judges whether each answer fits the sense the item is about (hover a verdict for its reason). Checks count answers in the wrong language, in a format the app can't read, cut off, with a preamble or failed.</p>
<div class="scroll"><table class="sum"><tr><th>Module</th><th>Sense, old</th><th>Sense, new</th><th>Check issues, old</th><th>new</th><th>Avg chars, old</th><th>new</th></tr>{summary}</table></div>
{"".join(blocks)}
</div>
"""
    open(args.out, "w").write(page)
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
