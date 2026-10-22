//==============================================================================
// Bounded, integer-only basic-block SLP with greedy and bounded exact packing.
// License: MIT
//==============================================================================
#include "BoundedSLP.h"

#include "llvm/ADT/SmallVector.h"
#include "llvm/Analysis/TargetTransformInfo.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/InstIterator.h"
#include "llvm/IR/Instructions.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Plugins/PassPlugin.h"

#include <array>
#include <cstdint>
#include <vector>

using namespace llvm;

namespace {
using Pair = std::pair<BinaryOperator *, BinaryOperator *>;

bool sameOperation(const BinaryOperator &A, const BinaryOperator &B) {
  return A.getOpcode() == B.getOpcode() && A.getType() == B.getType() &&
         A.getType()->isIntegerTy() &&
         A.getType()->getIntegerBitWidth() >= 8 &&
         A.getType()->getIntegerBitWidth() <= 64 &&
         A.getRawSubclassOptionalData() == B.getRawSubclassOptionalData();
}

bool inputsDominate(const BinaryOperator &A, const BinaryOperator &B,
                    const DominatorTree &DT) {
  const auto *First = A.comesBefore(&B) ? &A : &B;
  auto *Second = First == &A ? &B : &A;
  for (auto *I : {First, Second})
    for (Value *Operand : I->operands())
      if (auto *Def = dyn_cast<Instruction>(Operand))
        if (!DT.dominates(Def, First))
          return false;
  return true;
}

bool independent(const BinaryOperator &A, const BinaryOperator &B) {
  return A.getOperand(0) != &B && A.getOperand(1) != &B &&
         B.getOperand(0) != &A && B.getOperand(1) != &A;
}

int64_t arithmeticSavings(const Pair &P, const TargetTransformInfo &TTI) {
  auto Opcode = P.first->getOpcode();
  auto *ScalarTy = P.first->getType();
  auto *VectorTy = FixedVectorType::get(ScalarTy, 2);
  auto Scalar = TTI.getArithmeticInstrCost(Opcode, ScalarTy);
  auto Vector = TTI.getArithmeticInstrCost(Opcode, VectorTy);
  if (!Scalar.isValid() || !Vector.isValid())
    return 0;
  return 2 * Scalar.getValue() - Vector.getValue();
}

// Packing candidates are equivalent pairs; the exact search maximizes packed
// instructions, then favors pairs whose operands need fewer lane insertions.
unsigned insertionEstimate(const Pair &P) {
  unsigned Cost = 0;
  for (unsigned I = 0; I != 2; ++I)
    if (!(isa<Constant>(P.first->getOperand(I)) &&
          isa<Constant>(P.second->getOperand(I))))
      Cost += 2;
  return Cost;
}

SmallVector<Pair, 8> chooseGreedy(ArrayRef<BinaryOperator *> Ops,
                                  const DominatorTree &DT,
                                  const TargetTransformInfo &TTI) {
  SmallVector<Pair, 8> Result;
  for (size_t I = 0; I + 1 < Ops.size(); ++I) {
    Pair Candidate{Ops[I], Ops[I + 1]};
    if (sameOperation(*Ops[I], *Ops[I + 1]) &&
        independent(*Ops[I], *Ops[I + 1]) &&
        inputsDominate(*Ops[I], *Ops[I + 1], DT) &&
        arithmeticSavings(Candidate, TTI) > 0) {
      Result.push_back(Candidate);
      ++I;
    }
  }
  return Result;
}

SmallVector<Pair, 8> chooseBounded(ArrayRef<BinaryOperator *> Ops,
                                   const DominatorTree &DT,
                                   const TargetTransformInfo &TTI) {
  SmallVector<Pair, 8> Best;
  if (Ops.size() > 16)
    return chooseGreedy(Ops, DT, TTI);
  struct Edge {
    int64_t Savings = 0;
    unsigned Cost = 0;
    bool Legal = false;
  };
  struct Score {
    int64_t Savings = 0;
    unsigned Pairs = 0;
    unsigned Cost = 0;
  };
  struct Choice {
    Score Result;
    uint8_t Partner = 0xff;
    bool Ready = false;
  };
  auto better = [](const Score &A, const Score &B) {
    if (A.Savings != B.Savings)
      return A.Savings > B.Savings;
    if (A.Pairs != B.Pairs)
      return A.Pairs > B.Pairs;
    return A.Cost < B.Cost;
  };

  const unsigned Count = static_cast<unsigned>(Ops.size());
  std::array<std::array<Edge, 16>, 16> Edges{};
  for (unsigned I = 0; I != Count; ++I)
    for (unsigned J = I + 1; J != Count; ++J) {
      Pair Candidate{Ops[I], Ops[J]};
      int64_t Savings = arithmeticSavings(Candidate, TTI);
      if (!sameOperation(*Ops[I], *Ops[J]) || !independent(*Ops[I], *Ops[J]) ||
          !inputsDominate(*Ops[I], *Ops[J], DT) || Savings <= 0)
        continue;
      Edges[I][J] = {Savings, insertionEstimate(Candidate), true};
      Edges[J][I] = Edges[I][J];
    }

  std::vector<Choice> Cache(size_t(1) << Count);
  auto Solve = [&](auto &&Self, uint32_t Mask) -> Score {
    if (!Mask)
      return {};
    Choice &Current = Cache[Mask];
    if (Current.Ready)
      return Current.Result;
    unsigned At = 0;
    while ((Mask & (uint32_t(1) << At)) == 0)
      ++At;
    uint32_t WithoutAt = Mask & ~(uint32_t(1) << At);
    Current.Result = Self(Self, WithoutAt);
    Current.Partner = 0xff;
    for (unsigned Other = At + 1; Other != Count; ++Other) {
      const Edge &E = Edges[At][Other];
      if (!E.Legal || (Mask & (uint32_t(1) << Other)) == 0)
        continue;
      Score Candidate = Self(Self, WithoutAt & ~(uint32_t(1) << Other));
      Candidate.Savings += E.Savings;
      ++Candidate.Pairs;
      Candidate.Cost += E.Cost;
      if (better(Candidate, Current.Result)) {
        Current.Result = Candidate;
        Current.Partner = static_cast<uint8_t>(Other);
      }
    }
    Current.Ready = true;
    return Current.Result;
  };

  uint32_t Mask = (uint32_t(1) << Count) - 1;
  Solve(Solve, Mask);
  while (Mask) {
    unsigned At = 0;
    while ((Mask & (uint32_t(1) << At)) == 0)
      ++At;
    unsigned Partner = Cache[Mask].Partner;
    Mask &= ~(uint32_t(1) << At);
    if (Partner == 0xff)
      continue;
    Best.emplace_back(Ops[At], Ops[Partner]);
    Mask &= ~(uint32_t(1) << Partner);
  }
  return Best;
}

void vectorize(const Pair &P) {
  auto *A = P.first;
  auto *B = P.second;
  auto *First = A->comesBefore(B) ? A : B;
  auto *ScalarTy = A->getType();
  auto *VectorTy = FixedVectorType::get(ScalarTy, 2);
  IRBuilder<> Builder(First->getContext());
  Builder.SetInsertPoint(First->getParent(), First->getIterator());
  Value *Lanes[2][2] = {{A->getOperand(0), A->getOperand(1)},
                        {B->getOperand(0), B->getOperand(1)}};
  Value *Vectors[2];
  for (unsigned Operand = 0; Operand != 2; ++Operand) {
    if (auto *C0 = dyn_cast<Constant>(Lanes[0][Operand]))
      if (auto *C1 = dyn_cast<Constant>(Lanes[1][Operand])) {
        Vectors[Operand] = ConstantVector::get({C0, C1});
        continue;
      }
    Value *V = PoisonValue::get(VectorTy);
    for (unsigned Lane = 0; Lane != 2; ++Lane)
      V = Builder.CreateInsertElement(V, Lanes[Lane][Operand], Lane);
    Vectors[Operand] = V;
  }
  auto *Packed = BinaryOperator::Create(
      static_cast<Instruction::BinaryOps>(A->getOpcode()), Vectors[0],
      Vectors[1], "", First->getIterator());
  Packed->copyIRFlags(A);
  Packed->setDebugLoc(First->getDebugLoc());
  auto *OutA = Builder.CreateExtractElement(Packed, uint64_t(0));
  auto *OutB = Builder.CreateExtractElement(Packed, uint64_t(1));
  A->replaceAllUsesWith(A == First ? OutA : OutB);
  B->replaceAllUsesWith(B == First ? OutA : OutB);
  A->eraseFromParent();
  B->eraseFromParent();
}
} // namespace

