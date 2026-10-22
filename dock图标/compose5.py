# -*- coding: utf-8 -*-
"""v5 最终版：14 张 AI 拟人角色卡头像 → 贴纸徽章图标。"""
import os
from PIL import Image, ImageDraw

Q = "/home/dongyu/dock-icons/dl/dy2"
SRC = "/home/dongyu/dock-icons/final5"
os.makedirs(SRC, exist_ok=True)
S = 256
BOX = (18, 288, 345, 628)

def hex2rgb(s): return tuple(int(s[i:i+2], 16) for i in (1, 3, 5))

def sticker_card(top, bot):
    base = Image.new("RGBA",(S,S),(0,0,0,0))
    d = ImageDraw.Draw(base)
    d.rounded_rectangle([6,6,S-7,S-7], radius=64, fill=(255,255,255,255))
    grad = Image.new("RGB",(1,S-28))
    for y in range(S-28):
        t=y/(S-29)
        grad.putpixel((0,y), tuple(round(a+(b-a)*t) for a,b in zip(hex2rgb(top),hex2rgb(bot))))
    mask = Image.new("L",(S-28,S-28),0)
    ImageDraw.Draw(mask).rounded_rectangle([0,0,S-29,S-29],radius=52,fill=255)
    base.paste(grad.resize((S-28,S-28)).convert("RGBA"),(14,14),mask)
    return base

# 卡号: (图标本名, 渐变顶, 渐变底)
CARDS = {
    1:  ("card-deepseek", "#7E96FF", "#3D5AEA"),
    2:  ("card-gpt",      "#D9DCF5", "#9AA3D8"),
    3:  ("card-claude",   "#F0A983", "#D97757"),
    4:  ("card-qwen",     "#A8C8F0", "#4A6ED8"),
    5:  ("card-gemini",   "#8E9BFF", "#5B5FE8"),
    6:  ("card-kimi",     "#DDE4F5", "#8FA3D8"),
    7:  ("card-seed",     "#8FB8F5", "#3F6ED8"),
    8:  ("card-minimax",  "#F5B8C8", "#D85F88"),
    9:  ("card-grok",     "#B08898", "#3A1830"),
    10: ("card-mistral",  "#F5C088", "#D85A1F"),
    11: ("card-hunyuan",  "#D89A9A", "#7A2830"),
    12: ("card-glm",      "#C8B888", "#4A4232"),
    13: ("card-llama",    "#F0D8B8", "#C89858"),
    14: ("card-ernie",    "#88A8E8", "#2A4AC8"),
}
for n,(name,top,bot) in CARDS.items():
    im = Image.open(f"{Q}/card-{n}.png").crop(BOX).convert("RGBA")
    card = sticker_card(top, bot)
    size = round((S-28)*0.88)
    im2 = im.resize((size,size), Image.LANCZOS)
    m = Image.new("L",(size,size),0)
    ImageDraw.Draw(m).rounded_rectangle([0,0,size-1,size-1],radius=round(size*0.16),fill=255)
    card.paste(im2,(14+(S-28-size)//2, 14+(S-28-size)//2), m)
    card.save(f"{SRC}/{name}.png")
print("built", len(CARDS))

import subprocess, time
from PIL import ImageFont
zh = subprocess.run(["fc-match","-f","%{file}","Noto Sans CJK SC:bold"],capture_output=True,text=True).stdout.strip()
font = ImageFont.truetype(zh, 17)
labels = {1:"DeepSeek(共用)",2:"ChatGPT(D盘)",3:"Claude(C盘)",4:"Qwen",5:"Gemini(E盘)",6:"Kimi",7:"Seed",
          8:"MiniMax",9:"Grok",10:"Mistral",11:"混元",12:"GLM(外接默认)",13:"Llama",14:"文心"}
names = list(CARDS)
cell=150
sheet = Image.new("RGB",(5*(cell+10)+10, 3*(cell+48)+10), "#1d1d20")
d2 = ImageDraw.Draw(sheet)
for i,(n,(name,_,_)) in enumerate(CARDS.items()):
    x,y = 10+(i%5)*(cell+10), 10+(i//5)*(cell+48)
    im = Image.open(f"{SRC}/{name}.png").convert("RGBA").resize((cell-12,cell-12), Image.LANCZOS)
    sheet.paste(im,(x,y),im)
    d2.text((x+2,y+cell+4), labels[n], fill="#eeeeee", font=font)
out = f"/home/dongyu/dock-icons/preview-v5-{int(time.time())}.png"
sheet.save(out); print(out)
