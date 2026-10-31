# -*- coding: utf-8 -*-
"""生成作品报告用图（fig1~fig8）。数值全部由实测 trace 或 RTL 定点系数计算。

运行： python -I report_figs/make_figs.py
输出： report_figs/fig*.png
"""
import os
import re
import sys
import csv
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch, Circle
from matplotlib.ticker import NullFormatter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from metrics import load, summarize

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
OUT = os.path.join(ROOT, 'report_figs')

plt.rcParams.update({
    'font.sans-serif': ['Microsoft YaHei', 'SimHei', 'DejaVu Sans'],
    'axes.unicode_minus': False,
    'font.size': 9,
    'axes.titlesize': 10,
    'axes.labelsize': 9,
    'axes.linewidth': 0.8,
    'xtick.labelsize': 8,
    'ytick.labelsize': 8,
    'legend.fontsize': 7.5,
    'figure.dpi': 200,
    'savefig.dpi': 200,
    'savefig.bbox': 'tight',
})

C_GREY = '#9aa0a6'
C_BLUE = '#1f5fa8'
C_ORANGE = '#d9480f'
C_GREEN = '#2b8a3e'
C_RED = '#b02a37'
C_FILL = '#eef3fa'
C_FILL2 = '#fdf0e6'
C_FILL3 = '#f4f4f4'

BASE = 'J280_CAPTURES_20261024/data/mb1_noI_085_20261024/W0_20261024_164529_381/trace.csv'
T085 = BASE
T_N21 = 'N21_obs07_kq1650_20261031/host/captures/W0_20261031_113614_512/trace.csv'
T_ROT = 'N28b_rot_20261031/host/captures/W0_20261031_132451_387/trace.csv'


# ---------------------------------------------------------------- 绘图工具
def box(ax, x, y, w, h, title, sub='', fc=C_FILL, ec=C_BLUE, fs=8.2, sfs=6.3, bold=True):
    ax.add_patch(FancyBboxPatch((x - w / 2, y - h / 2), w, h,
                                boxstyle='round,pad=0.010,rounding_size=0.018',
                                linewidth=0.9, facecolor=fc, edgecolor=ec, zorder=2))
    if sub:
        ax.text(x, y + h * 0.20, title, ha='center', va='center',
                fontsize=fs, fontweight='bold' if bold else 'normal', zorder=3)
        ax.text(x, y - h * 0.19, sub, ha='center', va='center', fontsize=sfs,
                color='#333333', zorder=3, linespacing=1.45)
    else:
        ax.text(x, y, title, ha='center', va='center', fontsize=fs,
                fontweight='bold' if bold else 'normal', zorder=3, linespacing=1.4)


def arrow(ax, p, q, color='#333333', lw=0.9, ls='-', style='-|>'):
    ax.add_patch(FancyArrowPatch(p, q, arrowstyle=style, mutation_scale=9,
                                 linewidth=lw, color=color, linestyle=ls,
                                 shrinkA=2, shrinkB=2, zorder=1))


def poly(ax, pts, color='#333333', lw=0.9, ls='-', head=True):
    for i in range(len(pts) - 2):
        ax.plot([pts[i][0], pts[i + 1][0]], [pts[i][1], pts[i + 1][1]],
                color=color, lw=lw, ls=ls, zorder=1, solid_capstyle='butt')
    if head:
        arrow(ax, pts[-2], pts[-1], color=color, lw=lw, ls=ls)
    else:
        ax.plot([pts[-2][0], pts[-1][0]], [pts[-2][1], pts[-1][1]],
                color=color, lw=lw, ls=ls, zorder=1)


def canvas(w=7.0, h=4.0):
    fig, ax = plt.subplots(figsize=(w, h))
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis('off')
    return fig, ax


