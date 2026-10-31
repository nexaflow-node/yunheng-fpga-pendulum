# -*- coding: utf-8 -*-
"""统一口径的 trace 指标计算（报告用）。

口径说明（写进报告附录，避免与旧表混淆）：
  * trace 为 62.5 Hz 抽样（每 16 ms 一条记录）
  * 统计窗口默认 t = 10~30 s（起摆/重锚已结束的稳态段）
  * 臂摆包络 = 2 s 滑窗内 (max-min)/2，报告用其中位数与最大值
  * slow = 臂角 0.2~1 Hz 带通后的 RMS
  * duty 频带能量 = duty_permille 带通后的 RMS（单位‰）
"""
import numpy as np
import csv
import os

FS = 62.5


def load(path):
    with open(path, encoding='utf-8', errors='ignore') as f:
        rows = list(csv.DictReader(f))
    def col(name):
        return np.array([float(r[name]) if r.get(name) not in (None, '') else np.nan
                         for r in rows], dtype=float)
    d = {k: col(k) for k in ('arm_deg', 'theta_deg', 'duty_permille', 'arm_speed_deg_s',
                             'state', 'fault', 'run_epoch_ms', 'reference_deg')}
    d['t'] = np.arange(len(rows)) / FS
    return d


def _bp(x, lo, hi, fs=FS, order=2):
    """零相位带通（频域矩形窗，避免 scipy 依赖）。"""
    x = np.asarray(x, float)
    x = x - x.mean()
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1.0 / fs)
    m = (f >= lo) & (f <= hi)
    X[~m] = 0
    return np.fft.irfft(X, n)


def _lp(x, hi, fs=FS):
    return _bp(x, -1.0, hi, fs)


def summarize(path, t0=10.0, t1=30.0):
    d = load(path)
    t = d['t']
    m = (t >= t0) & (t <= t1) & np.isfinite(d['arm_deg'])
    if m.sum() < 100:
        m = np.isfinite(d['arm_deg'])
    arm = d['arm_deg'][m]
    th = d['theta_deg'][m]
    duty = d['duty_permille'][m]
    spd = d['arm_speed_deg_s'][m]
    ref = d['reference_deg'][m]

    # 包络：2 s 滑窗半幅
    w = int(2 * FS)
    half = []
    for i in range(0, max(1, len(arm) - w), max(1, w // 4)):
        seg = arm[i:i + w]
        half.append((seg.max() - seg.min()) / 2.0)
    half = np.array(half) if half else np.array([np.nan])

    slow = _bp(arm, 0.2, 1.0)
    out = dict(
        n=int(m.sum()),
        n_total=int(len(t)),
        dur=float(d['t'][-1]) if len(t) else 0.0,
        fault=int(d['fault'][-1]) if len(t) and np.isfinite(d['fault'][-1]) else -1,
        state_last=int(d['state'][-1]) if len(t) else -1,
        arm_p2p=float(arm.max() - arm.min()),
        arm_env_med=float(np.median(half)),
        arm_env_max=float(np.max(half)),
        arm_mean=float(arm.mean()),
        ref_mean=float(ref.mean()),
        theta_rms=float(np.sqrt(np.mean(th ** 2))),
        theta_mean=float(th.mean()),
        theta_max=float(np.max(np.abs(th))),
        slow_rms=float(np.sqrt(np.mean(slow ** 2))),
        duty_sigma=float(np.std(duty)),
        duty_mean=float(np.mean(duty)),
        arm_speed_rms=float(np.sqrt(np.mean(spd ** 2))),
        rail_pct=float(100.0 * np.mean(np.abs(duty) >= 500)),
    )
    for lo, hi in ((3, 8), (8, 12), (12, 18), (10, 25)):
        out['duty_%d_%d' % (lo, hi)] = float(np.sqrt(np.mean(_bp(duty, lo, hi) ** 2)))
    # 整圈旋转的臂行程
    out['arm_travel'] = float(abs(np.diff(arm)).sum())
    return out


if __name__ == '__main__':
    import json
    import sys
    for p in sys.argv[1:]:
        print(p)
        print(json.dumps(summarize(p), ensure_ascii=False, indent=1))
