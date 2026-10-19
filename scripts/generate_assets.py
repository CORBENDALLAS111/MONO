"""Generate original monochrome app identity; not a screenshot or UI mockup."""
from pathlib import Path
import json
from PIL import Image, ImageDraw

root=Path(__file__).resolve().parents[1]/'MONOApp/Assets.xcassets'
root.mkdir(parents=True,exist_ok=True)
(root/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}},indent=2)+'\n')
icon=root/'AppIcon.appiconset'
icon.mkdir(exist_ok=True)
image=Image.new('RGB',(1024,1024),(0,0,0))
draw=ImageDraw.Draw(image)
# Distinctive M built from four restrained, equal-width strokes.
draw.line([(260,730),(260,294),(512,560),(764,294),(764,730)],fill=(245,245,245),width=54,joint='curve')
image.save(icon/'AppIcon.png')
(icon/'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}},indent=2)+'\n')
print('Generated original 1024px monochrome app icon')
