module math;

import std.math;
import std.traits;

/++ 3D vector (x, y, z) +/
struct Vec3(T)
if (isNumeric!T) {
  T[3] p;
  alias p this;
  @property ref T x() { return p[0]; }
  @property ref T y() { return p[1]; }
  @property ref T z() { return p[2]; }
  @property T x() const { return p[0]; }
  @property T y() const { return p[1]; }
  @property T z() const { return p[2]; }

  this(T x_, T y_, T z_) {
    x = x_; y = y_; z = z_;
  }
  this(T[3] v) {
    p = v;
  }

  Vec3!T opBinary(string op)(const Vec3!T rhs) const {
    return mixin("Vec3!T(x "~op~" rhs.x, y "~op~" rhs.y, z "~op~" rhs.z)");
  }

  Vec3!T opBinary(string op)(T v) const {
    return mixin("Vec3!T(x "~op~" v, y "~op~" v, z "~op~" v)");
  }
}

long xyz2i(T)(Vec3!T n, Vec3!T v) {
  auto vl = Vec3!long(v.x, v.y, v.z);
  return vl.z*n.x*n.y + vl.y*n.x + vl.x;
}

long product(T)(Vec3!T v) {
  auto vl = Vec3!long(v.x, v.y, v.z);
  return vl.x * vl.y * vl.z;
}

T sum(T)(Vec3!T v) {
  return v.x + v.y + v.z;
}

T sqr_norm(T)(Vec3!T v) {
  return v.x*v.x + v.y*v.y + v.z*v.z;
}

long product(T)(T[3] v) {
  return cast(long)v[0] * cast(long)v[1] * cast(long)v[2];
}

unittest {
  auto x = Vec3!int(1000, 2000, 4000);
  auto n = Vec3!int(2048, 2048, 2048);
  auto i = xyz2i(n, x);
  assert(i == 16781313000);
}

/++ Approixmate log2(C(n, m)) with Sterling formula +/
double log2_C_n_m_sterling(int n, int m) {
  assert(n>=m);
  if (n == m) {
    return 0;
  }
  return n*log2(n) - m*log2(m) - (n-m)*log2(n-m);
}

double log2_C_n_m(int n, int m) {
  assert(n>=m);
  if (n == m) {
    return 0;
  }
  double s = 0;
  for (double i = 1; i <= m; ++i) {
    s += log2((n+1-i)/i);
  }
  return s;
}

T square(T)(T val) {
  return val*val;
}