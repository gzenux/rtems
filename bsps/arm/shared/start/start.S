/**
 * @file
 *
 * @brief Boot and system start code.
 */

/*
 * Copyright (c) 2008, 2018 embedded brains GmbH.  All rights reserved.
 *
 *  embedded brains GmbH
 *  Dornierstr. 4
 *  82178 Puchheim
 *  Germany
 *  <rtems@embedded-brains.de>
 *
 * The license and distribution terms for this file may be
 * found in the file LICENSE in this distribution or at
 * http://www.rtems.org/license/LICENSE.
 */

#include <rtems/asm.h>
#include <rtems/score/percpu.h>

#include <bspopts.h>
#include <bsp/irq.h>

	/* Global symbols */
	.globl	_start
	.globl	bsp_start_vector_table_begin
	.globl	bsp_start_vector_table_end
	.globl	bsp_start_vector_table_size
	.globl	bsp_vector_table_size

	.section	".bsp_start_text", "ax"

#if defined(ARM_MULTILIB_ARCH_V4)

#ifdef BSP_START_IN_HYP_SUPPORT
	.globl	bsp_start_hyp_vector_table_begin
#endif

	.arm

/*
 * This is the exception vector table and the pointers to the default
 * exceptions handlers.
 */

bsp_start_vector_table_begin:

	ldr	pc, .Lhandler_addr_reset
	ldr	pc, .Lhandler_addr_undef
	ldr	pc, .Lhandler_addr_swi
	ldr	pc, .Lhandler_addr_prefetch
	ldr	pc, .Lhandler_addr_abort

	/* Program signature checked by boot loader */
	.word	0xb8a06f58

	ldr	pc, .Lhandler_addr_irq
	ldr	pc, .Lhandler_addr_fiq

.Lhandler_addr_reset:

#ifdef BSP_START_RESET_VECTOR
	.word	BSP_START_RESET_VECTOR
#else
	.word	_start
#endif

.Lhandler_addr_undef:

	.word	_ARMV4_Exception_undef_default

.Lhandler_addr_swi:

	.word	_ARMV4_Exception_swi_default

.Lhandler_addr_prefetch:

	.word	_ARMV4_Exception_pref_abort_default

.Lhandler_addr_abort:

	.word	_ARMV4_Exception_data_abort_default

.Lhandler_addr_reserved:

	.word	_ARMV4_Exception_reserved_default

.Lhandler_addr_irq:

	.word	_ARMV4_Exception_interrupt

.Lhandler_addr_fiq:

	.word	_ARMV4_Exception_fiq_default

bsp_start_vector_table_end:

#ifdef BSP_START_IN_HYP_SUPPORT
bsp_start_hyp_vector_table_begin:
	ldr	pc, .Lhandler_addr_hyp_reset
	ldr	pc, .Lhandler_addr_hyp_undef
	ldr	pc, .Lhandler_addr_hyp_swi
	ldr	pc, .Lhandler_addr_hyp_prefetch
	ldr	pc, .Lhandler_addr_hyp_abort
	ldr	pc, .Lhandler_addr_hyp_hyp
	ldr	pc, .Lhandler_addr_hyp_irq
	ldr	pc, .Lhandler_addr_hyp_fiq

.Lhandler_addr_hyp_reset:
	.word	_ARMV4_Exception_reserved_default

.Lhandler_addr_hyp_undef:
	.word	_ARMV4_Exception_reserved_default

.Lhandler_addr_hyp_swi:
	.word	_ARMV4_Exception_reserved_default

.Lhandler_addr_hyp_prefetch:
	.word	_ARMV4_Exception_reserved_default

.Lhandler_addr_hyp_abort:
	.word	_ARMV4_Exception_reserved_default

.Lhandler_addr_hyp_hyp:
	.word	_ARMV4_Exception_reserved_default

.Lhandler_addr_hyp_irq:
	.word	_ARMV4_Exception_reserved_default

.Lhandler_addr_hyp_fiq:
	.word	_ARMV4_Exception_reserved_default
#endif

/* Start entry */

_start:

	/*
	 * We do not save the context since we do not return to the boot
	 * loader but preserve r1 and r2 to allow access to bootloader parameters
	 */
#ifndef BSP_START_NEEDS_REGISTER_INITIALIZATION
	mov	r5, r1		/* machine type number or ~0 for DT boot */
	mov	r6, r2		/* physical address of ATAGs or DTB */
#else /* BSP_START_NEEDS_REGISTER_INITIALIZATION */
	bl bsp_start_init_registers_core