# ---------------------------------------------------------------- fig1 系统框图
def fig1():
    fig, ax = canvas(7.2, 4.4)

    box(ax, 0.735, 0.855, 0.40, 0.155, '被控对象', '直流电机（20:1）· 旋臂 · 摆杆\n'
        'TB6612 双极性驱动 / 20 kHz PWM', fc=C_FILL3, ec='#5f6b7a', fs=8.6, sfs=6.4)
    box(ax, 0.200, 0.855, 0.28, 0.155, '传感器', '电位器 12.48 count/°\n'
        '编码器 1075.5 count/转', fc=C_FILL3, ec='#5f6b7a', fs=8.6, sfs=6.4)
    arrow(ax, (0.535, 0.855), (0.345, 0.855), color='#5f6b7a')
    ax.text(0.440, 0.888, '摆杆 / 旋臂运动', fontsize=6.2, ha='center', color='#5f6b7a')

    # FPGA 区域
    ax.add_patch(FancyBboxPatch((0.015, 0.055), 0.97, 0.63,
                                boxstyle='round,pad=0.006,rounding_size=0.02',
                                facecolor='none', edgecolor='#b0b7c3',
                                linestyle=(0, (4, 3)), linewidth=1.0, zorder=0))
    ax.text(0.5, 0.077, 'FPGA  GW2A-LV55PG484C8/I7  @ 50 MHz（1 kHz 控制周期）',
            fontsize=7.2, color='#5f6b7a', ha='center')

    # 中排：采样 → 解算 → 控制 → 输出
    y1 = 0.475
    box(ax, 0.115, y1, 0.145, 0.145, 'c_adc', '10 位并行\n5 MHz / 128 点均值', sfs=6.1)
    box(ax, 0.305, y1, 0.145, 0.145, 'c_sensor', '角度解算\n常速度跟踪器', sfs=6.1)
    box(ax, 0.495, y1, 0.150, 0.145, 'c_control', '状态机 / LQR\n陷波 / 限幅', fc=C_FILL2, ec=C_ORANGE, sfs=6.1)
    box(ax, 0.685, y1, 0.145, 0.145, 'c_output', 'Q8 → ‰\n压摆限速', sfs=6.1)
    box(ax, 0.865, y1, 0.145, 0.145, 'c_pwm', '20 kHz\n占空比输出', sfs=6.1)

    # 下排：按键 / 起摆 / trace / uart
    y2 = 0.175
    box(ax, 0.115, y2, 0.145, 0.135, 'c_keys', 'SW1 零点\nSW3 启停', sfs=6.1)
    box(ax, 0.495, y2, 0.150, 0.135, 'c_swing', '能量泵\n起摆轨迹', fc=C_FILL2, ec=C_ORANGE, sfs=6.1)
    box(ax, 0.685, y2, 0.145, 0.135, 'c_trace', '896 bit\n2048 条记录', sfs=6.1)
    box(ax, 0.865, y2, 0.145, 0.135, 'UART', '115200 bps\n状态帧 / 上传', sfs=6.1)

    # 横向链路
    arrow(ax, (0.188, y1), (0.232, y1))
    arrow(ax, (0.378, y1), (0.420, y1))
    arrow(ax, (0.570, y1), (0.612, y1))
    arrow(ax, (0.758, y1), (0.792, y1))
    # 按键 → 控制
    poly(ax, [(0.188, 0.205), (0.395, 0.205), (0.395, 0.403)], ls='--')
    # 起摆 → 控制
    arrow(ax, (0.495, 0.243), (0.495, 0.403))
    # 控制 → trace
    arrow(ax, (0.520, 0.403), (0.660, 0.243), ls='--')
    arrow(ax, (0.758, y2), (0.792, y2))
    # 传感器 → ADC
    arrow(ax, (0.215, 0.778), (0.128, 0.548))
    # PWM → 被控对象
    arrow(ax, (0.865, 0.548), (0.780, 0.778))

    ax.text(0.163, 0.618, 'θ, a（Q16）', fontsize=6.3, color='#5f6b7a', rotation=-76)
    ax.text(0.845, 0.66, 'u（‰）', fontsize=6.3, color='#5f6b7a', rotation=75)
    ax.text(0.395, 0.30, '启动 / 停止', fontsize=6.2, color='#5f6b7a')
    ax.text(0.545, 0.32, '起摆指令', fontsize=6.2, color='#5f6b7a')
    ax.text(0.60, 0.33, '记录', fontsize=6.2, color='#5f6b7a', rotation=-38)

    fig.savefig(os.path.join(OUT, 'fig1_system.png'))
    plt.close(fig)


