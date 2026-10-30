"""Render Kayleo's vector K-and-leaf mark into launcher assets.
Run from the repository root: python3 tools/generate_brand_assets.py
Requires Pillow; SVG geometry is the source for every platform size.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SCALE = 4
CREAM, INK, LIME = '#F7F5ED', '#111512', '#94CF32'
SHAPES = [
    (INK, [('M',142,119), ('C',142,97,158,86,181,86), ('L',190,86),
           ('C',211,86,221,99,221,119), ('L',221,385),
           ('C',221,407,207,418,185,418), ('L',177,418),
           ('C',155,418,142,407,142,385), ('Z',)]),
    (INK, [('M',228,301), ('C',243,212,316,160,423,145),
           ('C',422,246,352,281,282,296), ('L',228,326), ('Z',)]),
    (CREAM, [('M',224,326), ('C',260,273,312,239,379,219),
             ('C',332,244,296,271,271,300), ('Z',)]),
    (INK, [('M',229,320), ('C',250,291,274,291,292,322),
           ('L',354,408), ('C',361,419,354,423,337,423),
           ('L',292,423), ('C',276,423,269,418,260,403),
           ('L',230,351), ('C',221,337,220,331,229,320), ('Z',)]),
]

def svg_path(commands):
    return ' '.join(c[0] + ' '.join(str(n) for n in c[1:]) for c in commands)

svg = ['<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">',
       '<title>Kayleo K and leaf mark</title>',
       f'<rect width="512" height="512" rx="112" fill="{CREAM}"/>']
svg += [f'<path d="{svg_path(commands)}" fill="{color}"/>' for color, commands in SHAPES]
svg += [f'<circle cx="405" cy="391" r="32" fill="{LIME}"/>', '</svg>']
(ROOT / 'assets/images/kayleo-mark.svg').write_text('\n'.join(svg) + '\n')

notification_xml = '\n'.join([
    '<vector xmlns:android="http://schemas.android.com/apk/res/android"',
    '    android:width="24dp"',
    '    android:height="24dp"',
    '    android:viewportWidth="512"',
    '    android:viewportHeight="512">',
    f'    <path\n        android:fillColor="#FFFFFFFF"\n        android:pathData="{svg_path(SHAPES[0][1])}" />',
    f'    <path\n        android:fillColor="#FFFFFFFF"\n        android:fillType="evenOdd"\n        android:pathData="{svg_path(SHAPES[1][1])} {svg_path(SHAPES[2][1])}" />',
    f'    <path\n        android:fillColor="#FFFFFFFF"\n        android:pathData="{svg_path(SHAPES[3][1])}" />',
    '    <path\n        android:fillColor="#FFFFFFFF"\n        android:pathData="M373,391 A32,32 0 1,0 437,391 A32,32 0 1,0 373,391 Z" />',
    '</vector>',
])
(ROOT / 'android/app/src/main/res/drawable/ic_notification.xml').write_text(notification_xml + '\n')

image = Image.new('RGB', (512 * SCALE, 512 * SCALE), CREAM)
draw = ImageDraw.Draw(image)
for color, commands in SHAPES:
    points, position = [], (0, 0)
    for c in commands:
        if c[0] in ('M', 'L'):
            position = (c[1], c[2])
            points.append(position)
        elif c[0] == 'C':
            p0, p1, p2, p3 = position, c[1:3], c[3:5], c[5:7]
            for i in range(1, 49):
                t, u = i / 48, 1 - i / 48
                points.append(tuple(u**3*p0[j] + 3*u*u*t*p1[j] + 3*u*t*t*p2[j] + t**3*p3[j] for j in (0, 1)))
            position = p3
    draw.polygon([(round(x*SCALE), round(y*SCALE)) for x, y in points], fill=color)
draw.ellipse(tuple(n*SCALE for n in (373,359,437,423)), fill=LIME)

def save(relative_path, size):
    target = ROOT / relative_path
    target.parent.mkdir(parents=True, exist_ok=True)
    image.resize((size, size), Image.Resampling.LANCZOS).save(target)

for density, size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    save(f'android/app/src/main/res/mipmap-{density}/ic_launcher.png', size)
for size in [192, 512]:
    save(f'web/icons/Icon-{size}.png', size)
    save(f'web/icons/Icon-maskable-{size}.png', size)
save('web/favicon.png', 32)
for logical, multiplier in [(20,1),(20,2),(20,3),(29,1),(29,2),(29,3),(40,1),(40,2),(40,3),(60,2),(60,3),(76,1),(76,2),(83.5,2),(1024,1)]:
    save(f'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-{logical}x{logical}@{multiplier}x.png', round(logical*multiplier))
for size in [16,32,64,128,256,512,1024]:
    save(f'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{size}.png',size)
target = ROOT / 'windows/runner/resources/app_icon.ico'
target.parent.mkdir(parents=True,exist_ok=True)
image.resize((256,256), Image.Resampling.LANCZOS).save(target, format='ICO', sizes=[(s,s) for s in [16,32,48,64,128,256]])
for multiplier in [1,2,3]:
    launch = Image.new('RGBA',(240*multiplier,90*multiplier))
    font = ImageFont.truetype(str(ROOT/'assets/fonts/Manrope.ttf'),48*multiplier)
    font.set_variation_by_axes([800])
    painter = ImageDraw.Draw(launch)
    width = painter.textlength('kayleo',font=font)
    dot_width = painter.textlength('.',font=font)
    x = (240*multiplier-width-dot_width)/2
    painter.text((x,12*multiplier),'kayleo',font=font,fill=INK)
    painter.text((x+width,12*multiplier),'.',font=font,fill=LIME)
    suffix = '' if multiplier == 1 else f'@{multiplier}x'
    target = ROOT/f'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage{suffix}.png'
    target.parent.mkdir(parents=True,exist_ok=True)
    launch.save(target)
