module particle_compression;

import core.bitop;
import std.mathspecial;
import std.typecons;
import arithmetic_coder;
import bit_stream;
import kdtree;
import math;
import stats;
import bit_ops;

const double sqrt2 = sqrt(2.0);
const long all_nbins = 1 << 30;
const double epsilon = 1.0 / cast(double)(all_nbins);

// TODO: count the number of bits per level

/++ The Gaussian CDF. m = mean, s = standard deviation +/
double F(double m, double s, double x) {
  return 0.5 * std.mathspecial.erfc((m-x)/(s*sqrt2));
}

/++ The inverse Gaussian CDF. m = mean, s = standard deviation +/
double Finv(double m, double s, double y) {
  return m + s * (erfinv(2*y-1)*sqrt2);
}

const int scale = (1<<31)-1;
alias CodeVal = long;
/++ Binary probability model (0 happens with p probability, and 1 happens with 1-p probability) +/
struct ProbModel {
  CodeVal count_;
  CodeVal mid_; // anything below this is 0, otherwise it is 1
  mixin ModelConfigs!(CodeVal, 33, 31);


  // TODO: write this function?
  Prob!CodeVal get_prob(int s) {
    return Prob!CodeVal(0, 1, 1);
  }

  Prob!CodeVal get_val(CodeVal v, ref int s) {
    return Prob!CodeVal(0, 1, 1);
  }

  CodeVal get_count() { return count_; }
}
alias Coder = ArithmeticCoder!ProbModel;

/++ If the numbers of integers in [a,b] is even, we split the range into equal halves. If it is odd,
we split it so that the left half has one more integer than the right half +/
void encode_range(double m, double s, double a, double b, double c, ref Coder coder) {
  assert(a < b);
  while (true) {
    int beg = cast(int)ceil(a);
    int end = cast(int)floor(b);
    int nints = end - beg + 1;
    if (nints == 1) break; // we have narrowed down the number c
    /* compute F(a) and F(b) */
    double fa = F(m, s, a);
    double fb = F(m, s, b);
    double mid = (a+b) * 0.5;
    if ((nints&1) != 0) // there are an odd number of integers in [a,b]
      mid = floor(mid) + 0.5;
    double flo = fa;
    double fhi = F(m, s, mid);
    int lo, hi;
    if (c < mid) { // c falls on the left side
      lo = 0;
      hi = cast(int)((fhi-flo)/(fb-fa)*scale + 0.5);
      assert(lo<hi && hi<=scale);
    }
    else if (c > mid) { // c falls on the right side
      lo = cast(int)((fhi-flo)/(fb-fa)*scale + 0.5);
      hi = scale;
      assert(0<=lo && lo<hi);
    }
    else { // c == mid, cannot happen
      assert(false);
    }
    Prob!long prob = Prob!long(lo, hi, scale);
    coder.encode(prob);
    coder.encode_renormalize();
    if (c < mid)
      b = mid;
    else
      a = mid;
  }
}

/++ Assuming a Gaussian(m, s), and a range [a, b] (0<=a<=b<=N), and c (a<=c<=b), partition [a,b]
into two bins of equal probability +/
void encode_range(double m, double s, double a, double b, double c, ref BitStream bs) {
  assert(a < b);
  int beg = cast(int)ceil(a);
  int end = cast(int)floor(b);
  if (beg == end) return;
  /* compute F(a) and F(b) */
  double fa = F(m, s, a);
  double fb = F(m, s, b);
  /* compute F^-1((fa+fb)/2) */
  double mid = Finv(m, s, (fa+fb)*0.5);
  assert(a<=mid && mid<=b);
  if (a==mid || b==mid) {
    int v = cast(int)c-beg;
    int n = end - beg + 1;
    return encode_centered_minimal(v, n, bs);
  }
  assert(a<=mid && mid<=b);
  // TODO: should we take care of the case where there is only one whole number between a and mid?
  if (c < mid) {
    bs.write(0);
    if (a+1.5 < mid) {
      return encode_range(m, s, a, floor(mid)+0.5, c, bs);
    }
  }
  else { // c >= mid
    bs.write(1);
    if (mid+1 < b) {
      if (mid == cast(int)mid)
        return encode_range(m, s, mid, b, c, bs);
      else // mid is not a whole number
        return encode_range(m, s, ceil(mid), b, c, bs);
    }
  }
}

/++ The inverse of encode +/
int decode_range(double m, double s, double a, double b, ref BitStream bs) {
  assert(a < b);
  int beg = cast(int)ceil(a);
  int end = cast(int)floor(b);
  if (beg == end) return beg;
  /* compute F(a) and F(b) */
  double fa = F(m, s, a);
  double fb = F(m, s, b);
  /* compute F^-1((fa+fb)/2) */
  double mid = Finv(m, s, (fa+fb)*0.5);
  assert(a<=mid && mid<=b);
  if (a==mid || b==mid) {
    int n = end - beg + 1;
    return beg + decode_centered_minimal(n, bs);
  }
  assert(a<=mid && mid<=b);
  int bit = cast(int)bs.read();
  if (bit == 0) { // c < mid
    if (a+1 < mid)
      return decode_range(m, s, a, mid, bs);
    else
      return cast(int)ceil(a);
  }
  else { // c >= mid
    if (mid+1 <= b)
      return decode_range(m, s, mid, b, bs);
    else
      return cast(int)floor(b);
  }
}

