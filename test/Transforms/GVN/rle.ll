; RUN: opt < %s -gvn -S | FileCheck %s

; 32-bit little endian target.
target datalayout = "e-p:32:32:32-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:32:64-f32:32:32-f64:32:64-v64:64:64-v128:128:128-a0:0:64-f80:128:128"

;; Trivial RLE test.
define i32 @test0(i32 %V, i32* %P) {
  store i32 %V, i32* %P

  %A = load i32* %P
  ret i32 %A
; CHECK: @test0
; CHECK: ret i32 %V
}


;;===----------------------------------------------------------------------===;;
;; Tests for crashers
;;===----------------------------------------------------------------------===;;

;; PR5016
define i8 @crash0({i32, i32} %A, {i32, i32}* %P) {
  store {i32, i32} %A, {i32, i32}* %P
  %X = bitcast {i32, i32}* %P to i8*
  %Y = load i8* %X
  ret i8 %Y
}


;;===----------------------------------------------------------------------===;;
;; Store -> Load  and  Load -> Load forwarding where src and dst are different
;; types, but where the base pointer is a must alias.
;;===----------------------------------------------------------------------===;;

;; i32 -> f32 forwarding.
define float @coerce_mustalias1(i32 %V, i32* %P) {
  store i32 %V, i32* %P
   
  %P2 = bitcast i32* %P to float*

  %A = load float* %P2
  ret float %A
; CHECK: @coerce_mustalias1
; CHECK-NOT: load
; CHECK: ret float 
}

;; i32* -> float forwarding.
define float @coerce_mustalias2(i32* %V, i32** %P) {
  store i32* %V, i32** %P
   
  %P2 = bitcast i32** %P to float*

  %A = load float* %P2
  ret float %A
; CHECK: @coerce_mustalias2
; CHECK-NOT: load
; CHECK: ret float 
}

;; float -> i32* forwarding.
define i32* @coerce_mustalias3(float %V, float* %P) {
  store float %V, float* %P
   
  %P2 = bitcast float* %P to i32**

  %A = load i32** %P2
  ret i32* %A
; CHECK: @coerce_mustalias3
; CHECK-NOT: load
; CHECK: ret i32* 
}

;; i32 -> f32 load forwarding.
define float @coerce_mustalias4(i32* %P, i1 %cond) {
  %A = load i32* %P
  
  %P2 = bitcast i32* %P to float*
  %B = load float* %P2
  br i1 %cond, label %T, label %F
T:
  ret float %B
  
F:
  %X = bitcast i32 %A to float
  ret float %X

; CHECK: @coerce_mustalias4
; CHECK: %A = load i32* %P
; CHECK-NOT: load
; CHECK: ret float
; CHECK: F:
}

;; i32 -> i8 forwarding
define i8 @coerce_mustalias5(i32 %V, i32* %P) {
  store i32 %V, i32* %P
   
  %P2 = bitcast i32* %P to i8*

  %A = load i8* %P2
  ret i8 %A
; CHECK: @coerce_mustalias5
; CHECK-NOT: load
; CHECK: ret i8
}

;; i64 -> float forwarding
define float @coerce_mustalias6(i64 %V, i64* %P) {
  store i64 %V, i64* %P
   
  %P2 = bitcast i64* %P to float*

  %A = load float* %P2
  ret float %A
; CHECK: @coerce_mustalias6
; CHECK-NOT: load
; CHECK: ret float
}

;; i64 -> i8* (32-bit) forwarding
define i8* @coerce_mustalias7(i64 %V, i64* %P) {
  store i64 %V, i64* %P
   
  %P2 = bitcast i64* %P to i8**

  %A = load i8** %P2
  ret i8* %A
; CHECK: @coerce_mustalias7
; CHECK-NOT: load
; CHECK: ret i8*
}

; memset -> i16 forwarding.
define signext i16 @memset_to_i16_local(i16* %A) nounwind ssp {
entry:
  %conv = bitcast i16* %A to i8* 
  tail call void @llvm.memset.i64(i8* %conv, i8 1, i64 200, i32 1)
  %arrayidx = getelementptr inbounds i16* %A, i64 42
  %tmp2 = load i16* %arrayidx
  ret i16 %tmp2
; CHECK: @memset_to_i16_local
; CHECK-NOT: load
; CHECK: ret i16 257
}

