import numpy as np
R=0.7; tilt=np.radians(60); g=9.80665
def sm(x): c=np.clip(x,0,1); return c*c*(3-2*c)
def theta(t):
    if t<0.5: return 0
    if t<1.4: return -2.4*sm((t-0.5)/0.9)
    if t<1.75: return -2.4+5.0*sm((t-1.4)/0.35)
    return 2.6
u=np.array([1,0,0.]); up=np.array([0,np.cos(tilt),np.sin(tilt)])
pos=lambda t: R*(np.sin(theta(t))*u+(1-np.cos(theta(t)))*up)
def run(rate, noise=0.0, bias=0.0, seed=0):
    rng=np.random.default_rng(seed)
    dt=1/rate; n=int(2.6*rate); t=np.arange(n)*dt
    a=np.array([(pos(x+dt)-2*pos(x)+pos(x-dt))/dt**2/g for x in t])
    a=a+rng.normal(0,noise,a.shape)+bias
    nrm=np.cross(u,up); nrm/=np.linalg.norm(nrm)
    w=np.array([(theta(x+dt)-theta(x-dt))/(2*dt)*nrm for x in t])
    om=np.linalg.norm(w,axis=1); pk=om.argmax()
    def rest(step,span):
        i=pk;q=None
        while True:
            nx=i+step
            if nx<0 or nx>=n or abs(t[nx]-t[pk])>span: return i,False
            i=nx
            if om[i]<0.6:
                q=i if q is None else q
                if abs(t[i]-t[q])>=0.25: return i,True
            else: q=None
    s,rb=rest(-1,3.0); e,ra=rest(1,2.5)
    A=a[s:e+1]*g; T=t[s:e+1]
    v=np.zeros_like(A)
    for i in range(1,len(A)): v[i]=v[i-1]+0.5*(A[i]+A[i-1])*(T[i]-T[i-1])
    v-=np.outer((T-T[0])/(T[-1]-T[0]),v[-1])
    p=np.zeros_like(A)
    for i in range(1,len(A)): p[i]=p[i-1]+0.5*(v[i]+v[i-1])*(T[i]-T[i-1])
    truth=np.array([pos(x) for x in T]); truth-=truth[0]
    err=np.linalg.norm(p-truth,axis=1)
    vt=np.array([np.linalg.norm((pos(x+1e-4)-pos(x-1e-4))/2e-4) for x in T])
    print(f"rate={rate} noise={noise}g bias={bias}g window={T[0]:.2f}-{T[-1]:.2f}s rest={rb},{ra} "
          f"maxPosErr={err.max()*100:.1f}cm meanErr={err.mean()*100:.1f}cm "
          f"peakV rec={np.linalg.norm(v,axis=1).max()*3.6:.1f} true={vt.max()*3.6:.1f} km/h clubEst={om.max()*1.5*3.6:.0f} km/h")
run(200); run(100); run(200,noise=0.02); run(200,noise=0.02,bias=0.01); run(200,bias=0.03)
# zeitvariabler Fehler: Gravitations-Leck durch 2° Attitude-Fehler nur im Abschwung (1.4-1.75 s)
import types
def run_leak(deg):
    global pos
    rate=200; dt=1/rate; n=int(2.6*rate); t=np.arange(n)*dt
    leak=np.sin(np.radians(deg))
    a=np.array([(pos(x+dt)-2*pos(x)+pos(x-dt))/dt**2/g + (np.array([leak,0,0]) if 1.4<=x<1.75 else 0) for x in t])
    s=int(0.29*rate); e=int(2.0*rate)
    A=a[s:e+1]*g; T=t[s:e+1]
    v=np.cumsum(np.vstack([np.zeros(3),0.5*(A[1:]+A[:-1])*dt]),axis=0)
    v-=np.outer((T-T[0])/(T[-1]-T[0]),v[-1])
    p=np.cumsum(np.vstack([np.zeros(3),0.5*(v[1:]+v[:-1])*dt]),axis=0)
    truth=np.array([pos(x) for x in T]); truth-=truth[0]
    print(f"attitude-leak {deg}° im Abschwung: maxPosErr={np.linalg.norm(p-truth,axis=1).max()*100:.1f}cm")
for d in (1,2,5): run_leak(d)