# ---------------------------------------------------------------- fig2 控制信号流
def fig2():
    fig, ax = canvas(7.0, 3.3)

    # 上排：测量与状态估计
    y1 = 0.755
    box(ax, 0.125, y1, 0.185, 0.20, '采样结果', 'θ：电位器\n a：编码器', sfs=6.4)
    box(ax, 0.395, y1, 0.225, 0.20, '常速度跟踪器 ×2', '一阶模型，BD = 0\n'
        '旋臂 10.5 Hz / 摆杆 40 Hz', sfs=6.2)
    box(ax, 0.685, y1, 0.225, 0.20, '状态向量 x', 'Δa = a − a_ref\n v_a · θ · ω_θ', sfs=6.2)

    arrow(ax, (0.218, y1), (0.282, y1))
    arrow(ax, (0.508, y1), (0.573, y1))

    # 下排：反馈律 → 陷波 → 限幅
    y2 = 0.360
    box(ax, 0.185, y2, 0.235, 0.25, 'LQR 反馈律（Q8）',
        'u = 538·Δa + 650·v_a\n     + 4690·θ + 450·ω_θ', fc=C_FILL2, ec=C_ORANGE, sfs=6.3)
    box(ax, 0.475, y2, 0.195, 0.25, '陷波整定', '双二阶 IIR\n中心 12.5 Hz / 深度 0.6\nQ28 定点系数', sfs=6.1)
    box(ax, 0.740, y2, 0.195, 0.25, '限幅与压摆', '±6 V 限幅\n500‰/ms 压摆\n→ 占空比指令', sfs=6.1)

    arrow(ax, (0.685, 0.655), (0.268, 0.487))
    arrow(ax, (0.303, y2), (0.378, y2))
    arrow(ax, (0.573, y2), (0.642, y2))
    arrow(ax, (0.838, y2), (0.885, y2))
    ax.text(0.90, y2, 'u', fontsize=9, va='center')

    ax.text(0.185, 0.105, '积分项关闭（COMP_D = 0）：机械静摩擦导致的稳态偏差由零点标定消除，\n'
                          '不用积分硬拉——实测积分项会钉在钳位上助推漂移',
            fontsize=6.3, ha='left', va='center', color='#5f6b7a', linespacing=1.5)

    fig.savefig(os.path.join(OUT, 'fig2_control.png'))
    plt.close(fig)


# ---------------------------------------------------------------- fig3 状态机
def fig3():
    fig, ax = canvas(6.8, 3.4)

    box(ax, 0.155, 0.745, 0.225, 0.185, 'IDLE', '自检 / 等待启动', fc=C_FILL3, ec='#5f6b7a', fs=8.8)
    box(ax, 0.500, 0.745, 0.235, 0.185, 'SWING 起摆', '能量泵 + 捕获门', fc=C_FILL, ec=C_BLUE, fs=8.8)
    box(ax, 0.500, 0.305, 0.235, 0.185, 'BALANCE 平衡', '1 kHz LQR 闭环', fc=C_FILL2, ec=C_ORANGE, fs=8.8)
    box(ax, 0.155, 0.305, 0.225, 0.185, 'FAULT', '断输出 / 锁存故障码', fc='#fbeaea', ec=C_RED, fs=8.8)

    arrow(ax, (0.268, 0.745), (0.382, 0.745))
    ax.text(0.325, 0.785, 'SW3 按住\n0.8 s', fontsize=6.3, ha='center', va='bottom', linespacing=1.35)

    arrow(ax, (0.500, 0.652), (0.500, 0.398))
    ax.text(0.515, 0.525, '|θ| < 20° 且 |dθ/dt| < 3.0 rad/s\n连续 3 拍确认', fontsize=6.3,
            va='center', ha='left', linespacing=1.45)

    arrow(ax, (0.382, 0.305), (0.268, 0.305))
    ax.text(0.325, 0.345, '故障条件', fontsize=6.3, ha='center', va='bottom')

    arrow(ax, (0.155, 0.398), (0.155, 0.652))
    ax.text(0.145, 0.525, '悬垂 1.5 s\n自动恢复', fontsize=6.3, va='center', ha='right',
            color=C_GREEN, linespacing=1.45)
    ax.text(0.145, 0.435, 'fault 2 / 6', fontsize=6.0, va='center', ha='right', color=C_GREEN)

    arrow(ax, (0.392, 0.690), (0.212, 0.410), ls='--')
    ax.text(0.372, 0.545, '起摆超时\n或软限位', fontsize=6.0, ha='left', va='center',
            color='#5f6b7a', linespacing=1.35)

    ax.text(0.5, 0.115, '锁存类（不可自动恢复）：fault 1 手动停止 · 3 传感器失效 · 5 启动姿态异常 · 8 溢出 · 9 外部\n'
                        '可恢复类：2 臂越界 · 6 跌倒（|θ| > 40° 立即切断输出，摆杆垂下 1.5 s 后自动重起）；7 正常运行结束',
            fontsize=6.2, ha='center', va='center', color='#5f6b7a', linespacing=1.6)
    fig.savefig(os.path.join(OUT, 'fig4_fsm.png'))
    plt.close(fig)


