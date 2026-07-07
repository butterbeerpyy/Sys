"""
Improved version: Better interest detection
"""

import subprocess
import sys
from pathlib import Path

def main():
    print("="*70)
    print("  IMPROVED PYRAMID PROCESSOR - HARDWARE DEMONSTRATION")
    print("="*70)
    print("\nImproved interest detection:")
    print("  - Edge detection")
    print("  - Texture variance")
    print("  - Center weighting (focus on middle regions)")
    print()

    if len(sys.argv) > 1:
        input_img = sys.argv[1]
    else:
        if Path("../real_images/dog.jpg").exists():
            input_img = "../real_images/dog.jpg"
        else:
            input_img = "test_pattern.png"

    # Step 1
    print("[Step 1/3] Converting image...")
    result = subprocess.run([
        sys.executable, "img_to_hex.py", input_img, "test_image.hex", "112"
    ], capture_output=True, text=True)
    print(result.stdout)
    if result.returncode != 0:
        print("[ERROR]", result.stderr)
        return False

    # Step 2
    print("\n[Step 2/3] Running improved hardware simulation...")
    print("            (May take 1-2 minutes...)")

    compile_cmd = [
        "iverilog", "-g2012", "-o", "improved_pyramid.vvp",
        "simple_improved_scanner.v",
        "multicycle_topk_selector.v",
        "improved_pyramid_top.v",
        "improved_pyramid_tb.v"
    ]

    result = subprocess.run(compile_cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print("[ERROR] Compilation failed")
        print(result.stderr)
        return False

    print("            [OK] Compilation successful")

    result = subprocess.run(["vvp", "improved_pyramid.vvp"],
                          capture_output=True, text=True)
    if result.returncode != 0:
        print("[ERROR] Simulation failed")
        print(result.stderr)
        return False

    print("            [OK] Simulation complete")
    print(result.stdout)

    # Step 3
    print("\n[Step 3/3] Visualizing...")
    result = subprocess.run([
        sys.executable, "visualize_result.py", input_img,
        "output_indices.hex", "result_improved.png", "14", "8"
    ], capture_output=True, text=True)
    print(result.stdout)
    if result.returncode != 0:
        print("[ERROR]", result.stderr)
        return False

    print("\n" + "="*70)
    print("  [OK] SUCCESS!")
    print("="*70)
    print("\nGenerated: result_improved.png")
    print("Compare with previous result_medium.png to see improvement!")
    print()

    return True

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
