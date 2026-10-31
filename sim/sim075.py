# -*- coding: utf-8 -*-
"""J280 closed-loop simulation, structurally faithful to the 075 RTL.

Pipeline per 1 ms tick, mirroring c_sensor -> c_balance_core -> c_output:
  1. sensors: theta from the pot (0.080 deg/count quantization on the RAW ADC
     value), arm from the encoder (0.335 deg/count), 8-sample windowed
     velocities (like WINDOW=8 at 1 kHz) with one-pole beta smoothing.
  2. observer: same A_d, B_d, L as design_gains (Q20 state, Q20 corrections
     rounded the same way), re-init when |theta innovation| > 1.25 rad for
     5 ms (P_OBS_ERR_*), full state init at capture from measurements.
  3. control: u = +KQ . xc >> 8 with KQ = [538,315,4690,450] (Q8), then the
     12.4 Hz notch (Q28 biquad, 1 kHz), then the output stage:
     volts -> duty (6 V = 500 permille => duty = u/12*1000),
     rate limit 60 permille/ms, duty clip 500.
  4. motor: duty -> voltage (12 V full scale), PWM deadband + Coulomb model
     fitted to the 2026-10-21 slow test:
        breakaway duty 170..223 permille forward, 150..208 backward
        (i.e. 2.04..2.68 V fwd, 1.80..2.50 V bwd);
        running (kinetic) friction lower: 60 permille trough;
        stick: below breakaway the arm does not move (1 deg stick-slip steps
        emerge naturally from quantization + breakaway).
  5. plant: the official J280 drivetrain model (d2_drivetrain_model.py):
        qm (motor side, through 20:1), arm q_a, pendulum theta;
        crossover coupling, gravity on the pendulum, BA viscous on the arm,
        small play ignored (the gear train was measured play-free).

The reference path mirrors the RTL: ref locked at the capture arm angle; the
8 s one-shot re-anchor writes pos_rel to the 5-8 s envelope midpoint.

Usage:  python sim075.py [--K0 538 --K1 315 --K2 4690 --K3 450]
                         [--comp 0|120|200] [--hysteresis] [--seed 1]
        prints the same metrics as analyze_bands.py on real captures.
"""
import numpy as np
import sys

# ---------------- plant constants (official J280) ----------------
JP = .000675
J0 = .000693 + .09 * .152 ** 2
CROSS = .09 * .152 * .075
MGL = .09 * 9.81 * .075
KM = .1165 / 3.75
BEMF = .1165 * .2012 / 3.75
BA = .00264
BP = .0001
GEAR = 20.0

TS = 1e-3
V12 = 12.0

# ---------------- actuator model (from the 10-21 slow test) ----------------
BREAK_FWD = (170 + 223) / 2 / 1000 * V12   # V, forward breakaway
BREAK_BWD = (150 + 208) / 2 / 1000 * V12   # V, backward breakaway
RUN_FWD = 60 / 1000 * V12                  # V, kinetic (trough)
RUN_BWD = 60 / 1000 * V12

K_SPRING = 8.0   # N.m/rad equivalent: elastic wind-up of the gear train while stuck

def motor_torque_voltage(u_cmd, v_state, u_mem):
    """Return the effective voltage seen by the drivetrain.

    u_mem carries the sign of the last effective drive (stick state)."""
    if v_state != 0.0:
        s = np.sign(v_state)
        brk = BREAK_FWD if s > 0 else BREAK_BWD
        run = RUN_FWD if s > 0 else RUN_BWD
        # moving: kinetic friction, cannot reverse within one tick unless the
        # command flips hard; simple, matches the slow test qualitatively
        eff = u_cmd - s * run
        if s > 0 and eff < 0:
            return 0.0, 0.0
        if s < 0 and eff > 0:
            return 0.0, 0.0
        return eff, s
    # stalled: static friction
    if u_cmd > BREAK_FWD:
        return u_cmd - BREAK_FWD, +1.0
    if u_cmd < -BREAK_BWD:
        return u_cmd + BREAK_BWD, -1.0
    return 0.0, u_mem

