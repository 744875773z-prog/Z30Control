# -*- coding: utf-8 -*-
dim = 17
lines = [
    'TITLE "Kodak Portra 400 Film Simulation"',
    f'LUT_3D_SIZE {dim}',
    'DOMAIN_MIN 0.0 0.0 0.0',
    'DOMAIN_MAX 1.0 1.0 1.0',
    ''
]

for b_idx in range(dim):
    b = b_idx / (dim - 1)
    for g_idx in range(dim):
        g = g_idx / (dim - 1)
        for r_idx in range(dim):
            r = r_idx / (dim - 1)
            
            # 柯达胶片色彩曲线模拟
            r_out = pow(r, 0.95) * 1.04
            g_out = pow(g, 1.0) * 0.98
            b_out = pow(b, 1.08) * 0.92
            
            r_out = min(1.0, max(0.0, r_out))
            g_out = min(1.0, max(0.0, g_out))
            b_out = min(1.0, max(0.0, b_out))
            
            lines.append(f'{r_out:.6f} {g_out:.6f} {b_out:.6f}')

with open('Z30Control/Resources/BuiltinLUTs/Kodak_Portra_400.cube', 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines))

print(f'成功生成标准 3D LUT 文件: Kodak_Portra_400.cube, 数据点数: {dim**3}')
