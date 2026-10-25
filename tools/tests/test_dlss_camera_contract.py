"""Asset-free regression of the shipped Streamline camera patch stack.

Compile the actual matrix-converter bodies and compare SDK row-vector uploads
with independent world-to-camera projection. No GPU or DLSS runtime is implied.
Run with unittest discovery; CL_DLSS_AUDIT_OUTPUT optionally retains metrics.
"""
import ctypes
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
RELATIVE = Path("servers/rendering/renderer_rd/effects/dlss.cpp")

def mm(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def mv(a, b):
    return [sum(a[i][k] * b[k] for k in range(4)) for i in range(4)]


def identity():
    return [[float(i == j) for j in range(4)] for i in range(4)]


def inv(a):
    m = [row[:] + eye for row, eye in zip(a, identity())]
    for i in range(4):
        pivot = max(range(i, 4), key=lambda j: abs(m[j][i]))
        m[i], m[pivot] = m[pivot], m[i]
        d = m[i][i]
        assert abs(d) > 1e-14
        m[i] = [x / d for x in m[i]]
        for j in range(4):
            if j != i:
                f = m[j][i]
                m[j] = [x - f * y for x, y in zip(m[j], m[i])]
    return [row[4:] for row in m]


def perspective(fov=70.0, aspect=16 / 9, near=0.05, far=1000.0):
    y = 1 / math.tan(math.radians(fov) * 0.5)
    return [[y / aspect, 0, 0, 0], [0, y, 0, 0],
            [0, 0, -(far + near) / (far - near), -2 * near * far / (far - near)],
            [0, 0, -1, 0]]


def pose(x=0, y=0, z=0, yaw=0, pitch=0, roll=0):
    a, b, c = map(math.radians, (yaw, pitch, roll))
    cy, sy, cp, sp, cr, sr = math.cos(a), math.sin(a), math.cos(b), math.sin(b), math.cos(c), math.sin(c)
    ry = [[cy, 0, sy, 0], [0, 1, 0, 0], [-sy, 0, cy, 0], [0, 0, 0, 1]]
    rx = [[1, 0, 0, 0], [0, cp, -sp, 0], [0, sp, cp, 0], [0, 0, 0, 1]]
    rz = [[cr, -sr, 0, 0], [sr, cr, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
    result = mm(mm(ry, rx), rz)
    for i, v in enumerate((x, y, z)):
        result[i][3] = v
    return result


def screen(clip):
    return [(clip[0] / clip[3] * 0.5 + 0.5) * 3840,
            (0.5 - clip[1] / clip[3] * 0.5) * 2160,
            clip[2] / clip[3]]



def sources(directory):
    patch = (REPO / "engine_patches/godot-4.7/restore-dlss.patch").read_text()
    marker = "diff --git a/" + str(RELATIVE) + " b/" + str(RELATIVE)
    section = patch.split(marker, 1)[1].split("\ndiff --git ", 1)[0]
    assert "new file mode" in section
    baseline = "".join(line[1:] for line in section.splitlines(True)
                       if line.startswith("+") and not line.startswith("+++"))
    file = directory / RELATIVE
    file.parent.mkdir(parents=True)
    file.write_text(baseline)
    subprocess.run(["git", "apply", str(REPO / "engine_patches/godot-4.7/dlss-camera-contract.patch")],
                   cwd=directory, check=True, capture_output=True)
    return baseline, file.read_text()


def converter(source, directory, name):
    actual = re.search(r"static sl::float4x4 sl_convert_matrix\(const Projection &mtx\) \{.*?\n\}", source, re.S).group()
    # Minimal storage types reproduce setRow and field access only. Matrix
    # convention is tested independently by forward-projecting world points.
    unit = """namespace sl {
struct float4 { float x,y,z,w; float4(float a,float b,float c,float d):x(a),y(b),z(c),w(d){} float4():x(0),y(0),z(0),w(0){} };
struct float4x4 { float4 rows[4]; void setRow(int i,float4 row){rows[i]=row;} float4 operator[](int i)const{return rows[i];} };
}
struct V4 { float x,y,z,w; }; struct Projection { V4 columns[4]; };
""" + actual + """
extern "C" void convert(const float *in,float *out) {
 Projection p; for(int i=0;i<4;i++)p.columns[i]={in[i*4],in[i*4+1],in[i*4+2],in[i*4+3]};
 sl::float4x4 r=sl_convert_matrix(p);
 for(int i=0;i<4;i++){out[i*4]=r[i].x;out[i*4+1]=r[i].y;out[i*4+2]=r[i].z;out[i*4+3]=r[i].w;}
}
"""
    cpp = directory / (name + ".cpp"); library = directory / (name + ".so")
    cpp.write_text(unit)
    subprocess.run(["g++", "-shared", "-fPIC", "-O2", "-std=c++17", str(cpp), "-o", str(library)],check=True,capture_output=True)
    dll = ctypes.CDLL(str(library))
    dll.convert.argtypes = [ctypes.POINTER(ctypes.c_float), ctypes.POINTER(ctypes.c_float)]
    def upload(matrix):
        data = (ctypes.c_float * 16)(*[matrix[i][j] for j in range(4) for i in range(4)])
        out = (ctypes.c_float * 16)();dll.convert(data,out)
        return [[float(out[i*4+j]) for j in range(4)] for i in range(4)]
    return upload


def row_transform(vector, rows):
    return [sum(vector[k]*rows[k][j] for k in range(4)) for j in range(4)]


def audit(source, upload):
    helper = [[1,0,0,0],[0,-1,0,0],[0,0,-1,0],[0,0,0,1]]
    basis = [[1,0,0,0],[0,-1,0,0],[0,0,.5,.5],[0,0,0,1]]
    corrected = "constants.clipToPrevClip = sl_convert_matrix(streamline_reprojection)" in source
    if corrected:
        assert "streamline_clip_from_decoder.set_depth_correction(true, false, true)" in source
        assert "streamline_clip_from_decoder * p_params.reprojection * streamline_clip_from_decoder.inverse()" in source
    views = [pose(),pose(x=.1),pose(y=.05),pose(z=-.1),pose(yaw=1),pose(pitch=1),pose(roll=1),pose(x=.1,y=.03,z=-.07,yaw=1,pitch=.7,roll=.3)]
    errors=[]
    for fov in [50,70,100]:
        decoder_projection = mm(helper,perspective(fov))
        sdk_projection = mm(basis,decoder_projection)
        for current in views:
            reprojection = mm(mm(decoder_projection,current),inv(decoder_projection))
            rows = upload(mm(mm(basis,reprojection),inv(basis)) if corrected else reprojection)
            for distance in [1,3,5,10,50,250]:
                for u in [-.75,-.25,0,.25,.75]:
                    for v in [-.7,0,.7]:
                        local=[u*distance/sdk_projection[0][0],v*distance/sdk_projection[1][1],-distance,1]
                        expected=screen(mv(sdk_projection,mv(current,local)))
                        actual=screen(row_transform(mv(sdk_projection,local),rows))
                        errors.append(math.hypot(actual[0]-expected[0],actual[1]-expected[1]))
    projection = mm(helper,perspective())
    rows=upload(mm(basis,projection) if corrected else projection)
    depths={}
    for label,distance in [("near",.05),("far",1000)]:
        c=row_transform([0,0,-distance,1],rows);depths[label]=c[2]/c[3]
    return {"point_cases":len(errors),"max_pixel_error":max(errors),"failed_points":sum(e>.01 for e in errors),"depths":depths,"source_sha256":hashlib.sha256(source.encode()).hexdigest()}


class CameraContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        work=Path(os.environ.get("CL_TEST_WORK",str(REPO.parent/"test-work")));work.mkdir(parents=True,exist_ok=True)
        cls.temp=tempfile.TemporaryDirectory(prefix="dlss-camera-",dir=work)
        directory=Path(cls.temp.name)
        before,after=sources(directory)
        cls.results={name:audit(source,converter(source,directory,name)) for name,source in [("baseline",before),("corrected",after)]}
        output=os.environ.get("CL_DLSS_AUDIT_OUTPUT")
        if output:Path(output).write_text(json.dumps(cls.results,indent=2)+"\n")

    @classmethod
    def tearDownClass(cls):cls.temp.cleanup()

    def test_negative_control_reproduces_bad_camera_motion(self):
        self.assertEqual(self.results["baseline"]["point_cases"],2160)
        self.assertGreater(self.results["baseline"]["failed_points"],1000)

    def test_camera_motion_matches_independent_projection(self):
        self.assertEqual(self.results["corrected"]["point_cases"],2160)
        self.assertEqual(self.results["corrected"]["failed_points"],0)
        self.assertLess(self.results["corrected"]["max_pixel_error"],.01)

    def test_sdk_reverse_depth_contract(self):
        self.assertAlmostEqual(self.results["corrected"]["depths"]["near"],1,places=6)
        self.assertAlmostEqual(self.results["corrected"]["depths"]["far"],0,places=6)


if __name__ == "__main__":unittest.main()
