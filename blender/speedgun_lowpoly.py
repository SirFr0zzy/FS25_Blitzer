"""Low-Poly Blitzer-Radarpistole (Speed Gun) fuer FS25.
Ausfuehren: Blender -> Scripting -> Open/Paste -> Run Script.
Masse in Metern (1 BU = 1 m), Laufrichtung = -Y (Blender), Objekt-Ursprung am Griff.
"""
import bpy
import math

# --- Aufraeumen -------------------------------------------------------------
if bpy.context.object and bpy.context.object.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')
old = bpy.data.collections.get("SpeedGun")
if old:
    for o in list(old.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.collections.remove(old)

col = bpy.data.collections.new("SpeedGun")
bpy.context.scene.collection.children.link(col)


def mat(name, color, emit=None, rough=0.6, metal=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = color
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = emit
        b.inputs["Emission Strength"].default_value = 1.5
    return m


M_BODY = mat("SG_Body", (0.08, 0.09, 0.10, 1), rough=0.5)
M_ACCENT = mat("SG_Accent", (0.95, 0.70, 0.05, 1), rough=0.5)
M_DARK = mat("SG_Black", (0.02, 0.02, 0.02, 1), rough=0.8)
M_LENS = mat("SG_Lens", (0.05, 0.15, 0.25, 1), rough=0.15, metal=0.3)
M_SCREEN = mat("SG_Screen", (0.05, 0.4, 0.1, 1), emit=(0.1, 1.0, 0.2, 1))


def finish(obj, name, material, flat=True):
    obj.name = name
    obj.data.name = name
    obj.data.materials.append(material)
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    col.objects.link(obj)
    if flat:
        for p in obj.data.polygons:
            p.use_smooth = False
    return obj


def box(name, size, loc, material, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.object
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    return finish(o, name, material)


def cyl(name, r1, r2, depth, loc, material, verts=8, rot=(math.radians(90), 0, 0)):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2,
                                    depth=depth, location=loc, rotation=rot)
    return finish(bpy.context.object, name, material)


# --- Teile ------------------------------------------------------------------
# Griff (leicht nach hinten geneigt)
box("SG_Handle", (0.045, 0.055, 0.13), (0, 0.01, -0.065), M_DARK,
    rot=(math.radians(-12), 0, 0))
# Griff-Akzent
box("SG_HandleGrip", (0.047, 0.03, 0.05), (0, 0.016, -0.07), M_ACCENT,
    rot=(math.radians(-12), 0, 0))
# Abzug
box("SG_Trigger", (0.012, 0.02, 0.035), (0, -0.032, -0.02), M_ACCENT,
    rot=(math.radians(20), 0, 0))
# Hauptkoerper
box("SG_Body", (0.07, 0.22, 0.075), (0, -0.07, 0.04), M_BODY)
# Gelber Streifen oben
box("SG_Stripe", (0.072, 0.10, 0.012), (0, -0.07, 0.083), M_ACCENT)
# Radar-Horn / Trichter vorne
cyl("SG_Horn", 0.032, 0.058, 0.09, (0, -0.225, 0.04), M_BODY)
# Linse im Trichter
cyl("SG_Lens", 0.0, 0.048, 0.012, (0, -0.272, 0.04), M_LENS)
# Display hinten (schraeg)
box("SG_ScreenFrame", (0.058, 0.012, 0.045), (0, 0.045, 0.062), M_DARK,
    rot=(math.radians(-25), 0, 0))
box("SG_Screen", (0.046, 0.006, 0.03), (0, 0.0505, 0.0635), M_SCREEN,
    rot=(math.radians(-25), 0, 0))
# Visier
box("SG_SightRear", (0.012, 0.012, 0.014), (0, -0.01, 0.0895), M_DARK)
box("SG_SightFront", (0.008, 0.008, 0.014), (0, -0.15, 0.0895), M_DARK)
# Antennen-Stummel
cyl("SG_Antenna", 0.007, 0.005, 0.05, (0.03, 0.02, 0.098), M_DARK,
    verts=6, rot=(0, 0, 0))

# --- Zusammenfuegen (ein Mesh pro Material -> wenig Drawcalls) --------------
bpy.ops.object.select_all(action='DESELECT')
for o in col.objects:
    o.select_set(True)
bpy.context.view_layer.objects.active = col.objects[0]
bpy.ops.object.join()
gun = bpy.context.object
gun.name = "SpeedGun"
gun.data.name = "SpeedGun"
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')  # Ursprung = 3D-Cursor (Welt-0 am Griff)

tris = sum(len(p.vertices) - 2 for p in gun.data.polygons)
print(f"SpeedGun fertig: {len(gun.data.vertices)} Verts, {tris} Tris")
