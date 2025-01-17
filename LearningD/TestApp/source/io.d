module io;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.format;
import std.math;
import std.json;
import std.path;
import std.stdio;
import std.variant;
import array;
import expected;
import math;

/++ Read a raw binary file +/
Expected!(T[]) read_raw(T)(const string file_name) {
  try {
    return Expected!(T[])(cast(T[])std.file.read(file_name));
  }
  catch (Exception e) {
    return Expected!(T[])(e);
  }
}

/++ Write a raw binary file +/
Expected!bool write_raw(T)(const string file_name, const T[] data) {
  try {
    std.file.write(file_name, data);
    return Expected!bool(true);
  }
  catch (Exception e) {
    return Expected!bool(e);
  }
}

/++ Write an array to a raw text file +/
Expected!bool write_text(R)(const string file_name, R data, const string mode="w") {
  try {
    auto file = File(file_name, mode);
    foreach (e; data) {
      file.writefln("%s", e);
    }
    return Expected!bool(true);
  }
  catch (Exception e) {
    return Expected!bool(e);
  }
}

/++ Read data from a text file to an array +/
Expected!(T[]) read_text(string format, T)(const string file_name) {
  T[] data;
  try {
    auto file = File(file_name, "r");
    T val;
    while (file.readf(format, val)) {
      data ~= val;
    }
    return Expected!(T[])(data);
  }
  catch (Exception e) {
    return Expected!(T[])(e);
  }
}

struct Dataset {
  JSONValue metadata;
  // below is a sample json metadata
  //{
  //  "file": "tacc-turbulence-256x256x256-float32.raw",
  //  "name": "tacc",
  //  "field": "turbulence",
  //  "dimensionality": 3,
  //  "dims": [
  //    256,
  //    256,
  //    256
  //  ],
  //  "dtype": "float32"
  //}
  Variant data; // store a buffer to the actual data, typically of the Array3D type
}

/++ Read a json data set, including reading the raw data file from disk +/
Expected!Dataset read_json(const string file_name) {
  import std.array : array;
  Dataset d;
  try {
    string s = readText(file_name);
    d.metadata = parseJSON(s);
    auto dims = Vec3!int(to!(int[3])(d.metadata["dims"].array.map!(a => a.integer).array));
    auto raw_path = absolutePath(d.metadata["file"].str, absolutePath(dirName(file_name)));
    d.metadata["file"] = raw_path;
    writeln(d.metadata["file"]);
    string type_case(string type_name1, string type_name2)() {
      return
        "case \"" ~ type_name1 ~ "\":" ~
        "auto raw_buf = read_raw!" ~ type_name2 ~ "(raw_path);" ~
        "d.data = new Array3D!" ~ type_name2 ~ "(dims, raw_buf.value());" ~
        "break;";
    }
    switch (d.metadata["dtype"].str) {
      mixin (type_case!("int8", "byte"));
      mixin (type_case!("uint8", "ubyte"));
      mixin (type_case!("int16", "short"));
      mixin (type_case!("uint16", "ushort"));
      mixin (type_case!("int32", "int"));
      mixin (type_case!("uint32", "uint"));
      mixin (type_case!("int64", "long"));
      mixin (type_case!("uint64", "ulong"));
      mixin (type_case!("float32", "float"));
      mixin (type_case!("float64", "double"));
      default:
        throw new Exception("dtype not supported");
    }
    return Expected!(Dataset)(d);
  }
  catch (Exception e) {
    return Expected!(Dataset)(e);
  }
}
unittest {
  read_json("flame-64x64x64-float64.json");
}

/++ Read all the points from a hex mesh file (skip the hexes) +/
ParticleArray!double parse_hex_meshes(const string file_name) {
  auto file = File(file_name, "r");
  int npoints;
  char[] buf;
  file.readln(buf);
  string temp;
  buf.formattedRead!"# %s %s"(npoints, temp);
  ParticleArray!double particles;
  particles.position.length = 1;
  while (true) {
    if (!file.readln(buf)) {
      break;
    }
    if (buf[0]=='#') {
      continue;
    }
    else if (buf[0] == 'v') {
      double x, y, z;
      buf.formattedRead!"v %s %s %s"(x, y, z);
      particles.position[0] ~= Vec3!double(x, y, z);
    }
    else if (particles.position[0].length != npoints) {
      continue;
    }
    else {
      break;
    }
  }
  enforce(particles.position[0].length==npoints, "Number of particles mismatched");
  return particles;
}

