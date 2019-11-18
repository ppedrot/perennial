(* autogenerated from append_log *)
From Perennial.go_lang Require Import prelude.

(* disk FFI *)
From Perennial.go_lang Require Import ffi.disk_prelude.

Module Log.
  Definition S := struct.new [
    "sz" :: intT;
    "diskSz" :: intT
  ].
  Definition T: ty := struct.t S.
  Section fields.
    Context `{ext_ty: ext_types}.
    Definition get := struct.get S.
  End fields.
End Log.

Definition Log__writeHdr: val :=
  λ: "log",
    let: "hdr" := NewSlice byteT #4096 in
    UInt64Put "hdr" (Log.get "sz" "log");;
    UInt64Put (SliceSkip "hdr" #8) (Log.get "sz" "log");;
    disk.Write #0 "hdr".
Theorem Log__writeHdr_t: ⊢ Log__writeHdr : (Log.T -> unitT).
Proof. typecheck. Qed.
Hint Resolve Log__writeHdr_t : types.

Definition Init: val :=
  λ: "diskSz",
    if: "diskSz" < #1
    then
      (struct.mk Log.S [
         "sz" ::= #0;
         "diskSz" ::= #0
       ], #false)
    else
      let: "log" := struct.mk Log.S [
        "sz" ::= #0;
        "diskSz" ::= "diskSz"
      ] in
      Log__writeHdr "log";;
      ("log", #true).
Theorem Init_t: ⊢ Init : (intT -> (Log.T * boolT)).
Proof. typecheck. Qed.
Hint Resolve Init_t : types.

Definition Log__Get: val :=
  λ: "log" "i",
    let: "sz" := Log.get "sz" "log" in
    if: "i" < "sz"
    then (disk.Read (#1 + "i"), #true)
    else (slice.nil, #false).
Theorem Log__Get_t: ⊢ Log__Get : (Log.T -> intT -> (disk.blockT * boolT)).
Proof. typecheck. Qed.
Hint Resolve Log__Get_t : types.

Definition writeAll: val :=
  λ: "bks" "off",
    let: "numBks" := slice.len "bks" in
    let: "i" := ref #0 in
    for: (!"i" < "numBks"); ("i" <- !"i" + #1) :=
      let: "bk" := SliceGet "bks" !"i" in
      disk.Write ("off" + !"i") "bk";;
      Continue.
Theorem writeAll_t: ⊢ writeAll : (slice.T disk.blockT -> intT -> unitT).
Proof. typecheck. Qed.
Hint Resolve writeAll_t : types.

Definition Log__Append: val :=
  λ: "log" "bks",
    let: "sz" := Log.get "sz" !"log" in
    if: #1 + "sz" + slice.len "bks" ≥ Log.get "diskSz" !"log"
    then #false
    else
      writeAll "bks" (#1 + "sz");;
      let: "newLog" := struct.mk Log.S [
        "sz" ::= "sz" + slice.len "bks";
        "diskSz" ::= Log.get "diskSz" !"log"
      ] in
      Log__writeHdr "newLog";;
      "log" <- "newLog";;
      #true.
Theorem Log__Append_t: ⊢ Log__Append : (refT Log.T -> slice.T disk.blockT -> boolT).
Proof. typecheck. Qed.
Hint Resolve Log__Append_t : types.

Definition Log__Reset: val :=
  λ: "log",
    let: "newLog" := struct.mk Log.S [
      "sz" ::= #0;
      "diskSz" ::= Log.get "diskSz" !"log"
    ] in
    Log__writeHdr "newLog";;
    "log" <- "newLog".
Theorem Log__Reset_t: ⊢ Log__Reset : (refT Log.T -> unitT).
Proof. typecheck. Qed.
Hint Resolve Log__Reset_t : types.
