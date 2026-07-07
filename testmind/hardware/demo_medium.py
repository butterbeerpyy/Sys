"""
Medium version demo: 112x112 image, Top-16 selection
"""

import subprocess
import sys
from pathlib import Path

def main():
    print("="*70)
    print("  MEDIUM PYRAMID PROCESSOR - HARDWARE DEMONSTRATION")
    print("="*70)
    print("\nImage → Verilog Hardware → Visualization")
    print("Medium version: 112×112 image, Top-16 selection\n")

    # 检查输入
    if len(sys.argv) > 1:
        input_img = sys.argv[1]
    else:
        if Path("../real_images/dog.jpg").exists():
            input_img = "../real_images/dog.jpg"
        elif Path("test_pattern.png").exists():
            input_img = "test_pattern.png"
        else:
            input_img = None

    # Step 1: 图片转 hex (112x112)
    print("[Step 1/3] Converting image to hex (112x112)...")
    cmd = [sys.executable, "img_to_hex.py"]
    if input_img:
        cmd.extend([input_img, "test_image.hex", "112"])
    else:
        # 创建测试图案
        result = subprocess.run([sys.executable, "-c",
            "import numpy as np; from PIL import Image; "
            "img = np.random.randint(0, 256, (112, 112), dtype='uint8'); "
            "Image.fromarray(img).save('test_pattern.png'); "
            "with open('test_image.hex', 'w') as f: "
            "  [f.write(f'{p:02x}\\n') for p in img.flatten()]"
        ], capture_output=True, text=True)
        input_img = "test_pattern.png"
        print("[OK] Created test pattern")

    if input_img and Path(input_img).exists():
        result = subprocess.run(cmd, capture_output=True, text=True)
        print(result.stdout)
        if result.returncode != 0:
            print("[ERROR] Step 1 failed")
            print(result.stderr)
            return False

    # Step 2: 运行仿真
    print("\n[Step 2/3] Running hardware simulation...")
    print("            (This may take 1-2 minutes...)")

    # 编译
    compile_cmd = [
        "iverilog", "-g2012", "-o", "medium_pyramid.vvp",
        "medium_coarse_scanner.v",
        "medium_topk_selector.v",
        "medium_pyramid_top.v",
        "medium_pyramid_tb.v"
    ]

    result = subprocess.run(compile_cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print("[ERROR] Compilation failed")
        print(result.stderr)
        return False

    print("            [OK] Compilation successful")

    # 仿真
    sim_cmd = ["vvp", "medium_pyramid.vvp"]
    result = subprocess.run(sim_cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print("[ERROR] Simulation failed")
        print(result.stderr)
        return False

    print("            [OK] Simulation complete")
    print(result.stdout)

    # Step 3: 可视化 (patch_size=14, grid_size=8)
    print("\n[Step 3/3] Visualizing results...")
    result = subprocess.run([
        sys.executable, "visualize_result.py", input_img,
        "output_indices.hex", "result_medium.png", "14", "8"
    ], capture_output=True, text=True)
    print(result.stdout)
    if result.returncode != 0:
        print("[ERROR] Step 3 failed")
        print(result.stderr)
        return False

    print("\n" + "="*70)
    print("  [OK] SUCCESS!")
    print("="*70)
    print("\nGenerated files:")
    print("  test_image.hex         - Input (112x112 = 12,544 pixels)")
    print("  output_indices.hex     - Hardware output (16 indices)")
    print("  medium_pyramid.vcd     - Waveform")
    print("  result_medium.png      - Final visualization")
    print()

    return True

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
