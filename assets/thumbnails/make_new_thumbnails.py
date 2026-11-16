"""Create original, character-free Roblox thumbnails for Guess The K-Pop Song."""
from pathlib import Path
import math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).parent
OUT = ROOT / "new_set"
OUT.mkdir(exist_ok=True)
W, H = 1920, 1080
INK = (20, 22, 55)
WHITE = (255, 250, 239)
YELLOW = (255, 222, 54)
PINK = (255, 49, 150)
CYAN = (26, 220, 255)
PURPLE = (124, 74, 255)
FONT = ROOT / "fonts" / "LuckiestGuy-Regular.ttf"
BODY = ROOT / "fonts" / "BuilderSans-ExtraBold.otf"

def f(size, body=False):
    return ImageFont.truetype(str(BODY if body else FONT), size)

def burst(c, center=(960, 440), base=(14, 137, 250), rays=20):
    d = ImageDraw.Draw(c)
    d.rectangle((0, 0, W, H), fill=base)
    cx, cy = center
    r = 2400
    for i in range(rays):
        if i % 2 == 0:
            a0 = 2 * math.pi * i / rays
            a1 = 2 * math.pi * (i + 1) / rays
            d.polygon([(cx, cy), (cx + math.cos(a0)*r, cy + math.sin(a0)*r),
                       (cx + math.cos(a1)*r, cy + math.sin(a1)*r)], fill=(35, 164, 255))
    # light grain-like halftone dots in the corners
    for y in range(18, H, 52):
        for x in range(18, W, 52):
            if ((x-cx)**2 + (y-cy)**2) > 560**2:
                d.ellipse((x-3, y-3, x+3, y+3), fill=(128, 219, 255))

def label(c, text, xy, size, fill=WHITE, angle=0, anchor="mm", stroke=15):
    ft = f(size)
    box = ft.getbbox(text, stroke_width=stroke)
    layer = Image.new("RGBA", (box[2]-box[0]+60, box[3]-box[1]+70), (0,0,0,0))
    d = ImageDraw.Draw(layer)
    x, y = 30-box[0], 24-box[1]
    d.text((x+10,y+15), text, font=ft, fill=INK, stroke_width=stroke+7, stroke_fill=INK)
    d.text((x,y), text, font=ft, fill=fill, stroke_width=stroke, stroke_fill=INK)
    if angle: layer = layer.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)
    px, py = xy
    if anchor[0] == "m": px -= layer.width/2
    elif anchor[0] == "r": px -= layer.width
    if anchor[1] == "m": py -= layer.height/2
    elif anchor[1] == "b": py -= layer.height
    c.alpha_composite(layer, (round(px), round(py)))

def pill(c, text, box, fill=YELLOW, size=38):
    d = ImageDraw.Draw(c)
    x1,y1,x2,y2=box
    d.rounded_rectangle((x1+12,y1+14,x2+12,y2+14),radius=34,fill=INK)
    d.rounded_rectangle(box,radius=34,fill=fill,outline=INK,width=11)
    ft=f(size,True); b=d.textbbox((0,0),text,font=ft)
    d.text(((x1+x2-b[2]+b[0])/2,(y1+y2-b[3]+b[1])/2-2),text,font=ft,fill=INK)

