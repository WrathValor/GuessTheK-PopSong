from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance, ImageOps

ROOT=Path(__file__).parent
REN=ROOT/'renders'; OUT=ROOT/'final'; OUT.mkdir(exist_ok=True)
W,H=1920,1080
INK=(26,20,46); CREAM=(255,248,232); YELLOW=(255,218,74); PINK=(255,65,142); CYAN=(56,220,245); LILAC=(174,137,255)
FONT=ImageFont.truetype(str(ROOT/'fonts'/'LuckiestGuy-Regular.ttf'),72)
FONT_BIG=ImageFont.truetype(str(ROOT/'fonts'/'LuckiestGuy-Regular.ttf'),132)

def base(name, sat=1.15, contrast=1.12):
    im=Image.open(REN/name).convert('RGB')
    s=max(W/im.width,H/im.height); im=im.resize((round(im.width*s),round(im.height*s)),Image.Resampling.LANCZOS)
    im=im.crop(((im.width-W)//2,(im.height-H)//2,(im.width+W)//2,(im.height+H)//2))
    return ImageEnhance.Contrast(ImageEnhance.Color(im).enhance(sat)).enhance(contrast).convert('RGBA')

def gradient(im, top_alpha=130, bottom_alpha=110):
    shade=Image.new('RGBA',(W,H),(0,0,0,0)); px=shade.load()
    for y in range(H):
        a=int(top_alpha*max(0,1-y/420) + bottom_alpha*max(0,(y-760)/320))
        for x in range(W): px[x,y]=(*INK,a)
    im.alpha_composite(shade)

def text_layer(text, font, fill, stroke=12, stroke_fill=INK):
    d=ImageDraw.Draw(Image.new('RGBA',(1,1))); box=d.textbbox((0,0),text,font=font,stroke_width=stroke)
    layer=Image.new('RGBA',(box[2]-box[0]+44,box[3]-box[1]+44),(0,0,0,0)); q=ImageDraw.Draw(layer)
    q.text((22-box[0],22-box[1]),text,font=font,fill=fill,stroke_width=stroke,stroke_fill=stroke_fill)
    return layer

def centered(im,text,y,font,fill,stroke=12):
    layer=text_layer(text,font,fill,stroke); im.alpha_composite(layer,((W-layer.width)//2,y))

def pill(im,text,box,fill,fs=42):
    d=ImageDraw.Draw(im); x1,y1,x2,y2=box
    d.rounded_rectangle((x1+9,y1+13,x2+9,y2+13),radius=30,fill=INK)
    d.rounded_rectangle(box,radius=30,fill=fill,outline=INK,width=9)
    f=ImageFont.truetype(str(ROOT/'fonts'/'BuilderSans-ExtraBold.otf'),fs)
    b=d.textbbox((0,0),text,font=f); d.text(((x1+x2-b[2]+b[0])//2,(y1+y2-b[3]+b[1])//2-2),text,font=f,fill=INK)

# Daily song: preserve the actual playable screen; give the daily mechanic an immediate read.
im=base('thumb_daily_draft.png',1.22,1.15)
gradient(im,155,130)
# Quiet title band, keeping the question panel and the avatar unobstructed.
d=ImageDraw.Draw(im)
d.rounded_rectangle((48,34,1872,236),radius=38,fill=(26,20,46,228),outline=(255,248,232,235),width=7)
centered(im,'GUESS THE K-POP SONG',55,FONT_BIG,CREAM,13)
pill(im,'DAILY SONG CHALLENGE',(95,825,895,945),YELLOW,40)
pill(im,'NEW SONG EVERY DAY',(1025,825,1825,945),PINK,40)
# Small sound-wave accent near the quiz card's playback control.
d=ImageDraw.Draw(im)
for i,h in enumerate([28,48,72,42,62,33,53]):
    x=1640+i*24; d.rounded_rectangle((x,700-h//2,x+12,700+h//2),radius=6,fill=CYAN)
d.rectangle((12,12,W-12,H-12),outline=CREAM,width=10)
im.convert('RGB').save(OUT/'thumbnail_daily_song.png',quality=95)

# Party stage: use the real in-game stage and show six distinct player spots as custom tokens.
im=base('duel_stage.png',1.28,1.18)
# Keep the scene readable behind the title and six-seat strip.
shade=Image.new('RGBA',(W,H),(12,7,32,30)); im.alpha_composite(shade)
d=ImageDraw.Draw(im)
d.rectangle((0,0,W,218),fill=(24,14,54,226))
centered(im,'GUESS THE K-POP SONG',18,FONT,CREAM,11)
centered(im,'PARTY STAGE',99,FONT_BIG,YELLOW,14)
# Six separate blocky player tokens echo the Roblox avatars without cloning either render.
colors=[(255,91,145),(74,213,245),(255,193,74),(160,122,255),(109,222,150),(255,131,64)]
hairs=[(67,43,36),(38,34,60),(255,151,48),(35,30,48),(101,59,40),(65,46,70)]
centers=[170,486,802,1118,1434,1750]
for i,cx in enumerate(centers):
    y=730
    # sticker shadow, head, hair and simple face
    d.ellipse((cx-92,y-22,cx+92,y+158),fill=(14,10,32,210))
    d.rounded_rectangle((cx-60,y+57,cx+60,y+176),radius=20,fill=INK,outline=CREAM,width=6)
    d.rounded_rectangle((cx-49,y+66,cx+49,y+165),radius=16,fill=colors[i])
    d.rounded_rectangle((cx-54,y-70,cx+54,y+53),radius=15,fill=CREAM,outline=INK,width=8)
    d.rounded_rectangle((cx-57,y-82,cx+57,y-34),radius=17,fill=hairs[i],outline=INK,width=6)
    d.ellipse((cx-27,y-20,cx-12,y-5),fill=INK); d.ellipse((cx+12,y-20,cx+27,y-5),fill=INK)
    d.arc((cx-20,y-2,cx+20,y+24),5,175,fill=INK,width=5)
    d.ellipse((cx-65,y+174,cx+65,y+208),fill=colors[i],outline=INK,width=7)
    nf=ImageFont.truetype(str(ROOT/'fonts'/'LuckiestGuy-Regular.ttf'),31)
    nb=d.textbbox((0,0),str(i+1),font=nf)
    d.text((cx-(nb[2]-nb[0])//2,y+176-(nb[1])//2),str(i+1),font=nf,fill=INK)
# Front ribbon has the core promise at a size that survives Roblox's small thumbnail crop.
d.rectangle((0,938,W,H),fill=(24,14,54,244))
centered(im,'UP TO 6 PLAYERS  •  NAME THAT SONG!',946,FONT,CREAM,12)
d=ImageDraw.Draw(im); d.rectangle((12,12,W-12,H-12),outline=YELLOW,width=10)
im.convert('RGB').save(OUT/'thumbnail_party_stage.png',quality=95)
