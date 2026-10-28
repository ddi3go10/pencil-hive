import json, math, os
def poly(*pts): return {"type":"polygon","points":[list(p) for p in pts]}
def ell(cx,cy,rx,ry): return {"type":"ellipse","cx":cx,"cy":cy,"rx":rx,"ry":ry}
def rect(x,y,w,h,r=0): return {"type":"rect","x":x,"y":y,"w":w,"h":h,"radius":r}
def star(cx,cy,ro,ri,n=5):
    pts=[]
    for i in range(n*2):
        a=-math.pi/2+i*math.pi/n; r=ro if i%2==0 else ri
        pts.append((round(cx+r*math.cos(a),1),round(cy+r*math.sin(a),1)))
    return poly(*pts)
def reg(i,color,shape): return {"id":i,"color":color,"shape":shape}

L1 = {"id":1,"name":"Sunny Cottage","pencilSize":3,"boardRadius":2,"removed":[[2,-2],[-2,2]],
 "artwork":{"name":"Sunny Cottage","paper":"#FFF6DC","regions":[
   reg(1,"sky",rect(0,0,150,100)),
   reg(2,"lemon",ell(118,26,15,15)),
   reg(3,"mint",poly((0,70),(30,58),(70,64),(110,54),(150,62),(150,100),(0,100))),
   reg(4,"lemon",rect(42,56,52,32,2)),
   reg(5,"coral",poly((34,58),(68,30),(102,58)))],
  "lineArt":[rect(62,70,12,18,2),rect(48,62,9,9),rect(80,62,9,9)]}}
L2 = {"id":2,"name":"Little Fox","pencilSize":4,"boardRadius":2,"removed":[[2,-2],[-2,2]],
 "artwork":{"name":"Little Fox","paper":"#FFF6DC","regions":[
   reg(1,"sky",rect(0,0,150,100)),
   reg(2,"lemon",ell(122,22,13,13)),
   reg(3,"mint",rect(0,72,150,28)),
   reg(4,"coral",poly((26,66),(6,44),(32,46),(48,72))),
   reg(5,"amber",ell(70,66,28,16)),
   reg(6,"rose",poly((92,48),(94,28),(103,40),(109,40),(118,28),(120,48))),
   reg(7,"amber",ell(106,54,15,13))],
  "lineArt":[ell(110,52,2,2),ell(115,57,2.5,2),poly((52,80),(52,90)),poly((84,80),(84,90))]}}
L3 = {"id":3,"name":"Starlight Rocket","pencilSize":4,"boardRadius":3,"removed":[[3,-3],[-3,3],[3,0],[-3,0],[0,-3],[0,3]],
 "artwork":{"name":"Starlight Rocket","paper":"#F4EEFF","regions":[
   reg(1,"indigo",rect(0,0,150,100)),
   reg(2,"violet",ell(28,76,26,26)),
   reg(3,"lemon",star(122,24,13,5.5)),
   reg(4,"lemon",poly((65,80),(75,99),(85,80))),
   reg(5,"amber",poly((58,62),(44,86),(64,80))),
   reg(6,"amber",poly((92,62),(106,86),(86,80))),
   reg(7,"rose",ell(75,54,15,30)),
   reg(8,"coral",poly((61,34),(75,8),(89,34))),
   reg(9,"sky",ell(75,50,7,7))],
  "lineArt":[star(40,18,4,1.8),star(100,10,3,1.4),star(14,38,3,1.4),poly((75,80),(75,66))]}}
L4 = {"id":4,"name":"Moonlit Lighthouse","pencilSize":4,"boardRadius":3,"removed":[[3,-3],[-3,3],[3,0],[-3,0],[0,-3],[0,3],[-2,3],[2,-3]],
 "artwork":{"name":"Moonlit Lighthouse","paper":"#EEF2FF","regions":[
   reg(1,"indigo",rect(0,0,150,100)),
   reg(2,"lemon",ell(120,22,13,13)),
   reg(3,"sky",rect(0,76,150,24)),
   reg(4,"rose",poly((66,76),(70,30),(80,30),(84,76))),
   reg(5,"coral",poly((64,30),(75,14),(86,30))),
   reg(6,"mint",poly((0,80),(26,68),(56,80),(56,100),(0,100))),
   reg(7,"violet",ell(28,28,18,8)),
   reg(8,"lemon",rect(69,34,12,9,1))],
  "lineArt":[star(40,12,3,1.4),star(104,8,3,1.4),poly((75,43),(75,60))]}}
os.makedirs("skeletons", exist_ok=True)
for L in (L1,L2,L3,L4):
    L["supply"]=[]
    json.dump(L, open(f"skeletons/level_{L['id']:02d}.json","w"), indent=1)
print("ok")
