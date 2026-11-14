"""
Прототип алгоритма распознавания (тот же, что в Infrastructure/Recognition) на синтетических данных.
Нужен для подбора порогов MinScore/StrongScore/GoodMargin и проверки устойчивости к сдвигу,
масштабу, яркости, шуму, JPEG и обесцвечиванию (баны). Запуск: python recognition_prototype.py
Синтетика проще реальных портретов: финальная проверка — DataTool check-layout на скриншотах.
"""
import cv2, numpy as np
rng = np.random.default_rng(1)
def portrait(seed):
    r = np.random.default_rng(seed)
    img = np.zeros((144,256,3), np.uint8)
    base = r.integers(0,255,3)
    img[:] = base
    for _ in range(14):
        c = tuple(int(x) for x in r.integers(0,255,3))
        cv2.ellipse(img,(int(r.integers(0,256)),int(r.integers(0,144))),(int(r.integers(8,70)),int(r.integers(8,50))),float(r.integers(0,180)),0,360,c,-1)
    return cv2.GaussianBlur(img,(0,0),3)
N=125
T={i:portrait(i) for i in range(N)}
MIN,STRONG,MARGIN,INNER,WW=0.60,0.85,0.15,0.1,64
def ccrop(im,a):
    h,w=im.shape[:2]
    if w/h>a:
        nw=round(h*a); x=(w-nw)//2; return im[:,x:x+nw]
    nh=round(w/a); y=(h-nh)//2; return im[y:y+nh]
def inner(im,m):
    h,w=im.shape[:2]; mx,my=round(w*m),round(h*m); return im[my:h-my, mx:w-mx]
def hist(bgr):
    hsv=cv2.cvtColor(bgr,cv2.COLOR_BGR2HSV)
    h=cv2.calcHist([hsv],[0,1],None,[18,8],[0,180,0,256]); cv2.normalize(h,h,1,0,cv2.NORM_L1); return h
cache={}
def prep(size):
    if size in cache: return cache[size]
    a=size[0]/size[1]; out=[]
    for i,t in T.items():
        r=cv2.resize(ccrop(t,a),size,interpolation=cv2.INTER_AREA)
        out.append((i,cv2.cvtColor(r,cv2.COLOR_BGR2GRAY),hist(inner(r,INNER))))
    cache[size]=out; return out
def recognize(slot,ban=False):
    a=slot.shape[1]/slot.shape[0]; size=(WW,max(8,round(WW/a)))
    tp=prep(size)
    r=cv2.resize(slot,size,interpolation=cv2.INTER_AREA)
    q=inner(cv2.cvtColor(r,cv2.COLOR_BGR2GRAY),INNER); qh=hist(inner(r,INNER))
    sc={}
    for i,g,h in tp:
        n=max(0,cv2.minMaxLoc(cv2.matchTemplate(g,q,cv2.TM_CCOEFF_NORMED))[1])
        hs=max(0,cv2.compareHist(qh,h,cv2.HISTCMP_CORREL))
        sc[i]= n if ban else 0.75*n+0.25*hs
    s=sorted(sc.items(),key=lambda kv:-kv[1]); b,s2=s[0][1],s[1][1]
    conf=0.5*np.clip((b-MIN)/(STRONG-MIN),0,1)+0.5*np.clip((b-s2)/MARGIN,0,1)
    return (s[0][0] if b>=MIN else None), conf, b, s2
def degrade(t, w=88, shift=0.04, ban=False):
    h=round(w*9/16)
    # simulate calibration offset: crop slot area with shift then resize
    H,W=t.shape[:2]; dx=int(rng.uniform(-shift,shift)*W); dy=int(rng.uniform(-shift,shift)*H)
    M=np.float32([[1,0,dx],[0,1,dy]]); sh=cv2.warpAffine(t,M,(W,H),borderMode=cv2.BORDER_REPLICATE)
    s=cv2.resize(sh,(w,h),interpolation=cv2.INTER_AREA).astype(np.float32)
    s=s*rng.uniform(0.7,1.1)+rng.uniform(-20,20)+rng.normal(0,6,s.shape)
    s=np.clip(s,0,255).astype(np.uint8)
    if ban: s=cv2.cvtColor(cv2.cvtColor(s,cv2.COLOR_BGR2GRAY),cv2.COLOR_GRAY2BGR)
    ok,enc=cv2.imencode('.jpg',s,[cv2.IMWRITE_JPEG_QUALITY,80]); return cv2.imdecode(enc,1)
for label,kw in [("pick 88px shift4%",{}),("pick 60px shift6%",{"w":60,"shift":0.06}),("ban gray 60px",{"w":60,"ban":True})]:
    correct=wrong=unk=0; confs=[]
    for i in range(N):
        s=degrade(T[i],**kw); hid,c,b,s2=recognize(s,ban=kw.get("ban",False))
        ok = hid is not None and c>=0.6
        if ok and hid==i: correct+=1; confs.append(c)
        elif ok: wrong+=1
        else: unk+=1
    print(label, "correct",correct,"wrong",wrong,"unknown",unk,"meanconf",round(float(np.mean(confs)),2))
# negatives: unrelated images
fp=0
for k in range(100):
    s=degrade(portrait(10000+k)); hid,c,b,s2=recognize(s)
    if hid is not None and c>=0.6: fp+=1
print("negatives accepted as hero:",fp,"/100")
print("--- harder: scale mismatch (slot shows zoomed crop of portrait)")
def zoomed(t, z):
    H,W=t.shape[:2]; nw,nh=int(W/z),int(H/z); x,y=(W-nw)//2,(H-nh)//2
    return cv2.resize(t[y:y+nh,x:x+nw],(W,H))
for z in [1.1,1.2,1.35]:
    correct=wrong=unk=0
    for i in range(N):
        hid,c,b,s2=recognize(degrade(zoomed(T[i],z),w=60,shift=0.05))
        ok = hid is not None and c>=0.6
        correct+= ok and hid==i; wrong+= ok and hid!=i; unk+= not ok
    print("zoom",z,"correct",correct,"wrong",wrong,"unknown",unk)
negb=[recognize(degrade(portrait(20000+k)))[2] for k in range(100)]
posb=[recognize(degrade(T[i]))[2] for i in range(N)]
print("neg best score p50/p95/max",np.percentile(negb,50).round(2),np.percentile(negb,95).round(2),round(max(negb),2))
print("pos best score p5/p50",np.percentile(posb,5).round(2),np.percentile(posb,50).round(2))
