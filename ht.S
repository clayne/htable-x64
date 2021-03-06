/*
 * Hash table implementation in x64 assembly (AT&T flavour)
 * Copyright (c) 2014-2015 Ahmed Samy  <f.fallen45@gmail.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */
#define INITIAL_SPACE		64

#define DEF_FUN(name)		.type name, @function

#define HT_PTR(reg)		(reg)
#define __HT_PTR		HT_PTR(%rdi)

#define HT_COMMON_MASK(reg)	8(reg)
#define __HT_COMMON_MASK	HT_COMMON_MASK(%rdi)

#define HT_COMMON_BITS(reg)	16(reg)
#define __HT_COMMON_BITS	HT_COMMON_BITS(%rdi)

#define HT_SIZE(reg)		24(reg)
#define __HT_SIZE		HT_SIZE(%rdi)

#define HT_CAP(reg)		32(reg)
#define __HT_CAP		HT_CAP(%rdi)

/**
	void *htable_init() - Allocate and initialize a hash table

	The data structure:
		  (%ptr)	= table
		8 (%ptr)	= common mask
		16(%ptr)	= common bits
		24(%ptr)	= size
		32(%ptr)	= cap

	Example:
		call htable_init
		movq %rax, WHERE
*/
	.text
.globl htable_init
	DEF_FUN(htable_init)
htable_init:
	pushq	%rbx

	movl	$40, %edi	/* See structure above.  */
	call	malloc
	testq	%rax, %rax
	je	failure

	movq	$0,		HT_COMMON_MASK(%rax)	/* 8  */
	movq	$0,		HT_COMMON_BITS(%rax)	/* 16  */
	movq	$0,		HT_SIZE(%rax)		/* 24  */
	movq	$INITIAL_SPACE, HT_CAP(%rax)		/* 32 (See call to calloc below.) */

	movq	%rax, %rbx
	movl	$8, %esi				/* sizeof(uintptr_t)  */
	movl	$INITIAL_SPACE, %edi
	call	calloc					/* Allocate data for the ptr that will hold data.  */
	testq	%rax, %rax				/* Memory allocation failure?  */
	je	htable_failure

	movq	%rax, (%rbx)				/* Move it on top of the data structure.  */
	movq	%rbx, %rax				/* Put the data structure on %rax and return  */

	popq	%rbx
	ret

htable_failure:
	movq	%rbx, %rdi
	call	free

failure:
	popq	%rbx
	ret

/**
	void htable_free(void *ht)
*/
.globl htable_free
	DEF_FUN(htable_free)
htable_free:
	movq	%rdi, %rsi
	movq	(%rdi), %rdi
	call	free

	movq	%rsi, %rdi
	call	free

	xorq	%rax, %rax
	ret

/**
	void htable_expand(void *ht)
*/
	.section	.text.unlikely	/* cold  */
	DEF_FUN(htable_expand)
htable_expand:
	ret

/**
	void update_common(void *ht, const void *ptr)
*/
	.section 	.text.unlikely		/* cold  */
	DEF_FUN(update_common)
update_common:
	pushq	%rbx

	cmpq	$0, __HT_SIZE		/* No elements?  */
	je	__figure_commmons	/* Unlikely, let it have the longer jump.  */

	/* mask diff in %rsi */
	andq	__HT_COMMON_MASK, %rsi
	xorq	__HT_COMMON_BITS, %rsi
	notq	%rsi

	/* bits diff in %rbx */
	movq	%rsi, %rbx
	andq	__HT_COMMON_BITS, %rbx

	movq	__HT_SIZE, %rcx
	movq	__HT_PTR, %rdx

loop_table:
	andq	%rsi, (%rdx, %rcx, 8)	/* ht[i] &= ~maskdiff  */
	orq	%rbx, (%rdx, %rcx, 8)	/* ht[i] |= bitsdiff  */

	subq	$1, %rcx
	jnz	loop_table

	andq	%rsi, __HT_COMMON_MASK
	andq	%rsi, __HT_COMMON_BITS

	popq	%rbx
	ret

__figure_commmons:
	movq	$63, %rcx
	jmp 	figure_commons

again:
	subq	$1, %rcx
	jl	done

