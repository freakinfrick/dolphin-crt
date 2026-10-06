#!/usr/bin/env python3
# Preview a Dolphin post-process shader on a screenshot, CPU-only (OSMesa llvmpipe: no GPU, no display).
# Usage: python3 glrender.py SHADER.glsl INPUT.png OUTPUT.png   (options use their DefaultValue)
# Needs: numpy, Pillow, PyOpenGL, and libOSMesa (Debian/Ubuntu: libosmesa6). Unset DISPLAY if it hangs.
import os, sys, re, ctypes
os.environ["PYOPENGL_PLATFORM"] = "osmesa"
import numpy as np
from PIL import Image
from OpenGL import GL, arrays
from OpenGL.osmesa import *
W, H = 1440, 1080   # 4:3 output, scaled down from 1920x1440 to keep llvmpipe quick
attrs = arrays.GLintArray.asArray([OSMESA_FORMAT, OSMESA_RGBA, OSMESA_PROFILE, OSMESA_CORE_PROFILE,
    OSMESA_CONTEXT_MAJOR_VERSION, 3, OSMESA_CONTEXT_MINOR_VERSION, 3, 0])
ctx = OSMesaCreateContextAttribs(attrs, None)
buf = arrays.GLubyteArray.zeros((H, W, 4))
assert OSMesaMakeCurrent(ctx, buf, GL.GL_UNSIGNED_BYTE, W, H)
src = open(sys.argv[1]).read()
opts = dict(re.findall(r"OptionName\s*=\s*(\w+)\s*\n[^\[]*?DefaultValue\s*=\s*([-\d.]+)", src))
pre = "#version 330 core\n#define float2 vec2\n#define float3 vec3\n#define float4 vec4\n#define lerp mix\nuniform sampler2D samp1;\nin vec2 v_tex0;\nout vec4 ocol0;\n"
pre += "".join(f"uniform float {o};\n" for o in opts)
pre += "#define GetOption(x) (x)\nvec2 GetResolution(){return vec2(3840.0,3168.0);}\nvec2 GetWindowResolution(){return vec2(%d.0,%d.0);}\nvec2 GetCoordinates(){return v_tex0;}\nvec4 SampleLocation(vec2 p){return texture(samp1,p);}\nvoid SetOutput(vec4 c){ocol0=c;}\n" % (W, H)
vs = "#version 330 core\nout vec2 v_tex0;\nvoid main(){vec2 p=vec2((gl_VertexID<<1)&2, gl_VertexID&2); v_tex0=vec2(p.x, 1.0-p.y); gl_Position=vec4(p*2.0-1.0,0.0,1.0);}\n"
def sh(kind, s):
    o = GL.glCreateShader(kind); GL.glShaderSource(o, s); GL.glCompileShader(o)
    assert GL.glGetShaderiv(o, GL.GL_COMPILE_STATUS), GL.glGetShaderInfoLog(o)
    return o
p = GL.glCreateProgram()
GL.glAttachShader(p, sh(GL.GL_VERTEX_SHADER, vs)); GL.glAttachShader(p, sh(GL.GL_FRAGMENT_SHADER, pre + src))
GL.glLinkProgram(p); assert GL.glGetProgramiv(p, GL.GL_LINK_STATUS), GL.glGetProgramInfoLog(p)
GL.glUseProgram(p)
for o, v in opts.items(): GL.glUniform1f(GL.glGetUniformLocation(p, o), float(v))
img = np.array(Image.open(sys.argv[2]).convert("RGBA"))  # top row first; v_tex0.y=0 is top
tex = GL.glGenTextures(1); GL.glBindTexture(GL.GL_TEXTURE_2D, tex)
GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, GL.GL_RGBA8, img.shape[1], img.shape[0], 0, GL.GL_RGBA, GL.GL_UNSIGNED_BYTE, img)
for k in (GL.GL_TEXTURE_MIN_FILTER, GL.GL_TEXTURE_MAG_FILTER): GL.glTexParameteri(GL.GL_TEXTURE_2D, k, GL.GL_LINEAR)
GL.glUniform1i(GL.glGetUniformLocation(p, "samp1"), 0)
GL.glBindVertexArray(GL.glGenVertexArrays(1))
GL.glViewport(0, 0, W, H); GL.glDrawArrays(GL.GL_TRIANGLES, 0, 3); GL.glFinish()
out = np.frombuffer(GL.glReadPixels(0, 0, W, H, GL.GL_RGBA, GL.GL_UNSIGNED_BYTE), np.uint8).reshape(H, W, 4)[::-1]
Image.fromarray(out[:, :, :3]).save(sys.argv[3])
print("defaults", opts, "mean", out[:, :, :3].mean().round(1), "src mean", img[:, :, :3].mean().round(1))