#endif

#ifdef RTEMS_SMP
	/* Read MPIDR and get current processor index */
	mrc	p15, 0, r7, c0, c0, 5
	and	r7, #0xff
#endif

#ifdef BSP_START_COPY_FDT_FROM_U_BOOT
#ifdef RTEMS_SMP
	cmp	r7, #0
	bne	1f
#endif
	mov	r0, r6
	bl	bsp_fdt_copy
1:
#endif

#ifdef RTEMS_SMP
        /*
         * Get current per-CPU control and store it in PL1 only Thread ID
         * Register (TPIDRPRW).
         */
	ldr	r1, =_Per_CPU_Information
	add	r1, r1, r7, asl #PER_CPU_CONTROL_SIZE_LOG2
	mcr	p15, 0, r1, c13, c0, 4

#endif

	/* Calculate interrupt stack area end for current processor */
	ldr	r1, =_ISR_Stack_size
#ifdef RTEMS_SMP
	add	r7, #1
	mul	r1, r1, r7
#endif
	ldr	r2, =_ISR_Stack_area_begin
	add	r7, r1, r2

	/* Save original CPSR value */
	mrs	r4, cpsr

#ifdef BSP_START_IN_HYP_SUPPORT
	orr	r0, r4, #(ARM_PSR_I | ARM_PSR_F)
	msr	cpsr, r4

	and	r0, r4, #ARM_PSR_M_MASK
	cmp	r0, #ARM_PSR_M_HYP
	bne	.L_skip_hyp_svc_switch

	/* Boot loader starts kernel in HYP mode, switch to SVC necessary */
	ldr	r1, =bsp_stack_hyp_size
	mov	sp, r7
	sub	r7, r7, r1
	bl	bsp_start_arm_drop_hyp_mode

.L_skip_hyp_svc_switch:
#endif
	/* Initialize stack pointer registers for the various modes */

	/* Enter FIQ mode and set up the FIQ stack pointer */
	mov	r0, #(ARM_PSR_M_FIQ | ARM_PSR_I | ARM_PSR_F)
	msr	cpsr, r0
	ldr	r1, =bsp_stack_fiq_size
	mov	sp, r7
	sub	r7, r7, r1

#ifdef BSP_START_NEEDS_REGISTER_INITIALIZATION
	bl bsp_start_init_registers_banked_fiq
#endif

	/* Enter ABT mode and set up the ABT stack pointer */
	mov	r0, #(ARM_PSR_M_ABT | ARM_PSR_I | ARM_PSR_F)
	msr	cpsr, r0
	ldr	r1, =bsp_stack_abt_size
	mov	sp, r7
	sub	r7, r7, r1

	/* Enter UND mode and set up the UND stack pointer */
	mov	r0, #(ARM_PSR_M_UND | ARM_PSR_I | ARM_PSR_F)
	msr	cpsr, r0
	ldr	r1, =bsp_stack_und_size
	mov	sp, r7
	sub	r7, r7, r1

	/* Enter IRQ mode and set up the IRQ stack pointer */
	mov	r0, #(ARM_PSR_M_IRQ | ARM_PSR_I | ARM_PSR_F)
	msr	cpsr, r0
	mov	sp, r7

	/*
	 * Enter SVC mode and set up the SVC stack pointer, reuse IRQ stack
	 * (interrupts are disabled).
	 */
	mov	r0, #(ARM_PSR_M_SVC | ARM_PSR_I | ARM_PSR_F)
	msr	cpsr, r0
	mov	sp, r7

	/* Stay in SVC mode */

#ifdef ARM_MULTILIB_VFP
#ifdef ARM_MULTILIB_HAS_CPACR
	/* Read CPACR */
	mrc p15, 0, r0, c1, c0, 2

	/* Enable CP10 and CP11 */
	orr r0, r0, #(1 << 20)
	orr r0, r0, #(1 << 22)

	/*
	 * Clear ASEDIS and D32DIS.  Writes to D32DIS are ignored for VFP-D16.
	 */
	bic r0, r0, #(3 << 30)

	/* Write CPACR */
	mcr p15, 0, r0, c1, c0, 2
	isb
#endif

	/* Enable FPU */
	mov r0, #(1 << 30)
	vmsr FPEXC, r0

#ifdef BSP_START_NEEDS_REGISTER_INITIALIZATION
	bl bsp_start_init_registers_vfp
#endif