# ---------------- linear model ----------------
def linear_matrices():
    m11 = J0
    m12 = CROSS
    det = m11 * JP - m12 * m12
    A = np.zeros((4, 4))
    A[0, 1] = 1.0
    A[1, 1] = -JP * BEMF / det
    A[1, 2] = -m12 * MGL / det
    A[2, 3] = 1.0
    A[3, 1] = m12 * BEMF / det
    A[3, 2] = m11 * MGL / det
    A[3, 3] = -BP / JP
    B = np.zeros((4, 1))
    B[1, 0] = JP * KM / det
    B[3, 0] = -m12 * KM / det
    return A, B

def zoh(A, B, ts):
    n = A.shape[0]
    M = np.zeros((n + 1, n + 1))
    M[:n, :n] = A * ts
    M[:n, n:] = (B * ts).reshape(n, 1)
    E = np.linalg.solve(np.eye(n + 1), M)  # first-order ZOH (small ts)
    import scipy.linalg as sla
    E = sla.expm(M)
    return E[:n, :n], E[:n, n:]

A6 = np.load('A6.npy'); B6 = np.load('B6.npy')
A_c, B_c = linear_matrices()
A_d, B_d = zoh(A_c, B_c, TS)
KQ = np.array([538., 315., 4690., 450.])   # Q8 gains (V/rad per state /256)

# sensor scales / observer / notch (unchanged)
TH_SCALE = (93827 / 1024.0) / 65536.0
AR_SCALE = (98014 / 256.0) / 65536.0
POT_COUNTS = 2247 / np.pi
ENC_COUNTS = 1075.5 / (2 * np.pi)
VEL_CLIP = 2293760 / 65536.0
L = np.array([[233027/2.0**20, 0.0],
              [14616401/2.0**20, 0.0],
              [0.0, 414269/2.0**20],
              [0.0, 51786237/2.0**20]])
Q28 = 2.0 ** 28
NB = [265016636/Q28, -525503854/Q28, 262086219/Q28]
NA = [1.0, -525503854/Q28, 258667399/Q28]


# ---------------- faithful balance harness (no freeze approximation) ----------
def balance_run(seconds=30.0, KQ_v=None, ref_arm=-104.0, arm0=-90.0, th0=-2.0,
                vth0=0.0, mode=None, C=0.0, seed=1, theta_noise=0.35, enc_noise=1.0,
                bkw=2.30, bkb=2.15, kinetic=0.72, report=None):
    """Rigid 4-state balance sim. The arm NEVER freezes: when the motor is
    stalled (|u|<breakaway) the arm stays put but the PENDULUM keeps integrating
    on the locked arm (A_lock rows). Offset modes apply at 1 kHz exactly like
    the RTL would."""
    import numpy as np
    rng = np.random.default_rng(seed)
    Kv = (KQ_v if KQ_v is not None else KQ)/256.0
    A, B = A_d, B_d
    A_lock = A.copy(); A_lock[:,0]=0; A_lock[:,1]=0
    x = np.array([np.radians(arm0), 0.0, np.radians(th0), np.radians(vth0)])
    ref = np.radians(ref_arm)
    xo = x.copy()
    th_h = np.full(8, x[2]); a_h = np.full(8, x[0])
    thf = x[3]; af = 0.0
    nx1=nx2=ny1=ny2=0.0
    duty = 0.0
    n = int(seconds*1000)
    arm=np.zeros(n); th=np.zeros(n); du=np.zeros(n)
    for i in range(n):
        thm = np.round(x[2]*POT_COUNTS + rng.normal(0,theta_noise))/POT_COUNTS
        am  = np.round(x[0]*ENC_COUNTS + rng.normal(0,enc_noise))/ENC_COUNTS
        th_h[1:]=th_h[:-1]; th_h[0]=thm
        a_h[1:]=a_h[:-1];  a_h[0]=am
        vth_w = (th_h[0]-th_h[7])/8e-3
        va_w  = (a_h[0]-a_h[7])/8e-3
        thf += (vth_w-thf)*0.15
        af  += (va_w-af)*0.15
        xo = A@xo + B.ravel()*(duty/1000.0*12.0)
        xo = xo + L@np.array([am-xo[0], thm-xo[2]])
        u = float(Kv@np.array([xo[0]-ref, xo[1], xo[2], xo[3]]))
        ny = NB[0]*u+NB[1]*nx1+NB[2]*nx2-NA[1]*ny1-NA[2]*ny2
        nx2,nx1 = nx1,u; ny2,ny1 = ny1,ny
        duty = float(np.clip(ny/12.0*1000.0,-500,500))
        ucmd = duty/1000.0*12.0
        if mode=='offset':
            if ucmd>0: ucmd+=C
            elif ucmd<0: ucmd-=C
        elif mode=='smalldither':
            ucmd += C*np.sin(2*np.pi*37.5*i*1e-3)
        if x[1]==0.0:
            if ucmd>bkw: eff=ucmd-bkw
            elif ucmd<-bkb: eff=ucmd+bkb
            else:
                eff=0.0
                x[2:]=A_lock[2:,2:]@x[2:]
                arm[i]=np.degrees(x[0]); th[i]=np.degrees(x[2]); du[i]=duty
                continue
        else:
            sg=np.sign(x[1]); eff=ucmd-sg*kinetic
            if (sg>0 and eff<0) or (sg<0 and eff>0):
                eff=0.0; x[1]=0.0
                x[2:]=A_lock[2:,2:]@x[2:]
                arm[i]=np.degrees(x[0]); th[i]=np.degrees(x[2]); du[i]=duty
                continue
        x = A@x + B.ravel()*eff
        arm[i]=np.degrees(x[0]); th[i]=np.degrees(x[2]); du[i]=duty
    if report is not None:
        report(arm, th, du)
    return arm, th, du

