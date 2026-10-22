; Computed scalar operands must pay their target lane-insertion costs.
; RUN: opt -load-pass-plugin %shlibdir/libBoundedSLP%shlibext -passes=bounded-slp -verify-each -S %s | FileCheck %s --check-prefix=EXACT
; RUN: opt -load-pass-plugin %shlibdir/libBoundedSLP%shlibext -passes=bounded-slp-greedy -verify-each -S %s | FileCheck %s --check-prefix=GREEDY

define i32 @packing_shape(i32 %a, i32 %b, i32 %c, i32 %d,
                          i32 %e, i32 %f, i32 %g) {
  %first = add i32 %a, %b
  %dependent = add i32 %first, %c
  %third = add i32 %d, %e
  %fourth = add i32 %f, %g
  ret i32 %dependent
}

define i32 @slp_add2(i32 %a, i32 %b, i32 %c, i32 %d) {
  %left = add i32 %a, %b
  %right = add i32 %c, %d
  %sum = add i32 %left, %right
  ret i32 %sum
}

define i32 @constant_pair() {
  %left = add i32 1, 2
  %right = add i32 3, 4
  %sum = add i32 %left, %right
  ret i32 %sum
}

define void @slp_add2_ptr(ptr %out, ptr %a, ptr %b) {
  %a0 = load i32, ptr %a
  %b0 = load i32, ptr %b
  %a1ptr = getelementptr i32, ptr %a, i64 1
  %b1ptr = getelementptr i32, ptr %b, i64 1
  %a1 = load i32, ptr %a1ptr
  %b1 = load i32, ptr %b1ptr
  %left = add i32 %a0, %b0
  %right = add i32 %a1, %b1
  store i32 %left, ptr %out
  %out1 = getelementptr i32, ptr %out, i64 1
  store i32 %right, ptr %out1
  ret void
}

define void @slp_add2_volatile(ptr %out, ptr %a, ptr %b) {
  %a0 = load volatile i32, ptr %a
  %b0 = load volatile i32, ptr %b
  %a1ptr = getelementptr i32, ptr %a, i64 1
  %b1ptr = getelementptr i32, ptr %b, i64 1
  %a1 = load volatile i32, ptr %a1ptr
  %b1 = load volatile i32, ptr %b1ptr
  %left = add i32 %a0, %b0
  %right = add i32 %a1, %b1
  store i32 %left, ptr %out
  %out1 = getelementptr i32, ptr %out, i64 1
  store i32 %right, ptr %out1
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

define i32 @computed_lane_cost(i32 %a, i32 %b, i32 %c, i32 %d) {
  %x0 = mul i32 %a, %b
  %x1 = mul i32 %c, %d
  %y0 = add i32 %x0, 17
  %y1 = add i32 %x1, 17
  %result = xor i32 %y0, %y1
  ret i32 %result
}

; EXACT-LABEL: define i32 @packing_shape
; EXACT-COUNT-1: add <2 x i32>
; GREEDY-LABEL: define i32 @packing_shape
; GREEDY-COUNT-1: add <2 x i32>
; EXACT-LABEL: define i32 @slp_add2
; EXACT: add <2 x i32>
; EXACT-LABEL: define i32 @constant_pair
; EXACT: add <2 x i32>
; EXACT-LABEL: define void @slp_add2_ptr
; EXACT: add <2 x i32>
; EXACT-LABEL: define void @slp_add2_volatile
; EXACT-COUNT-4: load volatile i32
; EXACT: add <2 x i32>
; EXACT-LABEL: define i32 @mismatched_flags
; EXACT-NOT: add <2 x i32>
; EXACT-LABEL: define float @float_not_packed
; EXACT-NOT: fadd <2 x float>
; EXACT-LABEL: define i32 @computed_lane_cost
; EXACT-NOT: add <2 x i32>
; GREEDY-LABEL: define i32 @computed_lane_cost
; GREEDY-NOT: add <2 x i32>