; memset -> float forwarding.
define float @memset_to_float_local(float* %A, i8 %Val) nounwind ssp {
entry:
  %conv = bitcast float* %A to i8*                ; <i8*> [#uses=1]
  tail call void @llvm.memset.i64(i8* %conv, i8 %Val, i64 400, i32 1)
  %arrayidx = getelementptr inbounds float* %A, i64 42 ; <float*> [#uses=1]
  %tmp2 = load float* %arrayidx                   ; <float> [#uses=1]
  ret float %tmp2
; CHECK: @memset_to_float_local
; CHECK-NOT: load
; CHECK: zext
; CHECK-NEXT: shl
; CHECK-NEXT: or
; CHECK-NEXT: shl
; CHECK-NEXT: or
; CHECK-NEXT: bitcast
; CHECK-NEXT: ret float
}

;; non-local memset -> i16 load forwarding.
define i16 @memset_to_i16_nonlocal0(i16* %P, i1 %cond) {
  %P3 = bitcast i16* %P to i8*
  br i1 %cond, label %T, label %F
T:
  tail call void @llvm.memset.i64(i8* %P3, i8 1, i64 400, i32 1)
  br label %Cont
  
F:
  tail call void @llvm.memset.i64(i8* %P3, i8 2, i64 400, i32 1)
  br label %Cont

Cont:
  %P2 = getelementptr i16* %P, i32 4
  %A = load i16* %P2
  ret i16 %A

; CHECK: @memset_to_i16_nonlocal0
; CHECK: Cont:
; CHECK-NEXT:   %A = phi i16 [ 514, %F ], [ 257, %T ]
; CHECK-NOT: load
; CHECK: ret i16 %A
}

@GCst = constant {i32, float, i32 } { i32 42, float 14., i32 97 }

; memset -> float forwarding.
define float @memcpy_to_float_local(float* %A) nounwind ssp {
entry:
  %conv = bitcast float* %A to i8*                ; <i8*> [#uses=1]
  tail call void @llvm.memcpy.i64(i8* %conv, i8* bitcast ({i32, float, i32 }* @GCst to i8*), i64 12, i32 1)
  %arrayidx = getelementptr inbounds float* %A, i64 1 ; <float*> [#uses=1]
  %tmp2 = load float* %arrayidx                   ; <float> [#uses=1]
  ret float %tmp2
; CHECK: @memcpy_to_float_local
; CHECK-NOT: load
; CHECK: ret float 1.400000e+01
}


declare void @llvm.memset.i64(i8* nocapture, i8, i64, i32) nounwind
declare void @llvm.memcpy.i64(i8* nocapture, i8* nocapture, i64, i32) nounwind




;; non-local i32/float -> i8 load forwarding.
define i8 @coerce_mustalias_nonlocal0(i32* %P, i1 %cond) {
  %P2 = bitcast i32* %P to float*
  %P3 = bitcast i32* %P to i8*
  br i1 %cond, label %T, label %F
T:
  store i32 42, i32* %P
  br label %Cont
  
F:
  store float 1.0, float* %P2
  br label %Cont

Cont:
  %A = load i8* %P3
  ret i8 %A

; CHECK: @coerce_mustalias_nonlocal0
; CHECK: Cont:
; CHECK:   %A = phi i8 [
; CHECK-NOT: load
; CHECK: ret i8 %A
}


;; non-local i32/float -> i8 load forwarding.  This also tests that the "P3"
;; bitcast equivalence can be properly phi translated.
define i8 @coerce_mustalias_nonlocal1(i32* %P, i1 %cond) {
  %P2 = bitcast i32* %P to float*
  br i1 %cond, label %T, label %F
T:
  store i32 42, i32* %P
  br label %Cont
  
F:
  store float 1.0, float* %P2
  br label %Cont

Cont:
  %P3 = bitcast i32* %P to i8*
  %A = load i8* %P3
  ret i8 %A

;; FIXME: This is disabled because this caused a miscompile in the llvm-gcc
;; bootstrap, see r82411
;
; HECK: @coerce_mustalias_nonlocal1
; HECK: Cont:
; HECK:   %A = phi i8 [
; HECK-NOT: load
; HECK: ret i8 %A
}


;; non-local i32 -> i8 partial redundancy load forwarding.
define i8 @coerce_mustalias_pre0(i32* %P, i1 %cond) {
  %P3 = bitcast i32* %P to i8*
  br i1 %cond, label %T, label %F
T:
  store i32 42, i32* %P
  br label %Cont
  
F:
  br label %Cont

Cont:
  %A = load i8* %P3
  ret i8 %A

; CHECK: @coerce_mustalias_pre0
; CHECK: F:
; CHECK:   load i8* %P3
; CHECK: Cont:
; CHECK:   %A = phi i8 [
; CHECK-NOT: load
; CHECK: ret i8 %A
}

;;===----------------------------------------------------------------------===;;
;; Store -> Load  and  Load -> Load forwarding where src and dst are different
;; types, and the reload is an offset from the store pointer.
;;===----------------------------------------------------------------------===;;

;; i32 -> i8 forwarding.
;; PR4216
define i8 @coerce_offset0(i32 %V, i32* %P) {
  store i32 %V, i32* %P
   
  %P2 = bitcast i32* %P to i8*
  %P3 = getelementptr i8* %P2, i32 2

  %A = load i8* %P3
  ret i8 %A
; CHECK: @coerce_offset0
; CHECK-NOT: load
; CHECK: ret i8
}

;; non-local i32/float -> i8 load forwarding.
define i8 @coerce_offset_nonlocal0(i32* %P, i1 %cond) {
  %P2 = bitcast i32* %P to float*
  %P3 = bitcast i32* %P to i8*
  %P4 = getelementptr i8* %P3, i32 2
  br i1 %cond, label %T, label %F
T:
  store i32 42, i32* %P
  br label %Cont
  
F:
  store float 1.0, float* %P2
  br label %Cont

Cont:
  %A = load i8* %P4
  ret i8 %A

; CHECK: @coerce_offset_nonlocal0
; CHECK: Cont:
; CHECK:   %A = phi i8 [
; CHECK-NOT: load
; CHECK: ret i8 %A
}


;; non-local i32 -> i8 partial redundancy load forwarding.
define i8 @coerce_offset_pre0(i32* %P, i1 %cond) {
  %P3 = bitcast i32* %P to i8*
  %P4 = getelementptr i8* %P3, i32 2
  br i1 %cond, label %T, label %F
T:
  store i32 42, i32* %P
  br label %Cont
  
F:
  br label %Cont

Cont:
  %A = load i8* %P4
  ret i8 %A

; CHECK: @coerce_offset_pre0
; CHECK: F:
; CHECK:   load i8* %P4
; CHECK: Cont:
; CHECK:   %A = phi i8 [
; CHECK-NOT: load
; CHECK: ret i8 %A
}

define i32 @chained_load(i32** %p) {
block1:
  %z = load i32** %p
	br i1 true, label %block2, label %block3

block2:
 %a = load i32** %p
 br label %block4

block3:
  %b = load i32** %p
  br label %block4

block4:
  %c = load i32** %p
  %d = load i32* %c
  ret i32 %d
  
; CHECK: @chained_load
; CHECK: %z = load i32** %p
; CHECK-NOT: load
; CHECK: %d = load i32* %z
; CHECK-NEXT: ret i32 %d
}


declare i1 @cond() readonly
declare i1 @cond2() readonly

define i32 @phi_trans2() {
; CHECK: @phi_trans2
entry:
  %P = alloca i32, i32 400
  br label %F1
  
F1:
  %A = phi i32 [1, %entry], [2, %F]
  %cond2 = call i1 @cond()
  br i1 %cond2, label %T1, label %TY
  
T1:
  %P2 = getelementptr i32* %P, i32 %A
  %x = load i32* %P2
  %cond = call i1 @cond2()
  br i1 %cond, label %TX, label %F
  
F:
  %P3 = getelementptr i32* %P, i32 2
  store i32 17, i32* %P3
  
  store i32 42, i32* %P2  ; Provides "P[A]".
  br label %F1

TX:
  ; This load should not be compiled to 'ret i32 42'.  An overly clever
  ; implementation of GVN would see that we're returning 17 if the loop
  ; executes once or 42 if it executes more than that, but we'd have to do
  ; loop restructuring to expose this, and GVN shouldn't do this sort of CFG
  ; transformation.
  
; CHECK: TX:
; CHECK: ret i32 %x
  ret i32 %x
TY:
  ret i32 0
}

define i32 @phi_trans3(i32* %p) {
; CHECK: @phi_trans3
block1:
  br i1 true, label %block2, label %block3

block2:
 store i32 87, i32* %p
 br label %block4

block3:
  %p2 = getelementptr i32* %p, i32 43
  store i32 97, i32* %p2
  br label %block4

block4:
  %A = phi i32 [-1, %block2], [42, %block3]
  br i1 true, label %block5, label %exit
  
; CHECK: block4:
; CHECK-NEXT: %D = phi i32 [ 87, %block2 ], [ 97, %block3 ]  
; CHECK-NOT: load

block5:
  %B = add i32 %A, 1
  br i1 true, label %block6, label %exit
  
block6:
  %C = getelementptr i32* %p, i32 %B
  br i1 true, label %block7, label %exit
  
block7:
  %D = load i32* %C
  ret i32 %D
  
; CHECK: block7:
; CHECK-NEXT: ret i32 %D

exit:
  ret i32 -1
}

define i8 @phi_trans4(i8* %p) {
; CHECK: @phi_trans4
entry:
  %X3 = getelementptr i8* %p, i32 192
  store i8 192, i8* %X3
  
  %X = getelementptr i8* %p, i32 4
  %Y = load i8* %X
  br label %loop

loop:
  %i = phi i32 [4, %entry], [192, %loop]
  %X2 = getelementptr i8* %p, i32 %i
  %Y2 = load i8* %X2
  
; CHECK: loop:
; CHECK-NEXT: %Y2 = phi i8 [ %Y, %entry ], [ 0, %loop ]
; CHECK-NOT: load i8
  
  %cond = call i1 @cond2()

  %Z = bitcast i8 *%X3 to i32*
  store i32 0, i32* %Z
  br i1 %cond, label %loop, label %out
  
out:
  %R = add i8 %Y, %Y2
  ret i8 %R
}

define i8 @phi_trans5(i8* %p) {
; CHECK: @phi_trans5
entry:
  
  %X4 = getelementptr i8* %p, i32 2
  store i8 19, i8* %X4
  
  %X = getelementptr i8* %p, i32 4
  %Y = load i8* %X
  br label %loop

loop:
  %i = phi i32 [4, %entry], [3, %cont]
  %X2 = getelementptr i8* %p, i32 %i
  %Y2 = load i8* %X2  ; Ensure this load is not being incorrectly replaced.
  %cond = call i1 @cond2()
  br i1 %cond, label %cont, label %out

cont:
  %Z = getelementptr i8* %X2, i32 -1
  %Z2 = bitcast i8 *%Z to i32*
  store i32 50462976, i32* %Z2  ;; (1 << 8) | (2 << 16) | (3 << 24)


; CHECK: store i32
; CHECK-NEXT: getelementptr i8* %p, i32 3
; CHECK-NEXT: load i8*
  br label %loop
  
out:
  %R = add i8 %Y, %Y2
  ret i8 %R
}


; PR6642
define i32 @memset_to_load() nounwind readnone {
entry:
  %x = alloca [256 x i32], align 4                ; <[256 x i32]*> [#uses=2]
  %tmp = bitcast [256 x i32]* %x to i8*           ; <i8*> [#uses=1]
  call void @llvm.memset.i64(i8* %tmp, i8 0, i64 1024, i32 4)
  %arraydecay = getelementptr inbounds [256 x i32]* %x, i32 0, i32 0 ; <i32*>
  %tmp1 = load i32* %arraydecay                   ; <i32> [#uses=1]
  ret i32 %tmp1
; CHECK: @memset_to_load
; CHECK: ret i32 0
}