/++ v is from 0 to n-1 +/
void encode_centered_minimal(uint v, uint n, ref BitStream bs) {
  assert(n > 0);
  assert(v < n);
  import std.stdio;
  int l1 = bsr(n);
  int l2 = ((1<<l1)==n) ? l1 : l1+1;
  int d = (1<<l2) - n;
  int m = (n-d) / 2;
  if (v < m) {
    bool print = false;
    v = bit_reverse(v);
    v >>= v.sizeof*8 - l2;
    bs.write(v, l2);
    //writefln("%04b", v);
  }
  else if (v >= m+d) {
    v = bit_reverse(v-d);
    v >>= v.sizeof*8 - l2;
    bs.write(v, l2);
    //writefln("%04b", v-d);
  }
  else { // middle
    v = bit_reverse(v);
    v >>= v.sizeof*8 - l1;
    bs.write(v, l1);
    //writefln("%03b", v);
  }
}

int decode_centered_minimal(uint n, ref BitStream bs) {
  assert(n > 0);
  import std.stdio;
  int l1 = bsr(n);
  int l2 = ((1<<l1)==n) ? l1 : l1+1;
  uint d = (1<<l2) - n;
  uint m = (n-d) / 2;
  bs.refill(); // TODO: minimize the number of refill
  uint v = cast(int)bs.peek(l2);
  v <<= v.sizeof*8 - l2;
  v = bit_reverse(v);
  if (v < m) {
    bs.consume(l2);
    return v;
  }
  else if (v < 2*m) {
    bs.consume(l2);
    return v+d;
  }
  else {
    bs.consume(l1);
    return v >> 1;
  }
}

/++ For debugging purposes +/
void encode_array(int N, int[] nums, ref BitStream bs) {
  import std.stdio;
  float m = float(N) / 2; // mean
  float s = sqrt(float(N)) / 2; // standard deviation
  bs.init_write(100000000); // 100 MB // TODO
  foreach (n; nums) {
    encode_range(m, s, 0, N, n, bs);
    //encode_centered_minimal(n, N+1, bs); // uniform
  }
  //int N = cast(int)positions.length;
  bs.flush();
}

void encode(T)(KdTree!(T, Root) tree, ref Coder coder) {
  void traverse_encode(T,int R)(KdTree!(T,R) parent, ref Coder coder) {
    int N = parent.end_ - parent.begin_;
    if (N == 1) { // leaf level
      // do nothing
    }
    else { // non leaf
      int n = parent.left_ is null ? 0 : parent.left_.end_ - parent.left_.begin_;
      float m = float(N) / 2; // mean
      float s = sqrt(float(N)) / 2; // standard deviation
      encode_range(m, s, -0.5, N+0.5, n, coder);
      if (parent.left_)
        traverse_encode(parent.left_, coder);
      if (parent.right_)
        traverse_encode(parent.right_, coder);
    }
  }
  coder.encode_init(100000000);
  int N = tree.end_ - tree.begin_;
  coder.bit_stream_.write(N, 32);
  //File enc_file = File("encode.txt", "w");
  traverse_encode(tree, coder);
  coder.encode_finalize();
}

void encode(T)(KdTree!(T, Root) tree, ref BitStream bs) {
  import std.stdio;
  void traverse_encode(T,int R)(KdTree!(T,R) parent, ref BitStream bs) {
    int N = parent.end_ - parent.begin_;
    if (N == 1) { // leaf level
      // do nothing
    }
    else { // non leaf
      int n = parent.left_ is null ? 0 : parent.left_.end_ - parent.left_.begin_;
      float m = float(N) / 2; // mean
      float s = sqrt(float(N)) / 2; // standard deviation
      encode_range(m, s, -0.5, N+0.5, n, bs);
      //encode_centered_minimal(n, N+1, bs); // uniform
      enc_file.writeln(n);
      if (parent.left_)
        traverse_encode(parent.left_, bs);
      if (parent.right_)
        traverse_encode(parent.right_, bs);
    }
  }
  /* pre-compute and store a table of inverse gaussian(0,1) cdf */
  bs.init_write(100000000); // 100 MB // TODO
  //int N = cast(int)positions.length;
  int N = tree.end_ - tree.begin_;
  bs.write(N, 32);
  File enc_file = File("encode.txt", "w");
  traverse_encode(tree, bs);
  bs.flush();
}

void decode(ref BitStream bs) {
  import std.stdio;
  void traverse_decode(T)(int N, ref BitStream bs) {
    if (N == 1) { // leaf level
      // do nothing
    }
    else { // non leaf
      float m = float(N) / 2; // mean
      float s = sqrt(float(N)) / 2; // standard deviation
      //int n = decode_range(m, s, 0, N, bs);
      int n = decode_centered_minimal(N+1, bs); // uniform
      dec_file.writeln(n);
      if (n > 0)
        traverse_decode!T(n, bs);
      if (n < N)
        traverse_decode!T(N-n, bs);
    }
  }

  bs.init_read();
  int N = cast(int)bs.read(32);
  File dec_file = File("decode.txt", "w");
  dec_file.writeln(N);
  traverse_decode!int(N, bs);
}
