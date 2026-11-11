import sys
import numpy as np
from PIL import Image

def audit_textures(dir_path):
    print(f"Auditing textures in {dir_path}...")

    # 1. Albedo
    albedo_path = f"{dir_path}/arch_albedo.png"
    img_a = Image.open(albedo_path)
    arr_a = np.array(img_a)
    print(f"Albedo: format={img_a.format}, mode={img_a.mode}, size={img_a.size}")
    assert img_a.size == (2048, 2048), f"Bad size: {img_a.size}"
    black_a = np.sum(np.all(arr_a[:, :, :3] == [0, 0, 0], axis=-1))
    dark_a = np.sum(np.max(arr_a[:, :, :3], axis=-1) < 15)
    print(f"Albedo black pixels: {black_a}, near-black pixels (<15): {dark_a}")
    print(f"Albedo mean RGB: {np.mean(arr_a[:, :, :3], axis=(0,1))}")
    assert black_a == 0, f"Albedo has {black_a} black pixels!"

    # 2. Normal
    normal_path = f"{dir_path}/arch_normal.png"
    img_n = Image.open(normal_path)
    arr_n = np.array(img_n)
    print(f"Normal: format={img_n.format}, mode={img_n.mode}, size={img_n.size}")
    assert img_n.size == (2048, 2048), f"Bad size: {img_n.size}"
    black_n = np.sum(np.all(arr_n[:, :, :3] == [0, 0, 0], axis=-1))
    print(f"Normal black pixels: {black_n}")
    print(f"Normal mean RGB: {np.mean(arr_n[:, :, :3], axis=(0,1))}")
    # In tangent space normal maps, Z (Blue) should be high (typically > 128, mean ~ 200+)
    mean_b = np.mean(arr_n[:, :, 2])
    print(f"Normal Blue channel mean: {mean_b:.2f}")
    assert black_n == 0, f"Normal has {black_n} black pixels!"
    assert mean_b > 180, f"Normal blue channel unexpectedly low: {mean_b}"

    # 3. ORM
    orm_path = f"{dir_path}/arch_orm.png"
    img_o = Image.open(orm_path)
    arr_o = np.array(img_o)
    print(f"ORM: format={img_o.format}, mode={img_o.mode}, size={img_o.size}")
    assert img_o.size == (2048, 2048), f"Bad size: {img_o.size}"
    ao = arr_o[:, :, 0]
    roughness = arr_o[:, :, 1]
    metallic = arr_o[:, :, 2]
    print(f"AO (Red) range: [{np.min(ao)}, {np.max(ao)}], mean={np.mean(ao):.2f}")
    print(f"Roughness (Green) range: [{np.min(roughness)}, {np.max(roughness)}], mean={np.mean(roughness):.2f}")
    print(f"Metallic (Blue) range: [{np.min(metallic)}, {np.max(metallic)}], mean={np.mean(metallic):.2f}")
    assert np.all(metallic == 0), f"Stone should have 0 metallic, got max {np.max(metallic)}"
    assert np.min(ao) > 0, f"AO has 0 (pure black) pixels: min={np.min(ao)}"
    assert np.min(roughness) > 100, f"Roughness has unexpectedly low values: min={np.min(roughness)}"

    print("ALL TEXTURES PASSED INTEGRITY CHECKS!")

if __name__ == "__main__":
    audit_textures(sys.argv[-1])
