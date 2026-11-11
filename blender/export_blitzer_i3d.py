"""Exportiert die Blender-Collection "Blitzer" nach objects/blitzer/blitzer.i3d.
Ausfuehren in Blender (Scripting -> Run). Blender Z-up -> GIANTS Y-up, Vorderseite (-Y) -> +Z.
"""
import bpy, os
from mathutils import Vector

OUT = "/home/elias/code/lua/FS25_SpeedLaserGun/objects/blitzer/blitzer.i3d"
os.makedirs(os.path.dirname(OUT), exist_ok=True)
col = bpy.data.collections["Blitzer"]

GAME_MATS = {
    "BL_Silver": ((0.70, 0.72, 0.74), 1),
    "BL_Black": ((0.015, 0.015, 0.015), 2),
    "BL_Lens": ((0.55, 0.03, 0.03), 3),
    "BL_Base": ((0.30, 0.30, 0.31), 4),
    "BL_Panel": ((0.04, 0.35, 0.10), 5),
}
FLASH_OVERRIDE = {"Flash": "BL_Lens"}  # Blitzfenster unten: dunkles Rotglas


def conv(v):
    return (v.x, v.z, -v.y)


per_mat = {m: {"verts": [], "idx": []} for m in GAME_MATS}
for o in col.objects:
    me = o.data
    mw = o.matrix_world
    nm = mw.to_3x3().inverted().transposed()
    bucket = per_mat[FLASH_OVERRIDE.get(o.name, me.materials[0].name)]
    me.calc_loop_triangles()
    cn = me.corner_normals
    cache = {}
    for tri in me.loop_triangles:
        ids = []
        for li in tri.loops:
            v = me.vertices[me.loops[li].vertex_index]
            p = conv(mw @ v.co)
            n = conv((nm @ Vector(cn[li].vector)).normalized())
            key = tuple(round(x, 5) for x in p) + tuple(round(x, 3) for x in n)
            if key not in cache:
                cache[key] = len(bucket["verts"])
                bucket["verts"].append((p, n))
            ids.append(cache[key])
        bucket["idx"].append((ids[0], ids[1], ids[2]))  # reine Rotation -> Windung bleibt

verts, tris, subsets = [], [], []
for mname, b in per_mat.items():
    if not b["verts"]:
        continue
    fv, fi = len(verts), len(tris) * 3
    verts += b["verts"]
    tris += [(a + fv, c + fv, d + fv) for a, c, d in b["idx"]]
    subsets.append((fv, len(b["verts"]), fi, len(b["idx"]) * 3, mname))

