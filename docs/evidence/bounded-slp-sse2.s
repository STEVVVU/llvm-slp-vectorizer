	.def	@feat.00;
	.scl	3;
	.type	0;
	.endef
	.globl	@feat.00
@feat.00 = 0
	.att_syntax
	.file	"BoundedSLP.ll"
	.def	packing_shape;
	.scl	2;
	.type	32;
	.endef
	.text
	.globl	packing_shape                   # -- Begin function packing_shape
	.p2align	4
packing_shape:                          # @packing_shape
# %bb.0:
                                        # kill: def $edx killed $edx def $rdx
                                        # kill: def $ecx killed $ecx def $rcx
	leal	(%rcx,%rdx), %eax
	addl	%r8d, %eax
	retq
                                        # -- End function
	.def	slp_add2;
	.scl	2;
	.type	32;
	.endef
	.globl	slp_add2                        # -- Begin function slp_add2
	.p2align	4
slp_add2:                               # @slp_add2
# %bb.0:
	movd	%r8d, %xmm0
	movd	%ecx, %xmm1
	punpckldq	%xmm0, %xmm1            # xmm1 = xmm1[0],xmm0[0],xmm1[1],xmm0[1]
	movd	%r9d, %xmm0
	movd	%edx, %xmm2
	punpckldq	%xmm0, %xmm2            # xmm2 = xmm2[0],xmm0[0],xmm2[1],xmm0[1]
	paddd	%xmm1, %xmm2
	movd	%xmm2, %ecx
	pshufd	$85, %xmm2, %xmm0               # xmm0 = xmm2[1,1,1,1]
	movd	%xmm0, %eax
	addl	%ecx, %eax
	retq
                                        # -- End function
	.def	constant_pair;
	.scl	2;
	.type	32;
	.endef
	.globl	constant_pair                   # -- Begin function constant_pair
	.p2align	4
constant_pair:                          # @constant_pair
# %bb.0:
	movl	$10, %eax
	retq
                                        # -- End function
	.def	slp_add2_ptr;
	.scl	2;
	.type	32;
	.endef
	.globl	slp_add2_ptr                    # -- Begin function slp_add2_ptr
	.p2align	4
slp_add2_ptr:                           # @slp_add2_ptr
# %bb.0:
	movq	(%rdx), %xmm0                   # xmm0 = mem[0],zero
	movq	(%r8), %xmm1                    # xmm1 = mem[0],zero
	paddd	%xmm0, %xmm1
	pshufd	$85, %xmm1, %xmm0               # xmm0 = xmm1[1,1,1,1]
	movd	%xmm1, (%rcx)
	movd	%xmm0, 4(%rcx)
	retq
                                        # -- End function
	.def	slp_add2_volatile;
	.scl	2;
	.type	32;
	.endef
	.globl	slp_add2_volatile               # -- Begin function slp_add2_volatile
	.p2align	4
slp_add2_volatile:                      # @slp_add2_volatile
# %bb.0:
	movd	(%rdx), %xmm0                   # xmm0 = mem[0],zero,zero,zero
	movd	(%r8), %xmm1                    # xmm1 = mem[0],zero,zero,zero
	movd	4(%rdx), %xmm2                  # xmm2 = mem[0],zero,zero,zero
	punpckldq	%xmm2, %xmm0            # xmm0 = xmm0[0],xmm2[0],xmm0[1],xmm2[1]
	movd	4(%r8), %xmm2                   # xmm2 = mem[0],zero,zero,zero
	punpckldq	%xmm2, %xmm1            # xmm1 = xmm1[0],xmm2[0],xmm1[1],xmm2[1]
	paddd	%xmm0, %xmm1
	pshufd	$85, %xmm1, %xmm0               # xmm0 = xmm1[1,1,1,1]
	movd	%xmm1, (%rcx)
	movd	%xmm0, 4(%rcx)
	retq
                                        # -- End function
	.def	mismatched_flags;
	.scl	2;
	.type	32;
	.endef
	.globl	mismatched_flags                # -- Begin function mismatched_flags
	.p2align	4
mismatched_flags:                       # @mismatched_flags
# %bb.0:
                                        # kill: def $r9d killed $r9d def $r9
                                        # kill: def $r8d killed $r8d def $r8
                                        # kill: def $edx killed $edx def $rdx
                                        # kill: def $ecx killed $ecx def $rcx
	addl	%edx, %ecx
	leal	(%r8,%r9), %eax
	addl	%ecx, %eax
	retq
                                        # -- End function
	.def	float_not_packed;
	.scl	2;
	.type	32;
	.endef
	.globl	float_not_packed                # -- Begin function float_not_packed
	.p2align	4
float_not_packed:                       # @float_not_packed
# %bb.0:
	addss	%xmm1, %xmm0
	addss	%xmm3, %xmm2
	addss	%xmm2, %xmm0
	retq
                                        # -- End function
	.globl	_fltused
