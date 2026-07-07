"""
Step 2: Run Verilog simulation
"""

import subprocess
import sys
from pathlib import Path

def run_simulation():
    """运行 Verilog 仿真"""

    print("="*60)
    print("  Running Hardware Simulation")
    print("="*60)

    # 检查文件
    required_files = [
        "mini_coarse_scanner.v",
        "mini_topk_selector.v",
        "mini_pyramid_top.v",
        "mini_pyramid_tb.v",
        "test_image.hex"
    ]

    for f in required_files:
        if not Path(f).exists():
            print(f"[ERROR] {f} not found")
            return False

    print("\n[1] Compiling Verilog...")

    # 编译
    compile_cmd = [
        "iverilog",
        "-g2012",
        "-o", "mini_pyramid.vvp",
        "mini_coarse_scanner.v",
        "mini_topk_selector.v",
        "mini_pyramid_top.v",
        "mini_pyramid_tb.v"
    ]

    result = subprocess.run(compile_cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print(f"[ERROR] Compilation failed:")
        print(result.stderr)
        return False

    print("[OK] Compilation successful")

    print("\n[2] Running simulation...")

    # 运行仿真
    sim_cmd = ["vvp", "mini_pyramid.vvp"]
    result = subprocess.run(sim_cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print(f"[ERROR] Simulation failed:")
        print(result.stderr)
        return False

    print("[OK] Simulation complete")
    print("\nSimulation output:")
    print(result.stdout)

    # 检查输出文件
    if Path("output_indices.hex").exists():
        print("\n[OK] Output file generated: output_indices.hex")
        return True
    else:
        print("\n[WARNING] output file not found")
        return False

if __name__ == "__main__":
    success = run_simulation()
    sys.exit(0 if success else 1)