def capture_states_from_trace(path, run_offset_ms=0):
    """Return (arm_deg, theta_deg, vth_deg_s, va_deg_s) at a real capture."""
    import csv
    rows = list(csv.DictReader(open(path, encoding='utf-8', errors='replace')))
    r = rows[run_offset_ms]
    return (float(r['arm_deg']), float(r['theta_deg']),
            float(r['pend_speed_deg_s']), float(r['arm_speed_deg_s']))


def simulate(seconds=30.0, KQ_v=None, seed=1, comp=0.0, hysteresis=False,
             arm0_deg=-90.0, theta0_deg=-2.0, ref_arm_deg=None,
             vth0_deg_s=0.0, va0_deg_s=0.0, verbose=False):
    """BALANCE-phase sim on the 6-state elastic plant.

    Controller sees the MOTOR-side arm angle (encoder) and theta (pot), exactly
    like the RTL; the pendulum is driven by the LOAD-side arm through the
    measured gear elasticity (4.7 Nm/rad -> 4.7-6.2 deg lag at breakaway)."""
    rng = np.random.default_rng(seed)
    if KQ_v is None:
        KQ_v = KQ
    K_volts = KQ_v / 256.0
    n = int(seconds / TS)
    th0 = np.radians(theta0_deg)
    X = np.array([np.radians(arm0_deg), np.radians(va0_deg_s),
                  np.radians(arm0_deg), np.radians(va0_deg_s),
                  th0, np.radians(vth0_deg_s)])
    ref = np.radians(ref_arm_deg if ref_arm_deg is not None else arm0_deg)

    xo = np.array([X[0], X[1], X[4], X[5]])   # observer = motor arm + theta
    dth = X[5]; dal = X[1]
    th_h = np.array([X[4] - dth*TS*(7-k) for k in range(8)])
    a_h = np.array([X[0] - dal*TS*(7-k) for k in range(8)])
    th_f = dth; a_f = dal
    nx1=nx2=ny1=ny2=0.0
    stick = 0.0
    duty = 0.0
    log = {k: np.zeros(n) for k in ('t','arm','theta','duty','asp','ref','st')}

    for i in range(n):
        t = i*TS
        am_meas = np.round(X[0]*ENC_COUNTS)/ENC_COUNTS
        th_meas = np.round(X[4]*POT_COUNTS + rng.normal(0,0.35))/POT_COUNTS
        tw = th_meas
        th_h[1:] = th_h[:-1]; th_h[0]=tw
        a_h[1:] = a_h[:-1]; a_h[0]=am_meas
        vth_w = (tw - th_h[7])/8e-3
        va_w = (am_meas - a_h[7])/8e-3
        vth_w = float(np.clip(vth_w,-35,35)); va_w=float(np.clip(va_w,-35,35))
        th_f += (vth_w-th_f)*0.15
        a_f += (va_w-a_f)*0.15

        # observer: 4-state rigid model on [motor arm, arm speed, theta, theta speed]
        xo = A_d @ xo + B_d.ravel()*(duty/1000.0*12.0)
        xo = xo + L @ np.array([am_meas-xo[0], tw-xo[2]])

        u_V = float(K_volts @ np.array([xo[0]-ref, xo[1], xo[2], xo[3]]))
        ny = NB[0]*u_V + NB[1]*nx1 + NB[2]*nx2 - NA[1]*ny1 - NA[2]*ny2
        nx2,nx1 = nx1,u_V; ny2,ny1 = ny1,ny
        duty = float(np.clip(ny/12*1000,-500,500))

        u_cmd = duty/1000.0*12.0
        if comp:
            if u_cmd>0: u_cmd+=comp
            elif u_cmd<0: u_cmd-=comp
        # motor with breakaway/kinetic friction (motor side, load referred 20:1)
        vm = X[1]
        if vm != 0.0:
            sg = np.sign(vm); run = 0.72 if sg>0 else 0.72
            eff = u_cmd - sg*run
            if sg>0 and eff<0: eff=0.0; stick=0.0
            elif sg<0 and eff>0: eff=0.0; stick=0.0
        else:
            if u_cmd > 2.30: eff = u_cmd-2.30; stick=1
            elif u_cmd < -2.15: eff = u_cmd+2.15; stick=-1
            else: eff=0.0; stick=0
        # motor+load rigid per B6 row 1? No: B6[1] drives the MOTOR; elastic load
        # transfers through A6. eff is volts on the motor.
        if eff == 0.0 and stick == 0 and X[1] == 0.0 and abs(X[3]) < 1e-9 and abs(X[5]) < 0.02:
            # motor stalled: gear-train static friction (0.45 Nm at the load)
            # holds the whole train; pendulum gravity torque (<=0.007 Nm near
            # vertical) cannot overcome it. Freeze the plant this tick.
            pass
        else:
            X = A6 @ X + B6.ravel()*(eff)
        if not np.isfinite(X).all() or abs(X[4])>3.5:
            for k in log: log[k][i:]=np.nan
            if verbose: print('diverged t=%.2f'%t)
            break
        log['t'][i]=t; log['arm'][i]=np.degrees(X[0])
        log['theta'][i]=np.degrees(X[4]); log['duty'][i]=duty
        log['asp'][i]=np.degrees(X[1]); log['ref'][i]=np.degrees(ref); log['st'][i]=2
    return log

