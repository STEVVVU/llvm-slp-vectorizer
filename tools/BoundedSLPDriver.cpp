// A small standalone host for the pass, used where LLVM plugins cannot share
// the host's statically linked LLVM libraries.
#include "BoundedSLP.h"

#include "llvm/Analysis/TargetTransformInfo.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/PassManager.h"
#include "llvm/IR/Verifier.h"
#include "llvm/IRReader/IRReader.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/InitLLVM.h"
#include "llvm/TargetParser/Host.h"
#include "llvm/Support/SourceMgr.h"
#include "llvm/Support/TargetSelect.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Target/TargetMachine.h"

#include <memory>

using namespace llvm;

static cl::opt<std::string> Input(cl::Positional, cl::Required,
                                  cl::desc("input LLVM IR"));
static cl::opt<std::string> Output("o", cl::init("-"),
                                   cl::desc("output LLVM IR"));
static cl::opt<bool> Greedy("greedy", cl::init(false),
                             cl::desc("use greedy local packing"));

int main(int Argc, char **Argv) {
  InitLLVM Init(Argc, Argv);
  cl::ParseCommandLineOptions(Argc, Argv, "bounded basic-block SLP\n");
  LLVMContext Context;
  SMDiagnostic Diagnostic;
  auto M = parseIRFile(Input, Diagnostic, Context);
  if (!M) {
    Diagnostic.print(Argv[0], errs());
    return 1;
  }
  if (verifyModule(*M, &errs()))
    return 1;

  if (InitializeNativeTarget() || InitializeNativeTargetAsmPrinter()) {
    errs() << "native LLVM target initialization failed\n";
    return 1;
  }
  if (M->getTargetTriple().empty())
    M->setTargetTriple(Triple(sys::getDefaultTargetTriple()));
  std::string Error;
  const Target *TheTarget =
      TargetRegistry::lookupTarget(M->getTargetTriple(), Error);
  if (!TheTarget) {
    errs() << Error << '\n';
    return 1;
  }
  TargetOptions Options;
  std::unique_ptr<TargetMachine> TM(TheTarget->createTargetMachine(
      M->getTargetTriple(), "generic", "", Options, std::nullopt));
  if (!TM) {
    errs() << "could not create target machine for " << M->getTargetTriple().str()
           << '\n';
    return 1;
  }
  if (M->getDataLayoutStr().empty())
    M->setDataLayout(TM->createDataLayout());

  LoopAnalysisManager LAM;
  FunctionAnalysisManager FAM;
  CGSCCAnalysisManager CGAM;
  ModuleAnalysisManager MAM;
  PassBuilder PB(TM.get());
  PB.registerModuleAnalyses(MAM);
  PB.registerCGSCCAnalyses(CGAM);
  PB.registerFunctionAnalyses(FAM);
  PB.registerLoopAnalyses(LAM);
  PB.crossRegisterProxies(LAM, FAM, CGAM, MAM);
  for (Function &F : *M)
    if (!F.isDeclaration())
      BoundedSLP(Greedy).run(F, FAM);
  if (verifyModule(*M, &errs()))
    return 1;

  std::error_code EC;
  raw_fd_ostream OS(Output, EC);
  if (EC) {
    errs() << "cannot write " << Output << ": " << EC.message() << '\n';
    return 1;
  }
  M->print(OS, nullptr);
  return 0;
}