alias ParticlePos = Vec3!float;

/++ Store particle data in all time steps +/
struct ParticleArray(T) {
  BoundingBox!T bbox;
  Vec3!T[][] position;
  Vec3!T[][] velocity;
  T[][] concentration;
}

/++ Read all particles from a GRO file +/
ParticleArray!T parse_gro(T)(const string file_name) {
  auto file = File(file_name, "r");
  ParticleArray!T particles;

  char[] line;
  int nparticles = 0;
  int i = 0;
  int timestep = 0;
  while (true) {
    file.readln(line);
    if (file.eof) {
      break;
    }
    float time;
    bool new_time_step = line.startsWith("Generated");
    if (new_time_step) {
      line.formattedRead!"Generated by trjconv : Dzugutov system t= %s"(time);
      file.readln(line); // number of particles
      nparticles = to!int(line[0..$-1]);
      ++particles.position.length;
      ++particles.velocity.length;
    }
    else { // within a time step
      if (i < nparticles) {
        T px, py, pz, vx, vy, vz;
        int temp;
        line.formattedRead!" %d DZATO DZ %d %f %f %f %f %f %f"(temp, temp, px, py, pz, vx, vy, vz);
        ++i;
        assert(timestep < particles.position.length);
        particles.position[timestep] ~= Vec3!T(px, py, pz);
        particles.velocity[timestep] ~= Vec3!T(vx, vy, vz);
      }
      else { // finished reading all particles in the current time step
        i = 0;
        ++timestep;
        T bx, by, bz;
        line.formattedRead!" %f %f %f"(bx, by, bz);
        particles.bbox.max = Vec3!T(bx, by, bz);
      }
    }
  }
  particles.bbox.min = Vec3!T(0, 0, 0);
  return particles;
}

/++ Read all particles from a XYZ file +/
ParticleArray!T parse_xyz(T)(const string file_name) {
  auto file = File(file_name, "r");
  ParticleArray!T particles;

  char[] line;
  file.readln(line);
  int nparticles = to!int(line[0..$-1]);
  file.readln(line); // dummy second line
  int timestep = 0;
  particles.position.length = 1;
  string c;
  for (int i = 0; i<nparticles && !file.eof; ++i) {
    file.readln(line);
    float px, py, pz;
    line.formattedRead!"%s %s %s %s"(c, px, py, pz);
    particles.position[0] ~= Vec3!T(px, py, pz);
  }
  return particles;
}

void dump_xyz(T)(const string file_name, Vec3!T[] particles) {
  auto file = File(file_name, "w");
  int nparticles = cast(int)particles.length;
  file.writeln(nparticles);
  file.writeln("dummy");
  for (int i = 0; i < nparticles; ++i) {
    file.writeln("C ", particles[i].x, " ", particles[i].y, " ", particles[i].z);
  }
}

