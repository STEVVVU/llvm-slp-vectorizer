; ModuleID = 'C:\Users\steve\Projects\llvm-slp-vectorizer\test\BoundedSLP.ll'
source_filename = "C:\\Users\\steve\\Projects\\llvm-slp-vectorizer\\test\\BoundedSLP.ll"
target datalayout = "e-m:w-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-windows-msvc"

define i32 @packing_shape(i32 %a, i32 %b, i32 %c, i32 %d, i32 %e, i32 %f, i32 %g) {
  %1 = insertelement <2 x i32> poison, i32 %a, i64 0
  %2 = insertelement <2 x i32> %1, i32 %d, i64 1
  %3 = insertelement <2 x i32> poison, i32 %b, i64 0
  %4 = insertelement <2 x i32> %3, i32 %e, i64 1
  %5 = add <2 x i32> %2, %4
  %6 = extractelement <2 x i32> %5, i64 0
  %7 = extractelement <2 x i32> %5, i64 1
  %8 = insertelement <2 x i32> poison, i32 %6, i64 0
  %9 = insertelement <2 x i32> %8, i32 %f, i64 1
  %10 = insertelement <2 x i32> poison, i32 %c, i64 0
  %11 = insertelement <2 x i32> %10, i32 %g, i64 1
  %12 = add <2 x i32> %9, %11
  %13 = extractelement <2 x i32> %12, i64 0
  %14 = extractelement <2 x i32> %12, i64 1
  ret i32 %13
}

define i32 @slp_add2(i32 %a, i32 %b, i32 %c, i32 %d) {
  %1 = insertelement <2 x i32> poison, i32 %a, i64 0
  %2 = insertelement <2 x i32> %1, i32 %c, i64 1
  %3 = insertelement <2 x i32> poison, i32 %b, i64 0
  %4 = insertelement <2 x i32> %3, i32 %d, i64 1
  %5 = add <2 x i32> %2, %4
  %6 = extractelement <2 x i32> %5, i64 0
  %7 = extractelement <2 x i32> %5, i64 1
  %sum = add i32 %6, %7
  ret i32 %sum
}

define i32 @constant_pair() {
  %1 = add <2 x i32> <i32 1, i32 3>, <i32 2, i32 4>
  %2 = extractelement <2 x i32> %1, i64 0
  %3 = extractelement <2 x i32> %1, i64 1
  %sum = add i32 %2, %3
  ret i32 %sum
}

define void @slp_add2_ptr(ptr %out, ptr %a, ptr %b) {
  %a0 = load i32, ptr %a, align 4
  %b0 = load i32, ptr %b, align 4
  %a1ptr = getelementptr i32, ptr %a, i64 1
  %b1ptr = getelementptr i32, ptr %b, i64 1
  %a1 = load i32, ptr %a1ptr, align 4
  %b1 = load i32, ptr %b1ptr, align 4
  %1 = insertelement <2 x i32> poison, i32 %a0, i64 0
  %2 = insertelement <2 x i32> %1, i32 %a1, i64 1
  %3 = insertelement <2 x i32> poison, i32 %b0, i64 0
  %4 = insertelement <2 x i32> %3, i32 %b1, i64 1
  %5 = add <2 x i32> %2, %4
  %6 = extractelement <2 x i32> %5, i64 0
  %7 = extractelement <2 x i32> %5, i64 1
  store i32 %6, ptr %out, align 4
  %out1 = getelementptr i32, ptr %out, i64 1
  store i32 %7, ptr %out1, align 4
  ret void
}

define void @slp_add2_volatile(ptr %out, ptr %a, ptr %b) {
  %a0 = load volatile i32, ptr %a, align 4
  %b0 = load volatile i32, ptr %b, align 4
  %a1ptr = getelementptr i32, ptr %a, i64 1
  %b1ptr = getelementptr i32, ptr %b, i64 1
  %a1 = load volatile i32, ptr %a1ptr, align 4
  %b1 = load volatile i32, ptr %b1ptr, align 4
  %1 = insertelement <2 x i32> poison, i32 %a0, i64 0
  %2 = insertelement <2 x i32> %1, i32 %a1, i64 1
  %3 = insertelement <2 x i32> poison, i32 %b0, i64 0
  %4 = insertelement <2 x i32> %3, i32 %b1, i64 1
  %5 = add <2 x i32> %2, %4
  %6 = extractelement <2 x i32> %5, i64 0
  %7 = extractelement <2 x i32> %5, i64 1
  store i32 %6, ptr %out, align 4
  %out1 = getelementptr i32, ptr %out, i64 1
  store i32 %7, ptr %out1, align 4
  ret void
}

define i32 @mismatched_flags(i32 %a, i32 %b, i32 %c, i32 %d) {
  %left = add nsw i32 %a, %b
  %right = add i32 %c, %d
  %sum = add i32 %left, %right
  ret i32 %sum
}

define float @float_not_packed(float %a, float %b, float %c, float %d) {
  %left = fadd float %a, %b
  %right = fadd float %c, %d
  %sum = fadd float %left, %right
  ret float %sum
}
