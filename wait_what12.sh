# What if it's the POSTPASS binding 8 that we removed from the SHADER but is STILL in `SunshineClouds.gd`?
# NO, I checked! I deleted `postpass_camera_data_uniform.binding = 8` from `SunshineClouds.gd`!
# Let me double check it's ACTUALLY deleted!
cat -n addons/SunshineClouds2/SunshineClouds.gd | sed -n '930,950p'
