import numpy as np
from PIL import Image
import rpy

assert Image.new("RGB", (16, 16), "teal").size == (16, 16)
assert len(rpy.chart.notes(2000, 4200, kind="hold")) == 1
factor = float(np.asarray([1.25, 1.35]).mean())
rpy.chart.scale_hold_paths(2000, 4200, factor)
rpy.result({"factor": factor, "canvas": [1920, 1080]})
print("Scaled the hold path without changing its timing.")
