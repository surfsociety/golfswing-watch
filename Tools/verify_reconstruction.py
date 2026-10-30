"""Prüft die Rekonstruktion aus iOS/SwingReconstructor.swift gegen den Demo-Schwung aus iOS/DemoSwing.swift.

Gleiche Mathematik wie in Swift (Quaternionen, Trapez-Integration, lineare Drift-Korrektur,
Integration der Drehrate um die Unterarmachse). Aufruf: python3 Tools/verify_reconstruction.py
"""
import numpy as np

G = 9.80665
R = 0.7
TILT = np.radians(60)
U = np.array([1.0, 0, 0])
UP = np.array([0, np.cos(TILT), np.sin(TILT)])
N = np.cross(U, UP); N /= np.linalg.norm(N)

# Quaternionen als (w, x, y, z)
def qmul(a, b):
    w1, x1, y1, z1 = a; w2, x2, y2, z2 = b
    return np.array([w1*w2 - x1*x2 - y1*y2 - z1*z2, w1*x2 + x1*w2 + y1*z2 - z1*y2,
                     w1*y2 - x1*z2 + y1*w2 + z1*x2, w1*z2 + x1*y2 - y1*x2 + z1*w2])
def qinv(q): return q * np.array([1, -1, -1, -1])
def qaxis(angle, axis): return np.concatenate([[np.cos(angle/2)], np.sin(angle/2) * np.asarray(axis)])
def qact(q, v): return qmul(qmul(q, np.concatenate([[0], v])), qinv(q))[1:]
def qfromto(a, b):
    a = a/np.linalg.norm(a); b = b/np.linalg.norm(b)
    c = np.cross(a, b); q = np.concatenate([[1 + np.dot(a, b)], c]); return q/np.linalg.norm(q)

def smooth(x): c = np.clip(x, 0, 1); return c*c*(3 - 2*c)
def theta(t):
    if t < 0.5: return 0.0
    if t < 1.4: return -2.4*smooth((t - 0.5)/0.9)
    if t < 1.75: return -2.4 + 5.0*smooth((t - 1.4)/0.35)
    return 2.6
def roll(t): return 0.5*theta(t)
def pos(t): th = theta(t); return R*(np.sin(th)*U + (1 - np.cos(th))*UP)
BASE = qfromto(np.array([1.0, 0, 0]), -UP)
def att(t): return qmul(qmul(qaxis(theta(t), N), BASE), qaxis(roll(t), [1, 0, 0]))

def make(rate, noise=0.0, leak_deg=0.0, seed=0):
    rng = np.random.default_rng(seed)
    dt = 1/rate; t = np.arange(int(2.6*rate))*dt
    q = np.array([att(x) for x in t])
    a = []
    for x, qq in zip(t, q):
        aref = (pos(x + dt) - 2*pos(x) + pos(x - dt))/dt**2
        if 1.4 <= x < 1.75:  # Gravitationsleck durch Attitude-Fehler im Abschwung
            aref = aref + np.array([np.sin(np.radians(leak_deg))*G, 0, 0])
        a.append(qact(qinv(qq), aref)/G)
    a = np.array(a) + rng.normal(0, noise, (len(t), 3))
    w = []
    for x in t:
        dq = qmul(qinv(att(x - dt)), att(x + dt))
        if dq[0] < 0: dq = -dq
        w.append(dq[1:]/dt)
    return t, q, a, np.array(w)

def reconstruct(t, q, a, w, distal=np.array([1.0, 0, 0]), sup_sign=-1.0):
    om = np.linalg.norm(w, axis=1); pk = om.argmax(); n = len(t)
    def rest(step, span):
        i = pk; qs = None
        while True:
            nx = i + step
            if nx < 0 or nx >= n or abs(t[nx] - t[pk]) > span: return i, False
            i = nx
            if om[i] < 0.6:
                qs = i if qs is None else qs
                if abs(t[i] - t[qs]) >= 0.25: return i, True
            else: qs = None
    s, rb = rest(-1, 3.0); e, ra = rest(1, 2.5)
    T = t[s:e+1]
    A = np.array([qact(q[i], a[i])*G for i in range(s, e + 1)])
    v = np.zeros_like(A); p = np.zeros_like(A); rl = np.zeros(len(T))
    for i in range(1, len(T)):
        dt = T[i] - T[i-1]
        v[i] = v[i-1] + 0.5*(A[i] + A[i-1])*dt
        rl[i] = rl[i-1] + 0.5*(w[s+i] @ distal + w[s+i-1] @ distal)*dt
    v -= np.outer((T - T[0])/(T[-1] - T[0]), v[-1])
    for i in range(1, len(T)):
        p[i] = p[i-1] + 0.5*(v[i] + v[i-1])*(T[i] - T[i-1])
    return T, p, v, np.degrees(rl*sup_sign), rb and ra

def report(label, rate, **kw):
    t, q, a, w = make(rate, **kw)
    T, p, v, rot, rest_ok = reconstruct(t, q, a, w)
    truth = np.array([pos(x) for x in T]); truth -= truth[0]
    rot_true = np.array([-np.degrees(roll(x) - roll(T[0])) for x in T])  # linker Arm: +X-Rollen = Pronation
    vt = np.array([np.linalg.norm((pos(x + 1e-4) - pos(x - 1e-4))/2e-4) for x in T])
    print(f"{label:<38} Bahn max {np.linalg.norm(p - truth, axis=1).max()*100:5.1f} cm | "
          f"Speed {np.linalg.norm(v, axis=1).max()*3.6:5.1f}/{vt.max()*3.6:5.1f} km/h | "
          f"Rotation max Fehler {np.abs(rot - rot_true).max():4.1f}° (Top {rot_true.max():+.0f}°, Finish {rot_true[-1]:+.0f}°) | Ruhe {rest_ok}")

report("200 Hz ideal", 200)
report("100 Hz ideal", 100)
report("200 Hz, Rauschen 0,02 g", 200, noise=0.02)
for d in (1, 2, 5):
    report(f"200 Hz, {d}° Attitude-Fehler im Abschwung", 200, leak_deg=d)