figure_commons:
	btq	%rcx, %rsi
	jnc	again		/* Not set?  */

	/* ~(1 << %cl)  */
	movq	$-2, %rdx
	rolq	%cl, %rdx
	/* Set mask  */
	movq	%rdx, __HT_COMMON_MASK

	/* Set bits  */
	andq	__HT_COMMON_MASK, %rsi
	movq	%rsi, __HT_COMMON_BITS

done:
	popq	%rbx
	ret


/**
	uintptr_t hash_ptr_bits(void *ht, size_t hash)
*/
	DEF_FUN(hash_ptr_bits)
hash_ptr_bits:
	movq	__HT_SIZE, %rcx
	movq	%rsi, %rax
	shrq	%cl, %rax		/* hash >> size  */
	xorq	%rsi, %rax		/* (hash >> size) ^ hash  */
	andq	__HT_COMMON_MASK, %rax	/* In total: (hash ^ (hash >> size)) & common_mask  */
	ret

/**
	void htable_add(void *table @rdi, const size_t hash @rsi, const void
	*p @rdx)
*/
.globl htable_add
	DEF_FUN(htable_add)
htable_add:
	pushq	%rbx
	pushq	%r8
	pushq	%r9

	movq	__HT_SIZE, %rcx
	incq	%rcx
	cmpq	%rcx, __HT_CAP		/* Full?  */
	jl	proceed	
	call	htable_expand

proceed:
	movq	__HT_COMMON_MASK, %rcx
	movq	%rdx, %rbx
	andq	%rbx, %rcx		/* (ptr & common_mask)  */
	cmpq	__HT_COMMON_BITS, %rcx
	je	addit
	call	update_common

addit:
	call 	hash_ptr_bits
	movq	__HT_COMMON_MASK, %rcx
	notq	%rcx			/* ~common_mask  */
	andq	%rdx, %rcx		/* ptr & ~common_mask  */
	orq	%rax, %rcx		/* (ptr & ~common_mask) | bits  */

	/* Add it  */
	movq	__HT_PTR, %r9
	movq	__HT_SIZE, %r8
	movq	%rcx, (%r9, %r8, 8)
	incq	__HT_SIZE

	popq	%r9
	popq	%r8
	popq	%rbx

	xorq 	%rax, %rax
	ret

/**
	void *htable_get(table, idx) - Get the pointer at @idx
	@table: the table pointer returned by htable_init()

	Example:
		movq	TABLE, %rdi
		movq	INDEX, %rsi
		call	htable_get
		movq	%rax, RESULT
*/
.globl htable_get
	DEF_FUN(htable_get)
htable_get:
	movq	__HT_COMMON_MASK, %rax
	notq	%rax				/* ~mask  */
	movq	__HT_PTR, %rdx
	andq	(%rdx, %rsi, 8), %rax		/* (table[index] & ~mask)  */
	orq	__HT_COMMON_BITS, %rax		/* (table[index] & ~mask) | bits  */
	ret

/*
	void *htable_getbyhash(void *ht @rdi, size_t hash @rsi)
 */
.globl htable_getbyhash
	DEF_FUN(htable_getbyhash)
htable_getbyhash:
	pushq	%r8
	pushq	%r9
	pushq	%r10

	call 	hash_ptr_bits
	movq	__HT_PTR, %rdx
	movq	__HT_COMMON_MASK, %r9
	xorq	%rcx, %rcx

looptable:
	movq	(%rdx, %rcx, 8), %r8
	testq	%r8, %r8
	jz	next_please		/* Unlikely.  */

	movq	%r8, %r10
	andq	%r10, %r9
	cmpq	%r9, %rax
	jnz	next_please

	movq	__HT_COMMON_MASK, %r10
	notq	%r10
	andq	%r10, %r8
	orq	__HT_COMMON_BITS, %r8
	movq	%r8, %rax
	jmp	finished

next_please:
	incq	%rcx
	cmpq	__HT_SIZE, %rcx
	jnz	looptable
	xorq	%rax, %rax

finished:
	popq	%r10
	popq	%r9
	popq	%r8

	ret

	.section	.text.unlikely					/* cold  */
.globl htable_size
	DEF_FUN(htable_size)
htable_size:
	movq	__HT_SIZE, %rax
	ret

	.section	.text.unlikely					/* cold  */
.globl htable_cap
	DEF_FUN(htable_cap)
htable_cap:
	movq	__HT_CAP, %rax
	ret

/* vim: set ft=gas:  */

