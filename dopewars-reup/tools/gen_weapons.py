#!/usr/bin/env python3
"""Generate data/weapons.json — the weapon catalog with REAL US legal mechanics.

Two acquisition paths, like the rest of the game's realism:
  - LEGAL (FFL / knife shop): real-world prices, background check (NICS), a serial number ON RECORD
    (traceable), age gates. NFA classes (full-auto, suppressors, destructive devices) legally need an
    ATF Form 4, a $200 tax stamp, a months-long wait, and only pre-'86 transferables — so they're
    priced absurdly high + slow, i.e. realistically out of reach for a street operator.
  - BLACK MARKET: no serial (filed/none), no check, faster — but illegal to possess, adds heat, and
    scam/bust risk. This is the real path for anything NFA.

Prices are gameplay dollars anchored to real ballparks. Names are generic/parody (trademark-safe),
matching the game's brand-parody convention. Not a how-to: no mechanics of making/using anything.
"""
import json, os

OUT = os.path.join(os.path.dirname(__file__), "..", "data", "weapons.json")

# category → legal rule profile
LAW = {
  "knife":   dict(ffl=False, nfa=False, check=False, min_age=18, legal=True,  note="Generally legal to buy; carry laws vary."),
  "shiv":    dict(ffl=False, nfa=False, check=False, min_age=0,  legal=False, note="Improvised. Illegal to carry concealed; black-market/craft only."),
  "handgun": dict(ffl=True,  nfa=False, check=True,  min_age=21, legal=True,  note="FFL + NICS check, 21+, serialized and on record."),
  "rifle":   dict(ffl=True,  nfa=False, check=True,  min_age=18, legal=True,  note="FFL + NICS check, 18+, serialized."),
  "shotgun": dict(ffl=True,  nfa=False, check=True,  min_age=18, legal=True,  note="FFL + NICS check, 18+, serialized."),
  "smg":     dict(ffl=True,  nfa=True,  check=True,  min_age=21, legal=True,  note="Full-auto = NFA: Form 4, $200 stamp, ~10-month wait, transferable-only."),
  "machinegun": dict(ffl=True, nfa=True, check=True, min_age=21, legal=True,  note="NFA belt-fed; legal transferables are rare + extremely expensive."),
  "explosive": dict(ffl=True, nfa=True, check=True,  min_age=21, legal=False, note="Destructive device (NFA). Effectively unobtainable legally."),
}