def avatar(c, cx, ground, shirt, hair, pose=0, scale=1.0, face=(255,220,184)):
    """A fresh, simple block avatar drawn from shapes; no project character assets."""
    d=ImageDraw.Draw(c)
    s=scale
    # thick graphic shadow
    d.ellipse((cx-72*s,ground-32*s,cx+75*s,ground+8*s),fill=(8,32,90))
    # legs and shoes
    d.polygon([(cx-42*s,ground-115*s),(cx-4*s,ground-110*s),(cx-15*s,ground-18*s),(cx-55*s,ground-18*s)],fill=(24,32,72),outline=INK)
    d.polygon([(cx+4*s,ground-110*s),(cx+44*s,ground-115*s),(cx+60*s,ground-18*s),(cx+19*s,ground-18*s)],fill=(24,32,72),outline=INK)
    d.rounded_rectangle((cx-67*s,ground-28*s,cx-10*s,ground-4*s),radius=9*s,fill=WHITE,outline=INK,width=max(2,int(5*s)))
    d.rounded_rectangle((cx+12*s,ground-28*s,cx+69*s,ground-4*s),radius=9*s,fill=WHITE,outline=INK,width=max(2,int(5*s)))
    # torso and neck
    d.rounded_rectangle((cx-62*s,ground-252*s,cx+62*s,ground-106*s),radius=22*s,fill=shirt,outline=INK,width=max(3,int(8*s)))
    d.rectangle((cx-18*s,ground-278*s,cx+18*s,ground-239*s),fill=face,outline=INK,width=max(2,int(4*s)))
    # raised arm / fist for high-energy poses
    if pose:
        d.polygon([(cx+42*s,ground-231*s),(cx+76*s,ground-246*s),(cx+110*s,ground-324*s),(cx+139*s,ground-311*s),(cx+102*s,ground-196*s),(cx+62*s,ground-176*s)],fill=face,outline=INK)
        d.ellipse((cx+107*s,ground-350*s,cx+151*s,ground-309*s),fill=face,outline=INK,width=max(2,int(5*s)))
    else:
        d.polygon([(cx-50*s,ground-229*s),(cx-81*s,ground-190*s),(cx-127*s,ground-158*s),(cx-109*s,ground-129*s),(cx-47*s,ground-161*s),(cx-21*s,ground-195*s)],fill=face,outline=INK)
    # large head and distinct hairstyle
    d.rounded_rectangle((cx-66*s,ground-382*s,cx+66*s,ground-267*s),radius=24*s,fill=face,outline=INK,width=max(3,int(8*s)))
    if pose % 3 == 0:
        d.polygon([(cx-72*s,ground-346*s),(cx-62*s,ground-401*s),(cx-30*s,ground-375*s),(cx-1*s,ground-416*s),(cx+24*s,ground-373*s),(cx+67*s,ground-395*s),(cx+72*s,ground-331*s),(cx+35*s,ground-354*s),(cx-2*s,ground-342*s),(cx-35*s,ground-360*s)],fill=hair,outline=INK)
    elif pose % 3 == 1:
        d.ellipse((cx-72*s,ground-402*s,cx+73*s,ground-334*s),fill=hair,outline=INK,width=max(3,int(6*s)))
        d.rectangle((cx-69*s,ground-362*s,cx+68*s,ground-338*s),fill=hair)
    else:
        d.polygon([(cx-74*s,ground-344*s),(cx-65*s,ground-410*s),(cx+8*s,ground-421*s),(cx+73*s,ground-379*s),(cx+67*s,ground-326*s),(cx+29*s,ground-356*s),(cx-10*s,ground-341*s)],fill=hair,outline=INK)
    # delighted face
    d.ellipse((cx-36*s,ground-330*s,cx-23*s,ground-317*s),fill=INK)
    d.ellipse((cx+22*s,ground-330*s,cx+35*s,ground-317*s),fill=INK)
    d.arc((cx-24*s,ground-319*s,cx+25*s,ground-286*s),5,175,fill=INK,width=max(2,int(5*s)))

