import os, sys, zlib, struct

def decode_png(filename):
    with open(filename, 'rb') as f:
        data = f.read()
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError("Not a PNG file")
    
    idx = 8
    width = height = bit_depth = color_type = None
    idat = bytearray()
    
    while idx < len(data):
        length, chunk_type = struct.unpack('>I4s', data[idx:idx+8])
        idx += 8
        chunk_data = data[idx:idx+length]
        idx += length + 4 # skip CRC
        
        if chunk_type == b'IHDR':
            width, height, bit_depth, color_type, _, _, _ = struct.unpack('>IIBBBBB', chunk_data)
        elif chunk_type == b'IDAT':
            idat.extend(chunk_data)
        elif chunk_type == b'IEND':
            break
            
    decompressed = zlib.decompress(bytes(idat))
    bytes_per_pixel = 4 if color_type == 6 else 3
    stride = width * bytes_per_pixel
    raw = bytearray(width * height * bytes_per_pixel)
    
    src_idx = 0
    dst_idx = 0
    prev_row = bytearray(stride)
    
    for y in range(height):
        filter_type = decompressed[src_idx]
        src_idx += 1
        cur_row = bytearray(decompressed[src_idx:src_idx+stride])
        src_idx += stride
        
        if filter_type == 0: # None
            pass
        elif filter_type == 1: # Sub
            for x in range(bytes_per_pixel, stride):
                cur_row[x] = (cur_row[x] + cur_row[x - bytes_per_pixel]) & 0xFF
        elif filter_type == 2: # Up
            for x in range(stride):
                cur_row[x] = (cur_row[x] + prev_row[x]) & 0xFF
        elif filter_type == 3: # Average
            for x in range(stride):
                left = cur_row[x - bytes_per_pixel] if x >= bytes_per_pixel else 0
                up = prev_row[x]
                cur_row[x] = (cur_row[x] + ((left + up) >> 1)) & 0xFF
        elif filter_type == 4: # Paeth
            for x in range(stride):
                a = cur_row[x - bytes_per_pixel] if x >= bytes_per_pixel else 0
                b = prev_row[x]
                c = prev_row[x - bytes_per_pixel] if x >= bytes_per_pixel else 0
                p = a + b - c
                pa = abs(p - a)
                pb = abs(p - b)
                pc = abs(p - c)
                if pa <= pb and pa <= pc:
                    pr = a
                elif pb <= pc:
                    pr = b
                else:
                    pr = c
                cur_row[x] = (cur_row[x] + pr) & 0xFF
                
        raw[dst_idx:dst_idx+stride] = cur_row
        prev_row = cur_row
        dst_idx += stride
        
    return width, height, bytes_per_pixel, raw

def get_pixel(raw, width, bpp, x, y):
    idx = (y * width + x) * bpp
    return tuple(raw[idx:idx+bpp])

def analyze_image(path):
    w, h, bpp, raw = decode_png(path)
    print(f"Loaded {path}: {w}x{h}, bpp={bpp}")
    
    # Check background color at top-left
    bg = get_pixel(raw, w, bpp, 5, 5)
    print(f"  Header area sample (5,5): {bg}")
    
    # Check for empty/black image
    non_zero = sum(1 for i in range(0, len(raw), 100) if raw[i] > 20)
    print(f"  Non-dark samples check: {non_zero} non-dark out of {len(raw)//100}")
    
    # Check bounds and borders
    print(f"  Sample center (w//2, h//2): {get_pixel(raw, w, bpp, w//2, h//2)}")
    return w, h, bpp, raw

for fname in sorted(os.listdir("ui_screenshots")):
    if fname.endswith(".png"):
        analyze_image(os.path.join("ui_screenshots", fname))