/++ Read particles in the vtu format (e.g., VIS 2016 contest
// TODO: this function reads only one time step +/
ParticleArray!float parse_vtu(const string file_name) {
  struct Header {
    uint pad3;
    uint size;
    uint pad1;
    uint step;
    uint pad2;
    float time;
  }
  auto fp = File(file_name, "rb");

  ParticleArray!float particles;
  Header[1] header;
  int magic_offset = 4072;
  fp.seek(magic_offset, SEEK_SET);
  fp.rawRead(header);
  auto size = header[0].size;
  writeln(header[0].size);
  particles.position ~= new Vec3!float[](size);
  particles.velocity ~= new Vec3!float[](size);
  particles.concentration ~= new float[](size);
  fp.seek(4, SEEK_CUR);
  fp.rawRead(particles.position[0]);
  fp.seek(4, SEEK_CUR);
  fp.rawRead(particles.velocity[0]);
  fp.seek(4, SEEK_CUR);
  fp.rawRead(particles.concentration[0]);
  return particles;
}

/++ Parse cosmology simulation data from Mengjiao +/
ParticleArray!float parse_cosmo(const string file_name) {
  struct CosmicWebHeader {
    int np_local; // number of particles
    float a, t, tau;
    int nts;
    float dt_f_acc, dt_pp_acc, dt_c_acc;
    int cur_checkpoint, cur_projection, cur_halofind;
    float massp;
  }
  auto fp = File(file_name, "rb");
  CosmicWebHeader[1] header;
  fp.rawRead(header);
  writeln("number of particles = ", header[0].np_local);
  ParticleArray!float particles;
  particles.position ~= new Vec3!float[](header[0].np_local);
  particles.velocity ~= new Vec3!float[](header[0].np_local);
  for (int i = 0; i < header[0].np_local; ++i) {
    fp.rawRead(particles.position[0][i..i+1]);
    fp.rawRead(particles.velocity[0][i..i+1]);
  }
  return particles;
}

/++ Convert a ParticleArray from one type to another +/
ParticleArray!T2 convert_type(T2, T1)(const ParticleArray!T1 particles) {
  ParticleArray!T2 out_particles;
  string s(string m)() {
    return
      "if (particles."~m~" !is null) {" ~
        "out_particles."~m~".length = particles."~m~".length;" ~
        "for (size_t i = 0; i < particles."~m~".length; ++i) {" ~
          "out_particles."~m~"[i].length = particles."~m~"[i].length;" ~
          "for (size_t j = 0; j < particles."~m~"[i].length; ++j) {" ~
            "auto p = particles."~m~"[i][j];" ~
            "out_particles."~m~"[i][j] = math.convert_type!(T2, T1)(p);" ~
          "}" ~
        "}" ~
      "}";
  }
  foreach (m; __traits(allMembers, ParticleArray!float)) {
    static if (m != "bbox") {
      mixin (s!m());
    }
  }
  return out_particles;
}

Vec3!T2[] convert_particle_type(T2, T1)(Vec3!T1[] particles) {
  Vec3!T2[] out_particles;
  out_particles.length = particles.length;
  for (size_t i = 0; i < particles.length; ++i) {
    auto p = particles[i];
    out_particles[i] = math.convert_type!(T2, T1)(p);
  }
  return out_particles;
}

/++ Group particles every k time steps. TODO: we probably don't need to explicitly perform this concatenation. +/
ParticleArray!T concat_time_steps(T)(const ParticleArray!T particles, int k) {
  ParticleArray!T out_particles;
  string s(string m)() {
    return
      "out_particles."~m~".length = (particles."~m~".length + k-1) / k;" ~
      "for (int i = 0; i < out_particles."~m~".length; ++i) {" ~
        "for (int j = 0; j < k; ++j) {" ~
          "out_particles."~m~"[i] ~= particles."~position~"[i*k+j];" ~
        "}" ~
      "}";
  }
  foreach (m; __traits(allMembers, ParticleArray!float)) {
    mixin (s!m());
  }
  return out_particles;
}

/++ Undo the process that makes a particle enter the boundary from the other side if it goes out of the simulation box +/
void undo_periodic_boundary(T)(ref ParticleArray!T particles) {
  assert(particles.position.length > 0); // has at least one time step
  auto full_box = particles.bbox.max - particles.bbox.min;
  auto half_box = full_box / 2;
  for (int i = 0; i < particles.position[0].length; ++i) { // each particle
    for (int j = 1; j < particles.position.length; ++j) { // each time step
      Vec3!T* pos_curr = &particles.position[j  ][i];
      Vec3!T* pos_prev = &particles.position[j-1][i];
      for (int k = 0; k < 3; ++k) {
        T d = (*pos_curr)[k] - (*pos_prev)[k];
        if (abs(d) >= half_box[k]) {
          if (d < 0) {
            (*pos_curr)[k] = (*pos_prev)[k] + full_box[k] + d;
          }
          else {
            (*pos_curr)[k] = (*pos_prev)[k] - full_box[k] + d;
          }
        }
      }
    }
  }
}