PreservedAnalyses BoundedSLP::run(Function &F, FunctionAnalysisManager &AM) {
  if (F.isDeclaration())
    return PreservedAnalyses::all();
  auto &DT = AM.getResult<DominatorTreeAnalysis>(F);
  auto &TTI = AM.getResult<TargetIRAnalysis>(F);
  bool Changed = false;
  for (auto &BB : F) {
    SmallVector<BinaryOperator *, 16> Ops;
    for (auto &I : BB)
      if (auto *BO = dyn_cast<BinaryOperator>(&I))
        if ((BO->getOpcode() == Instruction::Add ||
             BO->getOpcode() == Instruction::Sub ||
             BO->getOpcode() == Instruction::Mul) &&
            BO->getType()->isIntegerTy() &&
            BO->getType()->getIntegerBitWidth() >= 8 &&
            BO->getType()->getIntegerBitWidth() <= 64)
          Ops.push_back(BO);
    auto Pairs = Greedy ? chooseGreedy(Ops, DT, TTI)
                        : chooseBounded(Ops, DT, TTI);
    for (const auto &P : Pairs)
      vectorize(P);
    Changed |= !Pairs.empty();
  }
  return Changed ? PreservedAnalyses::none() : PreservedAnalyses::all();
}

static PassPluginLibraryInfo getBoundedSLPPluginInfo() {
  return {LLVM_PLUGIN_API_VERSION, "BoundedSLP", LLVM_VERSION_STRING,
          [](PassBuilder &PB) {
            PB.registerPipelineParsingCallback(
                [](StringRef Name, FunctionPassManager &FPM,
                   ArrayRef<PassBuilder::PipelineElement>) {
                  if (Name == "bounded-slp-greedy") {
                    FPM.addPass(BoundedSLP(true));
                    return true;
                  }
                  if (Name != "bounded-slp")
                    return false;
                  FPM.addPass(BoundedSLP());
                  return true;
                });
          }};
}

extern "C" LLVM_ATTRIBUTE_WEAK PassPluginLibraryInfo llvmGetPassPluginInfo() {
  return getBoundedSLPPluginInfo();
}
