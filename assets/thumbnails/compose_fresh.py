"""Build a varied, game-specific thumbnail set from the project's Blender renders."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance
import math

ROOT = Path(__file__).parent
OUT = ROOT / "final"
RENDERS = ROOT / "renders"
OUT.mkdir(exist_ok=True)
INK = (27, 22, 43)
YELLOW = (255, 222, 105)
WHITE = (255, 250, 239)
PINK = (255, 100, 166)
CYAN = (73, 220, 255)
RED = (255, 75, 70)
FONT = ROOT / "fonts" / "LuckiestGuy-Regular.ttf"

def font(size):
    return ImageFont.truetype(str(FONT), size)

def cover(im, size, center=(.5, .5)):
    w, h = size
    s = max(w / im.width, h / im.height)
    im = im.resize((round(im.width*s), round(im.height*s)), Image.Resampling.LANCZOS)
    x = round((im.width-w)*center[0]); y = round((im.height-h)*center[1])
    return im.crop((x,y,x+w,y+h)).convert("RGBA")

def base(name, center=(.5,.5), sat=1.25, contrast=1.12, blur=0):
    im=cover(Image.open(RENDERS/name), (1920,1080), center)
    im=ImageEnhance.Color(im).enhance(sat); im=ImageEnhance.Contrast(im).enhance(contrast)
    if blur: im=im.filter(ImageFilter.GaussianBlur(blur))
    return im

def label(im, text, xy, size, fill=YELLOW, stroke=15, angle=0, anchor="mm"):
    f=font(size); box=f.getbbox(text,stroke_width=stroke)
    layer=Image.new("RGBA",(box[2]-box[0]+80,box[3]-box[1]+80),(0,0,0,0)); d=ImageDraw.Draw(layer)
    pos=(40-box[0],40-box[1])
    d.text((pos[0]+8,pos[1]+12),text,font=f,fill=INK,stroke_width=stroke+7,stroke_fill=INK)
    d.text(pos,text,font=f,fill=fill,stroke_width=stroke,stroke_fill=INK)
    if angle: layer=layer.rotate(angle,Image.Resampling.BICUBIC,expand=True)
    im.alpha_composite(layer,(round(xy[0]-layer.width/2),round(xy[1]-layer.height/2)))

def question(im, xy, size, fill=YELLOW):
    label(im,"?",xy,size,fill,stroke=20,angle=-10)

def vignette(im, alpha=95):
    w,h=im.size
    mask=Image.new("L",(w,h),0); d=ImageDraw.Draw(mask)
    d.ellipse((-w*.2,-h*.3,w*1.2,h*1.3),fill=255)
    mask=mask.filter(ImageFilter.GaussianBlur(180))
    shade=Image.new("RGBA",(w,h),(8,5,24,alpha))
    im.alpha_composite(Image.composite(Image.new("RGBA",(w,h),(0,0,0,0)),shade,mask))
    return im

def stripes(im, color, spacing=54, width=16, opacity=80):
    layer=Image.new("RGBA",im.size,(0,0,0,0));d=ImageDraw.Draw(layer);w,h=im.size
    for x in range(-h,w,spacing): d.line((x,0,x+h,h),fill=(*color,opacity),width=width)
    im.alpha_composite(layer)

def border(im,color,width=16):
    ImageDraw.Draw(im).rectangle((8,8,im.width-9,im.height-9),outline=(*color,255),width=width)

# Duel: split-color versus poster, grounded in the actual duel stage.
im=base("duel_stage.png",(.5,.5),1.4,1.18)
overlay=Image.new("RGBA",im.size,(0,0,0,0));d=ImageDraw.Draw(overlay)
d.polygon([(0,0),(930,0),(750,1080),(0,1080)],fill=(255,70,125,46))
d.polygon([(1920,0),(1030,0),(1180,1080),(1920,1080)],fill=(50,130,255,60))
im.alpha_composite(overlay); vignette(im,100)
label(im,"GUESS THE K-POP SONG",(960,126),102,WHITE,17)
label(im,"1V1 DUEL",(960,940),150,YELLOW,20)
label(im,"YOU",(285,820),74,(166,245,190),13)
label(im,"RIVAL",(1625,820),74,PINK,13)
ImageDraw.Draw(im).ellipse((825,440,1095,710),fill=(*RED,255),outline=(*INK,255),width=22)
label(im,"VS",(960,575),112,YELLOW,16)
im.save(OUT/"thumb_duel.png")

# Panic: arcade-comic timer burst, with the buzzer and raised arm in-frame.
im=base("shot1.png",(.50,.48),1.45,1.22)
stripes(im,YELLOW,75,10,18); vignette(im,115)
label(im,"0.1s",(350,300),235,RED,23,-8)
label(im,"GUESS IT!",(375,850),118,YELLOW,18,5)
label(im,"BUZZ!",(1530,250),83,WHITE,13,8)
border(im,RED,18)
im.save(OUT/"thumb_panic.png")

# Faceoff: cool-toned cinematic crop, with only game-native round and score cues.
im=base("shot2.png",(.5,.47),1.22,1.18)
im=ImageEnhance.Color(im).enhance(.76)
glow=Image.new("RGBA",im.size,(0,0,0,0));gd=ImageDraw.Draw(glow)
gd.ellipse((700,220,1220,740),fill=(110,100,255,100))
im.alpha_composite(glow.filter(ImageFilter.GaussianBlur(100)))
label(im,"FINAL ROUND",(960,965),100,YELLOW,18)
label(im,"38",(300,175),114,RED,16,-5)
label(im,"VS",(960,175),83,WHITE,14)
label(im,"37",(1620,175),114,(150,120,255),16,5)
vignette(im,130); border(im,(160,145,255),12)
im.save(OUT/"thumb_faceoff.png")

# Meltdown: bright pop-art poster, song cards and question symbols foregrounded.
im=base("shot3.png",(.5,.49),1.45,1.15)
im=ImageEnhance.Color(im).enhance(1.28)
stripes(im,PINK,92,8,16)
question(im,(250,235),170,YELLOW); question(im,(1670,260),145,PINK)
label(im,"NAME THAT SONG!",(960,935),116,YELLOW,18,-2)
label(im,"?  ?  ?",(960,150),76,WHITE,10)
border(im,PINK,15)
im.save(OUT/"thumb_meltdown.png")

# Faceoff clean: graphic manga split panel; no text, letting the rival clash lead.
im=base("shot2.png",(.5,.47),1.0,1.32)
im=ImageEnhance.Color(im).enhance(.6)
layer=Image.new("RGBA",im.size,(0,0,0,0));d=ImageDraw.Draw(layer)
d.polygon([(0,0),(480,0),(350,1080),(0,1080)],fill=(255,50,132,18))
d.polygon([(1920,0),(1490,0),(1620,1080),(1920,1080)],fill=(70,100,255,20))
d.line((956,0,918,1080),fill=(*WHITE,220),width=7)
im.alpha_composite(layer); border(im,WHITE,10)
im.save(OUT/"thumb_faceoff_clean.png")

# Icon: square crop and polished badge treatment, readable at small Roblox sizes.
im=cover(Image.open(RENDERS/"icon3.png"),(512,512),(.5,.48))
im=ImageEnhance.Color(im).enhance(1.35);im=ImageEnhance.Contrast(im).enhance(1.16)
vignette(im,70)
label(im,"?",(128,100),140,YELLOW,16,-12)
ImageDraw.Draw(im).rounded_rectangle((8,8,503,503),radius=36,outline=(*WHITE,255),width=12)
im.convert("RGB").save(OUT/"icon.png")
