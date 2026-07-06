#!/usr/bin/env python3
"""Generate 100 curated cosmetic items -> 0011_cosmetics_seed.sql.
Cosmetics are flair only. store items cost CRED (earned currency); supporter/award items are
granted, never bought (source != 'store' => not purchasable). No item affects gameplay."""
import re

COST = {"common":250,"uncommon":500,"rare":1200,"epic":3000,"legendary":7000,"mythic":15000,"exclusive":0}

# (name, category, rarity, source, supporter_only)  — curated, on-tone (rust-belt / The Wire / street)
ITEMS = [
 # --- emblems (20) ---
 ("Corner Crown","emblem","uncommon","store",False),("The Re-Up","emblem","rare","store",False),
 ("Kilo Club","emblem","epic","store",False),("Burner","emblem","common","store",False),
 ("Evidence Bag","emblem","uncommon","store",False),("Trap King","emblem","legendary","store",False),
 ("Ghost Protocol","emblem","epic","store",False),("Wolf of Wolfline","emblem","rare","store",False),
 ("Concrete Rose","emblem","rare","store",False),("Rust Belt","emblem","common","store",False),
 ("Nightshift","emblem","uncommon","store",False),("The Connect","emblem","legendary","store",False),
 ("Skeleton Key","emblem","epic","store",False),("Dead Presidents","emblem","rare","store",False),
 ("Cut & Cook","emblem","uncommon","store",False),("Steel City","emblem","common","store",False),
 ("Bag Secured","emblem","rare","store",False),("No Face","emblem","mythic","store",False),
 ("The Ledger","emblem","epic","store",False),("Off the Books","emblem","uncommon","store",False),
 # --- titles (20) ---
 ("The Connect","title","legendary","store",False),("Ghost","title","epic","store",False),
 ("Trap Star","title","rare","store",False),("Made","title","legendary","store",False),
 ("Kingpin","title","mythic","store",False),("Corner Boy","title","common","store",False),
 ("The Plug","title","epic","store",False),("Wholesale","title","rare","store",False),
 ("Untouchable","title","mythic","store",False),("Snitch's Nightmare","title","rare","store",False),
 ("Certified","title","uncommon","store",False),("Heavy","title","uncommon","store",False),
 ("On Sight","title","common","store",False),("The Chemist","title","epic","store",False),
 ("Numbers Man","title","rare","store",False),("Weight Class","title","uncommon","store",False),
 ("First of the Month","title","common","store",False),("Franchise","title","legendary","store",False),
 ("The Fixer","title","epic","store",False),("Retired (Allegedly)","title","legendary","earned",False),
 # --- nameplates (15) ---
 ("Concrete","nameplate","common","store",False),("Neon Alley","nameplate","uncommon","store",False),
 ("Evidence Locker","nameplate","rare","store",False),("Rust & Rain","nameplate","uncommon","store",False),
 ("Blacktop","nameplate","common","store",False),("Pill Bottle","nameplate","rare","store",False),
 ("Turnpike","nameplate","common","store",False),("Riverfront","nameplate","uncommon","store",False),
 ("Section 8","nameplate","rare","store",False),("Cut Corners","nameplate","uncommon","store",False),
 ("Cold Open","nameplate","epic","store",False),("Static","nameplate","common","store",False),
 ("Burner Static","nameplate","uncommon","store",False),("Trap House 3AM","nameplate","epic","store",False),
 ("Gold Foil","nameplate","legendary","supporter",True),
 # --- frames (10) ---
 ("Barbed Wire","frame","common","store",False),("Chain Link","frame","common","store",False),
 ("Gold Chain","frame","legendary","supporter",True),("Police Tape","frame","uncommon","store",False),
 ("Duct Tape","frame","common","store",False),("Neon Trim","frame","rare","store",False),
 ("Brick","frame","uncommon","store",False),("Chrome","frame","epic","store",False),
 ("Blood Money","frame","mythic","supporter",True),("Founder's Laurel","frame","exclusive","supporter",True),
 # --- accents / name colors (10) ---
 ("Re-Up Red","accent","uncommon","store",False),("Evidence Yellow","accent","uncommon","store",False),
 ("Money Green","accent","rare","store",False),("Cold Blue","accent","common","store",False),
 ("Bruise Purple","accent","rare","store",False),("Ash Grey","accent","common","store",False),
 ("Uncut White","accent","epic","store",False),("Hazard Orange","accent","uncommon","store",False),
 ("Solid Gold","accent","legendary","supporter",True),("Blackout","accent","mythic","store",False),
 # --- badges (12) mostly earned / award ---
 ("First Kilo","badge","common","earned",False),("Clean Record","badge","rare","earned",False),
 ("Ten Trips","badge","uncommon","earned",False),("Marathon","badge","epic","earned",False),
 ("Made Man","badge","legendary","earned",False),("Survivor","badge","epic","earned",False),
 ("High Roller","badge","rare","earned",False),("Beta Pioneer","badge","exclusive","award",False),
 ("Bug Bounty","badge","exclusive","award",False),("Community Award","badge","exclusive","award",False),
 ("Ghost (Never Seen)","badge","mythic","earned",False),("Founder","badge","exclusive","supporter",True),
 # --- markers (5) ---
 ("Red Dot","marker","common","store",False),("Crosshair","marker","uncommon","store",False),
 ("Skull Pin","marker","rare","store",False),("Dollar Pin","marker","uncommon","store",False),
 ("Ghost Pin","marker","epic","store",False),
 # --- tags / graffiti (5) ---
 ("RE-UP Tag","tag","uncommon","store",False),("Crown Tag","tag","rare","store",False),
 ("Wolf Tag","tag","rare","store",False),("Skull Tag","tag","uncommon","store",False),
 ("Dollar Tag","tag","common","store",False),
 # --- phone charms / cases (3) ---
 ("Burner Charm","charm","common","store",False),("Gold Grillz Charm","charm","legendary","supporter",True),
 ("Evidence Tag Charm","charm","uncommon","store",False),
]

def slug(s): return re.sub(r'[^a-z0-9]+','_', s.lower()).strip('_')
def esc(s): return s.replace("'","''")

seen=set(); rows=[]
for name,cat,rar,src,sup in ITEMS:
    cid=f"{cat}_{slug(name)}"
    while cid in seen: cid+="_x"
    seen.add(cid)
    cost = 0 if src!="store" else COST[rar]
    desc = f"{rar.capitalize()} {cat} cosmetic. Flair only — no gameplay effect."
    rows.append("('{}','{}','{}','{}',{},{},'{}','{}')".format(
        cid, esc(name), cat, rar, cost, 'true' if sup else 'false', src, esc(desc)))

sql = ("-- 0011_cosmetics_seed.sql — 100 curated cosmetics. store=buyable w/ CRED; supporter/award/earned = granted.\n"
       "insert into cosmetics (id,name,category,rarity,cred_cost,supporter_only,source,description) values\n"
       + ",\n".join(rows) + "\non conflict (id) do update set name=excluded.name, rarity=excluded.rarity,\n"
       "  cred_cost=excluded.cred_cost, supporter_only=excluded.supporter_only, source=excluded.source;\n")
open("/var/home/reaver/Documents/GitHub/dopewars/backend/supabase/migrations/0011_cosmetics_seed.sql","w").write(sql)
print(f"wrote {len(rows)} cosmetics")
