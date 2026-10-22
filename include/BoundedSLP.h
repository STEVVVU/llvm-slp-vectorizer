//==============================================================================
// Declares a bounded basic-block SLP vectorization pass.
// License: MIT
//==============================================================================
#ifndef LLVM_TUTOR_BOUNDED_SLP_H
#define LLVM_TUTOR_BOUNDED_SLP_H

#include "llvm/IR/PassManager.h"

struct BoundedSLP : llvm::PassInfoMixin<BoundedSLP> {
  explicit BoundedSLP(bool UseGreedy = false) : Greedy(UseGreedy) {}
  llvm::PreservedAnalyses run(llvm::Function &, llvm::FunctionAnalysisManager &);
  static bool isRequired() { return true; }

private:
  bool Greedy;
};

#endif