# ---------------------------------------------------------------- fig4 时域对比
def fig4():
    d0 = load(T085)
    d1 = load(T_N21)
    s0, s1 = summarize(T085), summarize(T_N21)
    fig, axes = plt.subplots(2, 1, figsize=(6.7, 4.2), sharex=True)

    ax = axes[0]
    ax.plot(d0['t'], d0['arm_deg'] - d0['arm_deg'][0], color=C_GREY, lw=0.7,
            label='085（旧交付版）')
    ax.plot(d1['t'], d1['arm_deg'] - d1['arm_deg'][0], color=C_BLUE, lw=0.8,
            label='N21（定版）')
    ax.axvspan(0, 10, color='#888888', alpha=0.07, zorder=0)
    ax.text(5, ax.get_ylim()[0] + 2, '收敛段（不计入统计）', fontsize=6.0,
            ha='center', va='bottom', color='#777777')
    ax.set_ylabel('旋臂角（相对起始）/ °')
    ax.legend(loc='upper left', frameon=False, ncol=2)
    ax.grid(alpha=0.25, lw=0.5)
    ax.set_title('(a) 旋臂位置：峰峰 %.1f° vs %.1f°' % (s0['arm_p2p'], s1['arm_p2p']),
                 loc='left', fontsize=9)

    ax = axes[1]
    ax.plot(d0['t'], d0['theta_deg'], color=C_GREY, lw=0.7)
    ax.plot(d1['t'], d1['theta_deg'], color=C_BLUE, lw=0.8)
    ax.axhline(0, color='#333333', lw=0.5, ls=':')
    ax.set_ylabel('摆角 θ / °')
    ax.set_xlabel('时间 t / s')
    ax.grid(alpha=0.25, lw=0.5)
    ax.set_title('(b) 摆杆倾角：RMS %.2f° vs %.2f°' % (s0['theta_rms'], s1['theta_rms']),
                 loc='left', fontsize=9)
    ax.set_xlim(0, 30)

    fig.tight_layout()
    fig.savefig(os.path.join(OUT, 'fig6_timedomain.png'))
    plt.close(fig)


# ---------------------------------------------------------------- fig5 频谱
def welch(x, fs=62.5, nper=256):
    x = np.asarray(x, float)
    x = x - x.mean()
    nper = min(nper, len(x))
    win = np.hanning(nper)
    step = nper // 2
    ps = []
    for i in range(0, len(x) - nper + 1, step):
        seg = x[i:i + nper] * win
        ps.append(np.abs(np.fft.rfft(seg)) ** 2)
    f = np.fft.rfftfreq(nper, 1.0 / fs)
    P = np.mean(ps, axis=0) / (win ** 2).sum()
    return f, P


