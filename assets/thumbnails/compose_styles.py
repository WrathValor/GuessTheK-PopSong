"""Generate five additional thumbnails in deliberately distinct visual styles."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance, ImageOps
import random

ROOT=Path(__file__).parent
RENDERS=ROOT/"renders"
OUT=ROOT/"final"
FONT=ROOT/"fonts"/"LuckiestGuy-Regular.ttf"
OUT.mkdir(exist_ok=True)
W,H=1920,1080
INK=(26,21,43); CREAM=(255,247,224); YELLOW=(255,219,77); PINK=(255,62,142); BLUE=(52,215,235)

def f(size): return ImageFont.truetype(str(FONT),size)
def cover(name, focus=(.5,.5)):
    im=Image.open(RENDERS/name).convert("RGB")
    s=max(W/im.width,H/im.height); im=im.resize((int(im.width*s),int(im.height*s)),Image.Resampling.LANCZOS)
    x=int((im.width-W)*focus[0]); y=int((im.height-H)*focus[1])
    return im.crop((x,y,x+W,y+H))
def text(d,xy,s,size,color=CREAM,stroke=0,sc=INK,anchor="mm"):
    d.text(xy,s,font=f(size),fill=color,stroke_width=stroke,stroke_fill=sc,anchor=anchor)
def save(im,name): im.convert("RGB").save(OUT/name,quality=95)

# 1. Pixel arcade: chunky low-resolution palette and pixel-font-like block lettering.
im=cover("shot1.png",(.50,.48)).resize((240,135),Image.Resampling.NEAREST).resize((W,H),Image.Resampling.NEAREST)
im=ImageEnhance.Color(im).enhance(1.8).quantize(colors=20).convert("RGB")
im=ImageEnhance.Contrast(im).enhance(1.12)
d=ImageDraw.Draw(im)
d.rectangle((0,0,W,150),fill=INK); d.rectangle((0,H-190,W,H),fill=INK)
text(d,(W//2,75),"K-POP ARCADE",70,YELLOW)
text(d,(W//2,H-100),"CAN YOU NAME IT?",84,CREAM)
d.rectangle((20,20,W-20,H-20),outline=BLUE,width=16)
save(im,"thumb_pixel_arcade.png")

# 2. Manga panel: monochrome halftone with explosive red accents and speed rays.
im=cover("shot2.png",(.5,.47)).convert("L")
im=ImageOps.autocontrast(im).convert("RGB")
# Halftone screen blended softly over the grayscale scene.
small=im.resize((W//7,H//7),Image.Resampling.BILINEAR).convert("L")
dot=Image.new("RGB",(W,H),CREAM); dd=ImageDraw.Draw(dot)
for y in range(0,H,12):
  for x in range(0,W,12):
    lum=small.getpixel((min(x//7,small.width-1),min(y//7,small.height-1)))
    r=max(1,int((255-lum)/255*5.2)); dd.ellipse((x-r,y-r,x+r,y+r),fill=INK)
im=Image.blend(im,dot,.17)
burst=Image.new("RGBA",(W,H),(0,0,0,0)); bd=ImageDraw.Draw(burst)
for i in range(24):
  x=(i*173+91)%W
  bd.polygon([(x,0),(x+24,0),(x+380,720),(x+346,720)],fill=(255,52,80,20))
im=Image.alpha_composite(im.convert("RGBA"),burst)
d=ImageDraw.Draw(im); d.polygon([(0,0),(960,0),(840,150),(0,245)],fill=(*CREAM,245))
text(d,(420,95),"FINAL ROUND!",78,PINK,8,INK)
d.polygon([(1250,850),(1920,780),(1920,1080),(1190,1080)],fill=(*PINK,245))
text(d,(1580,960),"WHO KNOWS IT?",65,CREAM,8,INK)
d.rectangle((12,12,W-12,H-12),outline=INK,width=24)
save(im,"thumb_manga.png")

# 3. Retro synthwave: sunset bands, neon frame, deep violet palette.
im=cover("duel_stage.png",(.5,.5))
im=ImageEnhance.Color(im).enhance(.58); im=ImageEnhance.Brightness(im).enhance(.72)
im=Image.blend(im,Image.new("RGB",im.size,(24,8,68)),.38).convert("RGBA")
sun=Image.new("RGBA",(W,H),(0,0,0,0)); sd=ImageDraw.Draw(sun)
sd.ellipse((690,90,1230,630),fill=(255,70,155,180))
for y in range(350,610,32): sd.rectangle((680,y,1240,y+13),fill=(30,7,60,235))
im=Image.alpha_composite(im,sun.filter(ImageFilter.GaussianBlur(2)))
grid=Image.new("RGBA",(W,H),(0,0,0,0)); gd=ImageDraw.Draw(grid)
for y in range(720,1080,35): gd.line((0,y,W,y),fill=(47,220,255,80),width=3)
for x in range(-1000,3000,110): gd.line((960,680,x,1080),fill=(47,220,255,85),width=3)
im=Image.alpha_composite(im,grid)
d=ImageDraw.Draw(im); d.rectangle((28,28,W-28,H-28),outline=(255,74,198,255),width=12)
text(d,(960,115),"NEON SHOWDOWN",105,CREAM,8,(31,10,60))
text(d,(960,965),"GUESS THE TRACK",73,BLUE,7,(31,10,60))
save(im,"thumb_synthwave.png")

# 4. Minimalist graphic poster: large color blocks, silhouette scene and clear hook.
im=Image.new("RGB",(W,H),(245,239,222)); d=ImageDraw.Draw(im)
d.rectangle((0,0,W,300),fill=INK); text(d,(960,144),"HEAR IT. NAME IT.",92,CREAM)
scene=cover("icon3.png",(.5,.48)).resize((670,670),Image.Resampling.LANCZOS)
mask=Image.new("L",scene.size,0); ImageDraw.Draw(mask).ellipse((0,0,670,670),fill=255)
im.paste(scene,(625,255),mask)
d=ImageDraw.Draw(im); d.ellipse((560,190,1360,990),outline=PINK,width=26)
d.rounded_rectangle((105,405,430,730),radius=24,fill=YELLOW)
text(d,(267,560),"?",230,INK)
d.rounded_rectangle((1490,405,1815,730),radius=24,fill=BLUE)
text(d,(1652,560),"♪",180,INK)
d.rectangle((0,990,W,H),fill=INK); text(d,(960,1034),"THE K-POP SONG QUIZ",48,YELLOW)
save(im,"thumb_minimal_poster.png")

# 5. Glossy magazine cover: fashion editorial framing with sharp typography.
im=cover("shot3.png",(.5,.48))
im=ImageEnhance.Color(im).enhance(.78); im=ImageEnhance.Contrast(im).enhance(1.22)
shade=Image.new("RGBA",(W,H),(0,0,0,0)); sh=ImageDraw.Draw(shade)
sh.rectangle((0,0,W,220),fill=(12,8,27,205)); sh.rectangle((0,850,W,H),fill=(12,8,27,220))
im=Image.alpha_composite(im.convert("RGBA"),shade)
d=ImageDraw.Draw(im)
text(d,(960,105),"THE SOUND CHECK",96,CREAM)
d.line((170,185,1750,185),fill=(*YELLOW,255),width=8)
text(d,(960,960),"7 ROUNDS. ONE WINNER.",86,YELLOW,5,INK)
d.rounded_rectangle((60,285,480,395),radius=18,fill=(*PINK,245))
text(d,(270,340),"THE DUEL ISSUE",42,CREAM)
d.rounded_rectangle((1440,290,1860,420),radius=18,fill=(*BLUE,240))
text(d,(1650,355),"0.1 SEC CLIPS",40,INK)
d.rectangle((14,14,W-14,H-14),outline=CREAM,width=8)
save(im,"thumb_magazine.png")
