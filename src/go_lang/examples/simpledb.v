(* autogenerated from simpledb *)
From Perennial.go_lang Require Import prelude.

(* disk FFI *)
From Perennial.go_lang Require Import ffi.disk_prelude.

(* Package simpledb implements a one-table version of LevelDB

   It buffers all writes in memory; to make data durable, call Compact().
   This operation re-writes all of the data in the database
   (including in-memory writes) in a crash-safe manner.
   Keys in the table are cached for efficient reads. *)

Module Table.
  (* A Table provides access to an immutable copy of data on the filesystem,
     along with an index for fast random access. *)
  Definition S := struct.new [
    "Index" :: mapT intT;
    "File" :: fileT
  ].
  Definition T: ty := struct.t S.
  Section fields.
    Context `{ext_ty: ext_types}.
    Definition get := struct.get S.
  End fields.
End Table.

(* CreateTable creates a new, empty table. *)
Definition CreateTable: val :=
  λ: "p",
    let: "index" := NewMap intT in
    let: ("f", <>) := FS.create #(str"db") "p" in
    FS.close "f";;
    let: "f2" := FS.open #(str"db") "p" in
    struct.mk Table.S [
      "Index" ::= "index";
      "File" ::= "f2"
    ].

Module Entry.
  (* Entry represents a (key, value) pair. *)
  Definition S := struct.new [
    "Key" :: intT;
    "Value" :: slice.T byteT
  ].
  Definition T: ty := struct.t S.
  Section fields.
    Context `{ext_ty: ext_types}.
    Definition get := struct.get S.
  End fields.
End Entry.

(* DecodeUInt64 is a Decoder(uint64)

   All decoders have the shape func(p []byte) (T, uint64)

   The uint64 represents the number of bytes consumed; if 0,
   then decoding failed, and the value of type T should be ignored. *)
