"""
One-click demo: Image → Hardware Simulation → Result
Mini pyramid processor demonstration
"""

import subprocess
import sys
from pathlib import Path

def main():
    print("="*70)
    print("  MINI PYRAMID PROCESSOR - HARDWARE DEMONSTRATION")
    print("="*70)
    print("\nThis demo shows: Image → Verilog Hardware → Visualization")
    print("Mini version: 32×32 image, Top-4 selection\n")

    # 检查输入
    if len(sys.argv) > 1:
        input_img = sys.argv[1]
    else:
        # 使用默认图像
        if Path("../real_images/dog.jpg").exists():
            input_img = "../real_images/dog.jpg"
        elif Path("test_pattern.png").exists():
            input_img = "test_pattern.png"
        else:
            input_img = None

    # Step 1: 图片转 hex
    print("[Step 1/3] Converting image to hex...")
    if input_img:
        result = subprocess.run([sys.executable, "img_to_hex.py", input_img],
                              capture_output=True, text=True)
    else:
        result = subprocess.run([sys.executable, "img_to_hex.py"],
                              capture_output=True, text=True)
        input_img = "test_pattern.png"

    print(result.stdout)
    if result.returncode != 0:
        print("[ERROR] Step 1 failed")
        print(result.stderr)
        return False

    # Step 2: 运行仿真
    print("\n[Step 2/3] Running hardware simulation...")
    result = subprocess.run([sys.executable, "run_simulation.py"],
                          capture_output=True, text=True)
    print(result.stdout)
    if result.returncode != 0:
        print("[ERROR] Step 2 failed")
        print(result.stderr)
        return False

    # Step 3: 可视化
    print("\n[Step 3/3] Visualizing results...")
    result = subprocess.run([sys.executable, "visualize_result.py", input_img],
                          capture_output=True, text=True)
    print(result.stdout)
    if result.returncode != 0:
        print("[ERROR] Step 3 failed")
        print(result.stderr)
        return False

    print("\n" + "="*70)
    print("  [OK] SUCCESS!")
    print("="*70)
    print("\nGenerated files:")
    print("  📄 test_image.hex         - Input image data")
    print("  📄 output_indices.hex     - Hardware output")
    print("  📄 mini_pyramid.vcd       - Waveform (view with gtkwave)")
    print("  📄 result_hardware.png    - Final visualization")
    print("\nTo view waveform:")
    print("  gtkwave mini_pyramid.vcd")
    print()

    return True

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
