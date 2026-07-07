MATRIX_DIM = 8
a = []
b = []
for row in range(MATRIX_DIM):
    for col in range(MATRIX_DIM):
        a.append(row + col + 1)
        b.append((MATRIX_DIM - row) + (MATRIX_DIM - col - 1))

print('A row 0:', a[0:8])
print('B col 0:', [b[k * MATRIX_DIM] for k in range(8)])

c00 = sum(a[k] * b[k * MATRIX_DIM] for k in range(MATRIX_DIM))
print('Expected C[0][0] =', c00, hex(c00))
print('Hardware C[0][0] =', 0x7f, hex(0x7f))