#endif /* ARM_MULTILIB_VFP */

	/*
	 * Invoke the start hook 0.
	 *
	 * The previous code and parts of the start hook 0 may run with an
	 * address offset.  After the return from start hook 0 it is assumed
	 * that the code can run at its intended position.  Thus the link
	 * register will be loaded with the absolute address and the branch
	 * link instruction cannot be used.  In THUMB mode the branch
	 * instruction as a very limited address range of 2KiB.  Use a bx to
	 * the start hook 0 address instead corrected by the address offset.
	 */

	ldr	lr, =.Lstart_hook_0_done
	mov	r0, pc
	ldr	r1, =.Lget_absolute_pc
.Lget_absolute_pc:
	sub	r1, r0
	ldr	r7, =bsp_start_hook_0
	add	r7, r1

	mov	r0, r4		/* original CPSR value */
	mov	r1, r5		/* machine type number or ~0 for DT boot */
	mov	r2, r6		/* physical address of ATAGs or DTB */

	bx	r7

.Lstart_hook_0_done:

	/*
	 * Initialize the exception vectors.  This includes the exceptions
	 * vectors and the pointers to the default exception handlers.
	 */

	stmdb	sp!, {r4, r5, r6}

	ldr	r0, =bsp_vector_table_begin
	adr	r1, bsp_start_vector_table_begin
	cmp	r0, r1
	beq	.Lvector_table_copy_done
	ldmia	r1!, {r2-r9}
	stmia	r0!, {r2-r9}
	ldmia	r1!, {r2-r9}
	stmia	r0!, {r2-r9}

.Lvector_table_copy_done:

	ldmia	sp!, {r0, r1, r2}

	SWITCH_FROM_ARM_TO_THUMB	r3

	/* Branch to start hook 1 */
	bl	bsp_start_hook_1

	/* Branch to boot card */
	mov	r0, #0
	bl	boot_card

#elif defined(ARM_MULTILIB_ARCH_V7M)

#include <rtems/score/armv7m.h>

	.syntax	unified

	.thumb

bsp_start_vector_table_begin:

	.word	_ISR_Stack_area_end
	.word	_start /* Reset */
	.word	_ARMV7M_Exception_default /* NMI */
	.word	_ARMV7M_Exception_default /* Hard Fault */
	.word	_ARMV7M_Exception_default /* MPU Fault */
	.word	_ARMV7M_Exception_default /* Bus Fault */
	.word	_ARMV7M_Exception_default /* Usage Fault */
	.word	_ARMV7M_Exception_default /* Reserved */
	.word	_ARMV7M_Exception_default /* Reserved */
	.word	_ARMV7M_Exception_default /* Reserved */
	.word	_ARMV7M_Exception_default /* Reserved */
	.word	_ARMV7M_Exception_default /* SVC */
	.word	_ARMV7M_Exception_default /* Debug Monitor */
	.word	_ARMV7M_Exception_default /* Reserved */
	.word	_ARMV7M_Exception_default /* PendSV */
	.word	_ARMV7M_Exception_default /* SysTick */
	.rept	BSP_INTERRUPT_VECTOR_MAX + 1
	.word	_ARMV7M_Exception_default /* IRQ */
	.endr

bsp_start_vector_table_end:

	.thumb_func

_start:

#ifdef BSP_START_NEEDS_REGISTER_INITIALIZATION
	bl bsp_start_init_registers_core
#endif

#ifdef ARM_MULTILIB_VFP
#ifdef ARM_MULTILIB_HAS_CPACR
	/*
	 * Enable CP10 and CP11 coprocessors for privileged and user mode in
	 * CPACR (bits 20-23).  Ensure that write to register completes.
	 */
	ldr	r0, =ARMV7M_CPACR
	ldr	r1, [r0]
	orr	r1, r1, #(0xf << 20)
	str	r1, [r0]
	dsb
	isb
#endif

#ifdef BSP_START_NEEDS_REGISTER_INITIALIZATION
	bl bsp_start_init_registers_vfp
#endif

#endif /* ARM_MULTILIB_VFP */

	ldr	sp, =_ISR_Stack_area_end
	ldr	lr, =.Lstart_hook_0_done + 1
	b	bsp_start_hook_0

.Lstart_hook_0_done:

	bl	bsp_start_hook_1
	movs	r0, #0
	bl	boot_card

#endif /* defined(ARM_MULTILIB_ARCH_V7M) */

	.set	bsp_start_vector_table_size, bsp_start_vector_table_end - bsp_start_vector_table_begin
	.set	bsp_vector_table_size, bsp_start_vector_table_size