def metrics(log):
    t = log['t']; a = log['arm']; th = log['theta']; du = log['duty']
    fs = 1000.0
    m = t > 10
    out = {}
    out['arm_p2p'] = a[m].max() - a[m].min()
    out['th_rms'] = np.sqrt((th[m] ** 2).mean())
    def band(x, lo, hi):
        y = x - x.mean(); n = len(y)
        f = np.fft.rfftfreq(n, 1 / fs)
        P = np.abs(np.fft.rfft(y * np.hanning(n))) * 2 / (n * 0.5)
        b = (f >= lo) & (f < hi)
        return float(np.sqrt((P[b] ** 2).sum()) / 2 ** 0.5)
    out['th_02_1'] = band(th[m], .2, 1)
    out['th_6_10'] = band(th[m], 6, 10)
    p2 = [a[(t >= k) & (t < k + 1)].max() - a[(t >= k) & (t < k + 1)].min()
          for k in range(10, int(t[-1]))]
    out['slips'] = int(sum(1 for v in p2 if v > 25))
    out['duty_absmean'] = float(np.mean(np.abs(du[m])))
    return out

if __name__ == '__main__':
    log = simulate(30.0)
    mt = metrics(log)
    print('baseline KQ=[538,315,4690,450], comp=0:')
    for k, v in mt.items():
        print('  %-12s %.2f' % (k, v))
