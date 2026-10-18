from inspect_screenshots import decode_png, get_pixel

w, h, bpp, raw1 = decode_png("ui_screenshots/01_controls_and_buttons.png")

print("=== Checking Slider Label In-Bounds ===")
# rightPanelRect: x: 650, y: 128, w: 610, h: 650
# Sliders are at rightPanelRect.x + 16 = 666
# In the previous bug, label was drawn at 666 - measured.x - 8 (~570 to 660), which was OUTSIDE rightPanelRect (650)!
# Let's check region x: 550..649, y: 180..300 (gap between panels and panel border)
leak_pixels = 0
for y in range(180, 300):
    for x in range(550, 648):
        r, g, b, _ = get_pixel(raw1, w, bpp, x, y)
        if r > 100 and g > 100: # bright text pixels
            leak_pixels += 1

print(f"Bright pixels in left-of-container margin (x: 550..648, y: 180..300): {leak_pixels} (Expected 0)")
assert leak_pixels == 0, f"Slider label still leaking out of container! ({leak_pixels} pixels)"

# Check that slider label "Main Volume" is inside x: 666..766
slider_label_pixels = 0
for y in range(190, 225):
    for x in range(666, 766):
        r, g, b, _ = get_pixel(raw1, w, bpp, x, y)
        if r > 150:
            slider_label_pixels += 1
print(f"Slider label pixels inside container (x: 666..766, y: 190..225): {slider_label_pixels} (Found label text cleanly inside container!)")
assert slider_label_pixels > 50, "Slider label missing inside container!"

print("\n=== Checking Vertical Tab Container (06_vertical_tab_container.png) ===")
w6, h6, bpp6, raw6 = decode_png("ui_screenshots/06_vertical_tab_container.png")

# Vertical tab bar is at x: 36, w: 220, y: 176
# Tab 1 ("2. Propulsion Dynamics") is active (y: 220..264)
# Check left accent bar at x: 36..39, y: 225..255 (should be blue accent: 80, 140, 245)
accent_pixels = 0
for y in range(225, 255):
    for x in range(36, 40):
        r, g, b, _ = get_pixel(raw6, w6, bpp6, x, y)
        if b > 200:
            accent_pixels += 1
print(f"Vertical tab active accent line blue pixels: {accent_pixels}")
assert accent_pixels > 20, "Vertical tab active accent line not found!"

# Check knob fine mode in vertical tab sub-panel:
# Warp knob is at x: 280, y: 254..334
# "FINE" text is inside center of knob
fine_badge_pixels = 0
for y in range(260, 310):
    for x in range(270, 360):
        r, g, b, _ = get_pixel(raw6, w6, bpp6, x, y)
        # Amber/gold text (255, 235, 180)
        if r > 200 and g > 180 and b < 200:
            fine_badge_pixels += 1
print(f"Knob FINE mode badge amber pixels: {fine_badge_pixels}")
assert fine_badge_pixels > 10, "Knob FINE badge not found!"

print("\nALL VERIFICATIONS PASSED PERFECTLY!")
