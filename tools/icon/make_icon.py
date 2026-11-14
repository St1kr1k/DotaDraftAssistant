from PIL import Image, ImageDraw
S=1024
RED=(229,56,59,255); BG=(9,9,11,255); EDGE=(38,38,44,255)
def render(size):
    # отрисовка в 4x и сглаживание вниз
    k=4; N=size*k
    im=Image.new("RGBA",(N,N),(0,0,0,0)); d=ImageDraw.Draw(im)
    r=int(N*0.2)
    d.rounded_rectangle([0,0,N-1,N-1],radius=r,fill=BG)
    # тонкая рамка у больших размеров
    if size>=48:
        w=max(2,int(N*0.006))
        d.rounded_rectangle([w,w,N-1-w,N-1-w],radius=r-w,outline=EDGE,width=w)
    c=N/2
    # внешний ромб: контур (толще на маленьких размерах, чтобы не пропадал)
    R=N*0.30
    sw=N*(0.045 if size>=64 else 0.075)
    outer=[(c,c-R),(c+R,c),(c,c+R),(c-R,c)]
    Ri=R-sw*1.41
    inner=[(c,c-Ri),(c+Ri,c),(c,c+Ri),(c-Ri,c)]
    d.polygon(outer,fill=RED); d.polygon(inner,fill=BG)
    # внутренний заполненный ромб
    r2=N*0.11
    d.polygon([(c,c-r2),(c+r2,c),(c,c+r2),(c-r2,c)],fill=RED)
    return im.resize((size,size),Image.LANCZOS)
big=render(1024); big.save("icon_1024.png")
render(256).save("icon_256.png")
sizes=[16,20,24,32,40,48,64,128,256]
imgs=[render(s) for s in sizes]
imgs[-1].save("app.ico",format="ICO",sizes=[(s,s) for s in sizes],append_images=imgs[:-1])
# превью: крупно + размеры как в Windows
prev=Image.new("RGBA",(980,420),(24,24,28,255)); x=40
prev.paste(render(320),(40,50),render(320))
x=420
for s in [128,64,48,32,24,16]:
    im=render(s); prev.paste(im,(x,210-s//2),im); x+=s+30
prev.save("preview.png")
print("ok")