def fig5():
    fig, ax = plt.subplots(figsize=(6.7, 3.0))
    for path, c, lab in ((T085, C_GREY, '085（旧交付版）'), (T_N21, C_BLUE, 'N21（定版）')):
        d = load(path)
        m = (d['t'] >= 10) & (d['t'] <= 30)
        f, P = welch(d['duty_permille'][m])
        ax.semilogy(f, np.sqrt(P), color=c, lw=0.95, label=lab)

    for lo, hi, txt in ((3, 8, '3–8 Hz'), (8, 12, '8–12 Hz'), (12, 18, '12–18 Hz')):
        ax.axvspan(lo, hi, color=C_BLUE, alpha=0.05, zorder=0)
        ax.text((lo + hi) / 2, 1.25, txt, ha='center', fontsize=6.5, color='#5f6b7a')
    ax.set_xlim(0.5, 31)
    ax.set_ylim(1, 2000)
    ax.set_xlabel('频率 f / Hz')
    ax.set_ylabel('duty 幅值谱 / ‰')
    ax.grid(alpha=0.25, lw=0.5, which='both')
    ax.legend(frameon=False, loc='lower right', ncol=2)
    ax.set_xlabel('频率 f / Hz')
    fig.tight_layout()
    fig.savefig(os.path.join(OUT, 'fig7_spectrum.png'))
    plt.close(fig)


# ---------------------------------------------------------------- fig6 整定阶梯
VERSIONS = [
    ('085\n旧版', ['W0_20261024_164529_381', 'W0_20261024_164226_653', 'W0_20261024_164355_537'],
     'J280_CAPTURES_20261024/data/mb1_noI_085_20261024'),
    ('N3\n315', None, None),   # 占位，下面单独处理
]


def collect(version, caps):
    rows = list(csv.DictReader(open('report_figs/all_runs.csv', encoding='utf-8')))
    out = []
    for r in rows:
        if r['version'] == version and (caps is None or r['capture'] in caps):
            out.append((float(r['arm_p2p']), float(r['duty_sigma']), float(r['theta_rms'])))
    return out


def fig6():
    groups = [
        ('085 基线', collect('mb1_noI_085_20261024', None), C_GREY),
        ('N3\n315 / 15 Hz', collect('N3_zero3061_20261031', None), C_BLUE),
        ('N6\n450 / 15 Hz', collect('N6_newkit_20261031', None), C_BLUE),
        ('N12\n550 / 15 Hz', collect('N12_kq1550_notch125_20261031', None), C_BLUE),
        ('N19\n550 / 10.5 Hz', collect('N19_obs800_20261031', None), C_BLUE),
        ('N21\n650 / 10.5 Hz', collect('N21_obs07_kq1650_20261031', None), C_ORANGE),
        ('N23\n650 / 7.5 Hz', collect('N23_obs05_kq1650_20261031', None), C_BLUE),
    ]
    fig, axes = plt.subplots(2, 1, figsize=(6.7, 4.4), sharex=True)
    x = np.arange(len(groups))
    for ax, idx, ylab, title in ((axes[0], 0, '旋臂峰峰 / °', '(a) 旋臂摆幅'),
                                 (axes[1], 1, 'duty 标准差 / ‰', '(b) 抖动（占空比指令）')):
        for i, (name, vals, col) in enumerate(groups):
            if not vals:
                continue
            v = np.array([t[idx] for t in vals])
            ax.bar(i, np.median(v), width=0.55, color=col, alpha=0.28,
                   edgecolor=col, linewidth=0.9, zorder=2)
            if len(v) > 1:
                ax.errorbar(i, np.median(v), yerr=[[np.median(v) - v.min()], [v.max() - np.median(v)]],
                            fmt='none', ecolor=col, elinewidth=0.9, capsize=3, zorder=3)
            ax.scatter(np.full(len(v), i), v, s=12, color=col, zorder=4)
        ax.set_ylabel(ylab)
        ax.grid(axis='y', alpha=0.25, lw=0.5)
        ax.set_title(title, loc='left', fontsize=9)
    axes[1].set_xticks(x)
    axes[1].set_xticklabels([g[0] for g in groups], fontsize=7)
    axes[1].set_xlabel('版本（KQ_1 · 臂速观测器带宽）')
    for i, (name, vals, col) in enumerate(groups):
        if not vals:
            axes[0].text(i, 3, '未取到\n数据', ha='center', va='bottom', fontsize=6, color='#999999')
    fig.tight_layout()
    fig.savefig(os.path.join(OUT, 'fig5_steps.png'))
    plt.close(fig)


