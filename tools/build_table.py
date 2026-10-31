# -*- coding: utf-8 -*-
"""扫描全部 trace，生成统一口径的跑次表 report_figs/all_runs.csv"""
import sys, glob, os, csv, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from metrics import summarize

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def main():
    os.chdir(ROOT)
    paths = (sorted(glob.glob('J280_CAPTURES_20261024/data/*/**/trace.csv', recursive=True))
             + sorted(glob.glob('J280_FINAL_20261031/captures/*.csv'))
             + sorted(glob.glob('N*_20261031/host/captures/*/trace.csv')))
    seen, rows = set(), []
    for p in paths:
        rp = os.path.realpath(p)
        if rp in seen:
            continue
        seen.add(rp)
        try:
            s = summarize(p)
        except Exception:
            continue
        parts = p.replace(chr(92), '/').split('/')
        if parts[0] == 'J280_CAPTURES_20261024':
            ver = parts[2]
        elif parts[0] == 'J280_FINAL_20261031':
            ver = 'J280_FINAL'
        else:
            ver = parts[0]
        rows.append((ver, os.path.basename(os.path.dirname(p)), s))
    ok = [r for r in rows if r[2]['n_total'] >= 1800]
    print('traces %d, full-length %d' % (len(rows), len(ok)))
    keys = list(ok[0][2].keys())
    with open('report_figs/all_runs.csv', 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(['version', 'capture'] + keys)
        for v, c, s in ok:
            w.writerow([v, c] + [s[k] for k in keys])
    print(collections.Counter(v for v, _, _ in ok).most_common(15))
    print('fault==7:', sum(1 for _, _, s in ok if s['fault'] == 7))

if __name__ == '__main__':
    main()
