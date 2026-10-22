#include <array>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <utility>
#include <vector>

extern "C" uint32_t slp_add2(uint32_t, uint32_t, uint32_t, uint32_t);
extern "C" void slp_add2_ptr(uint32_t *, const uint32_t *, const uint32_t *);
extern "C" void slp_add2_volatile(uint32_t *, const uint32_t *,
                                   const uint32_t *);

__declspec(noinline) uint32_t scalar_add2(uint32_t A, uint32_t B, uint32_t C,
                                          uint32_t D) {
  return (A + B) + (C + D);
}

struct Inputs {
  uint32_t A;
  uint32_t B;
  uint32_t C;
  uint32_t D;
};

static uint32_t next(uint32_t &State) {
  State ^= State << 13;
  State ^= State >> 17;
  State ^= State << 5;
  return State;
}

template <typename Fn> static double timeCalls(Fn Function,
                                                const std::vector<Inputs> &Data,
                                                uint64_t &Sink) {
  volatile uint64_t Sum = 0;
  auto Start = std::chrono::steady_clock::now();
  for (const Inputs &I : Data)
    Sum += Function(I.A, I.B, I.C, I.D);
  auto Stop = std::chrono::steady_clock::now();
  Sink += Sum;
  return std::chrono::duration<double, std::nano>(Stop - Start).count() /
         Data.size();
}

int main() {
  constexpr std::array<uint32_t, 8> Edges = {
      0, 1, 2, UINT32_MAX, UINT32_MAX - 1, 0x80000000u, 0x7fffffffu,
      0x55555555u};
  std::vector<Inputs> Data;
  for (uint32_t A : Edges)
    for (uint32_t B : Edges)
      Data.push_back({A, B, A, B});
  uint32_t State = 0x9e3779b9u;
  for (unsigned I = 0; I != 65536; ++I)
    Data.push_back({next(State), next(State), next(State), next(State)});

  for (const Inputs &I : Data)
    if (scalar_add2(I.A, I.B, I.C, I.D) !=
        slp_add2(I.A, I.B, I.C, I.D)) {
      std::cerr << "native differential mismatch\n";
      return 1;
    }
  std::cout << "DIFFERENTIAL_OK inputs=" << Data.size() << '\n';

  auto checkPointers = [](bool Volatile) {
    for (unsigned Alias = 0; Alias != 4; ++Alias) {
      std::array<uint32_t, 4> A = {3, UINT32_MAX, 7, 9};
      std::array<uint32_t, 4> B = {11, 13, UINT32_MAX, 17};
      std::array<uint32_t, 2> SeparateOut{};
      uint32_t *Out = Alias == 1 ? A.data() : Alias == 2 ? B.data()
                                                          : SeparateOut.data();
      const uint32_t *Left = A.data();
      const uint32_t *Right = Alias == 3 ? A.data() : B.data();
      uint32_t Left0 = Left[0] + Right[0];
      uint32_t Left1 = Left[1] + Right[1];
      if (Volatile)
        slp_add2_volatile(Out, Left, Right);
      else
        slp_add2_ptr(Out, Left, Right);
      const uint32_t *Actual = Out;
      if (Actual[0] != Left0 || Actual[1] != Left1) {
        std::cerr << "alias mismatch volatile=" << Volatile << " case="
                  << Alias << " actual=" << Actual[0] << ',' << Actual[1]
                  << " expected=" << Left0 << ',' << Left1 << '\n';
        return false;
      }
    }
    return true;
  };
  if (!checkPointers(false) || !checkPointers(true)) {
    std::cerr << "native pointer-alias differential mismatch\n";
    return 1;
  }
  std::cout << "ALIAS_DIFFERENTIAL_OK cases=8\n";

  std::array<double, 9> ScalarNs{};
  std::array<double, 9> VectorNs{};
  uint64_t Sink = 0;
  for (unsigned Round = 0; Round != ScalarNs.size(); ++Round) {
    if (Round % 2 == 0) {
      ScalarNs[Round] = timeCalls(scalar_add2, Data, Sink);
      VectorNs[Round] = timeCalls(slp_add2, Data, Sink);
    } else {
      VectorNs[Round] = timeCalls(slp_add2, Data, Sink);
      ScalarNs[Round] = timeCalls(scalar_add2, Data, Sink);
    }
  }
  auto Median = [](std::array<double, 9> Values) {
    for (size_t I = 0; I != Values.size(); ++I)
      for (size_t J = I + 1; J != Values.size(); ++J)
        if (Values[J] < Values[I])
          std::swap(Values[I], Values[J]);
    return Values[Values.size() / 2];
  };
  std::cout << "INTERLEAVED_MEDIAN_NS scalar=" << Median(ScalarNs)
            << " vector=" << Median(VectorNs) << " sink=" << Sink << '\n';
  std::cout << "INTERLEAVED_ROUNDS_NS scalar=";
  for (double Ns : ScalarNs)
    std::cout << Ns << ',';
  std::cout << " vector=";
  for (double Ns : VectorNs)
    std::cout << Ns << ',';
  std::cout << '\n';
}
