"""Simulate the arm-position integral (the PID branch) on top of the 085 law.

Mirrors the RTL: pos_i += (a-ref) each ms while |theta|<10 deg, clamped to
+/-2e6 (Q16*ms); u += P_POS_I_K*pos_i>>16 before the notch.
"""
import numpy as np, sim075
A6=None
def run(seconds=20.0, KQ0=538.0, Ki=0.0, ref_arm=-104.0, arm0=-90.0, th0=-2.0,
        seed=1, poslim=2_000_000.0):
    A,B = sim075.linear_matrices(); Ad,Bd = sim075.zoh(A,B,sim075.TS)
    Kv = np.array([KQ0,315.,4690.,450.])/256.0
    L = np.array([[233027/2.0**20,0.0],[14616401/2.0**20,0.0],
                  [0.0,414269/2.0**20],[0.0,51786237/2.0**20]])
    Q28=2.0**28
    NB=[266466115/Q28,-526272766/Q28,260558092/Q28]
    NA=[1.0,-526272766/Q28,258588751/Q28]
    POT=2247/np.pi; ENC=1075.5/(2*np.pi)
    rng=np.random.default_rng(seed)
    A_lock=Ad.copy(); A_lock[:,0]=0; A_lock[:,1]=0
    x=np.array([np.radians(arm0),0.0,np.radians(th0),0.0]); ref=np.radians(ref_arm)
    xo=x.copy(); th_h=np.full(8,x[2]); a_h=np.full(8,x[0])
    thf=x[3]; af=0.0; nx1=nx2=ny1=ny2=0.0; duty=0.0; pos_i=0.0
    n=int(seconds*1000); arm=np.zeros(n); th=np.zeros(n); du=np.zeros(n); pi_=np.zeros(n)
    for i in range(n):
        thm=np.round(x[2]*POT+rng.normal(0,0.35))/POT
        am =np.round(x[0]*ENC+rng.normal(0,1.0))/ENC
        th_h[1:]=th_h[:-1]; th_h[0]=thm; a_h[1:]=a_h[:-1]; a_h[0]=am
        vth_w=(th_h[0]-th_h[7])/8e-3; va_w=(a_h[0]-a_h[7])/8e-3
        thf+=(vth_w-thf)*0.15; af+=(va_w-af)*0.15
        xo=Ad@xo+Bd.ravel()*(duty/1000.0*12.0)
        xo=xo+L@np.array([am-xo[0],thm-xo[2]])
        a_err=xo[0]-ref
        u=float(Kv@np.array([a_err,xo[1],xo[2],xo[3]]))
        if Ki>0:
            if abs(xo[2])<np.radians(10):
                pos_i=float(np.clip(pos_i+a_err*65536.0,-poslim,poslim))
            u+=Ki*pos_i/65536.0/65536.0*65536.0/65536.0 if False else Ki*pos_i/65536.0/65536.0
        ny=NB[0]*u+NB[1]*nx1+NB[2]*nx2-NA[1]*ny1-NA[2]*ny2
        nx2,nx1=nx1,u; ny2,ny1=ny1,ny
        duty=float(np.clip(ny/12.0*1000.0,-500,500))
        ucmd=duty/1000.0*12.0
        if x[1]==0.0:
            if ucmd>2.30: eff=ucmd-2.30
            elif ucmd<-2.15: eff=ucmd+2.15
            else:
                eff=0.0; x[2:]=A_lock[2:,2:]@x[2:]
                arm[i]=np.degrees(x[0]); th[i]=np.degrees(x[2]); du[i]=duty; pi_[i]=pos_i; continue
        else:
            sg=np.sign(x[1]); eff=ucmd-sg*0.72
            if (sg>0 and eff<0) or (sg<0 and eff>0):
                eff=0.0; x[1]=0.0; x[2:]=A_lock[2:,2:]@x[2:]
                arm[i]=np.degrees(x[0]); th[i]=np.degrees(x[2]); du[i]=duty; pi_[i]=pos_i; continue
        x=Ad@x+Bd.ravel()*eff
        arm[i]=np.degrees(x[0]); th[i]=np.degrees(x[2]); du[i]=duty; pi_[i]=pos_i
    return arm,th,du,pi_
if __name__=='__main__':
    import itertools
    inits=[(-104.0,-90.0,-2.0),(-70.0,-60.0,-5.0)]
    seeds=[1,7,13]
    print('Ki   KQ0 | arm_p2p  th_rms | |duty| | int pinned%')
    for Ki,KQ0 in [(0,538),(120,538),(300,538),(600,538),(120,650),(120,900)]:
        arms=[];ths=[];ds=[];pin=[]
        for (r,a0,t0),s in itertools.product(inits,seeds):
            arm,th,du,pi_=run(20.0,KQ0,Ki,r,a0,t0,s)
            m=slice(5000,20000)
            arms.append(np.ptp(arm[m])); ths.append(np.sqrt(np.mean(th[m]**2)))
            ds.append(np.mean(np.abs(du[m]))); pin.append(100*np.mean(np.abs(pi_[m])>=1.99e6))
        print('%4d %4d | %6.1f   %5.2f  | %5.0f  | %5.1f'%(Ki,KQ0,np.median(arms),np.median(ths),np.median(ds),np.median(pin)))