def sound_card(c, box, caption="WHO SANG IT?"):
    x1,y1,x2,y2=box; d=ImageDraw.Draw(c)
    d.rounded_rectangle((x1+14,y1+18,x2+14,y2+18),radius=34,fill=INK)
    d.rounded_rectangle(box,radius=34,fill=(25,20,57),outline=WHITE,width=9)
    # album icon with question mark
    d.rounded_rectangle((x1+30,y1+34,x1+225,y2-35),radius=22,fill=PURPLE,outline=INK,width=8)
    d.ellipse((x1+77,y1+75,x1+177,y1+175),fill=YELLOW,outline=INK,width=7)
    label(c,"?",(x1+127,y1+123),88,WHITE,stroke=7)
    # colorful waveform and play button
    mid=(y1+y2)//2+5
    for i,h in enumerate((35,70,112,58,135,80,48,112,62,135,75,42)):
        x=x1+264+i*31
        d.rounded_rectangle((x,mid-h//2,x+16,mid+h//2),radius=8,fill=(CYAN,PINK,YELLOW)[i%3])
    d.ellipse((x2-149,mid-58,x2-33,mid+58),fill=YELLOW,outline=INK,width=8)
    d.polygon([(x2-103,mid-29),(x2-103,mid+29),(x2-55,mid)],fill=INK)
    ft=f(34,True); b=d.textbbox((0,0),caption,font=ft)
    d.text((x1+254,y1+20),caption,font=ft,fill=WHITE,stroke_width=2,stroke_fill=INK)

def answer_tiles(c, x, y, labels=("A", "B", "C")):
    d=ImageDraw.Draw(c)
    cols=(PINK,CYAN,YELLOW)
    for i,t in enumerate(labels):
        bx=x+i*183
        d.rounded_rectangle((bx+8,y+11,bx+170,y+92),radius=19,fill=INK)
        d.rounded_rectangle((bx,y,bx+162,y+82),radius=19,fill=cols[i],outline=INK,width=7)
        ft=f(39,True); bb=d.textbbox((0,0),t,font=ft)
        d.text((bx+(162-(bb[2]-bb[0]))/2,y+19),t,font=ft,fill=INK)

def main_thumbnail():
    c=Image.new("RGBA",(W,H)); burst(c,(980,500))
    # diagonal color accents
    d=ImageDraw.Draw(c)
    d.polygon([(0,0),(520,0),(0,330)],fill=(31,219,255))
    label(c,"GUESS THE K-POP SONG",(960,128),112,WHITE,stroke=16)
    # Three original players reacting to the mystery clip
    avatar(c,330,1002,(255,69,142),(68,39,94),1,1.12)
    avatar(c,1595,1000,(255,193,36),(31,33,53),0,1.12)
    sound_card(c,(535,275,1385,550))
    answer_tiles(c,602,590,("SONG A","SONG B","SONG C"))
    pill(c,"HEAR A CLIP • NAME THAT SONG",(367,830,1553,936),YELLOW,43)
    return c.convert("RGB")

def party_thumbnail():
    c=Image.new("RGBA",(W,H)); burst(c,(970,480),(23,114,228),24)
    d=ImageDraw.Draw(c)
    # stage deck
    d.polygon([(0,733),(1920,733),(1920,1080),(0,1080)],fill=(25,20,63),outline=INK)
    d.polygon([(0,733),(1920,733),(1810,850),(110,850)],fill=(255,51,154),outline=INK)
    d.line((0,744,1920,744),fill=CYAN,width=20)
    # six independently designed players in a lineup
    shirts=[PINK,CYAN,YELLOW,PURPLE,(74,232,146),(255,132,47)]
    hairs=[(52,39,73),(30,29,58),(236,104,34),(41,34,61),(82,52,41),(49,39,73)]
    for i,cx in enumerate((165,480,795,1110,1425,1740)):
        avatar(c,cx,848,shirts[i],hairs[i],i%3,0.72)
        d=ImageDraw.Draw(c)
        d.ellipse((cx-30,805,cx+30,865),fill=YELLOW,outline=INK,width=6)
        ft=f(34); bb=d.textbbox((0,0),str(i+1),font=ft)
        d.text((cx-(bb[2]-bb[0])/2,808),str(i+1),font=ft,fill=INK)
    label(c,"PARTY STAGE!",(960,132),150,YELLOW,stroke=19)
    sound_card(c,(580,270,1340,500),"GUESS THE K-POP SONG")
    # callout badge
    d=ImageDraw.Draw(c)
    d.ellipse((1440,238,1808,606),fill=PINK,outline=INK,width=18)
    label(c,"6",(1623,352),174,WHITE,stroke=18)
    label(c,"PLAYERS",(1623,485),51,WHITE,stroke=8)
    pill(c,"PLAY WITH FRIENDS • UP TO 6 PLAYERS",(353,938,1567,1040),YELLOW,38)
    return c.convert("RGB")

def duel_thumbnail():
    c=Image.new("RGBA",(W,H)); burst(c,(960,460),(26,131,244),18)
    d=ImageDraw.Draw(c)
    d.polygon([(0,0),(970,0),(700,1080),(0,1080)],fill=(255,51,142,105))
    d.polygon([(1920,0),(950,0),(1220,1080),(1920,1080)],fill=(50,82,255,115))
    label(c,"GUESS THE K-POP SONG",(960,140),103,WHITE,stroke=15)
    avatar(c,430,976,(255,76,145),(49,36,72),1,1.25)
    avatar(c,1490,976,(62,222,255),(251,145,49),1,1.25)
    d.ellipse((795,407,1125,737),fill=YELLOW,outline=INK,width=22)
    label(c,"VS",(960,568),132,WHITE,stroke=14)
    sound_card(c,(545,765,1375,955),"NAME THE SONG TO WIN")
    return c.convert("RGB")

def daily_thumbnail():
    c=Image.new("RGBA",(W,H)); burst(c,(950,460),(102,65,207),18)
    d=ImageDraw.Draw(c)
    # giant calendar / countdown card
    d.rounded_rectangle((1035,260,1745,850),radius=46,fill=WHITE,outline=INK,width=20)
    d.rounded_rectangle((1035,260,1745,420),radius=42,fill=PINK,outline=INK,width=20)
    d.rectangle((1038,365,1742,430),fill=PINK)
    for x in (1190,1580):
        d.rounded_rectangle((x-28,218,x+28,330),radius=20,fill=YELLOW,outline=INK,width=9)
    label(c,"DAILY",(1390,342),82,WHITE,stroke=12)
    label(c,"SONG",(1390,592),148,PURPLE,stroke=16)
    # clue strip and attempts
    sound_card(c,(1070,680,1710,850),"5 TRIES")
    avatar(c,515,1002,(64,220,248),(244,133,40),1,1.35)
    label(c,"CAN YOU",(490,165),79,WHITE,stroke=12)
    label(c,"GUESS TODAY'S",(490,260),70,YELLOW,stroke=12)
    label(c,"K-POP HIT?",(490,353),95,WHITE,stroke=13)
    pill(c,"ONE NEW SONG EVERY DAY",(277,862,985,967),YELLOW,39)
    return c.convert("RGB")

if __name__ == "__main__":
    for name, fn in (("thumbnail_main.png",main_thumbnail),
                     ("thumbnail_party_6_players.png",party_thumbnail),
                     ("thumbnail_1v1_duel.png",duel_thumbnail),
                     ("thumbnail_daily_song.png",daily_thumbnail)):
        fn().save(OUT/name, optimize=True)
        print(OUT/name)