# (name, category, legal_price, bm_price, weight_lb, threat)  — threat is a combat stat for fights later.
ITEMS = [
  # knives (legal, cheap, no FFL)
  ("Folding pocket knife","knife",25,15,0.2,2),("Hunting fixed blade","knife",80,60,0.6,3),
  ("Combat utility knife","knife",70,55,0.7,4),("Karambit","knife",90,70,0.4,4),
  ("Bowie knife","knife",110,80,1.1,4),("Switchblade","knife",60,50,0.3,3),
  ("Butterfly knife","knife",45,40,0.3,3),("Machete","knife",40,30,1.4,4),
  ("Cleaver","knife",35,25,1.2,3),("Tactical tanto","knife",130,95,0.7,4),
  # shivs (illegal / improvised — black market only)
  ("Toothbrush shank","shiv",0,20,0.1,2),("Sharpened spoon","shiv",0,15,0.1,1),
  ("Glass shard wrap","shiv",0,10,0.1,2),("Filed rebar spike","shiv",0,25,0.5,3),
  ("Prison-made shank","shiv",0,40,0.2,3),("Ice-pick shiv","shiv",0,30,0.2,3),
  ("Razor knuckles","shiv",0,35,0.2,2),("Screwdriver shiv","shiv",0,18,0.3,2),
  ("Bike-spoke pick","shiv",0,12,0.1,2),("Padlock-in-sock","shiv",0,8,0.6,2),
  # handguns (FFL, serialized)
  ("Striker 9 Compact","handgun",520,650,1.5,5),("M&P-pattern 9mm","handgun",480,600,1.6,5),
  ("P320-pattern 9mm","handgun",550,700,1.7,5),("Pocket .380","handgun",280,400,0.8,4),
  ("1911 .45","handgun",700,850,2.4,6),("92-pattern 9mm","handgun",600,720,2.1,5),
  (".38 snub revolver","handgun",400,520,1.4,4),("Hand-cannon .50","handgun",1800,2400,4.5,7),
  ("Budget 9mm (Hi-Point-ish)","handgun",180,300,2.4,4),("Polymer .40","handgun",420,560,1.6,5),
  # rifles (FFL)
  ("AR-pattern 5.56","rifle",900,1600,6.5,7),("AK-pattern 7.62","rifle",950,1700,7.5,7),
  (".22 plinker","rifle",300,450,4.5,3),("Bolt-action hunter .308","rifle",700,1000,7.8,6),
  ("Mini ranch rifle","rifle",1100,1600,6.8,6),("SKS 7.62","rifle",500,800,8.5,6),
  ("Lever-action .30-30","rifle",600,850,6.7,5),("Precision .308","rifle",1600,2400,9.5,7),
  ("PCC 9mm carbine","rifle",650,950,6.0,5),("Battle rifle .308","rifle",1900,2900,9.2,7),
  # shotguns
  ("Pump 12ga","shotgun",350,550,7.0,6),("Tactical pump 12ga","shotgun",500,750,7.2,6),
  ("Semi-auto 12ga","shotgun",800,1200,7.5,6),("Double-barrel","shotgun",450,650,6.8,5),
  ("Sawed-off (illegal SBS)","shotgun",0,900,5.5,6),("Youth 20ga","shotgun",300,450,6.0,4),
  ("Riot 12ga","shotgun",600,900,7.4,6),("Bullpup 12ga","shotgun",1100,1700,7.0,6),
  ("Coach gun","shotgun",400,600,6.5,5),("Mag-fed 12ga","shotgun",700,1100,7.8,6),
  # submachine guns (NFA full-auto — legal absurd, black market real)
  ("MP-pattern SMG","smg",22000,3200,6.8,8),("Uzi-pattern SMG","smg",18000,2600,7.7,7),
  ("MAC-pattern machine pistol","smg",12000,1800,6.3,7),("Scorpion-pattern","smg",16000,2400,5.0,7),
  ("Grease-gun style","smg",14000,2000,8.0,6),("PPSh-pattern","smg",15000,2200,8.0,7),
  ("Micro SMG","smg",20000,2800,5.5,7),("Suppressed SMG","smg",25000,3800,7.2,8),
  ("Sten-pattern","smg",13000,1600,6.5,6),("P90-pattern PDW","smg",28000,4200,6.6,8),
  # machine guns (NFA belt-fed)
  ("Squad LMG 5.56","machinegun",35000,6500,17.0,9),("GPMG 7.62","machinegun",45000,9000,24.0,9),
  ("Belt-fed .50 HMG","machinegun",120000,20000,84.0,10),("Light MG carbine","machinegun",30000,5500,12.0,8),
  ("PKM-pattern","machinegun",40000,7500,17.5,9),("M60-pattern","machinegun",42000,8000,23.0,9),
  ("Minigun (display)","machinegun",250000,45000,60.0,10),("RPK-pattern LMG","machinegun",28000,5000,11.0,8),
  ("MG42-pattern","machinegun",55000,10000,25.0,9),("Vintage BAR","machinegun",38000,7000,19.0,8),
  # explosives (destructive devices — black market only, high heat)
  ("Pipe device","explosive",0,400,2.0,8),("Frag grenade","explosive",0,900,1.0,9),
  ("Composition brick","explosive",0,3500,1.3,10),("Stick charge","explosive",0,600,0.5,8),
  ("Molotov","explosive",0,20,1.5,5),("Improvised roadside device","explosive",0,1200,6.0,10),
  ("Smoke/incendiary","explosive",0,150,1.2,6),("Det cord bundle","explosive",0,800,2.0,8),
  ("Thermite pack","explosive",0,700,1.8,8),("Breaching charge","explosive",0,1500,2.5,9),
]

def slug(s):
    import re
    return re.sub(r'[^a-z0-9]+','_', s.lower()).strip('_')

items=[]; seen=set()
for name,cat,legal_price,bm_price,wt,threat in ITEMS:
    law=LAW[cat]
    wid=f"{cat}_{slug(name)}"
    while wid in seen: wid+="_x"
    seen.add(wid)
    # NFA legal wait/stamp; legal availability off if legal_price==0 (illegal item) or law says illegal.
    legal_ok = law["legal"] and legal_price>0
    items.append({
      "id":wid,"name":name,"category":cat,"weight_lb":wt,"threat":threat,
      "legal":{"available":legal_ok,"price":legal_price if legal_ok else None,
               "ffl_required":law["ffl"],"nics_check":law["check"],"min_age":law["min_age"],
               "serialized":True,"nfa":law["nfa"],
               "tax_stamp":200 if law["nfa"] else 0,
               "wait_days":(300 if law["nfa"] else (3 if law["ffl"] else 0))},
      "black_market":{"available":bm_price>0,"price":bm_price,"serial":"filed" if law["ffl"] else "none",
                      "heat":min(10, threat + (3 if law["nfa"] else (1 if law["ffl"] else 0)))},
      "law_note":law["note"],
    })

by_cat={}
for it in items: by_cat[it["category"]]=by_cat.get(it["category"],0)+1
doc={"_comment":"Weapon catalog with real US legal mechanics. legal = FFL/knife-shop path (NICS check, "
     "serial on record, age gate, NFA = Form 4 + $200 stamp + ~10mo wait, transferable-only). "
     "black_market = no/filed serial, illegal, adds heat + bust/scam risk. Not instructional. "
     "Generic/parody names.", "categories":by_cat, "weapons":items}
open(OUT,"w").write(json.dumps(doc,indent=1))
print(f"wrote {len(items)} weapons across {len(by_cat)} categories: {by_cat}")
