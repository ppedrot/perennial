(* autogenerated from marshal *)
From Perennial.goose_lang Require Import prelude.

(* disk FFI *)
From Perennial.goose_lang Require Import ffi.disk_prelude.

(* Enc is a stateful encoder for a single disk block. *)
Module Enc.
  Definition S := struct.decl [
    "b" :: disk.blockT;
    "off" :: refT uint64T
  ].
End Enc.

Definition NewEnc: val :=
  λ: <>,
    struct.mk Enc.S [
      "b" ::= NewSlice byteT disk.BlockSize;
      "off" ::= ref (zero_val uint64T)
    ].

Definition Enc__PutInt: val :=
  λ: "enc" "x",
    let: "off" := ![uint64T] (struct.get Enc.S "off" "enc") in
    UInt64Put (SliceSkip byteT (struct.get Enc.S "b" "enc") "off") "x";;
    struct.get Enc.S "off" "enc" <-[refT uint64T] ![uint64T] (struct.get Enc.S "off" "enc") + #8.

Definition Enc__Finish: val :=
  λ: "enc",
    struct.get Enc.S "b" "enc".

(* Dec is a stateful decoder that returns values encoded
   sequentially in a single disk block. *)
Module Dec.
  Definition S := struct.decl [
    "b" :: disk.blockT;
    "off" :: refT uint64T
  ].
End Dec.

Definition NewDec: val :=
  λ: "b",
    struct.mk Dec.S [
      "b" ::= "b";
      "off" ::= ref (zero_val uint64T)
    ].

Definition Dec__GetInt: val :=
  λ: "dec",
    let: "off" := ![uint64T] (struct.get Dec.S "off" "dec") in
    struct.get Dec.S "off" "dec" <-[refT uint64T] ![uint64T] (struct.get Dec.S "off" "dec") + #8;;
    UInt64Get (SliceSkip byteT (struct.get Dec.S "b" "dec") "off").