xs = [v[0][0] for v in verts]; ys = [v[0][1] for v in verts]; zs = [v[0][2] for v in verts]
bc = ((max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2, (max(zs) + min(zs)) / 2)
br = max(((v[0][0] - bc[0]) ** 2 + (v[0][1] - bc[1]) ** 2 + (v[0][2] - bc[2]) ** 2) ** 0.5 for v in verts)

# --- Kollisionskoerper: einfaches 12-Eck-Prisma um die Saeule (Y-up) -------
import math
COL_R, COL_H, COL_N = 0.22, 2.3, 12
cverts, ctris = [], []
def cv(p, n):
    cverts.append((p, n)); return len(cverts) - 1
for i in range(COL_N):
    a0 = 2 * math.pi * i / COL_N
    a1 = 2 * math.pi * (i + 1) / COL_N
    am = (a0 + a1) / 2
    n = (math.cos(am), 0.0, math.sin(am))
    b0 = cv((COL_R * math.cos(a0), 0, COL_R * math.sin(a0)), n)
    b1 = cv((COL_R * math.cos(a1), 0, COL_R * math.sin(a1)), n)
    t1 = cv((COL_R * math.cos(a1), COL_H, COL_R * math.sin(a1)), n)
    t0 = cv((COL_R * math.cos(a0), COL_H, COL_R * math.sin(a0)), n)
    ctris += [(b0, t1, b1), (b0, t0, t1)]
ctop = cv((0, COL_H, 0), (0, 1, 0)); cbot = cv((0, 0, 0), (0, -1, 0))
for i in range(COL_N):
    a0 = 2 * math.pi * i / COL_N
    a1 = 2 * math.pi * (i + 1) / COL_N
    p0t = cv((COL_R * math.cos(a0), COL_H, COL_R * math.sin(a0)), (0, 1, 0))
    p1t = cv((COL_R * math.cos(a1), COL_H, COL_R * math.sin(a1)), (0, 1, 0))
    p0b = cv((COL_R * math.cos(a0), 0, COL_R * math.sin(a0)), (0, -1, 0))
    p1b = cv((COL_R * math.cos(a1), 0, COL_R * math.sin(a1)), (0, -1, 0))
    ctris += [(ctop, p1t, p0t), (cbot, p0b, p1b)]

f = lambda x: "%.6g" % x
L = ['<?xml version="1.0" encoding="utf-8"?>',
     '<i3D name="blitzer" version="1.6" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://i3d.giants.ch/schema/i3d-1.6.xsd">',
     '  <Asset><Export program="Claude/Blender" version="1.0"/></Asset>',
     '  <Files/>', '  <Materials>']
for name, (c, mid) in GAME_MATS.items():
    L.append(f'    <Material name="{name}" materialId="{mid}" diffuseColor="{c[0]} {c[1]} {c[2]} 1" specularColor="0.4 1 0"/>')
L += ['  </Materials>', '  <Shapes>',
      f'    <IndexedTriangleSet name="blitzerShape" shapeId="1" bvCenter="{f(bc[0])} {f(bc[1])} {f(bc[2])}" bvRadius="{f(br)}">',
      f'      <Vertices count="{len(verts)}" normal="true">']
for p, n in verts:
    L.append(f'        <v p="{f(p[0])} {f(p[1])} {f(p[2])}" n="{f(n[0])} {f(n[1])} {f(n[2])}"/>')
L += ['      </Vertices>', f'      <Triangles count="{len(tris)}">']
for t in tris:
    L.append(f'        <t vi="{t[0]} {t[1]} {t[2]}"/>')
L += ['      </Triangles>', f'      <Subsets count="{len(subsets)}">']
for fv, nv, fi, ni, _ in subsets:
    L.append(f'        <Subset firstVertex="{fv}" numVertices="{nv}" firstIndex="{fi}" numIndices="{ni}"/>')
L += ['      </Subsets>', '    </IndexedTriangleSet>']
L += [f'    <IndexedTriangleSet name="blitzerCollisionShape" shapeId="2" bvCenter="0 {f(COL_H/2)} 0" bvRadius="{f(math.hypot(COL_R, COL_H/2))}">',
      f'      <Vertices count="{len(cverts)}" normal="true">']
for p, n in cverts:
    L.append(f'        <v p="{f(p[0])} {f(p[1])} {f(p[2])}" n="{f(n[0])} {f(n[1])} {f(n[2])}"/>')
L += ['      </Vertices>', f'      <Triangles count="{len(ctris)}">']
for t in ctris:
    L.append(f'        <t vi="{t[0]} {t[1]} {t[2]}"/>')
L += ['      </Triangles>', '      <Subsets count="1">',
      f'        <Subset firstVertex="0" numVertices="{len(cverts)}" firstIndex="0" numIndices="{len(ctris) * 3}"/>',
      '      </Subsets>', '    </IndexedTriangleSet>', '  </Shapes>']
mids = ",".join(str(GAME_MATS[s[4]][1]) for s in subsets)
L += ['  <Scene>',
      '    <TransformGroup name="blitzer" lockedgroup="true" nodeId="1">',
      '      <TransformGroup name="testAreas" static="true" nodeId="2">',
      '        <TransformGroup name="testAreaStart01" translation="-0.5 0 -0.5" nodeId="3">',
      '          <TransformGroup name="testAreaEnd01" translation="1 3 1" nodeId="4"/>',
      '        </TransformGroup>',
      '      </TransformGroup>',
      f'      <Shape name="blitzerBody" shapeId="1" static="true" collision="false" castsShadows="true" receiveShadows="true" clipDistance="200" materialIds="{mids}" nodeId="5"/>',
      '      <TransformGroup name="sensorNode" translation="0 1.62 0.19" nodeId="6"/>',
      '      <TransformGroup name="panelNode" translation="0 1.30 -0.19" rotation="0 180 0" nodeId="7"/>',
      '      <Light name="flashLight" translation="0 0.78 0.7" type="point" color="14 0.15 0.1" emitDiffuse="true" emitSpecular="true" decayRate="2" range="14" castShadowMap="false" visibility="false" nodeId="8"/>',
      '      <Shape name="blitzerCollision" shapeId="2" static="true" collisionFilterGroup="0x3e" collisionFilterMask="0xfffffbff" nonRenderable="true" materialIds="1" nodeId="9"/>',
      '    </TransformGroup>', '  </Scene>', '</i3D>']
open(OUT, "w").write("\n".join(L) + "\n")
print("exportiert:", len(verts), "Verts,", len(tris), "Tris")
