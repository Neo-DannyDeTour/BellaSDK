import re

with open("test/unit/test_teleport.gd", "r") as f:
    content = f.read()

# the test failed with "Portal sound should be playing."
# That's because _teleport.portal_sound.play() is called, but is it playing? AudioStreamPlayer needs a stream to actually play.
# Let's add a dummy AudioStream to portal_sound.

content = re.sub(
    r'portal_sound\.name = "AudioStreamPlayer"',
    r'portal_sound.name = "AudioStreamPlayer"\n\tvar dummy_stream: AudioStreamWAV = AudioStreamWAV.new()\n\tportal_sound.stream = dummy_stream',
    content
)

with open("test/unit/test_teleport.gd", "w") as f:
    f.write(content)