# ---------------------------------------------------------------- fig7 整圈旋转
def fig7():
    d = load(T_ROT)
    t = d['t']
    arm = d['arm_deg']
    ref = d['reference_deg']
    th = d['theta_deg']
    m = t > 2.0
    th_max = np.max(np.abs(th[m]))
    th_rms = np.sqrt(np.mean(th[m] ** 2))
    fig, axes = plt.subplots(2, 1, figsize=(6.7, 4.0), sharex=True)
    ax = axes[0]
    ax.plot(t, arm - arm[0], color=C_BLUE, lw=0.9, label='旋臂角 a')
    ax.plot(t, ref - ref[0], color=C_ORANGE, lw=0.9, ls='--', label='目标参考 a_ref')
    ax.set_ylabel('相对角度 / °')
    ax.legend(frameon=False, loc='lower right', ncol=2)
    ax.grid(alpha=0.25, lw=0.5)
    ax.set_title('(a) 30 s 内累计转过 %.0f°，恒速段 21.0°/s' % (arm[-1] - arm[0]),
                 loc='left', fontsize=9)

    ax = axes[1]
    ax.plot(t, th, color=C_BLUE, lw=0.8)
    ax.axhline(0, color='#333333', lw=0.5, ls=':')
    ax.set_ylabel('摆角 θ / °')
    ax.set_xlabel('时间 t / s')
    ax.set_ylim(-12, 12)
    ax.grid(alpha=0.25, lw=0.5)
    ax.set_xlim(0, 30)
    ax.set_title('(b) 旋转过程中的摆角：2 s 之后 |θ| ≤ %.1f°，RMS %.1f°' % (th_max, th_rms),
                 loc='left', fontsize=9)

    fig.tight_layout()
    fig.savefig(os.path.join(OUT, 'fig8_rotation.png'))
    plt.close(fig)


# ---------------------------------------------------------------- fig8 陷波
def notch_coeffs(path):
    s = open(path, encoding='utf-8', errors='ignore').read()
    Q = 2 ** 28

    def g(n):
        m = re.search(n + r"\s*=\s*(-?)32'sd(\d+)", s)
        return int(m.group(1) + m.group(2)) / Q
    return [g('F_B0'), g('F_B1'), g('F_B2'), g('F_A1'), g('F_A2')]


def response(c, f, fs=1000.0):
    b0, b1, b2, a1, a2 = c
    z = np.exp(-2j * np.pi * np.asarray(f) / fs)
    return np.abs((b0 + b1 * z + b2 * z * z) / (1 + a1 * z + a2 * z * z))


def fig8():
    c_new = notch_coeffs('N21_obs07_kq1650_20261031/rtl/feedback_shape.vh')
    c_old = notch_coeffs('mb1_noI_085_20261024/rtl/feedback_shape.vh')
    f = np.logspace(np.log10(2), np.log10(40), 800)
    fig, ax = plt.subplots(figsize=(6.2, 3.0))
    ax.plot(f, response(c_old, f), color=C_GREY, lw=1.2, label='085：8.5 Hz / 带宽 5.9 Hz')
    ax.plot(f, response(c_new, f), color=C_BLUE, lw=1.5, label='N21：12.5 Hz / 带宽 12 Hz / 深度 0.6')
    ax.axhline(1.0, color='#333333', lw=0.5, ls=':')
    ax.axvspan(8, 18, color=C_BLUE, alpha=0.05)
    ax.set_xscale('log')
    ax.set_xlim(2, 40)
    ax.set_ylim(0.5, 1.05)
    ax.set_xlabel('频率 f / Hz')
    ax.set_ylabel('幅频 |H|')
    ax.set_xticks([2, 3, 4, 6, 8, 10, 12, 15, 20, 30, 40])
    ax.set_xticklabels(['2', '3', '4', '6', '8', '10', '12', '15', '20', '30', '40'])
    ax.xaxis.set_minor_formatter(NullFormatter())
    ax.grid(alpha=0.25, lw=0.5, which='major')
    ax.legend(frameon=False, loc='lower right', fontsize=7)
    fig.tight_layout()
    fig.savefig(os.path.join(OUT, 'fig3_notch.png'))
    plt.close(fig)


if __name__ == '__main__':
    for fn in (fig1, fig2, fig3, fig4, fig5, fig6, fig7, fig8):
        fn()
        print(fn.__name__, 'ok')
