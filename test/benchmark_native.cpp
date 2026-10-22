#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <dlfcn.h>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

using Kernel = void (*)(uint32_t *, const uint32_t *, const uint32_t *, uint64_t);
struct Workload { const char *Name; unsigned Width, Stride; };
const Workload Workloads[] = {{"add2",2,1},{"add8",8,1},{"sub8",8,1},{"mul8",8,1},{"mixed8",8,1},{"affine8",8,1},{"strided4",4,2},{"add16",16,1}};

uint32_t expected(const Workload &W, size_t I, uint32_t A, uint32_t B) {
  if (std::strcmp(W.Name, "sub8") == 0) return A - B;
  if (std::strcmp(W.Name, "mul8") == 0) return A * B;
  if (std::strcmp(W.Name, "affine8") == 0) return A * B + 17;
  if (std::strcmp(W.Name, "mixed8") == 0) {
    unsigned Op = (I % W.Width) % 3;
    return Op == 0 ? A+B : Op == 1 ? A-B : A*B;
  }
  return A+B;
}

int main(int Argc, char **Argv) { try {
  if (Argc < 3) throw std::runtime_error("usage: native-suite --smoke|--measure|--profile library.so ...");
  bool Smoke = std::strcmp(Argv[1], "--smoke") == 0;
  bool Profile = std::strcmp(Argv[1], "--profile") == 0;
  if (!Smoke && !Profile && std::strcmp(Argv[1], "--measure") != 0) throw std::runtime_error("invalid mode");
  std::vector<void *> Libraries;
  for (int I=2; I<Argc; ++I) {
    void *Library = dlopen(Argv[I], RTLD_NOW | RTLD_LOCAL);
    if (!Library) throw std::runtime_error(dlerror());
    Libraries.push_back(Library);
  }
  std::cout << "kernel,elements,side,repeat,ns_per_element,finished,failed,checksum\n";
  std::vector<size_t> Sizes = Smoke ? std::vector<size_t>{16384} : Profile ? std::vector<size_t>{1048576} : std::vector<size_t>{16384,1048576,8388608};
  uint64_t Sink = 0;
  for (const auto &W : Workloads) for (size_t N : Sizes) {
    std::vector<uint32_t> A(N*W.Stride), B(A.size()), Out(A.size()), Oracle(A.size(),0xdeadbeef);
    for (size_t I=0; I<A.size(); ++I) { A[I] = uint32_t(I*747796405ULL+2891336453ULL); B[I] = uint32_t(I*277803737ULL+UINT32_MAX); }
    for (size_t I=0; I<N; ++I) Oracle[I*W.Stride] = expected(W,I,A[I*W.Stride],B[I*W.Stride]);
    std::vector<Kernel> Functions;
    for (void *Library : Libraries) {
      auto Fn = reinterpret_cast<Kernel>(dlsym(Library,W.Name));
      if (!Fn) throw std::runtime_error("kernel missing");
      Functions.push_back(Fn);
      std::fill(Out.begin(),Out.end(),0xdeadbeef);
      Fn(Out.data(),A.data(),B.data(),N);
      if (Out != Oracle) throw std::runtime_error(std::string("warm oracle mismatch ")+W.Name);
      for (unsigned I=0; I<3; ++I) Fn(Out.data(),A.data(),B.data(),N);
    }
    if (Smoke) continue;
    unsigned Repeats = Profile ? 1 : 7, Calls = Profile ? 100 : 8;
    for (unsigned Round=0; Round<Repeats; ++Round) for (size_t Position=0; Position<Functions.size(); ++Position) {
      size_t Side = (Round+Position)%Functions.size();
      std::fill(Out.begin(),Out.end(),0xdeadbeef);
      auto Start = std::chrono::steady_clock::now();
      for (unsigned Call=0; Call<Calls; ++Call) Functions[Side](Out.data(),A.data(),B.data(),N);
      double Ns = std::chrono::duration<double,std::nano>(std::chrono::steady_clock::now()-Start).count()/(Calls*N);
      if (Out != Oracle) throw std::runtime_error(std::string("sample oracle mismatch ")+W.Name);
      Sink += Out[0] + Out[(N-1)*W.Stride];
      std::string SideName=Argv[Side+2];
      SideName=SideName.substr(SideName.find_last_of('/')+1);
      std::cout << W.Name << ',' << N << ',' << SideName << ',' << Round << ',' << Ns << ',' << Calls << ",0," << Sink << '\n';
    }
  }
  for (void *Library : Libraries) dlclose(Library);
  std::cerr << "PASS independent_oracle sentinel_stride warmup cleanup checksum=" << Sink << '\n';
  return 0;
} catch (const std::exception &Error) { std::cerr << "FAIL " << Error.what() << '\n'; return 1; } }