Definition DecodeUInt64: val :=
  λ: "p",
    if: slice.len "p" < #8
    then (#0, #0)
    else
      let: "n" := UInt64Get "p" in
      ("n", #8).

(* DecodeEntry is a Decoder(Entry) *)
Definition DecodeEntry: val :=
  λ: "data",
    let: ("key", "l1") := DecodeUInt64 "data" in
    if: "l1" = #0
    then
      (struct.mk Entry.S [
         "Key" ::= #0;
         "Value" ::= slice.nil
       ], #0)
    else
      let: ("valueLen", "l2") := DecodeUInt64 (SliceSkip "data" "l1") in
      if: "l2" = #0
      then
        (struct.mk Entry.S [
           "Key" ::= #0;
           "Value" ::= slice.nil
         ], #0)
      else
        if: slice.len "data" < "l1" + "l2" + "valueLen"
        then
          (struct.mk Entry.S [
             "Key" ::= #0;
             "Value" ::= slice.nil
           ], #0)
        else
          let: "value" := SliceSubslice "data" ("l1" + "l2") ("l1" + "l2" + "valueLen") in
          (struct.mk Entry.S [
             "Key" ::= "key";
             "Value" ::= "value"
           ], "l1" + "l2" + "valueLen").

Module lazyFileBuf.
  Definition S := struct.new [
    "offset" :: intT;
    "next" :: slice.T byteT
  ].
  Definition T: ty := struct.t S.
  Section fields.
    Context `{ext_ty: ext_types}.
    Definition get := struct.get S.
  End fields.
End lazyFileBuf.

(* readTableIndex parses a complete table on disk into a key->offset index *)
Definition readTableIndex: val :=
  λ: "f" "index",
    let: "buf" := ref (struct.mk lazyFileBuf.S [
      "offset" ::= #0;
      "next" ::= slice.nil
    ]) in
    for: (#true); (Skip) :=
      let: ("e", "l") := DecodeEntry (lazyFileBuf.get "next" !"buf") in
      if: "l" > #0
      then
        MapInsert "index" (Entry.get "Key" "e") (#8 + lazyFileBuf.get "offset" !"buf");;
        "buf" <- struct.mk lazyFileBuf.S [
          "offset" ::= lazyFileBuf.get "offset" !"buf" + "l";
          "next" ::= SliceSkip (lazyFileBuf.get "next" !"buf") "l"
        ];;
        Continue
      else
        let: "p" := FS.readAt "f" (lazyFileBuf.get "offset" !"buf" + slice.len (lazyFileBuf.get "next" !"buf")) #4096 in
        if: slice.len "p" = #0
        then Break
        else
          let: "newBuf" := Data.sliceAppendSlice (lazyFileBuf.get "next" !"buf") "p" in
          "buf" <- struct.mk lazyFileBuf.S [
            "offset" ::= lazyFileBuf.get "offset" !"buf";
            "next" ::= "newBuf"
          ];;
          Continue;;
      Continue.

(* RecoverTable restores a table from disk on startup. *)
Definition RecoverTable: val :=
  λ: "p",
    let: "index" := NewMap intT in
    let: "f" := FS.open #(str"db") "p" in
    readTableIndex "f" "index";;
    struct.mk Table.S [
      "Index" ::= "index";
      "File" ::= "f"
    ].

(* CloseTable frees up the fd held by a table. *)
Definition CloseTable: val :=
  λ: "t",
    FS.close (Table.get "File" "t").

Definition readValue: val :=
  λ: "f" "off",
    let: "startBuf" := FS.readAt "f" "off" #512 in
    let: "totalBytes" := UInt64Get "startBuf" in
    let: "buf" := SliceSkip "startBuf" #8 in
    let: "haveBytes" := slice.len "buf" in
    if: "haveBytes" < "totalBytes"
    then
      let: "buf2" := FS.readAt "f" ("off" + #512) ("totalBytes" - "haveBytes") in
      let: "newBuf" := Data.sliceAppendSlice "buf" "buf2" in
      "newBuf"
    else SliceTake "buf" "totalBytes".

Definition tableRead: val :=
  λ: "t" "k",
    let: ("off", "ok") := MapGet (Table.get "Index" "t") "k" in
    if: ~ "ok"
    then (slice.nil, #false)
    else
      let: "p" := readValue (Table.get "File" "t") "off" in
      ("p", #true).

Module bufFile.
  Definition S := struct.new [
    "file" :: fileT;
    "buf" :: refT (slice.T byteT)
  ].
  Definition T: ty := struct.t S.
  Section fields.
    Context `{ext_ty: ext_types}.
    Definition get := struct.get S.
  End fields.
End bufFile.

Definition newBuf: val :=
  λ: "f",
    let: "buf" := ref (zero_val (slice.T byteT)) in
    struct.mk bufFile.S [
      "file" ::= "f";
      "buf" ::= "buf"
    ].

Definition bufFlush: val :=
  λ: "f",
    let: "buf" := !(bufFile.get "buf" "f") in
    if: slice.len "buf" = #0
    then "tt"
    else
      FS.append (bufFile.get "file" "f") "buf";;
      bufFile.get "buf" "f" <- slice.nil.

Definition bufAppend: val :=
  λ: "f" "p",
    let: "buf" := !(bufFile.get "buf" "f") in
    let: "buf2" := Data.sliceAppendSlice "buf" "p" in
    bufFile.get "buf" "f" <- "buf2".

Definition bufClose: val :=
  λ: "f",
    bufFlush "f";;
    FS.close (bufFile.get "file" "f").

Module tableWriter.
  Definition S := struct.new [
    "index" :: mapT intT;
    "name" :: stringT;
    "file" :: bufFile.T;
    "offset" :: refT intT
  ].
  Definition T: ty := struct.t S.
  Section fields.
    Context `{ext_ty: ext_types}.
    Definition get := struct.get S.
  End fields.
End tableWriter.

Definition newTableWriter: val :=
  λ: "p",
    let: "index" := NewMap intT in
    let: ("f", <>) := FS.create #(str"db") "p" in
    let: "buf" := newBuf "f" in
    let: "off" := ref (zero_val intT) in
    struct.mk tableWriter.S [
      "index" ::= "index";
      "name" ::= "p";
      "file" ::= "buf";
      "offset" ::= "off"
    ].

Definition tableWriterAppend: val :=
  λ: "w" "p",
    bufAppend (tableWriter.get "file" "w") "p";;
    let: "off" := !(tableWriter.get "offset" "w") in
    tableWriter.get "offset" "w" <- "off" + slice.len "p".

Definition tableWriterClose: val :=
  λ: "w",
    bufClose (tableWriter.get "file" "w");;
    let: "f" := FS.open #(str"db") (tableWriter.get "name" "w") in
    struct.mk Table.S [
      "Index" ::= tableWriter.get "index" "w";
      "File" ::= "f"
    ].

(* EncodeUInt64 is an Encoder(uint64) *)
Definition EncodeUInt64: val :=
  λ: "x" "p",
    let: "tmp" := NewSlice byteT #8 in
    UInt64Put "tmp" "x";;
    let: "p2" := Data.sliceAppendSlice "p" "tmp" in
    "p2".

(* EncodeSlice is an Encoder([]byte) *)
Definition EncodeSlice: val :=
  λ: "data" "p",
    let: "p2" := EncodeUInt64 (slice.len "data") "p" in
    let: "p3" := Data.sliceAppendSlice "p2" "data" in
    "p3".

Definition tablePut: val :=
  λ: "w" "k" "v",
    let: "tmp" := NewSlice byteT #0 in
    let: "tmp2" := EncodeUInt64 "k" "tmp" in
    let: "tmp3" := EncodeSlice "v" "tmp2" in
    let: "off" := !(tableWriter.get "offset" "w") in
    MapInsert (tableWriter.get "index" "w") "k" ("off" + slice.len "tmp2");;
    tableWriterAppend "w" "tmp3".

Module Database.
  (* Database is a handle to an open database. *)
  Definition S := struct.new [
    "wbuffer" :: refT (mapT (slice.T byteT));
    "rbuffer" :: refT (mapT (slice.T byteT));
    "bufferL" :: lockRefT;
    "table" :: refT Table.T;
    "tableName" :: refT stringT;
    "tableL" :: lockRefT;
    "compactionL" :: lockRefT
  ].
  Definition T: ty := struct.t S.
  Section fields.
    Context `{ext_ty: ext_types}.
    Definition get := struct.get S.
  End fields.
End Database.

Definition makeValueBuffer: val :=
  λ: <>,
    let: "buf" := NewMap (slice.T byteT) in
    let: "bufPtr" := ref (zero_val (mapT (slice.T byteT))) in
    "bufPtr" <- "buf";;
    "bufPtr".

(* NewDb initializes a new database on top of an empty filesys. *)
Definition NewDb: val :=
  λ: <>,
    let: "wbuf" := makeValueBuffer #() in
    let: "rbuf" := makeValueBuffer #() in
    let: "bufferL" := Data.newLock #() in
    let: "tableName" := #(str"table.0") in
    let: "tableNameRef" := ref (zero_val stringT) in
    "tableNameRef" <- "tableName";;
    let: "table" := CreateTable "tableName" in
    let: "tableRef" := ref (zero_val Table.T) in
    "tableRef" <- "table";;
    let: "tableL" := Data.newLock #() in
    let: "compactionL" := Data.newLock #() in
    struct.mk Database.S [
      "wbuffer" ::= "wbuf";
      "rbuffer" ::= "rbuf";
      "bufferL" ::= "bufferL";
      "table" ::= "tableRef";
      "tableName" ::= "tableNameRef";
      "tableL" ::= "tableL";
      "compactionL" ::= "compactionL"
    ].

(* Read gets a key from the database.

   Returns a boolean indicating if the k was found and a non-nil slice with
   the value if k was in the database.

   Reflects any completed in-memory writes. *)
Definition Read: val :=
  λ: "db" "k",
    Data.lockAcquire Reader (Database.get "bufferL" "db");;
    let: "buf" := !(Database.get "wbuffer" "db") in
    let: ("v", "ok") := MapGet "buf" "k" in
    if: "ok"
    then
      Data.lockRelease Reader (Database.get "bufferL" "db");;
      ("v", #true)
    else
      let: "rbuf" := !(Database.get "rbuffer" "db") in
      let: ("v2", "ok") := MapGet "rbuf" "k" in
      if: "ok"
      then
        Data.lockRelease Reader (Database.get "bufferL" "db");;
        ("v2", #true)
      else
        Data.lockAcquire Reader (Database.get "tableL" "db");;
        let: "tbl" := !(Database.get "table" "db") in
        let: ("v3", "ok") := tableRead "tbl" "k" in
        Data.lockRelease Reader (Database.get "tableL" "db");;
        Data.lockRelease Reader (Database.get "bufferL" "db");;
        ("v3", "ok").

(* Write sets a key to a new value.

   Creates a new key-value mapping if k is not in the database and overwrites
   the previous value if k is present.

   The new value is buffered in memory. To persist it, call db.Compact(). *)
Definition Write: val :=
  λ: "db" "k" "v",
    Data.lockAcquire Writer (Database.get "bufferL" "db");;
    let: "buf" := !(Database.get "wbuffer" "db") in
    MapInsert "buf" "k" "v";;
    Data.lockRelease Writer (Database.get "bufferL" "db").

Definition freshTable: val :=
  λ: "p",
    if: "p" = #(str"table.0")
    then #(str"table.1")
    else
      if: "p" = #(str"table.1")
      then #(str"table.0")
      else "p".

Definition tablePutBuffer: val :=
  λ: "w" "buf",
    Data.mapIter "buf" (λ: "k" "v",
      tablePut "w" "k" "v").

(* add all of table t to the table w being created; skip any keys in the (read)
   buffer b since those writes overwrite old ones *)
Definition tablePutOldTable: val :=
  λ: "w" "t" "b",
    let: "buf" := ref (struct.mk lazyFileBuf.S [
      "offset" ::= #0;
      "next" ::= slice.nil
    ]) in
    for: (#true); (Skip) :=
      let: ("e", "l") := DecodeEntry (lazyFileBuf.get "next" !"buf") in
      if: "l" > #0
      then
        let: (<>, "ok") := MapGet "b" (Entry.get "Key" "e") in
        if: ~ "ok"
        then
          tablePut "w" (Entry.get "Key" "e") (Entry.get "Value" "e");;
          #()
        else #();;
        "buf" <- struct.mk lazyFileBuf.S [
          "offset" ::= lazyFileBuf.get "offset" !"buf" + "l";
          "next" ::= SliceSkip (lazyFileBuf.get "next" !"buf") "l"
        ];;
        Continue
      else
        let: "p" := FS.readAt (Table.get "File" "t") (lazyFileBuf.get "offset" !"buf" + slice.len (lazyFileBuf.get "next" !"buf")) #4096 in
        if: slice.len "p" = #0
        then Break
        else
          let: "newBuf" := Data.sliceAppendSlice (lazyFileBuf.get "next" !"buf") "p" in
          "buf" <- struct.mk lazyFileBuf.S [
            "offset" ::= lazyFileBuf.get "offset" !"buf";
            "next" ::= "newBuf"
          ];;
          Continue;;
      Continue.

(* Build a new shadow table that incorporates the current table and a
   (write) buffer wbuf.

   Assumes all the appropriate locks have been taken.

   Returns the old table and new table. *)
Definition constructNewTable: val :=
  λ: "db" "wbuf",
    let: "oldName" := !(Database.get "tableName" "db") in
    let: "name" := freshTable "oldName" in
    let: "w" := newTableWriter "name" in
    let: "oldTable" := !(Database.get "table" "db") in
    tablePutOldTable "w" "oldTable" "wbuf";;
    tablePutBuffer "w" "wbuf";;
    let: "newTable" := tableWriterClose "w" in
    ("oldTable", "newTable").

(* Compact persists in-memory writes to a new table.

   This simple database design must re-write all data to combine in-memory
   writes with existing writes. *)
Definition Compact: val :=
  λ: "db",
    Data.lockAcquire Writer (Database.get "compactionL" "db");;
    Data.lockAcquire Writer (Database.get "bufferL" "db");;
    let: "buf" := !(Database.get "wbuffer" "db") in
    let: "emptyWbuffer" := NewMap (slice.T byteT) in
    Database.get "wbuffer" "db" <- "emptyWbuffer";;
    Database.get "rbuffer" "db" <- "buf";;
    Data.lockRelease Writer (Database.get "bufferL" "db");;
    Data.lockAcquire Reader (Database.get "tableL" "db");;
    let: "oldTableName" := !(Database.get "tableName" "db") in
    let: ("oldTable", "t") := constructNewTable "db" "buf" in
    let: "newTable" := freshTable "oldTableName" in
    Data.lockRelease Reader (Database.get "tableL" "db");;
    Data.lockAcquire Writer (Database.get "tableL" "db");;
    Database.get "table" "db" <- "t";;
    Database.get "tableName" "db" <- "newTable";;
    let: "manifestData" := Data.stringToBytes "newTable" in
    FS.atomicCreate #(str"db") #(str"manifest") "manifestData";;
    CloseTable "oldTable";;
    FS.delete #(str"db") "oldTableName";;
    Data.lockRelease Writer (Database.get "tableL" "db");;
    Data.lockRelease Writer (Database.get "compactionL" "db").

Definition recoverManifest: val :=
  λ: <>,
    let: "f" := FS.open #(str"db") #(str"manifest") in
    let: "manifestData" := FS.readAt "f" #0 #4096 in
    let: "tableName" := Data.bytesToString "manifestData" in
    FS.close "f";;
    "tableName".

(* delete 'name' if it isn't tableName or "manifest" *)
Definition deleteOtherFile: val :=
  λ: "name" "tableName",
    if: "name" = "tableName"
    then "tt"
    else
      if: "name" = #(str"manifest")
      then "tt"
      else FS.delete #(str"db") "name".

Definition deleteOtherFiles: val :=
  λ: "tableName",
    let: "files" := FS.list #(str"db") in
    let: "nfiles" := slice.len "files" in
    let: "i" := ref #0 in
    for: (#true); (Skip) :=
      if: !"i" = "nfiles"
      then Break
      else
        let: "name" := SliceGet "files" !"i" in
        deleteOtherFile "name" "tableName";;
        "i" <- !"i" + #1;;
        Continue.

(* Recover restores a previously created database after a crash or shutdown. *)
Definition Recover: val :=
  λ: <>,
    let: "tableName" := recoverManifest #() in
    let: "table" := RecoverTable "tableName" in
    let: "tableRef" := ref (zero_val Table.T) in
    "tableRef" <- "table";;
    let: "tableNameRef" := ref (zero_val stringT) in
    "tableNameRef" <- "tableName";;
    deleteOtherFiles "tableName";;
    let: "wbuffer" := makeValueBuffer #() in
    let: "rbuffer" := makeValueBuffer #() in
    let: "bufferL" := Data.newLock #() in
    let: "tableL" := Data.newLock #() in
    let: "compactionL" := Data.newLock #() in
    struct.mk Database.S [
      "wbuffer" ::= "wbuffer";
      "rbuffer" ::= "rbuffer";
      "bufferL" ::= "bufferL";
      "table" ::= "tableRef";
      "tableName" ::= "tableNameRef";
      "tableL" ::= "tableL";
      "compactionL" ::= "compactionL"
    ].

(* Shutdown immediately closes the database.

   Discards any uncommitted in-memory writes; similar to a crash except for
   cleanly closing any open files. *)
Definition Shutdown: val :=
  λ: "db",
    Data.lockAcquire Writer (Database.get "bufferL" "db");;
    Data.lockAcquire Writer (Database.get "compactionL" "db");;
    let: "t" := !(Database.get "table" "db") in
    CloseTable "t";;
    Data.lockRelease Writer (Database.get "compactionL" "db");;
    Data.lockRelease Writer (Database.get "bufferL" "db").

(* Close closes an open database cleanly, flushing any in-memory writes.

   db should not be used afterward *)
Definition Close: val :=
  λ: "db",
    Compact "db";;
    Shutdown "db".
